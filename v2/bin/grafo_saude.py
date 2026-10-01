#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""grafo_saude.py - saude do grafo (graphify) e do LLM Wiki do vault, medida.

So LEITURA: nunca escreve no vault (sem git la) nem no estudio. Funcoes puras + CLI.
  frescor_clients  veredito do frescor.py por Client (mapa atrasado reprova)
  ciclo_wiki       datas do ultimo INGEST / QUERY / LINT no log.md do vault (so tipo e data, nunca o texto)
  cobertura_wiki   Client ativo com pagina em wiki/projects mais NOVA que o client.md
  privacidade      nada de wiki/people ou wiki/therapy em grafo nem em chamada de ferramenta dos transcripts
  index_primeiro   sessao que varreu o vault sem ler wiki/index.md antes
Uso: python grafo_saude.py --root ESTUDIO --vault VAULT [--transcripts DIR] [--check]
--check sai 1 se algum FAIL. Janela do ciclo: INGEST e LINT ate 14 dias, 1 ou mais QUERY guardada.
"""
from __future__ import annotations

import argparse
import datetime
import glob
import json
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
sys.path.insert(0, os.path.join(os.path.dirname(AQUI), "lib"))
import grafo_uso  # noqa: E402

_LOG = re.compile("^" + re.escape("[") + "([0-9T:Z-]+)" + re.escape("]") + " ([A-Z_]+) " + re.escape("|"))
_PRIV = re.compile(r"wiki/(people|therapy)(/|$)")
JANELA_DIAS = 14


def frescor_clients(root: str) -> list[dict]:
    import frescor
    return [frescor.avaliar_client(root, c) for c in frescor.clientes_ativos(root)]


def ciclo_wiki(vault: str, hoje: datetime.date | None = None) -> dict:
    hoje = hoje or datetime.date.today()
    ultimo: dict[str, str] = {}
    cont: dict[str, int] = {}
    p = os.path.join(vault, "log.md")
    if os.path.isfile(p):
        with open(p, "r", encoding="utf-8") as fh:
            for l in fh:
                m = _LOG.match(l)
                if m:
                    ultimo[m.group(2)] = max(ultimo.get(m.group(2), ""), m.group(1))
                    cont[m.group(2)] = cont.get(m.group(2), 0) + 1

    def dias(tipo):
        if tipo not in ultimo:
            return None
        return (hoje - datetime.date.fromisoformat(ultimo[tipo][:10])).days
    out = {"ultimo": {k: ultimo.get(k) for k in ("INGEST", "QUERY", "LINT")},
           "dias": {k: dias(k) for k in ("INGEST", "QUERY", "LINT")},
           "consultas_guardadas": len(glob.glob(os.path.join(vault, "wiki", "queries", "*.md"))),
           "contagem": {k: cont.get(k, 0) for k in ("INGEST", "QUERY", "LINT")}}
    falhas = []
    for k in ("INGEST", "LINT"):
        d = out["dias"][k]
        if d is None or d > JANELA_DIAS:
            falhas.append(k + " ha " + str(d) + " dias (janela " + str(JANELA_DIAS) + ")")
    if out["consultas_guardadas"] < 1:
        falhas.append("nenhuma consulta virou pagina")
    out["falhas"] = falhas
    return out


def cobertura_wiki(root: str, vault: str) -> dict:
    import frescor
    sem, velha, ok = [], [], []
    paginas = {os.path.basename(p)[:-3].lower(): p for p in glob.glob(os.path.join(vault, "wiki", "projects", "*.md"))}
    for cid in frescor.clientes_ativos(root):
        ficha = os.path.join(root, "clients", cid, "client.md")
        c = cid.lower()
        # pagina do Client: nome igual, ou com sufixo/prefixo (mOS-BeOne, eve-academy)
        pag = next((p for n, p in paginas.items() if n == c or n.startswith(c + "-") or n.endswith("-" + c)), None)
        if pag is None:
            sem.append(cid)
        elif os.path.isfile(ficha) and os.path.getmtime(pag) < os.path.getmtime(ficha):
            velha.append(cid)
        else:
            ok.append(cid)
    return {"ok": ok, "sem_pagina": sem, "pagina_mais_velha_que_a_ficha": velha, "falhas": [c + " sem pagina" for c in sem] + [c + " pagina velha" for c in velha]}


def _norm_texto(t: str) -> str:
    return t.replace(chr(92) + chr(92), "/").replace(chr(92), "/").lower()


def privacidade_grafos(root: str, vault: str) -> dict:
    achados = []
    padroes = [os.path.join(root, "clients", "**", "graphify-out", "*"), os.path.join(vault, "**", "graphify-out", "*"),
               os.path.join(root, "graphify-out", "*")]
    n = 0
    for pad in padroes:
        for f in glob.glob(pad, recursive=True):
            if os.path.isfile(f) and f.endswith((".json", ".md", ".html")):
                n += 1
                with open(f, "r", encoding="utf-8", errors="replace") as fh:
                    if _PRIV.search(_norm_texto(fh.read())):
                        achados.append(f)
    return {"arquivos_de_grafo": n, "com_people_therapy": achados, "falhas": ["grafo com people/therapy: " + a for a in achados]}


def _alvo(nome, inp):
    return " ".join(str(inp.get(k) or "") for k in ("file_path", "path", "command", "pattern"))


def varrer_transcripts(transcripts: str, vault: str) -> dict:
    """Por sessao: tocou people/therapy? varreu o vault sem ler wiki/index.md antes?"""
    vnorm = _norm_texto(vault).rstrip("/")
    priv, sem_indice, com_indice = [], [], []
    for p in sorted(glob.glob(os.path.join(transcripts, "*.jsonl"))):
        sid = os.path.basename(p)[:-6]
        indice_lido = False
        varreu = False
        tocou_priv = False
        for ts, cwd, nome, inp in grafo_uso.eventos(p):
            t = _norm_texto(_alvo(nome, inp))
            if vnorm not in t and "obsidian-gustavo" not in t:
                continue
            if _PRIV.search(t):
                tocou_priv = True
            if nome == "Read" and _norm_texto(str(inp.get("file_path") or "")).endswith("wiki/index.md"):
                indice_lido = True
            elif nome in ("Grep", "Glob") or (nome in ("Bash", "PowerShell") and any(x in grafo_uso.BUSCA for x in grafo_uso._TOK.split(t))):
                if not varreu:
                    varreu = True
                    if not indice_lido:
                        sem_indice.append(sid)
                    else:
                        com_indice.append(sid)
        if tocou_priv:
            priv.append(sid)
    return {"sessoes_que_tocaram_people_therapy": priv, "varreu_sem_index": sem_indice, "varreu_com_index": com_indice}


def codigo_consulta_le_index(aliaos_busca: str):
    if not os.path.isfile(aliaos_busca):
        return None
    with open(aliaos_busca, "r", encoding="utf-8") as fh:
        return "index.md" in fh.read()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--vault", required=True)
    ap.add_argument("--transcripts", default=grafo_uso.PASTA_PROJ)
    ap.add_argument("--aliaos-busca", default="")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    falhas = []
    fr = frescor_clients(a.root)
    atrasados = [r["client"] for r in fr if r["veredito"] == "VELHO"]
    print("frescor: VELHO =", atrasados or "nenhum", "| CALADO =", [r["client"] for r in fr if r["veredito"].startswith("CALADO")])
    falhas += ["frescor VELHO: " + c for c in atrasados]
    c = ciclo_wiki(a.vault)
    print("ciclo wiki:", json.dumps({k: c[k] for k in ("ultimo", "dias", "consultas_guardadas", "contagem")}, ensure_ascii=False))
    falhas += ["wiki ciclo: " + f for f in c["falhas"]]
    cb = cobertura_wiki(a.root, a.vault)
    print("cobertura wiki:", json.dumps({k: cb[k] for k in ("ok", "sem_pagina", "pagina_mais_velha_que_a_ficha")}, ensure_ascii=False))
    falhas += ["wiki cobertura: " + f for f in cb["falhas"]]
    pg = privacidade_grafos(a.root, a.vault)
    tr = varrer_transcripts(a.transcripts, a.vault)
    print("privacidade: grafos", pg["arquivos_de_grafo"], "com people/therapy", len(pg["com_people_therapy"]), "| sessoes que tocaram", len(tr["sessoes_que_tocaram_people_therapy"]))
    falhas += pg["falhas"] + ["sessao tocou people/therapy: " + s for s in tr["sessoes_que_tocaram_people_therapy"]]
    print("index primeiro: varreu com index", len(tr["varreu_com_index"]), "sem index", len(tr["varreu_sem_index"]))
    if tr["varreu_sem_index"]:
        falhas.append("sessoes que varreram o vault sem ler wiki/index.md: " + str(len(tr["varreu_sem_index"])))
    if a.aliaos_busca:
        le = codigo_consulta_le_index(a.aliaos_busca)
        print("codigo de busca cita index.md:", le)
        if le is False:
            falhas.append("codigo de busca nao le wiki/index.md antes de varrer")
    for f in falhas:
        print("FAIL", f)
    return 1 if (a.check and falhas) else 0


if __name__ == "__main__":
    sys.exit(main())
