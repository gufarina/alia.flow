# -*- coding: utf-8 -*-
"""Provas permanentes do grafo e do LLM Wiki. Ligaveis a prova oficial (run_proofs/check).

Mecanismo (SEMPRE roda, sandbox fora de v2/): frescor reprova mapa atrasado; medidor de adocao distingue
varredura com e sem consulta; privacidade acusa people/therapy; index-primeiro; ciclo do wiki.
Acerto (roda se o codigo do Client do gabarito e o graphify existem; senao SKIP, nunca PASS falso): query contra
o gabarito em tests/token-budget/dados/grafo-gabarito.json, minimo 4 de 5.
Uso: python test_grafo.py  (sai 1 se algo falhar)
"""
from __future__ import annotations

import datetime
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
STUDIO = os.path.abspath(os.path.join(V2, "..", "..", ".."))
sys.path.insert(0, os.path.join(V2, "bin"))
sys.path.insert(0, os.path.join(V2, "lib"))  # lib por ultimo no insert = primeiro na busca (bin tambem tem frescor.py)
import frescor  # noqa: E402
import grafo_saude  # noqa: E402
import grafo_uso  # noqa: E402

FAILS: list[str] = []
NL = chr(10)


def check(nome: str, cond: bool) -> None:
    print(("PASS " if cond else "FAIL ") + nome)
    if not cond:
        FAILS.append(nome)


def grava(p: str, txt: str) -> None:
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8", newline="") as fh:
        fh.write(txt)


def antigo(p: str, dias: int) -> None:
    t = time.time() - dias * 86400
    os.utime(p, (t, t))


def evento(nome: str, inp: dict, ts: str, cwd: str) -> str:
    return json.dumps({"timestamp": ts, "cwd": cwd, "sessionId": "x", "message": {"content": [{"type": "tool_use", "name": nome, "input": inp}]}}) + NL


D = tempfile.mkdtemp(prefix="alia-grafo-")
try:
    # ---- 1. frescor reprova mapa atrasado
    raiz = os.path.join(D, "est")
    kn = os.path.join(raiz, "clients", "x", "squad", "knowledge")
    grava(os.path.join(raiz, "clients", "x", "client.md"), "# x" + NL)
    grava(os.path.join(kn, "graphify-out", "graph.json"), "{}")
    antigo(os.path.join(kn, "graphify-out", "graph.json"), 40)
    for i in range(3):
        grava(os.path.join(kn, "doc%d.md" % i), "novo" + NL)
    r = frescor.avaliar_client(raiz, "x")
    check("frescor: mapa de 40 dias com 3 docs novos = VELHO", r["veredito"] == "VELHO")
    os.utime(os.path.join(kn, "graphify-out", "graph.json"), None)
    r = frescor.avaliar_client(raiz, "x")
    check("frescor: mapa recem-gerado = OK", r["veredito"] == "OK")

    # ---- 2. medidor de adocao
    est = os.path.join(D, "est2")
    grava(os.path.join(est, "clients", "x", "client.md"), "- **codePath:** C:/ext/projeto-x/" + NL)
    tr = os.path.join(D, "tr")
    cwd = "C:/ext/projeto-x"
    grava(os.path.join(tr, "sa.jsonl"), evento("Grep", {"path": "C:/ext/projeto-x/src", "pattern": "foo"}, "2026-10-01T10:00:00Z", cwd))
    grava(os.path.join(tr, "sb.jsonl"),
          evento("Read", {"file_path": "C:/ext/projeto-x/graphify-out/GRAPH_REPORT.md"}, "2026-10-01T10:00:00Z", cwd)
          + evento("Grep", {"path": "C:/ext/projeto-x/src", "pattern": "foo"}, "2026-10-01T10:01:00Z", cwd))
    grava(os.path.join(tr, "sc.jsonl"),
          evento("Grep", {"path": "C:/ext/projeto-x/src", "pattern": "foo"}, "2026-10-01T10:00:00Z", cwd)
          + evento("Read", {"file_path": "C:/ext/projeto-x/graphify-out/GRAPH_REPORT.md"}, "2026-10-01T10:01:00Z", cwd))
    esc = grafo_uso.escopos(est)
    ra = grafo_uso.medir_sessao(os.path.join(tr, "sa.jsonl"), esc)
    rb = grafo_uso.medir_sessao(os.path.join(tr, "sb.jsonl"), esc)
    rc = grafo_uso.medir_sessao(os.path.join(tr, "sc.jsonl"), esc)
    check("adocao: varredura sem consulta = NAO adotada", len(ra) == 1 and ra[0]["scans"] == 1 and ra[0]["consulted_before"] is False)
    check("adocao: consulta antes da varredura = adotada", len(rb) == 1 and rb[0]["consulted_before"] is True)
    check("adocao: consulta DEPOIS da varredura nao conta", len(rc) == 1 and rc[0]["consulted_before"] is False and rc[0]["consulted_any"] is True)
    s = grafo_uso.resumo(ra + rb + rc)
    check("adocao: resumo 1 de 3", s["sessoes_com_varredura"] == 3 and s["adotadas"] == 1)

    # ---- 3. privacidade, index primeiro, ciclo do wiki
    vault = os.path.join(D, "vault")
    grava(os.path.join(vault, "log.md"), "[2026-01-01T00:00:00Z] LINT | x | y" + NL + "[2026-01-02T00:00:00Z] INGEST | x | y" + NL)
    c = grafo_saude.ciclo_wiki(vault, datetime.date(2026, 10, 1))
    check("wiki: ingestao e lint velhos reprovam o ciclo", len(c["falhas"]) >= 3)
    grava(os.path.join(vault, "wiki", "queries", "q.md"), "q")
    grava(os.path.join(vault, "log.md"), "[2026-09-30T00:00:00Z] LINT | x | y" + NL + "[2026-09-30T00:00:00Z] INGEST | x | y" + NL)
    c = grafo_saude.ciclo_wiki(vault, datetime.date(2026, 10, 1))
    check("wiki: ciclo em dia passa", c["falhas"] == [])
    grava(os.path.join(est, "clients", "x", "graphify-out", "graph.json"), json.dumps({"nodes": [{"source_file": "wiki/people/fulano.md"}]}))
    p = grafo_saude.privacidade_grafos(est, vault)
    check("privacidade: grafo com wiki/people e acusado", len(p["com_people_therapy"]) == 1)
    os.remove(os.path.join(est, "clients", "x", "graphify-out", "graph.json"))
    check("privacidade: grafo limpo passa", grafo_saude.privacidade_grafos(est, vault)["com_people_therapy"] == [])
    v = vault.replace(chr(92), "/")
    tv = os.path.join(D, "trv")
    grava(os.path.join(tv, "s1.jsonl"), evento("Grep", {"path": v + "/wiki", "pattern": "x"}, "2026-10-01T10:00:00Z", v))
    grava(os.path.join(tv, "s2.jsonl"), evento("Read", {"file_path": v + "/wiki/index.md"}, "2026-10-01T10:00:00Z", v)
          + evento("Grep", {"path": v + "/wiki", "pattern": "x"}, "2026-10-01T10:01:00Z", v))
    grava(os.path.join(tv, "s3.jsonl"), evento("Read", {"file_path": v + "/wiki/therapy/a.md"}, "2026-10-01T10:00:00Z", v))
    t = grafo_saude.varrer_transcripts(tv, vault)
    check("index primeiro: varrer sem ler index e acusado", t["varreu_sem_index"] == ["s1"] and t["varreu_com_index"] == ["s2"])
    check("privacidade: sessao que leu wiki/therapy e acusada", t["sessoes_que_tocaram_people_therapy"] == ["s3"])
finally:
    shutil.rmtree(D, ignore_errors=True)

# ---- 4. acerto da query contra gabarito (codigo real do Client do gabarito)
gab_path = os.path.join(STUDIO, "tests", "token-budget", "dados", "grafo-gabarito.json")
if os.path.isfile(gab_path):
    gab = json.load(open(gab_path, encoding="utf-8"))
    cod = gab["codigo"]
    if os.path.isfile(os.path.join(cod, "graphify-out", "graph.json")):
        acertos = 0
        for q in gab["perguntas"]:
            fonte = open(os.path.join(cod, q["arquivo"]), encoding="utf-8").read()
            assert q["simbolo"] in fonte, "gabarito desatualizado: " + q["arquivo"]
            r = subprocess.run([sys.executable, "-m", "graphify", "query", q["q"]], cwd=cod, capture_output=True, text=True, encoding="utf-8", errors="replace")
            hit = q["arquivo"].lower() in r.stdout.replace(chr(92), "/").lower()
            acertos += 1 if hit else 0
            print(("  hit  " if hit else "  MISS ") + q["q"] + " -> " + q["arquivo"])
        check("acerto da query: %d de %d (minimo 4)" % (acertos, len(gab["perguntas"])), acertos >= 4)
    else:
        print("SKIP acerto da query: mapa do Client do gabarito ausente")
else:
    print("SKIP acerto da query: gabarito ausente")
sys.exit(1 if FAILS else 0)
