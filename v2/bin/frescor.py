#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""frescor.py (CLI) - conferencia de FRESCOR do conhecimento por Client (TASK-856).

Uso:
  python frescor.py --root <estudio> [--client <id>] [--json] [--check]

Sem --client, roda sobre todos os Clients ativos (status != arquivado/pontual, ver
lib/frescor.py::clientes_ativos). --check sai 1 se algum Client ativo estiver VELHO
(CALADO_ATE por divida valida nunca conta como falha - a divida existe exatamente para isso).

So biblioteca padrao. UTF-8 explicito. Saida sempre 1 objeto JSON (com --json) ou 1 linha por
Client (sem --json) em stdout; exit 0/1.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(V2, "lib"))
import frescor  # noqa: E402
import paths as _paths  # noqa: E402  (v2/lib/paths.py - raiz do studio pelo cwd/CLAUDE_PROJECT_DIR)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="frescor.py")
    p.add_argument("--root", default=None,
                   help="raiz do estudio (default: sobe do cwd/CLAUDE_PROJECT_DIR ate state.json)")
    p.add_argument("--client", default=None, help="so este Client (default: todos os ativos)")
    p.add_argument("--json", action="store_true", help="saida em JSON")
    p.add_argument("--check", action="store_true", help="exit 1 se algum Client ativo estiver VELHO")
    return p


def main() -> int:
    args = build_parser().parse_args()
    root = args.root or _paths.studio_root()
    ids = [args.client] if args.client else frescor.clientes_ativos(root)

    resultados = [frescor.avaliar_client(root, cid) for cid in ids]

    if args.json:
        sys.stdout.write(json.dumps({"clients": resultados}, ensure_ascii=False))
        sys.stdout.write("\n")
    else:
        for r in resultados:
            print(frescor.linha_humana(r))

    if args.check and any(r["veredito"] == "VELHO" for r in resultados):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
