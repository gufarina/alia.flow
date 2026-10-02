# -*- coding: utf-8 -*-
"""Prova de L91 (v2/bin/rsi_decisao.py). Pelo negativo: padrao parado alem do prazo = exit 1."""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(os.path.dirname(HERE), "bin", "rsi_decisao.py")
FAILS: list[str] = []


def check(nome: str, cond: bool) -> None:
    print(("PASS " if cond else "FAIL ") + nome)
    if not cond:
        FAILS.append(nome)


def roda(raiz: str) -> int:
    return subprocess.run([sys.executable, BIN, "--root", raiz, "--check"], stdout=subprocess.PIPE).returncode


with tempfile.TemporaryDirectory() as raiz:
    pasta = os.path.join(raiz, "memory", "_proposals")
    os.makedirs(pasta)
    check("sem relatorio vivo passa", roda(raiz) == 0)
    rel = os.path.join(pasta, "patterns-2026-09-01.md")
    open(rel, "w", encoding="utf-8").write("## atrito:x - 3 sessao(oes)\n")
    check("relatorio novo (dentro do prazo) passa", roda(raiz) == 0)
    velho = time.time() - 4 * 86400
    os.utime(rel, (velho, velho))
    check("NEGATIVO: relatorio com 4 dias sem decisao reprova", roda(raiz) == 1)
    os.makedirs(os.path.join(pasta, "_archive"))
    os.replace(rel, os.path.join(pasta, "_archive", "patterns-2026-09-01.md"))
    check("depois de arquivado (decidido) passa", roda(raiz) == 0)

sys.exit(1 if FAILS else 0)
