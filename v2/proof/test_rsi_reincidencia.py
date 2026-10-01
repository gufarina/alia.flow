# -*- coding: utf-8 -*-
"""Prova do teste de reincidencia do RSI (v2/bin/rsi_reincidencia.py). Sandbox fora de v2/.

Uso: python test_rsi_reincidencia.py  (sai 1 se alguma prova falhar)
Prova pelo negativo: contagem igual/maior = FAIL; menor = PASS; sem rodada posterior = PENDENTE.
O caso REAL (correcao-repetida 12 -> 13) e conferido contra o estudio quando a raiz existe.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
BIN = os.path.join(V2, "bin", "rsi_reincidencia.py")
FAILS: list[str] = []
NL = chr(10)


def check(nome: str, cond: bool) -> None:
    print(("PASS " if cond else "FAIL ") + nome)
    if not cond:
        FAILS.append(nome)


def monta(raiz: str, base: int, depois: int | None, bucket: str = "x") -> None:
    cand = os.path.join(raiz, "engine", "rsi", "_candidates", bucket + "-2026-09-01")
    os.makedirs(cand)
    os.makedirs(os.path.join(raiz, "memory", "_proposals"))
    with open(os.path.join(cand, "manifest.md"), "w", encoding="utf-8") as fh:
        fh.write("---" + NL + "motivated_by: patterns-2026-09-01.md | atrito:%s - %d sessao(oes) distinta(s)" % (bucket, base) + NL + "---" + NL)
    if depois is not None:
        with open(os.path.join(raiz, "memory", "_proposals", "patterns-2026-09-10.md"), "w", encoding="utf-8") as fh:
            fh.write("## atrito:%s - %d sessao(oes) distinta(s)" % (bucket, depois) + NL)


def roda(raiz: str) -> tuple[int, str]:
    r = subprocess.run([sys.executable, BIN, "--root", raiz, "--check"], capture_output=True, text=True, encoding="utf-8")
    return r.returncode, r.stdout


def caso(base: int, depois: int | None, bucket: str = "x") -> tuple[int, str]:
    d = tempfile.mkdtemp(prefix="alia-rsi-reinc-")
    try:
        monta(d, base, depois, bucket)
        return roda(d)
    finally:
        shutil.rmtree(d, ignore_errors=True)


rc, out = caso(5, 5)
check("igual reincide (exit 1, FAIL)", rc == 1 and "[FAIL]" in out)
rc, out = caso(5, 7)
check("maior reincide (exit 1, FAIL)", rc == 1 and "[FAIL]" in out)
rc, out = caso(5, 4)
check("menor passa (exit 0, PASS)", rc == 0 and "[PASS]" in out)
rc, out = caso(5, None)
check("sem rodada posterior e PENDENTE (exit 0)", rc == 0 and "[PENDENTE]" in out)

# o caso que motivou o sensor (correcao-repetida 12 -> 13, e nada reprovou) reproduzido num sandbox: a prova roda
# sempre, em qualquer copia (2.1.3: antes ela so rodava se o estudio real existisse e fora do release/alia-flow)
rc, out = caso(12, 13, "correcao-repetida")
check("caso do estudio reproduzido em sandbox: correcao-repetida 12 -> 13 reincide (FAIL)", rc == 1 and "[FAIL] correcao-repetida" in out)

sys.exit(1 if FAILS else 0)
