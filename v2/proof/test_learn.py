# -*- coding: utf-8 -*-
"""Bateria de prova do I8 (modulo memoria/RSI: reflector, curator, promote). So biblioteca
padrao, sem rede. Sandbox proprio, NUNCA toca studio/ real.

Uso: python test_learn.py
Sai com codigo 1 se alguma prova falhar.
"""
from __future__ import annotations

import atexit
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
LEARN = os.path.join(V2, "learn")
sys.path.insert(0, LEARN)
sys.path.insert(0, os.path.join(V2, "lib"))

import reflector  # noqa: E402
import curator  # noqa: E402
import promote  # noqa: E402

def _sandbox_tempdir(prefix: str) -> str:
    """Sandbox de teste SEMPRE fora de v2/ (pasta temporaria do sistema), nunca dentro do
    motor - a origem do vazamento medido pelo CEO. Removida no fim do processo mesmo se o
    teste falhar no meio (atexit, nao so no caminho feliz)."""
    d = tempfile.mkdtemp(prefix=prefix)
    atexit.register(shutil.rmtree, d, ignore_errors=True)
    return d
SANDBOX = _sandbox_tempdir("alia-v2-test-learn-")
REAL_STUDIO = os.path.abspath(os.path.join(V2, "..", "studio"))

FAILS = []


def check(name, cond, detail=""):
    status = "PASS" if cond else "FAIL"
    print("[" + status + "] " + name + " " + str(detail))
    if not cond:
        FAILS.append(name)


def fresh_sandbox():
    if os.path.exists(SANDBOX):
        shutil.rmtree(SANDBOX)
    os.makedirs(SANDBOX)
    assert not SANDBOX.startswith(REAL_STUDIO), "NUNCA gravar no studio real"
    return SANDBOX


def write_state(path, tasks):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump({"tasks": tasks}, fh, ensure_ascii=False, sort_keys=True)


# 1. Prova positiva: 1 Gate FAIL de exemplo gera 1 item com id.
def prova_positiva_gate_fail():
    sb = fresh_sandbox()
    state_path = os.path.join(sb, "state.json")
    activity_path = os.path.join(sb, "activity.jsonl")
    write_state(state_path, [{
        "id": "TASK-901",
        "client": "acme",
        "gate_verdict": "FAIL",
        "gate_criteria_failed": ["fonte-ausente"],
    }])
    itens = reflector.collect("TASK-901", activity_path, state_path)
    check("positiva: Gate FAIL gera exatamente 1 item", len(itens) == 1, str(itens))
    if itens:
        check("positiva: item tem id", bool(itens[0].get("id")), itens[0].get("id"))
        esperado = {"tipo": "gate_fail", "criterio": "fonte-ausente"}
        check("positiva: causa e gate_fail com criterio", itens[0]["causa"] == esperado, str(itens[0]["causa"]))


# 2. Prova negativa: patterns-2026-09-22.md real, convertido em entrada, gera ZERO item.
def prova_negativa_patterns_real():
    sb = fresh_sandbox()
    state_path = os.path.join(sb, "state.json")
    activity_path = os.path.join(sb, "activity.jsonl")
    # patterns-2026-09-22.md (memory/_proposals/) e um digest de sessoes de friccao: titulo,
    # contagem de sessoes e trechos de texto, mas NENHUM dos 4 campos causais (gate_verdict com
    # criterio, supersedes, budget_exceeded_count, root_cause). Convertido para Task e exatamente
    # isso: metadado descritivo sem causa estruturada.
    write_state(state_path, [{
        "id": "TASK-902",
        "client": "alia-flow",
        "title": "Candidatos a padrao - 2026-09-22 (patterns-2026-09-22.md)",
        "notes": "atrito:qualidade-fraca 16 sessoes; atrito:linguagem-forte 17 sessoes",
        "status": "done",
    }])
    itens = reflector.collect("TASK-902", activity_path, state_path)
    check("negativa: patterns real vira ZERO item (sem causa)", len(itens) == 0, str(itens))


# 3. Sem sinal: nada muda no playbook.
def prova_sem_sinal_nao_muda_playbook():
    sb = fresh_sandbox()
    playbook = os.path.join(sb, "playbooks", "acme.md")
    resultado = curator.apply_items(playbook, [])
    vazio = {"acrescentados": [], "incrementados": [], "aposentados": []}
    check("sem sinal: nenhum acrescentado/incrementado/aposentado", resultado == vazio, str(resultado))
    check("sem sinal: playbook nao chega a ser criado", not os.path.exists(playbook))


# 4. Chave unica por task_id: rodar reflector + curator 2x nao duplica.
def prova_dedup_task_id():
    sb = fresh_sandbox()
    state_path = os.path.join(sb, "state.json")
    activity_path = os.path.join(sb, "activity.jsonl")
    playbook = os.path.join(sb, "playbooks", "acme.md")
    write_state(state_path, [{
        "id": "TASK-903",
        "client": "acme",
        "gate_verdict": "FAIL",
        "gate_criteria_failed": ["travessao"],
    }])
    itens1 = reflector.collect("TASK-903", activity_path, state_path)
    curator.apply_items(playbook, itens1)
    itens2 = reflector.collect("TASK-903", activity_path, state_path)
    r2 = curator.apply_items(playbook, itens2)

    texto = open(playbook, encoding="utf-8").read()
    marcador = "<!-- item:TASK-903:gate_fail:travessao -->"
    n_blocos = texto.count(marcador)
    check("dedup: reflector devolve o mesmo id nas 2 rodadas", itens1[0]["id"] == itens2[0]["id"])
    check("dedup: playbook tem exatamente 1 bloco (nao duplicou)", n_blocos == 1, "n_blocos=" + str(n_blocos))
    check("dedup: 2a rodada so incrementou, nao acrescentou", r2["incrementados"] == [itens2[0]["id"]], str(r2))
    check("dedup: contador final = 2", "- contador: 2" in texto, texto)


# 5. Teto de 2.000 tokens respeitado (descarta/aposenta o item de pior saldo).
def prova_teto_respeitado():
    sb = fresh_sandbox()
    playbook = os.path.join(sb, "playbooks", "acme.md")
    teto_pequeno = 230  # tokens (bytes/4); forca estouro com poucos itens de texto longo
    itens = []
    for i in range(3):
        itens.append({
            "id": "TASK-9" + str(i) + ":gate_fail:criterio-" + str(i),
            "task_id": "TASK-9" + str(i),
            "client": "acme",
            "pattern_key": "gate_fail:criterio-" + str(i),
            "polaridade": "nocivo",
            "causa": {"tipo": "gate_fail", "criterio": "criterio-" + str(i)},
            "texto": "Gate FAIL de exemplo numero " + str(i) + " com texto para engordar o bloco.",
        })
    resultado = curator.apply_items(playbook, itens, teto_tokens=teto_pequeno)
    texto = open(playbook, encoding="utf-8").read()
    tokens_finais = len(texto.encode("utf-8")) / 4
    detalhe = "tokens_finais=" + str(tokens_finais) + " teto=" + str(teto_pequeno)
    check("teto: arquivo final cabe no teto apos aposentar", tokens_finais <= teto_pequeno, detalhe)
    check("teto: pelo menos 1 item foi aposentado", len(resultado["aposentados"]) >= 1, str(resultado))
    marcadores_presentes = all(("<!-- item:" + aid + " -->") in texto for aid in resultado["aposentados"])
    check("teto: item aposentado nunca some do arquivo (so encolhe)", marcadores_presentes)


# 6. Promocao: item em 3+ Clients distintos vai para a fila; idempotente.
def prova_promocao():
    sb = fresh_sandbox()
    playbooks_dir = os.path.join(sb, "playbooks")
    fila = os.path.join(sb, "promotion-queue.jsonl")
    for client in ("acme", "zeta", "beta"):
        p = os.path.join(playbooks_dir, client + ".md")
        itens = [{
            "id": "TASK-" + client + ":gate_fail:travessao",
            "task_id": "TASK-" + client,
            "client": client,
            "pattern_key": "gate_fail:travessao",
            "polaridade": "nocivo",
            "causa": {"tipo": "gate_fail", "criterio": "travessao"},
            "texto": "Gate FAIL: travessao encontrado na peca.",
        }]
        curator.apply_items(p, itens)
    novas1 = promote.run(playbooks_dir, fila, min_clients=3)
    novas2 = promote.run(playbooks_dir, fila, min_clients=3)
    check("promocao: 3 clients com o mesmo padrao geram 1 linha na fila", len(novas1) == 1, str(novas1))
    if novas1:
        check("promocao: dono e Archive", novas1[0]["dono"] == "Archive", str(novas1[0]))
        dias = _dias_entre(novas1[0]["criado_em"], novas1[0]["prazo"])
        check("promocao: prazo = criado_em + 7 dias", dias == 7, "dias=" + str(dias))
    check("promocao: rodar de novo nao duplica (idempotente)", novas2 == [], str(novas2))
    with open(fila, encoding="utf-8") as fh:
        n_linhas = sum(1 for _ in fh)
    check("promocao: fila tem exatamente 1 linha apos rodar 2x", n_linhas == 1, "n_linhas=" + str(n_linhas))


def _dias_entre(a, b):
    from datetime import date
    ya, ma, da = [int(x) for x in a.split("-")]
    yb, mb, db = [int(x) for x in b.split("-")]
    return (date(yb, mb, db) - date(ya, ma, da)).days


def main():
    prova_positiva_gate_fail()
    prova_negativa_patterns_real()
    prova_sem_sinal_nao_muda_playbook()
    prova_dedup_task_id()
    prova_teto_respeitado()
    prova_promocao()

    if os.path.exists(SANDBOX):
        shutil.rmtree(SANDBOX)

    print()
    if FAILS:
        print("FAIL: " + str(len(FAILS)) + " prova(s) falharam: " + str(FAILS))
        return 1
    print("PASS: todas as provas do I8 passaram.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
