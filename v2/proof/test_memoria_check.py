# -*- coding: utf-8 -*-
"""Prova de bin/memoria_check.py. Sandbox fora de v2/. Negativos: nota nova sem valido_de reprova;
nota orfa reprova; nota ligada ao indice e com valido_de passa. Sai 1 se algo falhar."""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(os.path.dirname(HERE), "bin", "memoria_check.py")
NL = chr(10)
FAILS = []


def check(nome, cond):
    print(("PASS " if cond else "FAIL ") + nome)
    if not cond:
        FAILS.append(nome)


def nota(d, nome, valido=True):
    fm = "---" + NL + "name: " + nome + NL + "metadata:" + NL + (("  valido_de: 2026-09-30" + NL) if valido else "") + "---" + NL + "corpo" + NL
    with open(os.path.join(d, nome + ".md"), "w", encoding="utf-8") as fh:
        fh.write(fm)


def roda(d):
    base = os.path.join(d, "baseline.txt")
    r = subprocess.run([sys.executable, BIN, "--memory", d, "--baseline", base, "--check"], capture_output=True, text=True, encoding="utf-8")
    return r.returncode, r.stdout


d = tempfile.mkdtemp(prefix="alia-mem-chk-")
try:
    nota(d, "boa")
    with open(os.path.join(d, "MEMORY.md"), "w", encoding="utf-8") as fh:
        fh.write("- [boa](boa.md) - ok" + NL)
    rc, out = roda(d)
    check("nota ligada e com valido_de passa", rc == 0)
    nota(d, "sem-data", valido=False)
    with open(os.path.join(d, "MEMORY.md"), "a", encoding="utf-8") as fh:
        fh.write("- [x](sem-data.md) - x" + NL)
    rc, out = roda(d)
    check("nota NOVA sem valido_de reprova", rc == 1 and "VALIDO sem-data.md" in out)
    with open(os.path.join(d, "baseline.txt"), "w", encoding="utf-8") as fh:
        fh.write("sem-data.md" + NL)
    rc, out = roda(d)
    check("nota na baseline congelada passa", rc == 0)
    nota(d, "orfa")
    rc, out = roda(d)
    check("nota orfa reprova", rc == 1 and "ORFA   orfa.md" in out)
finally:
    shutil.rmtree(d, ignore_errors=True)
sys.exit(1 if FAILS else 0)
