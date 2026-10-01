#!/usr/bin/env python3
"""accept.py - teste de aceite de agente: roda 1 tarefa em `claude -p` e confere o gabarito regex.

Contrato do <id>.accept.json (mesmo formato de golden.py): p (tarefa), deve[] (regex que TEM de
casar), nao[] (regex que NAO pode casar). Exit 0 so se todos os agentes passam; 1 se algum falha.

Uso: python v2/squad/accept.py <caminho>.accept.json [...] [--client macro] [--model sonnet] [--dry-run]
O agente <client>-<id> precisa estar em .claude/agents (rode bridge.ps1 antes). Cada chamada custa
modelo: o teto e do chamador, aqui so ha 1 chamada por arquivo.
So biblioteca padrao. Saida: 1 linha JSON por agente.
"""
import argparse
import json
import os
import re
import subprocess
import sys


def checa(texto: str, spec: dict) -> dict:
    faltam = [r for r in spec.get("deve", []) if not re.search(r, texto, re.I | re.S)]
    proibidos = [r for r in spec.get("nao", []) if re.search(r, texto, re.I | re.S)]
    return {"ok": not faltam and not proibidos, "faltam": faltam, "proibidos": proibidos}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("arquivos", nargs="+")
    ap.add_argument("--client", default="macro")
    ap.add_argument("--model", default="sonnet")
    ap.add_argument("--dry-run", action="store_true", help="so valida o formato do json, nao chama o modelo")
    a = ap.parse_args()
    falhou = False
    for path in a.arquivos:
        agente = f"{a.client}-{os.path.basename(path).split('.')[0]}".lower()
        with open(path, encoding="utf-8") as fh:
            spec = json.load(fh)
        if not spec.get("p") or not spec.get("deve"):
            print(json.dumps({"agente": agente, "ok": False, "erro": "json sem p ou deve"}, ensure_ascii=False))
            falhou = True
            continue
        if a.dry_run:
            print(json.dumps({"agente": agente, "ok": True, "dry_run": True}, ensure_ascii=False))
            continue
        cmd = ["claude", "-p", f"Use o subagente {agente}: {spec['p']}", "--model", a.model,
               "--disallowedTools", "Write,Edit,NotebookEdit"]
        r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", timeout=300)
        res = checa(r.stdout, spec) if r.returncode == 0 else {"ok": False, "erro": f"claude exit {r.returncode}"}
        falhou = falhou or not res["ok"]
        print(json.dumps({"agente": agente, **res}, ensure_ascii=False))
    return 1 if falhou else 0


if __name__ == "__main__":
    sys.exit(main())
