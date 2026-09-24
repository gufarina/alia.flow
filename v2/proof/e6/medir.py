# -*- coding: utf-8 -*-
"""medir.py - gasto REAL de um sub-agente, lido do proprio transcript (E6, TASK-801).

Por que existe: [MEDIDO pela coordenacao, 23/09] o campo que o PostToolUse do Agent devolve
(subagent_tokens) e o TAMANHO DO CONTEXTO no ultimo turno (quanto o sub-agente tinha na cabeca
naquele momento), nao o GASTO acumulado da chamada inteira. E o mesmo defeito, por outra porta,
que gerou os 78.504.999 tokens identicos de TASK-565/TASK-569 (e6-linha-de-base.md): ler um
numero que representa "tamanho agora" como se fosse "soma de tudo que foi cobrado".

O gasto real mora no transcript do proprio sub-agente
(<projeto>/subagents/agent-<id>.jsonl). Cada mensagem do assistente pode aparecer em VARIAS
linhas do jsonl (streaming: a API manda deltas parciais antes do total final) - por isso este
script agrupa por id de mensagem (`message.id`) e pega o MAIOR valor de cada categoria
(input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens) antes de
somar entre mensagens, nunca soma toda linha do jsonl direto (isso contaria o delta parcial E o
total final como se fossem 2 cobrancas).

Uso:
    python medir.py <agent_id> [<agent_id> ...] --dir <pasta subagents>
    python medir.py --dir <pasta subagents> --all

Pesos do equivalente em tokens de entrada (pedido da coordenacao, 23/09): cache lido a 10%,
cache escrito (cache_creation) a 125%, saida a 5x, entrada (input_tokens) a 1x - aproxima o custo
real de cada categoria ao preco de um token de entrada comum, para comparar 1.84 e 2.0 na mesma
unidade.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import statistics
from datetime import datetime, timezone

PESO_CACHE_LIDO = 0.10
PESO_CACHE_ESCRITO = 1.25
PESO_SAIDA = 5.0
PESO_ENTRADA = 1.0


def _parse_ts(raw: str):
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except Exception:
        return None


def gasto_real(path: str) -> dict:
    """Le 1 transcript e devolve o gasto real por categoria, chamadas e tempo.

    Categoria = MAIOR valor visto por `message.id` (evita contar delta parcial + total
    final como 2 cobrancas). Chamadas = quantidade de blocos `tool_use` no conteudo do
    assistente. Tempo = diferenca entre o primeiro e o ultimo timestamp do arquivo.
    """
    por_msg: dict[str, dict] = {}
    tool_uses = 0
    primeiro_ts = None
    ultimo_ts = None
    linhas_lidas = 0
    linhas_invalidas = 0

    if not os.path.isfile(path):
        raise FileNotFoundError(path)

    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            linhas_lidas += 1
            try:
                ev = json.loads(raw)
            except json.JSONDecodeError:
                linhas_invalidas += 1
                continue

            ts = _parse_ts(ev.get("timestamp", "")) if ev.get("timestamp") else None
            if ts is not None:
                if primeiro_ts is None or ts < primeiro_ts:
                    primeiro_ts = ts
                if ultimo_ts is None or ts > ultimo_ts:
                    ultimo_ts = ts

            msg = ev.get("message")
            if not isinstance(msg, dict):
                continue

            content = msg.get("content")
            if isinstance(content, list):
                for bloco in content:
                    if isinstance(bloco, dict) and bloco.get("type") == "tool_use":
                        tool_uses += 1

            usage = msg.get("usage")
            msg_id = msg.get("id")
            if not usage or not msg_id:
                continue

            atual = por_msg.setdefault(msg_id, {
                "input_tokens": 0, "output_tokens": 0,
                "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0,
            })
            for campo in atual:
                valor = usage.get(campo) or 0
                if valor > atual[campo]:
                    atual[campo] = valor

    total = {"input_tokens": 0, "output_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}
    for valores in por_msg.values():
        for campo in total:
            total[campo] += valores[campo]

    tempo_ms = None
    if primeiro_ts is not None and ultimo_ts is not None:
        tempo_ms = (ultimo_ts - primeiro_ts).total_seconds() * 1000

    return {
        "path": path,
        "mensagens_distintas": len(por_msg),
        "linhas_lidas": linhas_lidas,
        "linhas_invalidas": linhas_invalidas,
        "tool_uses": tool_uses,
        "tempo_ms": tempo_ms,
        **total,
    }


def equivalente_entrada(gasto: dict) -> float:
    """Soma ponderada das 4 categorias na unidade de 'token de entrada comum'."""
    return (
        gasto["input_tokens"] * PESO_ENTRADA
        + gasto["output_tokens"] * PESO_SAIDA
        + gasto["cache_creation_input_tokens"] * PESO_CACHE_ESCRITO
        + gasto["cache_read_input_tokens"] * PESO_CACHE_LIDO
    )


def medir_agente(agent_id: str, pasta: str) -> dict:
    nome = agent_id if agent_id.startswith("agent-") else f"agent-{agent_id}"
    if not nome.endswith(".jsonl"):
        nome += ".jsonl"
    path = os.path.join(pasta, nome)
    gasto = gasto_real(path)
    gasto["agent_id"] = agent_id
    gasto["equivalente_entrada"] = round(equivalente_entrada(gasto), 1)
    return gasto


def _fmt(gasto: dict) -> str:
    return (
        f"[MEDIDO] {gasto['agent_id']}: input={gasto['input_tokens']} output={gasto['output_tokens']} "
        f"cache_escrito={gasto['cache_creation_input_tokens']} cache_lido={gasto['cache_read_input_tokens']} "
        f"| equivalente_entrada={gasto['equivalente_entrada']} tok | chamadas={gasto['tool_uses']} "
        f"| tempo={gasto['tempo_ms']:.0f} ms | mensagens={gasto['mensagens_distintas']} "
        f"(linhas={gasto['linhas_lidas']}, invalidas={gasto['linhas_invalidas']})"
    )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("agent_ids", nargs="*", help="id do agente (com ou sem prefixo agent-/.jsonl)")
    ap.add_argument("--dir", required=True, help="pasta subagents/ do transcript da sessao")
    ap.add_argument("--all", action="store_true", help="mede todos os agent-*.jsonl da pasta")
    args = ap.parse_args()

    ids = list(args.agent_ids)
    if args.all:
        ids = [
            os.path.basename(p)[len("agent-"):-len(".jsonl")]
            for p in sorted(glob.glob(os.path.join(args.dir, "agent-*.jsonl")))
        ]
    if not ids:
        ap.error("informe pelo menos 1 agent_id ou use --all")

    resultados = []
    for aid in ids:
        try:
            g = medir_agente(aid, args.dir)
        except FileNotFoundError as exc:
            print(f"[ERRO] transcript nao encontrado: {exc}")
            continue
        resultados.append(g)
        print(_fmt(g))

    if len(resultados) > 1:
        eqs = [r["equivalente_entrada"] for r in resultados]
        print(f"\n[MEDIDO] {len(resultados)} agentes | mediana equivalente_entrada={statistics.median(eqs):.1f} tok")


if __name__ == "__main__":
    main()
