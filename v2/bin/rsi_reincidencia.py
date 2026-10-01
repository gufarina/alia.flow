#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rsi_reincidencia.py - teste de reincidencia por aprendizado do RSI.

Motivo medido: o RSI registrava aprendizado e o padrao reincidia (qualidade-fraca 14->16,
correcao-repetida 12->13) sem nada que reprovasse. Sensor sem atuador verificado.

Regra: todo aprendizado registrado (engine/rsi/_candidates/<slug>/manifest.md, campo
`motivated_by: patterns-AAAA-MM-DD.md | atrito:<bucket> - N sessao(oes) ...`) carrega a contagem
N da rodada que o originou. A rodada seguinte (relatorio patterns-*.md MAIS NOVO que o de origem,
em memory/_proposals/) tem que mostrar contagem MENOR que N para o mesmo bucket. Igual ou maior
= FAIL (o aprendizado nao fez efeito). Bucket ausente na rodada seguinte = 0 = PASS. Sem rodada
posterior = PENDENTE (nao reprova: ainda nao ha o que comparar).

Uso: python rsi_reincidencia.py [--root RAIZ_DO_ESTUDIO] [--check]
--check sai 1 se algum aprendizado reincide. So biblioteca padrao.
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import sys

_MOTIVO_RE = re.compile(
    r"^motivated_by:[ ]*(patterns-[0-9]{4}-[0-9]{2}-[0-9]{2})[.]md[ ]*[|][ ]*([^ ]+)[ ]+-[ ]+([0-9]+)[ ]+sess", re.M)
_SECAO_RE = re.compile(r"^##[ ]+([^ ]+)[ ]+-[ ]+([0-9]+)[ ]+sess", re.M)


def _ler(path: str) -> str:
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def relatorios(root: str) -> list[tuple[str, dict]]:
    """[(nome 'patterns-AAAA-MM-DD', {bucket: contagem})] em ordem de data."""
    out = []
    for p in sorted(glob.glob(os.path.join(root, "memory", "_proposals", "patterns-*.md"))):
        nome = os.path.basename(p)[:-3]
        out.append((nome, {b: int(n) for b, n in _SECAO_RE.findall(_ler(p))}))
    return out


def candidatos(root: str) -> list[tuple[str, str, str, int]]:
    """[(slug, relatorio_origem, bucket, baseline)] de todo manifest com motivated_by valido."""
    achados = []
    padroes = (os.path.join(root, "engine", "rsi", "_candidates", "*", "manifest.md"),
               os.path.join(root, "clients", "alia-flow-lab", "engine", "rsi", "_candidates", "*", "manifest.md"))
    for padrao in padroes:
        for m in sorted(glob.glob(padrao)):
            achou = _MOTIVO_RE.search(_ler(m))
            if achou:
                slug = os.path.basename(os.path.dirname(m))
                achados.append((slug, achou.group(1), achou.group(2), int(achou.group(3))))
    return achados


def avaliar(root: str) -> list[dict]:
    rels = relatorios(root)
    res = []
    for slug, origem, bucket, base in candidatos(root):
        depois = [(n, c) for n, c in rels if n > origem]
        if not depois:
            res.append({"slug": slug, "bucket": bucket, "baseline": base, "atual": None,
                        "rodada": None, "veredito": "PENDENTE"})
            continue
        nome, contagens = depois[-1]
        atual = contagens.get(bucket, 0)
        res.append({"slug": slug, "bucket": bucket, "baseline": base, "atual": atual, "rodada": nome,
                    "veredito": "PASS" if atual < base else "FAIL"})
    return res


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.getcwd())
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    res = avaliar(a.root)
    for r in res:
        if r["veredito"] == "PENDENTE":
            print(f"[PENDENTE] {r['slug']}: {r['bucket']} base {r['baseline']}, sem rodada posterior")
        else:
            print(f"[{r['veredito']}] {r['slug']}: {r['bucket']} {r['baseline']} -> {r['atual']} em {r['rodada']}"
                  + (" (REINCIDE: o aprendizado nao fez a contagem cair)" if r["veredito"] == "FAIL" else ""))
    if not res:
        print("nenhum aprendizado registrado")
    falhas = [r for r in res if r["veredito"] == "FAIL"]
    return 1 if (a.check and falhas) else 0


if __name__ == "__main__":
    sys.exit(main())
