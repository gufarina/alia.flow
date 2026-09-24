#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""contexto.py - contexto da COORDENADORA, lido do proprio transcript (TASK-804).

Por que existe: 5 porques medidos em PASSAGEM-alia-2.0.md (23/09) - a coordenadora
terminou uma sessao com 585 mil tokens de contexto e 75% do gasto foi RELEITURA (8,5 de
11,3 milhoes de tokens equivalentes). Ninguem media o contexto da propria coordenadora em
tempo real; so o do sub-agente (v2/proof/e6/medir.py). Este script e o mesmo principio
aplicado ao transcript PRINCIPAL da sessao (nao ao subagents/agent-<id>.jsonl).

Duas medidas, nunca confundir (mesmo alerta do medir.py):
  - "contexto da ultima chamada": quanto a coordenadora tinha na cabeca no ULTIMO turno
    (input + cache_lido + cache_escrito da mensagem mais recente do assistente). E o que
    decide se estourou o teto AGORA.
  - "gasto acumulado": soma de TODAS as mensagens distintas da sessao (reusa
    proof/e6/medir.gasto_real, que agrupa por message.id e pega o maior valor de cada
    categoria antes de somar - evita contar delta parcial de streaming e total final como
    2 cobrancas). E quanto a sessao custou ate aqui, nunca o numero para decidir o teto.

Uso:
    python contexto.py <transcript.jsonl> [--teto 150000]

Sai 1 objeto JSON em stdout. Acima do teto (v2/AGENTS.md: 150 mil), imprime tambem o
aviso [MEDIDO] de que e hora de gerar passagem (bin/passagem.py) e comecar conversa nova.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(V2, "proof", "e6"))
import medir  # noqa: E402  (v2/proof/e6/medir.py - soma por id de mensagem, reusada aqui)

TETO_PASSAGEM_PADRAO = 150_000


def contexto_ultima_chamada(path: str) -> dict | None:
    """Tamanho de contexto da mensagem do assistente com o MAIOR timestamp do arquivo.

    Nao usa a ultima LINHA do jsonl (streaming manda deltas parciais antes do total
    final) - agrupa por message.id como medir.py e so depois olha o timestamp para achar
    a mensagem mais recente.
    """
    por_msg: dict[str, dict] = {}
    ts_por_msg: dict[str, str] = {}

    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                ev = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if ev.get("type") != "assistant":
                continue
            msg = ev.get("message")
            if not isinstance(msg, dict):
                continue
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

            ts = ev.get("timestamp")
            if ts:
                anterior = ts_por_msg.get(msg_id)
                if anterior is None or ts > anterior:
                    ts_por_msg[msg_id] = ts

    if not por_msg:
        return None

    ultimo_id = max(ts_por_msg, key=lambda mid: ts_por_msg[mid]) if ts_por_msg else max(por_msg)
    g = por_msg[ultimo_id]
    contexto = g["input_tokens"] + g["cache_read_input_tokens"] + g["cache_creation_input_tokens"]
    return {
        "msg_id": ultimo_id,
        "timestamp": ts_por_msg.get(ultimo_id),
        "contexto_tokens": contexto,
        **g,
    }


def medir_sessao(path: str, teto: int) -> dict:
    if not os.path.isfile(path):
        raise FileNotFoundError(path)
    gasto = medir.gasto_real(path)
    gasto["equivalente_entrada"] = round(medir.equivalente_entrada(gasto), 1)
    ultima = contexto_ultima_chamada(path)
    estourou = bool(ultima and ultima["contexto_tokens"] > teto)
    return {
        "path": path,
        "teto": teto,
        "gasto_acumulado": gasto,
        "contexto_ultima_chamada": ultima,
        "estourou_teto": estourou,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("transcript", help="path do transcript .jsonl da sessao principal (coordenadora)")
    ap.add_argument("--teto", type=int, default=TETO_PASSAGEM_PADRAO,
                     help=f"teto de contexto em tokens (default {TETO_PASSAGEM_PADRAO}, v2/AGENTS.md)")
    args = ap.parse_args()

    try:
        resultado = medir_sessao(args.transcript, args.teto)
    except FileNotFoundError as exc:
        print(json.dumps({"ok": False, "erro": f"transcript nao encontrado: {exc}"}, ensure_ascii=False))
        return 1

    g = resultado["gasto_acumulado"]
    print(f"[MEDIDO] gasto acumulado da sessao (soma por id de mensagem, medir.py reusado): "
          f"input={g['input_tokens']} output={g['output_tokens']} "
          f"cache_escrito={g['cache_creation_input_tokens']} cache_lido={g['cache_read_input_tokens']} "
          f"| equivalente_entrada={g['equivalente_entrada']} tok | mensagens={g['mensagens_distintas']} "
          f"| chamadas={g['tool_uses']}")

    u = resultado["contexto_ultima_chamada"]
    if u:
        print(f"[MEDIDO] contexto da ultima chamada (msg {u['msg_id']}, {u['timestamp']}): "
              f"{u['contexto_tokens']} tokens (input={u['input_tokens']} "
              f"cache_lido={u['cache_read_input_tokens']} cache_escrito={u['cache_creation_input_tokens']})")
        if resultado["estourou_teto"]:
            print(f"[MEDIDO] {u['contexto_tokens']} > teto {args.teto} tokens (v2/AGENTS.md): "
                  f"gere a passagem (bin/passagem.py) e siga em conversa nova")
    else:
        print("[MEDIDO] nenhuma mensagem de assistente com usage encontrada no transcript")

    print(json.dumps(resultado, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
