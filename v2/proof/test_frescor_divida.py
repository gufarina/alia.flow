# -*- coding: utf-8 -*-
"""Prova: divida de mapa renovavel no maximo 1 vez (frescor._checar_divida). Sandbox fora de v2/.
Negativo: a 3a linha de divida do mesmo Client NAO cala (esgotada). Sai 1 se falhar."""
from __future__ import annotations

import os
import shutil
import sys
import tempfile
from datetime import date, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "lib"))
import frescor  # noqa: E402

FAILS = []


def check(nome, cond):
    print(("PASS " if cond else "FAIL ") + nome)
    if not cond:
        FAILS.append(nome)


def dia(n):
    return (date.today() + timedelta(days=n)).isoformat()


d = tempfile.mkdtemp(prefix="alia-frescor-div-")
try:
    os.makedirs(os.path.join(d, "studio"))
    arq = os.path.join(d, "studio", "conhecimento-dividas.txt")

    def grava(linhas):
        with open(arq, "w", encoding="utf-8") as fh:
            fh.write(chr(10).join(linhas) + chr(10))

    grava(["x " + dia(5) + " registro"])
    r = frescor._checar_divida(d, "x")
    check("1 linha cala", r["valida"] == dia(5) and not r["esgotada"])
    grava(["x " + dia(-3) + " registro", "x " + dia(5) + " renovada 1 vez"])
    r = frescor._checar_divida(d, "x")
    check("1 renovacao ainda cala", r["valida"] == dia(5) and not r["esgotada"])
    grava(["x " + dia(-9) + " a", "x " + dia(-3) + " b", "x " + dia(5) + " c"])
    r = frescor._checar_divida(d, "x")
    check("2a renovacao NAO cala (esgotada)", r["valida"] is None and r["esgotada"])
    grava(["y " + dia(5) + " outro client", "x " + dia(5) + " a"])
    check("outro Client nao conta", not frescor._checar_divida(d, "x")["esgotada"])
finally:
    shutil.rmtree(d, ignore_errors=True)
sys.exit(1 if FAILS else 0)
