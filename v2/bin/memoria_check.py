#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""memoria_check.py - saude estrutural da memoria. So biblioteca padrao.

Duas checagens, ambas com saida 1 em --check:
  ORFA   nota que nenhum indice cita (MEMORY.md ou indice-*.md): ninguem a encontra.
  VALIDO nota SEM `valido_de: AAAA-MM-DD` no frontmatter que NAO esta na baseline congelada
         (studio/memoria-sem-valido-de-baseline.txt). A baseline so encolhe; nota nova sem
         valido_de reprova. Estado vencido/supersedido continua sendo do memory-curator -Validade.

Uso: python memoria_check.py --memory DIR [--baseline ARQ] [--check] [--congelar]
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import sys

_LINK = re.compile(r"[(]([^)(]+[.]md)[)]")
_WIKI = re.compile(re.escape("[[") + "([^]|]+)")
_VALIDO = re.compile(r"^[ ]*valido_de:[ ]*[0-9]{4}-[0-9]{2}-[0-9]{2}", re.M)


def _ler(p: str) -> str:
    with open(p, "r", encoding="utf-8") as fh:
        return fh.read()


def notas(mem: str) -> list[str]:
    return sorted(os.path.basename(p) for p in glob.glob(os.path.join(mem, "*.md")) if os.path.basename(p) != "MEMORY.md")


def orfas(mem: str) -> list[str]:
    citadas: set[str] = set()
    fontes = ["MEMORY.md"] + [n for n in notas(mem) if n.startswith("indice-")]
    for f in fontes:
        p = os.path.join(mem, f)
        if not os.path.isfile(p):
            continue
        t = _ler(p)
        citadas.update(os.path.basename(x) for x in _LINK.findall(t))
        citadas.update(x.strip() + ".md" for x in _WIKI.findall(t))
    return [n for n in notas(mem) if n not in citadas and not n.startswith("indice-")]


def sem_valido(mem: str) -> list[str]:
    return [n for n in notas(mem) if not _VALIDO.search(_ler(os.path.join(mem, n)))]


def baseline(path: str) -> set[str]:
    if not os.path.isfile(path):
        return set()
    return {l.strip() for l in _ler(path).splitlines() if l.strip() and not l.startswith("#")}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--memory", required=True)
    ap.add_argument("--baseline", default="")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--congelar", action="store_true", help="grava a baseline atual (so a 1a vez)")
    a = ap.parse_args()
    sv = sem_valido(a.memory)
    if a.congelar and a.baseline:
        with open(a.baseline, "w", encoding="utf-8", newline="") as fh:
            fh.write("# Notas SEM valido_de no congelamento. So encolhe: nota nova sem valido_de reprova." + chr(10))
            fh.write(chr(10).join(sv) + chr(10))
    base = baseline(a.baseline) if a.baseline else set()
    novas = [n for n in sv if n not in base]
    o = orfas(a.memory)
    print(f"notas={len(notas(a.memory))} orfas={len(o)} sem_valido_de={len(sv)} (baseline {len(base)}, novas sem valido_de {len(novas)})")
    for n in o:
        print("ORFA   " + n)
    for n in novas:
        print("VALIDO " + n + " sem valido_de e fora da baseline")
    return 1 if (a.check and (o or novas)) else 0


if __name__ == "__main__":
    sys.exit(main())
