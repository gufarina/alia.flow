#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""passagem.py - gera a passagem de 1 pagina (TASK-804).

Fonte: o PLANO (arquivo .md com a secao "Proxima tarefa"), o LEDGER (activity.jsonl) e as
Tasks ABERTAS (state.json) - nunca a conversa. E o mesmo formato de
artifacts/coordination/PASSAGEM-alia-2.0.md, gerado por script em vez de reescrito a mao:
evita a releitura que mediu 75% do gasto da coordenadora numa sessao so (mesma Task).

Uso:
    python passagem.py --plano <arquivo.md> --state <state.json> --ledger <activity.jsonl>
                        --titulo "Alia 2.0" --out <pasta artifacts/coordination>

--plano e opcional (sem ele, a secao "Proxima tarefa" sai [FALTA]). --state e --ledger sao
opcionais (sem eles, a secao correspondente sai vazia com aviso). Teto de 1 pagina: 6.000
bytes (mesmo teto do kernel, v2/proof/check.py) - listas grandes sao cortadas com contagem
do que ficou de fora.

Saida: escreve `PASSAGEM-<slug>-<data>.md` em --out e imprime 1 objeto JSON em stdout com
o path e o tamanho. Sem --out, so imprime o markdown em stdout (nao escreve arquivo).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time

TETO_BYTES = 6000
TETO_TASKS_ABERTAS = 15
TETO_EVENTOS_LEDGER = 8

SECAO_RE = re.compile(r"^##\s*Pr[oó]xima tarefa.*$", re.IGNORECASE | re.MULTILINE)


def _ler_texto(path: str | None) -> str | None:
    if not path or not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def extrair_proxima_tarefa(plano_texto: str | None) -> str:
    if not plano_texto:
        return "[FALTA] nenhum --plano informado ou arquivo nao encontrado."
    m = SECAO_RE.search(plano_texto)
    if not m:
        return "[FALTA] plano nao tem secao '## Proxima tarefa'."
    inicio = m.start()
    resto = plano_texto[m.end():]
    prox = re.search(r"^##\s", resto, re.MULTILINE)
    fim = m.end() + (prox.start() if prox else len(resto))
    return plano_texto[inicio:fim].strip()


def tasks_abertas(state_path: str | None) -> list[dict]:
    if not state_path or not os.path.isfile(state_path):
        return []
    with open(state_path, "r", encoding="utf-8") as fh:
        state = json.load(fh)
    return [t for t in state.get("tasks", []) if t.get("status") == "open"]


def resumo_ledger(ledger_path: str | None) -> dict:
    if not ledger_path or not os.path.isfile(ledger_path):
        return {"total": 0, "por_evento": {}, "ultimos": []}
    por_evento: dict[str, int] = {}
    ultimos: list[dict] = []
    total = 0
    with open(ledger_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                ev = json.loads(raw)
            except json.JSONDecodeError:
                continue
            total += 1
            nome = ev.get("event", "?")
            por_evento[nome] = por_evento.get(nome, 0) + 1
            ultimos.append(ev)
    return {"total": total, "por_evento": por_evento, "ultimos": ultimos[-TETO_EVENTOS_LEDGER:]}


def _linha_task(t: dict) -> str:
    titulo = t.get("objetivo") or t.get("title") or "(sem titulo)"
    if len(titulo) > 90:
        titulo = titulo[:87] + "..."
    return f"- {t.get('id', '?')}: {titulo} ({t.get('client', '?')}/{t.get('project', '?')}, dono: {t.get('specialist', '?')})"


def _linha_evento(ev: dict) -> str:
    return f"- {ev.get('event', '?')} | task={ev.get('task_id', '-')} | agente={ev.get('agent_id', ev.get('specialist', '-'))}"


def montar_markdown(titulo: str, proxima_tarefa: str, tasks: list[dict], ledger: dict) -> str:
    data = time.strftime("%Y-%m-%d")
    linhas = [
        f"# Passagem: {titulo}, {data}",
        "",
        "Leia so isto para continuar. Gerado por v2/bin/passagem.py a partir do plano, do "
        "ledger e das Tasks abertas - nunca da conversa.",
        "",
        proxima_tarefa,
        "",
        f"## Tasks abertas ({len(tasks)})",
    ]
    mostrar = tasks[:TETO_TASKS_ABERTAS]
    linhas += [_linha_task(t) for t in mostrar]
    if len(tasks) > TETO_TASKS_ABERTAS:
        linhas.append(f"- (+{len(tasks) - TETO_TASKS_ABERTAS} Task(s) aberta(s) fora do corte, ver state.json)")
    linhas.append("")
    linhas.append(f"## Ledger (resumo, {ledger['total']} evento(s))")
    for nome, qtd in sorted(ledger["por_evento"].items(), key=lambda kv: -kv[1]):
        linhas.append(f"- {nome}: {qtd}")
    if ledger["ultimos"]:
        linhas.append("")
        linhas.append(f"Ultimos {len(ledger['ultimos'])} evento(s):")
        linhas += [_linha_evento(ev) for ev in ledger["ultimos"]]
    texto = "\n".join(linhas) + "\n"

    if len(texto.encode("utf-8")) > TETO_BYTES:
        cortado = texto.encode("utf-8")[:TETO_BYTES].decode("utf-8", errors="ignore")
        texto = cortado + f"\n\n[CORTADO em {TETO_BYTES} bytes - abra state.json/ledger para o resto]\n"
    return texto


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--plano", help="arquivo .md com a secao '## Proxima tarefa'")
    p.add_argument("--state", help="state.json (para as Tasks abertas)")
    p.add_argument("--ledger", help="activity.jsonl (para o resumo de eventos)")
    p.add_argument("--titulo", default="Alia 2.0", help="titulo da passagem")
    p.add_argument("--out", help="pasta de destino (ex.: artifacts/coordination); sem isto, so imprime")
    return p


def main() -> int:
    args = build_parser().parse_args()

    proxima_tarefa = extrair_proxima_tarefa(_ler_texto(args.plano))
    tasks = tasks_abertas(args.state)
    ledger = resumo_ledger(args.ledger)
    markdown = montar_markdown(args.titulo, proxima_tarefa, tasks, ledger)

    if not args.out:
        sys.stdout.write(markdown)
        return 0

    slug = re.sub(r"[^a-z0-9]+", "-", args.titulo.lower()).strip("-") or "passagem"
    data = time.strftime("%Y-%m-%d")
    nome = f"PASSAGEM-{slug}-{data}.md"
    os.makedirs(args.out, exist_ok=True)
    caminho = os.path.join(args.out, nome)
    with open(caminho, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(markdown)

    resultado = {"ok": True, "path": caminho, "bytes": len(markdown.encode("utf-8")),
                 "tasks_abertas": len(tasks), "eventos_ledger": ledger["total"]}
    print(json.dumps(resultado, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
