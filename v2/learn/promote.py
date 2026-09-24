"""Promote - item presente em 3 ou mais playbooks de Clients diferentes vira fila de promocao
(modulo 6, I8). Nunca muda o motor: so LE playbooks/*.md e ACRESCENTA linha na fila.
"""
from __future__ import annotations

import json
import os
import sys
import time
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from curator import _parse_items  # noqa: E402

DONO = "Archive"
PRAZO_DIAS = 7


def _scan_playbooks(playbooks_dir: str) -> dict:
    """pattern_key -> set de clients com item ATIVO daquele padrao."""
    mapa: dict[str, set] = {}
    if not os.path.isdir(playbooks_dir):
        return mapa
    for nome in sorted(os.listdir(playbooks_dir)):
        if not nome.endswith(".md"):
            continue
        caminho = os.path.join(playbooks_dir, nome)
        with open(caminho, "r", encoding="utf-8") as fh:
            text = fh.read()
        for item_id, info in _parse_items(text).items():
            if info["status"] != "ativo":
                continue
            body = info["block"]
            pk_m = __import__("re").search(r"- pattern_key:\s*(.+)", body)
            cl_m = __import__("re").search(r"- client:\s*(.+)", body)
            if not pk_m or not cl_m:
                continue
            pattern_key = pk_m.group(1).strip()
            client = cl_m.group(1).strip()
            mapa.setdefault(pattern_key, set()).add(client)
    return mapa


def _fila_existente(fila_path: str) -> set:
    chaves = set()
    if not os.path.exists(fila_path):
        return chaves
    with open(fila_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                linha = json.loads(raw)
            except json.JSONDecodeError:
                continue
            chaves.add(linha.get("pattern_key"))
    return chaves


def run(playbooks_dir: str, fila_path: str, min_clients: int = 3) -> list[dict]:
    """Varre playbooks_dir, acrescenta na fila (fila_path, jsonl, so-acrescimo) 1 linha por
    pattern_key com >= min_clients distintos que ainda nao esta na fila. Devolve as linhas
    novas gravadas nesta chamada (idempotente: rodar 2x nao duplica)."""
    mapa = _scan_playbooks(playbooks_dir)
    ja_na_fila = _fila_existente(fila_path)
    novas = []
    hoje = date.today()
    for pattern_key, clients in sorted(mapa.items()):
        if len(clients) < min_clients:
            continue
        if pattern_key in ja_na_fila:
            continue
        linha = {
            "pattern_key": pattern_key,
            "clients": sorted(clients),
            "n_clients": len(clients),
            "dono": DONO,
            "criado_em": hoje.isoformat(),
            "prazo": (hoje + timedelta(days=PRAZO_DIAS)).isoformat(),
            "status": "pendente",
            "ts": time.time(),
        }
        novas.append(linha)

    if novas:
        os.makedirs(os.path.dirname(fila_path) or ".", exist_ok=True)
        with open(fila_path, "a", encoding="utf-8", newline="\n") as fh:
            for linha in novas:
                fh.write(json.dumps(linha, ensure_ascii=False, sort_keys=True) + "\n")
    return novas


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("uso: python promote.py <playbooks_dir> <fila.jsonl>")
        sys.exit(1)
    resultado = run(sys.argv[1], sys.argv[2])
    print(json.dumps(resultado, ensure_ascii=False, indent=1))
