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

    # ---- 5. TASK-867: grafo_gate (itens 1-5) + muralha /dev/null (6) + dispatch grava a Task da sessao (7).
    # Cada conserto e provado PELO NEGATIVO: um mutante que devolve o comportamento antigo tem de FALHAR no mesmo cenario.
    import importlib.util
    sys.path.insert(0, os.path.join(V2, "flow"))
    LIB, BIN, HOOKS = (os.path.join(V2, x) for x in ("lib", "bin", "hooks"))

    def carrega(fonte: str, mutacoes: list[tuple[str, str]] | None = None):
        src = open(fonte, encoding="utf-8").read()
        for velho, novo in mutacoes or []:
            assert velho in src, "mutante: trecho nao achado: " + velho[:50]
            src = src.replace(velho, novo, 1)
        alvo = os.path.join(D, "mut%d" % len(os.listdir(D)), os.path.basename(fonte))
        grava(alvo, src)
        spec = importlib.util.spec_from_file_location("m%d" % abs(hash(alvo)), alvo)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        return m

    ge = os.path.join(D, "est5")
    ext = os.path.join(D, "ext5")
    for c in ("alfa", "beta"):
        grava(os.path.join(ge, "clients", c, "graphify-out", "GRAPH_REPORT.md"), "# God Nodes" + NL)
        grava(os.path.join(ge, "clients", c, "graphify-out", "graph.json"), "{}")
        grava(os.path.join(ge, "clients", c, "src", "a.ts"), "x")
    grava(os.path.join(ge, "memory", "n.md"), "x")
    grava(os.path.join(ext, "graphify-out", "GRAPH_REPORT.md"), "# God Nodes" + NL)
    grava(os.path.join(ext, "memory", "codigo.py"), "x")
    alfa_map = ge.replace(chr(92), "/") + "/clients/alfa/graphify-out/GRAPH_REPORT.md"
    beta_map = alfa_map.replace("/alfa/", "/beta/")
    alfa_graph = alfa_map.replace("GRAPH_REPORT.md", "graph.json")
    antes_env = dict(os.environ)
    os.environ.update({"CLAUDE_PROJECT_DIR": ge, "ALIA_LEDGER_PATH": os.path.join(ge, "led.jsonl"),
                       "ALIA_CURRENT_TASK_PATH": os.path.join(ge, "cur.json")})
    for k in ("ALIA_GRAPH_GATE_OFF", "ALIA_DELEGATION_WALL_OFF", "ALIA_SPINE_OFF"):
        os.environ.pop(k, None)
    try:
        import ledger as _led
        GG = os.path.join(LIB, "grafo_gate.py")
        atual = carrega(GG)
        BS = chr(92)
        M_TRANSCRIPT = [("                try:\n                    obj = json.loads(linha)",
                         "                if _n(mapa).lower() in linha.replace(" + repr(BS + BS) + ', "/").replace(' + repr(BS) + ', "/").lower() or re.search("graphify' + BS + BS + 's+(query|path|explain)", linha, re.I):' + NL
                         + "                    return True" + NL + "                try:" + NL + "                    obj = json.loads(linha)")]
        M_REGISTRO = [("        escopo = _escopo_da_consulta(command, cwd)",
                       r'        escopo = "*" if re.search(r"graph_report|graphify\s+(query|path|explain)", command, re.I) else None')]
        M_RAIZ = [("for a in achados:", "for a in []:")]
        M_PATTERN = [("if path or not pattern or not os.path.isabs(pattern):", "if True:")]
        M_INFRA = [('return any(low.startswith(raiz + d + "/") for d in INFRA_RAIZ)', 'return any("/" + d + "/" in low for d in INFRA_RAIZ)')]
        mutantes = {"transcript": M_TRANSCRIPT, "registro": M_REGISTRO, "raiz": M_RAIZ, "pattern": M_PATTERN + M_RAIZ, "infra": M_INFRA}

        def cenarios(g, rotulo: str) -> dict:
            def ldt(linhas: list[str], mapa: str, escopo: str) -> bool:
                tr = os.path.join(D, "tr5-%s-%d.jsonl" % (rotulo, abs(hash(tuple(linhas)))))
                grava(tr, "".join(l + NL for l in linhas))
                try:
                    return g._lido_no_transcript(tr, mapa, escopo)
                except TypeError:
                    return g._lido_no_transcript(tr, mapa)

            def tu(nome: str, inp: dict) -> str:
                return json.dumps({"cwd": ge, "message": {"content": [{"type": "tool_use", "name": nome, "input": inp}]}})

            bq = tu("Bash", {"command": "python -m graphify query 'x' --graph " + alfa_graph})
            r = {}
            r["1a graphify query do alfa nao libera o beta"] = (ldt([bq], alfa_map, "clients/alfa") and not ldt([bq], beta_map, "clients/beta"))
            r["1b Write que cita o comando nao vale como leitura"] = not ldt(
                [tu("Write", {"file_path": "x.md", "content": "python -m graphify query x --graph " + alfa_graph})], alfa_map, "clients/alfa")
            r["2a Grep com pattern GRAPH_REPORT, Edit e ls nao contam como leitura"] = not any(ldt([l], alfa_map, "clients/alfa") for l in (
                tu("Grep", {"pattern": "GRAPH_REPORT", "path": alfa_map}), tu("Edit", {"file_path": alfa_map}),
                tu("Bash", {"command": "ls " + alfa_map})))
            r["2b Read do mapa conta (drive minusculo e barra invertida tambem)"] = (
                ldt([tu("Read", {"file_path": alfa_map})], alfa_map, "clients/alfa")
                and ldt([tu("Read", {"file_path": alfa_map[0].lower() + alfa_map[1:].replace("/", BS)})], alfa_map, "clients/alfa"))
            ra = g.registrar_leitura(_led, "S-reg-" + rotulo, command="ls " + alfa_map, cwd=ge)
            rb = g.registrar_leitura(_led, "S-reg2-" + rotulo, command="python -m graphify query x", cwd=ge + "/clients/alfa/src")
            r["3 ls do GRAPH_REPORT nao grava escopo; graphify query grava o escopo do cwd"] = (
                ra.get("registrado") is False and rb.get("registrado") is True and rb.get("escopo") == "clients/alfa")

            def acao(sess, tool, path):
                try:
                    return g.checar(_led, sess, tool, path, ge, "claude").get("acao")
                except Exception as e:  # Recusa grafo_nao_lido
                    return "bloqueia" if "grafo_nao_lido" in repr(e) or getattr(e, "regra", "") == "grafo_nao_lido" else "erro:" + repr(e)[:60]

            r["4a Grep sem path na raiz do studio e varredura de todos os escopos"] = acao("S-raiz-" + rotulo, "Grep", "") in ("bloqueia", "avisa")
            alvo = g.alvo_da_varredura("", ge + "/clients/alfa/**/*.ts") if hasattr(g, "alvo_da_varredura") else ""
            r["4b Glob com pattern absoluto vira varredura do escopo do pattern"] = acao("S-glob-" + rotulo, "Glob", alvo) in ("bloqueia", "avisa")
            r["5 /memory/ de codebase externo e varrido; o da raiz do studio segue infra"] = (
                g.achar_escopo(ext + "/memory/codigo.py") is not None and g.achar_escopo(ge + "/memory/n.md") is None)
            return r

        novo = cenarios(atual, "novo")
        for nome, ok in novo.items():
            check("TASK-867 " + nome + " (codigo novo)", ok)
        nomes = {"1a": "transcript", "1b": "transcript", "2a": "transcript", "2b": None, "3": "registro", "4a": "raiz", "4b": "pattern", "5": "infra"}
        antigos = {q: cenarios(carrega(GG, m), "m-" + q) for q, m in mutantes.items()}
        for nome in novo:
            qual = nomes[nome.split(" ")[0]]
            if qual:
                check("negativo TASK-867 " + nome + ": o mutante (codigo antigo) FALHA", not antigos[qual][nome])

        # 6. /dev/null nunca e alvo de escrita para a muralha
        DISP = os.path.join(HOOKS, "dispatch.py")
        sys.path.insert(0, LIB)

        def muralha(m) -> bool:
            ev = {"session_id": "w6", "cwd": ge, "tool_name": "Bash", "tool_input": {"command": "ls clients 2>/dev/null"}}
            return m._wall_check(ev) is None and m._wall_path_allowed("/dev/null") and m._wall_path_allowed("NUL")
        check("TASK-867 6 muralha: 2>/dev/null nao e escrita", muralha(carrega(DISP)))
        check("negativo TASK-867 6: mutante com a comparacao antiga FALHA", not muralha(carrega(
            DISP, [('p.lstrip("/") in tuple(x.lstrip("/") for x in _WALL_NULL_SINKS):', 'p.lstrip("/") in _WALL_NULL_SINKS:')])))

        # 7. task dispatch --session X --id T grava a Task corrente da sessao X
        ALIA = os.path.join(BIN, "alia.py")
        st = os.path.join(ge, "state.json")

        def dispatch_grava(m) -> bool:
            grava(st, json.dumps({"clients": [{"id": "acme", "status": "active", "squad": {"gateway": "gw", "specialists": ["bruno"]}, "projects": ["p"]}],
                                  "tasks": [{"id": "TASK-001", "client": "acme", "project": "p", "status": "open", "title": "t"}]}))
            if os.path.exists(os.environ["ALIA_CURRENT_TASK_PATH"]):
                os.remove(os.environ["ALIA_CURRENT_TASK_PATH"])
            rc, _res = m.run(["--state", st, "task", "dispatch", "--id", "TASK-001", "--specialist", "Explore", "--session", "sess7"])
            import paths as _p
            return rc == 0 and _p.read_current_task("sess7") == "TASK-001"
        check("TASK-867 7 dispatch --session grava a task corrente da sessao", dispatch_grava(carrega(ALIA)))
        check("negativo TASK-867 7: mutante sem a gravacao FALHA", not dispatch_grava(carrega(ALIA, [("if a.id and a.session:", "if False:")])))
    finally:
        os.environ.clear()
        os.environ.update(antes_env)
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
