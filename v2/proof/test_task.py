# -*- coding: utf-8 -*-
"""Prova do I2 (v2/bin/task.py), roda sem rede, so contra COPIA do state.json.

Uso: python test_task.py
Nunca abre o state.json VIVO do estudio para escrita, e (conserto FLAKE, 24/09) nem para hash:
o teste le o conteudo real uma unica vez, no boot, e daí em diante so enxerga um state.json
SENTINELA que ele mesmo cria numa sandbox propria - qualquer sessao aberta em paralelo que
escreva no arquivo vivo do estudio nao derruba mais esta prova.
"""
from __future__ import annotations

import atexit
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
TASK_PY = os.path.join(V2, "bin", "task.py")
def _sandbox_tempdir(prefix: str) -> str:
    """Sandbox de teste SEMPRE fora de v2/ (pasta temporaria do sistema), nunca dentro do
    motor - a origem do vazamento medido pelo CEO (state.json real copiado para dentro de
    v2/proof/_sandbox_task e pego pelo check-public-surface.ps1). Removida no fim do processo
    mesmo se o teste falhar no meio (atexit, nao so no caminho feliz)."""
    d = tempfile.mkdtemp(prefix=prefix)
    atexit.register(shutil.rmtree, d, ignore_errors=True)
    return d
SANDBOX = _sandbox_tempdir("alia-v2-test-task-")
# achar o state.json real: tenta layout de COPIA (v2/ direto na raiz da instancia, um
# nivel acima) primeiro, depois o layout da OFICINA (v2/ dentro de clients/alia-flow-lab/,
# tres niveis acima) - sem isso, o teste so funciona no caminho fixo da oficina e quebra
# ao copiar v2/ para testar em outra instancia (TASK-801 E7, achado da coordenacao).
_STATE_CANDIDATES = [
    os.path.abspath(os.path.join(V2, "..", "state.json")),
    os.path.abspath(os.path.join(V2, "..", "..", "..", "state.json")),
]
_LIVE_STATE = next((p for p in _STATE_CANDIDATES if os.path.exists(p)), None)
FIXTURE_GERADA = _LIVE_STATE is None

# state.json SENTINELA (conserto FLAKE, 24/09): a prova de "nada tocou o state real" nunca mais
# hashea o arquivo VIVO do estudio - qualquer sessao aberta em paralelo escreve nele e derrubava
# o check.py ao acaso (achado do Nexus). O teste le o conteudo real UMA VEZ (copia, nunca escreve)
# para dentro de uma sandbox exclusiva, e esse sentinela vira REAL_STATE para o resto do arquivo -
# nenhuma linha depois desta le ou hasheia o caminho vivo de novo.
_sentinel_dir = _sandbox_tempdir("alia-v2-test-task-sentinel-")
REAL_STATE = os.path.join(_sentinel_dir, "state.json")
if FIXTURE_GERADA:
    # O repositorio publico NUNCA tem state.json de operador (LEI: dado de Client nao versiona -
    # engine/governance/public-surface.md) - sem isto, quem instala do zero via git via a prova
    # falhar (achado do CEO, 24/09/2026, produto 79ed8cb). Fixture minima e sintetica, so com o
    # Client de exemplo publico (acme-saas/acme-pulse, studio.example/), prova o MESMO contrato
    # de task.py sem exigir nenhum dado real de operador.
    _fixture_state = {
        "studio": "Studio Exemplo",
        "clients": [
            {"id": "acme-saas", "squad": {"gateway": "gateway", "specialists": ["bruno", "rex"]}},
        ],
        "tasks": [
            {"id": "TASK-FIXTURE-001", "client": "acme-saas", "project": "acme-pulse",
             "status": "done", "operator_order": True},
        ],
    }
    with open(REAL_STATE, "w", encoding="utf-8") as fh:
        json.dump(_fixture_state, fh, ensure_ascii=False, indent=2)
    print("[INFO] sem state.json de operador (repo publico) - usando fixture sintetica do "
          "Client de exemplo (acme-saas)")
else:
    shutil.copyfile(_LIVE_STATE, REAL_STATE)

FAILS = []


def check(name: str, cond: bool, detail: str = "") -> None:
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {name} {detail}")
    if not cond:
        FAILS.append(name)


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()


def run_task(*args) -> tuple[dict, int]:
    # Ambiente LIMPO: nunca herda CLAUDE_PROJECT_DIR nem ALIA_* do host (achado do CEO,
    # 24/09/2026 - CLAUDE_PROJECT_DIR do studio vivo vazava dado real pro teste em sandbox).
    env = {k: v for k, v in os.environ.items()
           if k != "CLAUDE_PROJECT_DIR" and not k.startswith("ALIA_")}
    # nunca deixa `open` escrever a Task corrente fora da sandbox (lib/paths.py).
    env["ALIA_CURRENT_TASK_PATH"] = os.path.join(SANDBOX, ".alia-current-task.json")
    proc = subprocess.run([sys.executable, TASK_PY, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    out = {}
    if proc.stdout:
        try:
            out = json.loads(proc.stdout.decode("utf-8"))
        except json.JSONDecodeError:
            out = {"_raw": proc.stdout.decode("utf-8", "replace"), "_stderr": proc.stderr.decode("utf-8", "replace")}
    return out, proc.returncode


assert os.path.exists(REAL_STATE), f"state.json nao encontrado nem fixture gerada em {REAL_STATE}"
hash_before = sha256(REAL_STATE)

if os.path.exists(SANDBOX):
    shutil.rmtree(SANDBOX)
os.makedirs(SANDBOX)
COPY = os.path.join(SANDBOX, "state.json")
shutil.copyfile(REAL_STATE, COPY)
LEDGER = os.path.join(SANDBOX, "activity.jsonl")

with open(REAL_STATE, "r", encoding="utf-8") as fh:
    original = json.load(fh)

# Client de teste nunca e um nome real cravado no fonte: escolhido em tempo de execucao a
# partir do proprio state.json usado (real ou o studio.example publico), sem literal aqui.
CLIENTE = sorted(c.get("id") for c in original.get("clients", []) if c.get("id"))[0]
PROJETO_CLIENTE = sorted({
    t.get("project") for t in original.get("tasks", [])
    if t.get("client") == CLIENTE and t.get("project")
})[0]

print("=== I2 prova negativa: campo do checklist faltando ===")
brief_incompleto = json.dumps({"client": CLIENTE, "project": "teste-i2"})
out, rc = run_task("--state", COPY, "open", "--brief", brief_incompleto)
check("open com brief incompleto nao abre Task (ok=False)", out.get("ok") is False, str(out))
check("erro lista o campo que falta", "objetivo" in out.get("faltando", []), str(out.get("faltando")))
check("erro lista Clients validos", CLIENTE in out.get("clients_validos", []), str(out.get("clients_validos")))

print("\n=== I2 prova negativa: client invalido ===")
brief_client_invalido = json.dumps({
    "client": "client-que-nao-existe", "project": "x", "objetivo": "y ate criterio z",
    "paths": "v2/bin/task.py", "consumidor": "WARDEN", "destino": "interno",
    "exemplo_falha": "se nao abrir",
})
out, rc = run_task("--state", COPY, "open", "--brief", brief_client_invalido)
check("client invalido nao abre Task", out.get("ok") is False, str(out))
check("erro lista Clients validos", CLIENTE in out.get("clients_validos", []), str(out.get("clients_validos")))
check("erro lista Projects validos por Client", PROJETO_CLIENTE in out.get("projects_validos", {}).get(CLIENTE, []), str(out.get("projects_validos", {}).get(CLIENTE)))
squad_do_cliente = out.get("squad_valido", {}).get(CLIENTE, [])
check("erro lista squad valido por Client (agente completo client-papel)",
      len(squad_do_cliente) > 0 and all(s.startswith(f"{CLIENTE}-") for s in squad_do_cliente),
      str(squad_do_cliente))

print("\n=== I2 prova negativa (TASK-804): destino fora do enum nao abre ===")
brief_destino_invalido = json.dumps({
    "client": CLIENTE, "project": "teste-i2", "objetivo": "y ate criterio z",
    "paths": "v2/bin/task.py", "consumidor": "WARDEN", "destino": "producao-direto",
    "exemplo_falha": "destino nunca declarado publico nem interno",
})
out, rc = run_task("--state", COPY, "open", "--brief", brief_destino_invalido)
check("destino fora de (publico, interno) nao abre Task", out.get("ok") is False, str(out))
check("erro lista os destinos validos", out.get("destinos_validos") == ["publico", "interno"], str(out.get("destinos_validos")))

print("\n=== I2 prova negativa (TASK-804): fatia de contexto que nao resolve no disco nao abre ===")
TASK_PY_FATIA = TASK_PY.replace("\\", "/")
brief_fatia_invalida = json.dumps({
    "client": CLIENTE, "project": "teste-i2", "objetivo": "y ate criterio z",
    "paths": f"{TASK_PY_FATIA}#L1-99999", "consumidor": "WARDEN", "destino": "interno",
    "exemplo_falha": "fatia pede mais linhas do que o arquivo tem",
})
out, rc = run_task("--state", COPY, "open", "--brief", brief_fatia_invalida)
check("fatia com teto acima de 120 linhas nao abre Task", out.get("ok") is False, str(out))
check("erro nomeia o problema da fatia", any("teto" in p for p in out.get("problemas", [])), str(out.get("problemas")))

brief_fatia_inexistente = json.dumps({
    "client": CLIENTE, "project": "teste-i2", "objetivo": "y ate criterio z",
    "paths": f"{os.path.dirname(TASK_PY_FATIA)}/arquivo-que-nao-existe.py#L1-10", "consumidor": "WARDEN", "destino": "interno",
    "exemplo_falha": "fatia aponta para arquivo inexistente",
})
out, rc = run_task("--state", COPY, "open", "--brief", brief_fatia_inexistente)
check("fatia com arquivo inexistente nao abre Task", out.get("ok") is False, str(out))
check("erro diz que o arquivo nao existe no disco", any("nao existe" in p for p in out.get("problemas", [])), str(out.get("problemas")))

print("\n=== I2 prova positiva (TASK-804): fatia valida (arquivo e faixa reais) abre normalmente ===")
brief_fatia_valida = json.dumps({
    "client": CLIENTE, "project": "teste-i2", "objetivo": "y ate criterio z",
    "paths": f"{TASK_PY_FATIA}#L1-10", "consumidor": "WARDEN", "destino": "interno",
    "exemplo_falha": "fatia real rejeitada por engano",
})
out, rc = run_task("--state", COPY, "open", "--brief", brief_fatia_valida)
check("fatia real (arquivo e faixa existentes) abre a Task", out.get("ok") is True, str(out))

print("\n=== I2 prova positiva: open valido ===")
with open(COPY, "r", encoding="utf-8") as fh:
    copy_before_open = json.load(fh)
n_tasks_before = len(copy_before_open["tasks"])

brief_ok = json.dumps({
    "client": CLIENTE, "project": "teste-i2", "objetivo": "provar o task.py ate fechar com veredito",
    "paths": "v2/bin/task.py", "consumidor": "WARDEN", "destino": "interno",
    "exemplo_falha": "abrir Task sem os 6 campos",
})
out, rc = run_task("--state", COPY, "open", "--brief", brief_ok)
check("open com brief completo abre Task (ok=True)", out.get("ok") is True, str(out))
new_id = (out.get("task") or {}).get("id")
check("Task nova recebe risco (funcao pura de flow/risk.py)", (out.get("task") or {}).get("risco") in ("R1", "R2"), str(out.get("task")))
check("Task nova recebe modo (direto, sem 2+ frentes no brief)", (out.get("task") or {}).get("modo") == "direto", str(out.get("task")))

print("\n=== I2 prova negativa: close sem veredito ===")
out, rc = run_task("--state", COPY, "close", "--id", new_id, "--artifact", "x.md")
check("close sem --veredito nao fecha", out.get("ok") is False, str(out))

print("\n=== I2 prova negativa (TASK-804): close sem evidencia de veredito no ledger nao fecha ===")
with open(LEDGER, "w", encoding="utf-8") as fh:
    fh.write(json.dumps({"event": "post_agent", "task_id": new_id, "tokens_total": 12345, "agent_id": "a1"}) + "\n")
out, rc = run_task("--state", COPY, "close", "--id", new_id, "--artifact", "v2/proof/test_task.py",
                    "--veredito", "PASS", "--ledger", LEDGER)
check("close com veredito digitado mas sem review_verdict/gate_check no ledger nao fecha (autocertificacao morre aqui)",
      out.get("ok") is False, str(out))

print("\n=== I2 prova positiva: close valido soma custo do ledger e exige evidencia ===")
with open(LEDGER, "w", encoding="utf-8") as fh:
    fh.write(json.dumps({"event": "post_agent", "task_id": new_id, "tokens_total": 12345, "agent_id": "a1"}) + "\n")
    fh.write(json.dumps({"event": "post_agent", "task_id": new_id, "tokens_total": 678, "agent_id": "a2"}) + "\n")
    fh.write(json.dumps({"event": "post_agent", "task_id": "TASK-999-outra", "tokens_total": 99999, "agent_id": "a3"}) + "\n")
    fh.write(json.dumps({"event": "review_verdict", "task_id": new_id, "revisor": "WARDEN", "veredito": "PASS"}) + "\n")
out, rc = run_task("--state", COPY, "close", "--id", new_id, "--artifact", "v2/proof/test_task.py",
                    "--veredito", "PASS", "--ledger", LEDGER)
check("close valido fecha Task (ok=True)", out.get("ok") is True, str(out))
check("custo somado so das linhas desta Task (12345+678=13023, nao 99999)", out.get("custo_somado_do_ledger") == 13023, str(out.get("custo_somado_do_ledger")))
check("Task fechada muda status para done (veredito PASS)", (out.get("task") or {}).get("status") == "done", str(out.get("task")))
check("Task fechada registra a fonte da evidencia de veredito", (out.get("task") or {}).get("evidencia_veredito") == "ledger_review", str(out.get("task")))

print("\n=== I2 prova negativa (TASK-804): Task done nao reabre por cima ===")
out, rc = run_task("--state", COPY, "close", "--id", new_id, "--artifact", "v2/proof/test_task.py",
                    "--veredito", "PASS", "--ledger", LEDGER)
check("close de Task ja done nao reabre por cima", out.get("ok") is False, str(out))

print("\n=== I2 prova negativa: Task de correcao sem root_cause ===")
brief_correcao = json.dumps({
    "client": CLIENTE, "project": "teste-i2", "objetivo": "corrige o defeito medido",
    "paths": "v2/bin/task.py", "consumidor": "WARDEN", "destino": "interno",
    "exemplo_falha": "fechar sem causa raiz", "type": "correcao",
})
out, rc = run_task("--state", COPY, "open", "--brief", brief_correcao)
correcao_id = (out.get("task") or {}).get("id")
check("Task de correcao abre normalmente", out.get("ok") is True, str(out))
LEDGER_CORRECAO = os.path.join(SANDBOX, "activity-correcao.jsonl")
with open(LEDGER_CORRECAO, "w", encoding="utf-8") as fh:
    fh.write(json.dumps({"event": "gate_check", "task_id": correcao_id, "resultado": "PASS"}) + "\n")
out, rc = run_task("--state", COPY, "close", "--id", correcao_id, "--artifact", "x.md", "--veredito", "PASS",
                    "--ledger", LEDGER_CORRECAO)
check("close de Task de correcao sem --root-cause nao fecha", out.get("ok") is False, str(out))
out, rc = run_task("--state", COPY, "close", "--id", correcao_id, "--artifact", "x.md", "--veredito", "PASS",
                    "--root-cause", "a causa raiz medida pelos 5 porques", "--ledger", LEDGER_CORRECAO)
check("close de Task de correcao com --root-cause fecha (evidencia = gate_check)", out.get("ok") is True, str(out))
check("evidencia registrada veio do gate_check", (out.get("task") or {}).get("evidencia_veredito") == "gate_check", str(out.get("task")))

print("\n=== I2 prova negativa (TASK-825/826 B3): review_verdict PASS antes + gate_check FAIL depois no "
      "ledger - close PASS e recusado (o mais recente vence, nao so quem apareceu primeiro) ===")
brief_ordem = json.dumps({
    "client": CLIENTE, "project": "teste-i2", "objetivo": "prova a ordem review_verdict depois gate_check",
    "paths": "v2/lib/task_model.py", "consumidor": "WARDEN", "destino": "interno",
    "exemplo_falha": "review_verdict velho autoriza close por cima de gate_check mais novo",
})
out, rc = run_task("--state", COPY, "open", "--brief", brief_ordem)
check("Task da prova de ordem abre normalmente", out.get("ok") is True, str(out))
ordem_id = (out.get("task") or {}).get("id")
LEDGER_ORDEM = os.path.join(SANDBOX, "activity-ordem.jsonl")
with open(LEDGER_ORDEM, "w", encoding="utf-8") as fh:
    fh.write(json.dumps({"event": "review_verdict", "task_id": ordem_id, "revisor": "WARDEN", "veredito": "PASS"}) + "\n")
    fh.write(json.dumps({"event": "gate_check", "task_id": ordem_id, "veredito": "FAIL"}) + "\n")
out_ordem, rc_ordem = run_task("--state", COPY, "close", "--id", ordem_id, "--artifact", "x.md",
                                "--veredito", "PASS", "--ledger", LEDGER_ORDEM)
check("close PASS e recusado: gate_check MAIS RECENTE diverge, mesmo com review_verdict PASS mais antigo no ledger",
      out_ordem.get("ok") is False, str(out_ordem))

print("\n=== I2 prova negativa (TASK-804): close com veredito FAIL grava o criterio reprovado ===")
brief_fail = json.dumps({
    "client": CLIENTE, "project": "teste-i2", "objetivo": "Task que vai reprovar de proposito",
    "paths": "v2/bin/task.py", "consumidor": "WARDEN", "destino": "interno",
    "exemplo_falha": "gate nunca registra o criterio",
})
out, rc = run_task("--state", COPY, "open", "--brief", brief_fail)
fail_id = (out.get("task") or {}).get("id")
LEDGER_FAIL = os.path.join(SANDBOX, "activity-fail.jsonl")
with open(LEDGER_FAIL, "w", encoding="utf-8") as fh:
    fh.write(json.dumps({"event": "review_verdict", "task_id": fail_id, "veredito": "FAIL"}) + "\n")
out, rc = run_task("--state", COPY, "close", "--id", fail_id, "--artifact", "x.md", "--veredito", "FAIL",
                    "--criterio-reprovado", "prova pelo negativo ausente", "--ledger", LEDGER_FAIL)
check("close com FAIL fecha (status vira review, nao done)", out.get("ok") is True, str(out))
check("Task fica em review, nao done, quando o veredito e FAIL", (out.get("task") or {}).get("status") == "review", str(out.get("task")))
check("criterio reprovado fica gravado na Task", (out.get("task") or {}).get("gate_criteria_failed") == ["prova pelo negativo ausente"], str(out.get("task")))

print("\n=== I2 prova positiva: context le a continuidade sem mutar ===")
hash_copy_before_context = sha256(COPY)
out, rc = run_task("--state", COPY, "context", "--id", new_id)
check("context devolve a Task", (out.get("task") or {}).get("id") == new_id, str(out))
check("context nunca muta a copia (hash igual)", sha256(COPY) == hash_copy_before_context, "hash antes/depois de context")

print("\n=== I2 prova negativa: context de Task inexistente ===")
out, rc = run_task("--state", COPY, "context", "--id", "TASK-999999")
check("context de id inexistente da erro", out.get("ok") is False, str(out))

print("\n=== I2 prova: diff da copia so acrescenta campos/Tasks novas ===")
with open(COPY, "r", encoding="utf-8") as fh:
    copy_after = json.load(fh)
check("clients da copia identicos ao original (nunca reescritos)", copy_after["clients"] == original["clients"], "diff em clients")
old_tasks_by_id = {t["id"]: t for t in original["tasks"]}
new_tasks_by_id = {t["id"]: t for t in copy_after["tasks"]}
unchanged_ok = all(new_tasks_by_id.get(tid) == t for tid, t in old_tasks_by_id.items())
check("nenhuma Task pre-existente foi alterada", unchanged_ok, "diff em Tasks antigas")
added_ids = set(new_tasks_by_id) - set(old_tasks_by_id)
check("so 5 Tasks novas acrescentadas (teste-i2, a de correcao, a de FAIL, a de fatia valida e a de ordem review/gate)", len(added_ids) == 5, str(added_ids))
check("Task nova tem status done (fechada com PASS)", new_tasks_by_id[new_id]["status"] == "done", str(new_tasks_by_id[new_id]))

print("\n=== I2 prova: sentinela nunca tocado (hash igual antes/depois de tudo) ===")
hash_after = sha256(REAL_STATE)
check("hash do state.json sentinela igual antes e depois de toda a bateria", hash_before == hash_after,
      f"antes={hash_before[:12]} depois={hash_after[:12]}")

print("\n=== I2 prova negativa (conserto FLAKE): escrever no sentinela muda o hash - o mecanismo "
      "pegaria a escrita indevida se ela acontecesse de verdade ===")
with open(REAL_STATE, "r", encoding="utf-8") as fh:
    _bytes_sentinela_intacto = fh.read()
with open(REAL_STATE, "a", encoding="utf-8") as fh:
    fh.write("\n")  # simula codigo escrevendo no sentinela por engano
hash_sentinela_sujo = sha256(REAL_STATE)
check("sentinela alterado diverge do hash limpo (a escrita indevida seria pega)",
      hash_sentinela_sujo != hash_after, f"limpo={hash_after[:12]} sujo={hash_sentinela_sujo[:12]}")
with open(REAL_STATE, "w", encoding="utf-8") as fh:
    fh.write(_bytes_sentinela_intacto)  # desfaz a escrita, sentinela volta ao estado provado acima
check("sentinela restaurado volta ao hash limpo (PASS de volta)", sha256(REAL_STATE) == hash_after, "")

# ---------------------------------------------------------------------------
# TASK-825: o produtor v2/bin/gate.py - valida o parecer contra o contrato do gate (6
# criterios + goal-backward) e grava o evento gate_check que task.py close exige.
GATE_PY = os.path.join(V2, "bin", "gate.py")
ROTULOS_GATE = ("funciona", "aderente-ddd", "frugal", "rastreavel", "simplicidade",
                "fundamentada", "goal-backward")


def run_gate(*args) -> tuple[dict, int]:
    env = {k: v for k, v in os.environ.items()
           if k != "CLAUDE_PROJECT_DIR" and not k.startswith("ALIA_")}
    proc = subprocess.run([sys.executable, GATE_PY, *args], stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, env=env)
    out = {}
    if proc.stdout:
        try:
            out = json.loads(proc.stdout.decode("utf-8"))
        except json.JSONDecodeError:
            out = {"_raw": proc.stdout.decode("utf-8", "replace"), "_stderr": proc.stderr.decode("utf-8", "replace")}
    return out, proc.returncode


def _parecer(veredito: str, excluir: tuple = ()) -> str:
    """Parecer de gate minimo e valido: os 7 rotulos (6 criterios + goal-backward), cada um
    com resultado PASS e uma linha de evidencia logo abaixo, mais a linha de veredito."""
    linhas = []
    for rotulo in ROTULOS_GATE:
        if rotulo in excluir:
            continue
        linhas.append(f"{rotulo}: PASS")
        linhas.append(f"evidencia: [MEDIDO fixture de teste do gate.py, criterio {rotulo}]")
    linhas.append(f"veredito: {veredito}")
    return "\n".join(linhas) + "\n"


print("\n=== I5 (gate.py) prova positiva: parecer valido grava gate_check e close passa ===")
brief_gate = json.dumps({
    "client": CLIENTE, "project": "teste-gate", "objetivo": "provar o gate.py ate fechar com veredito",
    "paths": "v2/bin/gate.py", "consumidor": "WARDEN", "destino": "interno",
    "exemplo_falha": "fechar sem passar pelo gate.py",
})
out, rc = run_task("--state", COPY, "open", "--brief", brief_gate)
check("Task para o teste do gate.py abre normalmente", out.get("ok") is True, str(out))
gate_task_id = (out.get("task") or {}).get("id")

PARECER_VALIDO = os.path.join(SANDBOX, "parecer_valido.md")
with open(PARECER_VALIDO, "w", encoding="utf-8") as fh:
    fh.write(_parecer("PASS"))
LEDGER_GATE = os.path.join(SANDBOX, "activity-gate.jsonl")
out_gate, rc_gate = run_gate("--task", gate_task_id, "--parecer", PARECER_VALIDO,
                              "--session", "s-gate", "--ledger", LEDGER_GATE)
check("gate.py com parecer valido grava o evento (ok=True)", out_gate.get("ok") is True, str(out_gate))
with open(LEDGER_GATE, "r", encoding="utf-8") as fh:
    eventos_gate = [json.loads(l) for l in fh if l.strip()]
check("exatamente 1 evento gate_check gravado", len(eventos_gate) == 1 and eventos_gate[0].get("event") == "gate_check",
      str(eventos_gate))
check("evento gate_check tem os 7 rotulos de criterio",
      len(eventos_gate[0].get("criterios", {})) == 7, str(eventos_gate[0].get("criterios")))

out_close, rc_close = run_task("--state", COPY, "close", "--id", gate_task_id, "--artifact", "v2/bin/gate.py",
                                "--veredito", "PASS", "--ledger", LEDGER_GATE)
check("close com evidencia vinda do gate.py fecha a Task (ok=True)", out_close.get("ok") is True, str(out_close))
check("Task fechada tem status done", (out_close.get("task") or {}).get("status") == "done", str(out_close.get("task")))

print("\n=== I5 prova negativa: rotulo faltando no parecer nao grava evento ===")
PARECER_SEM_ROTULO = os.path.join(SANDBOX, "parecer_sem_rotulo.md")
with open(PARECER_SEM_ROTULO, "w", encoding="utf-8") as fh:
    fh.write(_parecer("PASS", excluir=("frugal",)))
LEDGER_GATE_ROTULO = os.path.join(SANDBOX, "activity-gate-rotulo.jsonl")
out_rotulo, rc_rotulo = run_gate("--task", gate_task_id, "--parecer", PARECER_SEM_ROTULO, "--ledger", LEDGER_GATE_ROTULO)
check("gate.py recusa parecer sem o rotulo 'frugal' (ok=False)", out_rotulo.get("ok") is False, str(out_rotulo))
check("mensagem cita o criterio ausente", any("frugal" in p for p in out_rotulo.get("problemas", [])),
      str(out_rotulo.get("problemas")))
check("nenhum evento gravado (arquivo de ledger nem chega a existir)", not os.path.exists(LEDGER_GATE_ROTULO), "")

print("\n=== I5 prova negativa: travessao no parecer nao grava evento ===")
PARECER_TRAVESSAO = os.path.join(SANDBOX, "parecer_travessao.md")
with open(PARECER_TRAVESSAO, "w", encoding="utf-8") as fh:
    fh.write(_parecer("PASS") + "nota" + chr(0x2014) + "texto com travessao\n")
LEDGER_GATE_TRAV = os.path.join(SANDBOX, "activity-gate-travessao.jsonl")
out_trav, rc_trav = run_gate("--task", gate_task_id, "--parecer", PARECER_TRAVESSAO, "--ledger", LEDGER_GATE_TRAV)
check("gate.py recusa parecer com travessao (ok=False)", out_trav.get("ok") is False, str(out_trav))
check("mensagem cita o travessao", any("travessao" in p for p in out_trav.get("problemas", [])),
      str(out_trav.get("problemas")))
check("nenhum evento gravado", not os.path.exists(LEDGER_GATE_TRAV), "")

print("\n=== I5 prova negativa (TASK-825/826 B2): criterio FAIL com veredito PASS e recusado ===")


def _parecer_com_valores(valores: dict, veredito: str) -> str:
    """Mesmo formato de _parecer, mas com o valor por rotulo customizado (default PASS)."""
    linhas = []
    for rotulo in ROTULOS_GATE:
        linhas.append(f"{rotulo}: {valores.get(rotulo, 'PASS')}")
        linhas.append(f"evidencia: [MEDIDO fixture de teste do gate.py, criterio {rotulo}]")
    linhas.append(f"veredito: {veredito}")
    return "\n".join(linhas) + "\n"


PARECER_CRITERIO_FAIL_VEREDITO_PASS = os.path.join(SANDBOX, "parecer_criterio_fail_veredito_pass.md")
with open(PARECER_CRITERIO_FAIL_VEREDITO_PASS, "w", encoding="utf-8") as fh:
    fh.write(_parecer_com_valores({"frugal": "FAIL"}, "PASS"))
LEDGER_GATE_CFVP = os.path.join(SANDBOX, "activity-gate-cfvp.jsonl")
out_cfvp, rc_cfvp = run_gate("--task", gate_task_id, "--parecer", PARECER_CRITERIO_FAIL_VEREDITO_PASS, "--ledger", LEDGER_GATE_CFVP)
check("gate.py recusa parecer com criterio 'frugal' FAIL e veredito PASS (ok=False)", out_cfvp.get("ok") is False, str(out_cfvp))
check("nenhum evento gravado (parecer com FAIL disfarcado de PASS nunca vira gate_check)", not os.path.exists(LEDGER_GATE_CFVP), "")

print("\n=== I5 prova negativa (TASK-825/826 B2): criterio CONCERN com veredito PASS e recusado ===")
PARECER_CONCERN_VEREDITO_PASS = os.path.join(SANDBOX, "parecer_concern_veredito_pass.md")
with open(PARECER_CONCERN_VEREDITO_PASS, "w", encoding="utf-8") as fh:
    fh.write(_parecer_com_valores({"rastreavel": "CONCERN"}, "PASS"))
LEDGER_GATE_CCVP = os.path.join(SANDBOX, "activity-gate-ccvp.jsonl")
out_ccvp, rc_ccvp = run_gate("--task", gate_task_id, "--parecer", PARECER_CONCERN_VEREDITO_PASS, "--ledger", LEDGER_GATE_CCVP)
check("gate.py recusa parecer com criterio 'rastreavel' CONCERN e veredito PASS (ok=False)", out_ccvp.get("ok") is False, str(out_ccvp))
check("nenhum evento gravado (CONCERN nunca vira PASS)", not os.path.exists(LEDGER_GATE_CCVP), "")

print("\n=== I5 prova negativa: close sem nenhum evento no ledger continua falhando ===")
brief_gate2 = json.dumps({
    "client": CLIENTE, "project": "teste-gate", "objetivo": "Task que vai testar veredito divergente do gate_check",
    "paths": "v2/bin/gate.py", "consumidor": "WARDEN", "destino": "interno",
    "exemplo_falha": "fechar sem qualquer evidencia no ledger",
})
out, rc = run_task("--state", COPY, "open", "--brief", brief_gate2)
gate_task_id2 = (out.get("task") or {}).get("id")
LEDGER_GATE_VAZIO = os.path.join(SANDBOX, "activity-gate-vazio.jsonl")
out_sem_evento, rc_sem_evento = run_task("--state", COPY, "close", "--id", gate_task_id2, "--artifact", "x.md",
                                          "--veredito", "PASS", "--ledger", LEDGER_GATE_VAZIO)
check("close sem evento algum no ledger continua falhando", out_sem_evento.get("ok") is False, str(out_sem_evento))

print("\n=== I5 prova negativa: veredito digitado divergente do gate_check mais recente e recusado ===")
PARECER_FAIL = os.path.join(SANDBOX, "parecer_fail.md")
with open(PARECER_FAIL, "w", encoding="utf-8") as fh:
    fh.write(_parecer("FAIL"))
LEDGER_GATE_FAIL = os.path.join(SANDBOX, "activity-gate-fail.jsonl")
out_gate_fail, rc_gate_fail = run_gate("--task", gate_task_id2, "--parecer", PARECER_FAIL, "--ledger", LEDGER_GATE_FAIL)
check("gate.py grava gate_check com veredito FAIL",
      out_gate_fail.get("ok") is True and out_gate_fail.get("event", {}).get("veredito") == "FAIL", str(out_gate_fail))

out_divergente, rc_divergente = run_task("--state", COPY, "close", "--id", gate_task_id2, "--artifact", "x.md",
                                          "--veredito", "PASS", "--ledger", LEDGER_GATE_FAIL)
check("close com --veredito PASS divergente do gate_check FAIL e recusado", out_divergente.get("ok") is False,
      str(out_divergente))

out_convergente, rc_convergente = run_task("--state", COPY, "close", "--id", gate_task_id2, "--artifact", "x.md",
                                            "--veredito", "FAIL", "--criterio-reprovado", "frugal",
                                            "--ledger", LEDGER_GATE_FAIL)
check("close com --veredito FAIL igual ao gate_check fecha (Task vai para review)",
      out_convergente.get("ok") is True, str(out_convergente))
check("Task fica em review (veredito FAIL nunca fecha done)",
      (out_convergente.get("task") or {}).get("status") == "review", str(out_convergente.get("task")))

print("\n=== resultado ===")
if FAILS:
    print(f"FALHOU: {len(FAILS)} prova(s): {FAILS}")
    sys.exit(1)
print("TODAS AS PROVAS PASSARAM")
