"""Ledger - unico escritor de activity.jsonl (schema v1, modulo 4 da arquitetura).

So esta biblioteca escreve activity.jsonl. Qualquer outro modulo LE, nunca escreve.
Toda funcao aqui e pura o bastante para testar sem rede nem estado global.
"""
from __future__ import annotations

import json
import os
import sys

SCHEMA_VERSION = 1


def append_event(path: str, event: dict) -> dict:
    """Acrescenta 1 linha JSON a activity.jsonl. So-acrescimo, nunca reescreve.

    Retorna o evento gravado (com "v" e "ts" preenchidos se faltarem). Tambem atualiza o
    indice pequeno ao lado do ledger (`<path>.idx.json`) para pre_agent/post_agent, para que
    cost_already_recorded/session_has_agent_prefix nunca precisem reler o arquivo inteiro.
    """
    import time

    out = dict(event)
    out.setdefault("v", SCHEMA_VERSION)
    out.setdefault("ts", time.time())
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    line = json.dumps(out, ensure_ascii=False, sort_keys=True)
    # abre em modo append binario com encoding utf-8 explicito; um write() por
    # linha e curto o bastante para ficar atomico no NTFS/ext4 no caso comum.
    with open(path, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(line + "\n")
    if out.get("event") in ("pre_agent", "post_agent"):
        _update_index(path, out)
    return out


# ---------------------------------------------------------------------------
# Indice (modulo 4/9, I9): sidecar pequeno ao lado do ledger, atualizado a cada
# pre_agent/post_agent. cost_already_recorded e session_has_agent_prefix consultam SO o
# indice (tamanho O(sessoes/agentes distintos), nao O(linhas do ledger)) - a leitura do
# ledger inteiro a cada evento (achado da revisao independente) so acontece 1x, se o
# indice ainda nao existir, para reconstrui-lo.
# ---------------------------------------------------------------------------

def _index_path(path: str) -> str:
    return path + ".idx.json"


def _load_index(path: str) -> dict:
    idx_path = _index_path(path)
    if not os.path.exists(idx_path):
        return {"agent_ids": [], "session_prefixes": {}}
    try:
        with open(idx_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (json.JSONDecodeError, OSError):
        return {"agent_ids": [], "session_prefixes": {}}
    data.setdefault("agent_ids", [])
    data.setdefault("session_prefixes", {})
    return data


def _save_index(path: str, idx: dict) -> None:
    idx_path = _index_path(path)
    os.makedirs(os.path.dirname(idx_path) or ".", exist_ok=True)
    with open(idx_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(idx, fh, ensure_ascii=False)


def _update_index(path: str, event: dict) -> None:
    idx = _load_index(path)
    if event.get("event") == "post_agent" and event.get("agent_id"):
        if event["agent_id"] not in idx["agent_ids"]:
            idx["agent_ids"].append(event["agent_id"])
    session_id = event.get("session_id")
    agent_type = event.get("agent_type")
    if session_id and agent_type:
        lst = idx["session_prefixes"].setdefault(session_id, [])
        if agent_type not in lst:
            lst.append(agent_type)
    _save_index(path, idx)


def _rebuild_index(path: str) -> dict:
    """Reconstroi o indice lendo o ledger 1 unica vez (ledger antigo, gravado antes deste
    indice existir, ou indice apagado). Depois desta chamada, o indice fica ao lado do
    ledger e as proximas leituras nunca mais escaneiam o arquivo inteiro."""
    for ev in read_events(path):
        if ev.get("event") in ("pre_agent", "post_agent"):
            _update_index(path, ev)
    return _load_index(path)


def read_events(path: str) -> list[dict]:
    if not os.path.exists(path):
        return []
    events = []
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                events.append(json.loads(raw))
            except json.JSONDecodeError:
                # linha corrompida por escrita concorrente nao derruba a leitura;
                # fica de fora, quem le a prova cross-check pode contar como furo.
                continue
    return events


def cost_already_recorded(path: str, agent_id: str) -> bool:
    """True se ja existe post_agent com custo gravado para este agent_id.

    Usado para a prova negativa: 2 Tasks na mesma sessao nunca colapsam no
    mesmo custo, e o mesmo agent_id nunca grava custo duas vezes (o bug do
    78.504.999 nao volta). Le so o indice (sidecar), nunca o ledger inteiro -
    se o indice nao existir ainda (ledger antigo), reconstroi 1 vez.
    """
    idx = _load_index(path) if os.path.exists(_index_path(path)) else _rebuild_index(path)
    return agent_id in idx.get("agent_ids", [])


def session_has_agent_prefix(path: str, session_id: str, prefix: str) -> bool:
    """True se a sessao ja viu um pre_agent/post_agent com agent_type comecando
    por `prefix` (ex.: "acme-" para o Client "acme"). Base da 4a negacao do
    guard (herdeira do delegation-gate L33/L45). Le so o indice, nao o ledger inteiro.
    """
    idx = _load_index(path) if os.path.exists(_index_path(path)) else _rebuild_index(path)
    prefix = prefix.lower()
    for agent_type in idx.get("session_prefixes", {}).get(session_id, []):
        if str(agent_type).lower().startswith(prefix):
            return True
    return False


if __name__ == "__main__":
    # uso manual: python ledger.py <path> read  -> imprime os eventos
    if len(sys.argv) >= 3 and sys.argv[2] == "read":
        for ev in read_events(sys.argv[1]):
            print(json.dumps(ev, ensure_ascii=False))
