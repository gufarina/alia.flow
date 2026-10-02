#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rsi_decisao.py - prazo da decisao de padrao do RSI (L91).

Quem decide padrao e a Alia (mandato do CEO, 01/10/2026), com criterio escrito e prazo de 3 dias:
  PROMOVER  se o padrao reincide em >=3 sessoes distintas E nao ha regra/memoria que o cubra
            (rsi-promote-pattern.ps1 -> candidato em engine/rsi/_candidates/);
  ARQUIVAR  com motivo escrito se a regra ja cobre (mover para memory/_proposals/_archive/).
O CEO so e chamado se a licao exigir mudar lei constitucional (constitution.md, principios I-X).

Este script e o cadeado: relatorio patterns-*.md vivo em memory/_proposals/ com mais de 3 dias
sem decisao = exit 1 (prazo vencido). Decisao = mover o relatorio para _archive/.
Uso: python rsi_decisao.py [--root RAIZ] [--check] [--dias 3]. So biblioteca padrao.
"""
from __future__ import annotations

import argparse
import glob
import os
import sys
import time


def vencidos(root: str, dias: int = 3) -> list[tuple[str, int]]:
    out = []
    for p in sorted(glob.glob(os.path.join(root, "memory", "_proposals", "patterns-*.md"))):
        idade = int((time.time() - os.path.getmtime(p)) // 86400)
        if idade > dias:
            out.append((os.path.basename(p), idade))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.getcwd())
    ap.add_argument("--dias", type=int, default=3)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    v = vencidos(a.root, a.dias)
    for nome, idade in v:
        print(f"VENCIDO {nome} ({idade}d > {a.dias}d): a Alia decide (promover se >=3 sessoes e sem regra; arquivar com motivo se coberto)")
    if not v:
        print("OK nenhum padrao sem decisao alem do prazo")
    return 1 if (v and a.check) else 0


if __name__ == "__main__":
    sys.exit(main())
