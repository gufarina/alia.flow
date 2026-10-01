#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""grafo_uso.py - medidor de ADOCAO do mapa (graphify) a partir dos transcripts.

Por que existe: o graph-usage-sensor.ps1 (1.x) parou em 24/09 00:20 (v2 nao tem os ganchos). Em vez
de religar um .ps1 de 450 ms por acao, o medidor le o transcript da sessao (custo zero de modelo,
zero latencia no turno) e grava 1 linha por (sessao, escopo) em studio/graph-usage-log.jsonl.

Definicoes (todas medidas no transcript):
  varredura   Grep/Glob, ou Bash com grep/rg/find, cujo alvo cai num codebase de Client ou em clients/<id>
  consulta    Read de GRAPH_REPORT.md / graph.json / index.md do escopo, ou Bash com graphify query/path/explain
  adotada     houve consulta do MESMO escopo ANTES da primeira varredura da sessao
Linha: {"v":2,"ts","session","scope","scans","consulted_before","consulted_any","first_scan"}

Uso: python grafo_uso.py --root ESTUDIO [--transcripts DIR] [--desde AAAA-MM-DD] [--gravar] [--resumo]
Idempotente: nao regrava (sessao, escopo) ja presente no log. So biblioteca padrao.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

PASTA_PROJ = os.path.expanduser("~/.claude/projects/") + re.sub(r"[^A-Za-z0-9]", "-", os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
_CODEPATH = re.compile(r"codePath[^:]*:[*]*[ ]*(.+)")
_TOK = re.compile(r"[^A-Za-z_-]+")
BUSCA = ("grep", "rg", "find", "egrep", "fgrep")
CONSULTA_ARQ = ("graph_report.md", "graph.json")


IDS: set = set()  # ids reais de clients/ (minusculos); preenchido por escopos()


def norm(p: str) -> str:
    return p.replace(chr(92), "/").lower().rstrip("/")


def escopos(root: str) -> dict[str, str]:
    """{prefixo normalizado: client} dos codePath externos de cada clients/<id>/client.md."""
    out: dict[str, str] = {}
    IDS.clear()
    IDS.update(d.lower() for d in os.listdir(os.path.join(root, "clients")) if os.path.isdir(os.path.join(root, "clients", d)))
    for md in glob.glob(os.path.join(root, "clients", "*", "client.md")):
        cid = os.path.basename(os.path.dirname(md)).lower()
        with open(md, "r", encoding="utf-8") as fh:
            for linha in fh:
                m = _CODEPATH.search(linha)
                if m:
                    p = m.group(1).strip().strip("`").strip()
                    if ":" in p[:3] and os.path.isabs(p):
                        out[norm(p)] = cid
    return out


def escopo_de(texto: str, esc: dict[str, str]) -> str | None:
    t = norm(texto)
    for pref, cid in esc.items():
        if pref in t:
            return cid
    m = re.search(r"clients/([a-z0-9._-]+)", t)
    if m and (not IDS or m.group(1) in IDS):  # so Client que existe: evita _tmp, acme-saas, nomes truncados
        return m.group(1)
    return None


def eventos(path: str):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for linha in fh:
            try:
                r = json.loads(linha)
            except ValueError:
                continue
            c = (r.get("message") or {}).get("content")
            if isinstance(c, list):
                for b in c:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        yield r.get("timestamp"), r.get("cwd") or "", b.get("name"), b.get("input") or {}


def classificar(nome, inp, cwd, esc):
    """-> ("scan"|"consulta"|None, escopo|None)"""
    if nome in ("Grep", "Glob"):
        alvo = str(inp.get("path") or "") + " " + str(inp.get("pattern") or "") if nome == "Glob" else str(inp.get("path") or "") + " " + cwd
        sc = escopo_de(str(inp.get("path") or "") or cwd, esc)
        return ("scan", sc) if sc else (None, None)
    if nome == "Read":
        fp = str(inp.get("file_path") or "")
        if os.path.basename(norm(fp)) in CONSULTA_ARQ or norm(fp).endswith("/index.md"):
            return "consulta", escopo_de(fp, esc)
        return None, None
    if nome in ("Bash", "PowerShell"):
        cmd = str(inp.get("command") or "")
        baixo = cmd.lower()
        if "graph_report" in baixo or "graphify query" in baixo or "graphify path" in baixo or "graphify explain" in baixo:
            return "consulta", escopo_de(cmd, esc) or escopo_de(cwd, esc) or "*"
        if any(t in BUSCA for t in _TOK.split(baixo)):
            sc = escopo_de(cmd, esc) or escopo_de(cwd, esc)
            return ("scan", sc) if sc else (None, None)
    return None, None


def medir_sessao(path: str, esc: dict[str, str]) -> list[dict]:
    sid = os.path.basename(path)[:-6]
    por: dict[str, dict] = {}
    consultados: dict[str, str] = {}
    for ts, cwd, nome, inp in eventos(path):
        tipo, sc = classificar(nome, inp, cwd, esc)
        if tipo == "consulta" and sc:
            consultados.setdefault(sc, ts)
        elif tipo == "scan" and sc:
            d = por.setdefault(sc, {"scans": 0, "first": ts, "antes": False})
            if d["scans"] == 0:
                d["antes"] = sc in consultados or "*" in consultados
            d["scans"] += 1
    return [{"v": 2, "ts": d["first"], "session": sid, "scope": sc, "scans": d["scans"],
             "consulted_before": d["antes"], "consulted_any": sc in consultados or "*" in consultados,
             "first_scan": d["first"]} for sc, d in sorted(por.items())]


def ja_gravados(log: str) -> set:
    s = set()
    if os.path.isfile(log):
        with open(log, "r", encoding="utf-8") as fh:
            for l in fh:
                try:
                    r = json.loads(l)
                except ValueError:
                    continue
                if r.get("v") == 2:
                    s.add((r["session"], r["scope"]))
    return s


def resumo(linhas: list[dict]) -> dict:
    tot = len(linhas)
    ad = sum(1 for r in linhas if r["consulted_before"])
    por: dict[str, list[int]] = {}
    for r in linhas:
        a = por.setdefault(r["scope"], [0, 0])
        a[0] += 1
        a[1] += 1 if r["consulted_before"] else 0
    return {"sessoes_com_varredura": tot, "adotadas": ad, "adocao_pct": round(100.0 * ad / tot, 1) if tot else None,
            "por_client": {k: {"sessoes": v[0], "adotadas": v[1]} for k, v in sorted(por.items())}}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--transcripts", default=PASTA_PROJ)
    ap.add_argument("--desde", default="")
    ap.add_argument("--gravar", action="store_true")
    ap.add_argument("--resumo", action="store_true")
    a = ap.parse_args()
    esc = escopos(a.root)
    log = os.path.join(a.root, "studio", "graph-usage-log.jsonl")
    ja = ja_gravados(log) if a.gravar else set()
    todas: list[dict] = []
    for p in sorted(glob.glob(os.path.join(a.transcripts, "*.jsonl"))):
        for r in medir_sessao(p, esc):
            if a.desde and (r["ts"] or "") < a.desde:
                continue
            todas.append(r)
    novas = [r for r in todas if (r["session"], r["scope"]) not in ja]
    if a.gravar and novas:
        with open(log, "a", encoding="utf-8", newline="") as fh:
            for r in novas:
                fh.write(json.dumps(r, ensure_ascii=False) + chr(10))
    if a.resumo or not a.gravar:
        print(json.dumps(resumo(todas), ensure_ascii=False, indent=1))
    print("linhas medidas", len(todas), "novas gravadas", len(novas) if a.gravar else 0, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
