# -*- coding: utf-8 -*-
"""Prova da espinha Cliente>Projeto>Tarefa: CLI `alia`, schema, adaptadores, trava do grafo/wiki.

Metodo (PROVA PELO NEGATIVO): cada recusa roda numa copia REAL do motor (tem que recusar com a `regra`
certa) e numa copia MUTADA (a linha que impoe a regra e desligada; NAO pode recusar pela mesma regra).
Mutante que sobrevive = prova furada. Sandbox em tempdir, nunca o state.json nem o ledger reais.
Adaptadores: Claude Code com eventos reais de hook no dispatch.py; Codex/OpenCode/Pi por teste de unidade da
traducao evento -> CLI (sem Codex CLI nesta maquina; OpenCode/Pi exigem node, senao [SKIP] declarado).
Uso: python test_espinha.py  (sai 1 se algo falhar)
"""
from __future__ import annotations

import argparse
import atexit
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
ACENTO_PARECER = "\n".join(f"{c}: PASS\nevidencia: ok" for c in
                           ("aderente-ddd", "frugal", "rastreavel", "simplicidade", "fundamentada"))


def montar(work: str, mapa: str) -> dict:
    """Fixture: state com 2 Clients cadastrados + artefato + mapa de grafo em `mapa`."""
    os.makedirs(work, exist_ok=True)
    estado = {"clients": [
        {"id": "acme", "status": "active", "squad": {"gateway": "gw", "specialists": ["bruno", "rex"]}, "projects": ["p"]},
        {"id": "other", "status": "active", "squad": {"gateway": "gw2", "specialists": ["x"]}, "projects": ["q"]}],
        "tasks": [{"id": "TASK-001", "client": "acme", "project": "Nome Antigo", "status": "done", "title": "legado"}]}
    json.dump(estado, open(os.path.join(work, "state.json"), "w", encoding="utf-8"))
    art = os.path.join(work, "artefato.md")
    open(art, "w", encoding="utf-8").write("entrega de prova da espinha\n")
    os.makedirs(os.path.join(mapa, "clients", "acme", "graphify-out"), exist_ok=True)
    os.makedirs(os.path.join(mapa, "clients", "acme", "src"), exist_ok=True)
    open(os.path.join(mapa, "clients", "acme", "graphify-out", "GRAPH_REPORT.md"), "w").write("# God Nodes\n")
    os.makedirs(os.path.join(mapa, "vault", "wiki", "paginas"), exist_ok=True)
    open(os.path.join(mapa, "vault", "wiki", "index.md"), "w").write("# indice\n")
    return {"state": os.path.join(work, "state.json"), "art": art}


def ambiente(work: str) -> None:
    for k in [k for k in os.environ if k.startswith("ALIA_") or k == "CLAUDE_PROJECT_DIR"]:
        del os.environ[k]
    os.environ.update({"ALIA_LEDGER_PATH": os.path.join(work, "led.jsonl"), "ALIA_STATE_PATH": os.path.join(work, "state.json"),
                       "ALIA_CURRENT_TASK_PATH": os.path.join(work, "cur.json"), "CLAUDE_PROJECT_DIR": work})


# ---------------------------------------------------------------------------
# Modo filho: 1 cenario de recusa contra um v2/ (o real ou o mutado). Imprime o JSON da CLI.
# ---------------------------------------------------------------------------
def cenario(nome: str, v2root: str, work: str) -> dict:
    for sub in ("flow", "lib", "bin"):
        sys.path.insert(0, os.path.join(v2root, sub))
    ambiente(work)
    fx = montar(work, os.path.join(work, "mapa"))
    import alia  # noqa: E402  (do v2root pedido)
    import ledger  # noqa: E402
    st, art = fx["state"], fx["art"]

    def run(*a):
        return alia.run(["--state", st, *a])[1]

    def abre(coord=False):
        b = {"client": "acme", "project": "p", "objetivo": "provar a espinha ate o criterio", "paths": art,
             "consumidor": "WARDEN", "destino": "interno", "exemplo_falha": "regra so em prosa"}
        if coord:
            b["coordenacao"] = True
        return run("task", "open", "--brief", json.dumps(b), "--session", "s1")["task"]["id"]

    if nome == "projeto":
        b = {"client": "acme", "project": "fora-do-cadastro", "objetivo": "x ate y", "paths": art, "consumidor": "w",
             "destino": "interno", "exemplo_falha": "z"}
        return run("task", "open", "--brief", json.dumps(b))
    if nome in ("veredito", "artifact"):
        tid = abre()
        ledger.append_event(os.environ["ALIA_LEDGER_PATH"], {"event": "review_verdict", "task_id": tid, "veredito": "PASS"})
        if nome == "veredito":
            return run("task", "close", "--id", tid, "--artifact", art, "--veredito", "")
        return run("task", "close", "--id", tid, "--artifact", os.path.join(work, "nao-existe.md"), "--veredito", "PASS")
    if nome == "gateway_ack":
        return run("task", "dispatch", "--id", abre(), "--specialist", "acme-bruno", "--session", "s1")
    if nome == "coordenacao":
        return run("task", "dispatch", "--id", abre(), "--specialist", "alia", "--session", "s1")
    if nome == "outro_client":
        tid = abre()
        run("task", "dispatch", "--id", tid, "--specialist", "acme-gw", "--session", "s1")
        return run("task", "dispatch", "--id", tid, "--specialist", "other-x", "--session", "s1")
    if nome == "sem_task":
        return run("task", "dispatch", "--specialist", "acme-gw", "--session", "sessao-sem-task")
    if nome == "proj_duplicado":
        return run("project", "add", "--client", "acme", "--id", "p")
    if nome == "proj_invalido":
        return run("project", "add", "--client", "acme", "--id", "Bad_Id")
    if nome == "gate_task":
        return run("gate", "record", "--task", "TASK-999", "--parecer", art)
    if nome in ("grafo", "grafo_off"):
        if nome == "grafo_off":
            os.environ["ALIA_GRAPH_GATE_OFF"] = "1"
        return run("graph", "check", "--session", "s9", "--tool", "Grep", "--path",
                   os.path.join(work, "mapa", "clients", "acme", "src"), "--host", "claude")
    if nome == "state_corrompido":
        open(st, "w", encoding="utf-8").write('{"clients": [{"id": "acme", "squad"')  # truncado no meio
        return run("task", "dispatch", "--id", "TASK-001", "--specialist", "acme-gw", "--session", "s1")
    if nome == "nome_curto":
        return run("task", "dispatch", "--id", abre(), "--specialist", "gw", "--session", "s1")
    if nome in ("brief_lista", "coord_texto", "type_enum", "schema_open"):
        b = {"client": "acme", "project": "p", "objetivo": "provar a espinha ate o criterio", "paths": art,
             "consumidor": "WARDEN", "destino": "interno", "exemplo_falha": "regra so em prosa"}
        if nome == "brief_lista":
            b["paths"] = [art]
        if nome == "coord_texto":
            b["coordenacao"] = "true"
        if nome == "type_enum":
            b["type"] = "Correcao"
        if nome == "schema_open":  # cadastro legado com projeto fora do formato: o schema da Task nova tem que pegar
            d = json.load(open(st, encoding="utf-8"))
            d["clients"][0]["projects"].append("Nome Velho")
            json.dump(d, open(st, "w", encoding="utf-8"))
            b["project"] = "Nome Velho"
        return run("task", "open", "--brief", json.dumps(b), "--session", "s1")
    if nome == "criterio":
        tid = abre()
        ledger.append_event(os.environ["ALIA_LEDGER_PATH"], {"event": "review_verdict", "task_id": tid, "veredito": "FAIL"})
        return run("task", "close", "--id", tid, "--artifact", art, "--veredito", "FAIL")
    raise SystemExit(f"cenario desconhecido: {nome}")


# nome -> (regra esperada na copia REAL, arquivo a mutar, trecho, troca)
CENARIOS = {
    "projeto": ("projeto_fora_do_cadastro", "lib/task_model.py", 'if brief["project"] not in cadastrados:', "if False:"),
    "veredito": ("fechar_sem_veredito", "lib/task_model.py", "    if veredito not in VEREDITOS_VALIDOS:\n        raise TaskError(\"close exige --veredito",
                 "    if False:\n        raise TaskError(\"close exige --veredito"),
    "artifact": ("artifact_inexistente", "lib/task_model.py", "    if faltam_disco:", "    if False:"),
    "gateway_ack": ("dispatch_sem_gateway_ack", "lib/espinha.py", 'elif not task.get("gateway_ack"):', "elif False:"),
    "coordenacao": ("alia_sem_coordenacao", "lib/espinha.py", 'if task.get("coordenacao") is not True:', "if False:"),
    "outro_client": ("specialist_de_outro_client", "lib/espinha.py", 'elif dono != task["client"]:', "elif False:"),
    "sem_task": ("dispatch_sem_task", "bin/alia.py", "    if not tid:", "    if False:"),
    "proj_duplicado": ("projeto_ja_cadastrado", "lib/espinha.py", "if pid in projetos:", "if False:"),
    "proj_invalido": ("projeto_id_invalido", "lib/espinha.py", "if not pid or not ID_CANONICO.match(pid):", "if not pid:"),
    "gate_task": ("task_inexistente", "bin/alia.py", 'if not any(t.get("id") == a.task for t in espinha.carregar(state).get("tasks", [])):',
                  "if False:"),
    "grafo": ("grafo_nao_lido", "lib/grafo_gate.py", '    if acao == "bloqueia":\n        raise', '    if False:\n        raise'),
    # interruptor: com ALIA_GRAPH_GATE_OFF=1 NAO pode recusar (regra None); mutante que ignora o interruptor recusa
    "grafo_off": (None, "lib/grafo_gate.py", '"bloqueia" if (modo == "bloqueia" and not desligado) else "avisa"',
                  '"bloqueia" if (modo == "bloqueia" and True) else "avisa"'),
    "state_corrompido": ("state_corrompido", "lib/espinha.py", "except (ValueError, UnicodeDecodeError) as exc:", "except OSError as exc:"),
    "nome_curto": ("agente_nome_curto", "lib/espinha.py", "curtos = _nome_curto(state, specialist)", "curtos = []"),
    "brief_lista": ("brief_tipo_invalido", "lib/task_model.py", 'if brief.get(campo) not in (None, "") and not isinstance(brief[campo], str):', "if False:"),
    "coord_texto": ("brief_tipo_invalido", "lib/task_model.py", 'if "coordenacao" in brief and not isinstance(brief["coordenacao"], bool):', "if False:"),
    "type_enum": ("type_invalido", "lib/task_model.py", 'if brief.get("type") not in (None, "") and brief["type"] not in TIPOS_VALIDOS:', "if False:"),
    "schema_open": ("schema_invalido", "bin/task.py", "erros = espinha.validar_task_nova(new_task)", "erros = []"),
    "criterio": ("criterio_reprovado_ausente", "lib/task_model.py", 'if veredito != "PASS" and not criterio_reprovado:', "if False:"),
}


def _copia_do_motor(destino: str, mutacao: tuple[str, str, str] | None) -> str:
    raiz = os.path.join(destino, "v2")
    for sub in ("bin", "lib", "flow", "adapters"):
        shutil.copytree(os.path.join(V2, sub), os.path.join(raiz, sub), ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copy(os.path.join(V2, "state.schema.json"), raiz)
    if mutacao:
        arq, velho, novo = mutacao
        caminho = os.path.join(raiz, arq)
        texto = open(caminho, encoding="utf-8", newline="").read()
        assert velho in texto, f"ponto de mutacao sumiu: {arq}: {velho[:50]}"
        open(caminho, "w", encoding="utf-8", newline="").write(texto.replace(velho, novo, 1))
    return raiz


def _roda_cenario(nome: str, mutar: bool) -> dict:
    tmp = tempfile.mkdtemp(prefix="alia-espinha-cen-")
    atexit.register(shutil.rmtree, tmp, ignore_errors=True)
    raiz = _copia_do_motor(os.path.join(tmp, "motor"), CENARIOS[nome][1:] if mutar else None)
    proc = subprocess.run([sys.executable, os.path.abspath(__file__), "--cenario", nome, "--v2", raiz, "--work", os.path.join(tmp, "w")],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        return json.loads(proc.stdout.decode("utf-8").strip().splitlines()[-1])
    except (ValueError, IndexError):
        return {"_erro": proc.stderr.decode("utf-8", "replace")[-300:]}


FAILS: list[str] = []
SKIPS: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    print(f"[{'PASS' if cond else 'FAIL'}] {name} {detail}")
    if not cond:
        FAILS.append(name)


def principal() -> int:
    sandbox = tempfile.mkdtemp(prefix="alia-espinha-")
    atexit.register(shutil.rmtree, sandbox, ignore_errors=True)

    print("=== cada recusa pelo negativo (copia real recusa com a regra; copia mutada nao) ===")
    with ThreadPoolExecutor(max_workers=12) as ex:
        reais = {n: ex.submit(_roda_cenario, n, False) for n in CENARIOS}
        mutados = {n: ex.submit(_roda_cenario, n, True) for n in CENARIOS}
    for nome, (regra, arq, velho, _novo) in CENARIOS.items():
        real, mut = reais[nome].result(), mutados[nome].result()
        check(f"{nome}: motor real {'recusa com ' + regra if regra else 'libera (interruptor)'}", real.get("regra") == regra,
              str(real)[:200])
        check(f"{nome}: mutante ({arq}) NAO imita a recusa - a prova pega o defeito", mut.get("regra") != regra and "_erro" not in mut,
              str(mut)[:200])

    work = os.path.join(sandbox, "w")
    mapa = os.path.join(sandbox, "mapa")
    fx = montar(work, mapa)
    ambiente(work)
    for sub in ("flow", "lib", "bin"):
        sys.path.insert(0, os.path.join(V2, sub))
    import alia  # noqa: E402
    import espinha  # noqa: E402
    import ledger  # noqa: E402
    import task_model  # noqa: E402
    st, art = fx["state"], fx["art"]

    def run(*a):
        return alia.run(["--state", st, *a])

    def eventos():
        return ledger.read_events(os.environ["ALIA_LEDGER_PATH"])

    print("\n=== schema: paridade com o codigo ===")
    sch = espinha.schema()
    trans = {(None if k == "<nova>" else k): set(v) for k, v in sch["x-transicoes"].items()}
    check("schema x-transicoes == task_model.TRANSICOES_VALIDAS", trans == task_model.TRANSICOES_VALIDAS, str(trans))
    check("schema veredito == task_model.VEREDITOS_VALIDOS", tuple(sch["$defs"]["veredito"]["enum"]) == task_model.VEREDITOS_VALIDOS)
    check("schema destino == task_model.DESTINOS_VALIDOS", tuple(sch["$defs"]["task_nova"]["properties"]["destino"]["enum"]) == task_model.DESTINOS_VALIDOS)
    fontes = "".join(open(os.path.join(V2, p), encoding="utf-8").read() for p in ("lib/task_model.py", "lib/espinha.py", "lib/grafo_gate.py", "bin/alia.py"))
    ausentes = [r for r in sch["x-recusas"] if f'"{r}"' not in fontes]
    check("toda recusa documentada no schema existe no codigo", not ausentes, str(ausentes))
    check("validador pega task nova com projeto fora do formato canonico",
          bool(espinha.validar_task_nova({"id": "T", "client": "c", "status": "open", "project": "Nome Antigo", "title": "t",
                                          "destino": "interno", "type": "construcao"})))
    check("validador pega done sem veredito/artifact (schema, nao so CLI)",
          len(espinha.validar_task_nova({"id": "T", "client": "c", "status": "done"}, so_status=True)) >= 2)

    print("\n=== CLI: caminho feliz, escrita pelo schema ===")
    rc, res = run("open", "--session", "s-open")
    check("alia open devolve o estado e grava session_opened", rc == 0 and res.get("session_opened") and res["clients"]
          and any(e.get("event") == "session_opened" and e.get("session_id") == "s-open" for e in eventos()), str(res)[:160])
    rc, res = run("project", "add", "--client", "acme", "--id", "novo-projeto")
    check("project add cadastra projeto canonico", rc == 0 and "novo-projeto" in res["projects"], str(res)[:120])
    rc, res = run("project", "add", "--client", "acme", "--from-tasks")
    check("project add --from-tasks nao cadastra nome legado fora do formato", rc == 0 and "Nome Antigo" not in res["projects"], str(res)[:120])
    brief = {"client": "acme", "project": "p", "objetivo": "provar a espinha ate o criterio", "paths": art, "consumidor": "WARDEN",
             "destino": "interno", "exemplo_falha": "regra so em prosa"}
    rc, res = run("task", "open", "--brief", json.dumps(brief), "--session", "s1")
    tid = res["task"]["id"]
    check("task open com projeto cadastrado abre e a Task cumpre task_nova", rc == 0 and espinha.validar_task_nova(res["task"]) == [], str(res)[:160])
    rc, res = run("task", "dispatch", "--specialist", "acme-gw", "--session", "s1")
    check("dispatch do Gateway grava gateway_ack (Task corrente da sessao)", rc == 0 and res.get("gateway_ack"), str(res))
    rc, res = run("task", "dispatch", "--specialist", "acme-bruno", "--session", "s1")
    check("dispatch de Specialist depois do ack passa", rc == 0 and res.get("registrado"), str(res))
    rc, res = run("task", "dispatch", "--specialist", "Explore", "--session", "s1")
    check("agente fora de qualquer squad nao e assunto da espinha", rc == 0 and res.get("registrado") is False, str(res))
    b2 = dict(brief, coordenacao=True)
    rc, res = run("task", "open", "--brief", json.dumps(b2), "--session", "s2")
    rc, res = run("task", "dispatch", "--specialist", "alia", "--session", "s2")
    check("alia com coordenacao:true passa", rc == 0 and res.get("registrado"), str(res))
    rc, res = run("task", "pending", "--session", "s1")
    check("task pending lista a Task da sessao sem veredito", rc == 0 and tid in res["pendentes"] and "closed_without_gate" in res["divida"], str(res)[:160])
    parecer = os.path.join(work, "parecer.md")
    pa = art.replace("\\", "/")
    open(parecer, "w", encoding="utf-8").write(f"funciona: PASS\nevidencia: {pa}\n{ACENTO_PARECER}\ngoal-backward: PASS\nevidencia: {pa}\nveredito: PASS\n")
    rc, res = run("gate", "record", "--task", tid, "--parecer", parecer, "--session", "s1")
    check("gate record grava gate_check (parecer valido)", rc == 0 and any(e.get("event") == "gate_check" and e.get("task_id") == tid for e in eventos()), str(res)[:160])
    rc, res = run("task", "close", "--id", tid, "--artifact", art, "--veredito", "PASS")
    check("close com veredito + artifact + evidencia fecha e cumpre o schema do status",
          rc == 0 and res["task"]["status"] == "done" and espinha.validar_task_nova(res["task"], so_status=True) == [], str(res)[:200])
    rc, res = run("task", "pending", "--session", "s1")
    check("depois do veredito a Task sai das pendencias", rc == 0 and tid not in res["pendentes"], str(res)[:120])

    print("\n=== legado: as tasks antigas nao quebram ===")
    real = next((p for p in (os.path.join(V2, "..", "state.json"), os.path.join(V2, "..", "..", "..", "state.json")) if os.path.exists(p)), None)
    if real:
        copia = os.path.join(sandbox, "state-real-copia.json")
        shutil.copyfile(real, copia)
        antes = open(copia, "rb").read()
        rc1, r1 = alia.run(["--state", copia, "open", "--session", "s-leg"])
        rc2, r2 = alia.run(["--state", copia, "task", "pending", "--id", "TASK-001"])
        dados = json.load(open(copia, encoding="utf-8"))
        vazios = sum(1 for t in dados["tasks"] if t.get("status") in ("done", "review") and not str(t.get("gate_verdict") or "").strip())
        check(f"alia open/pending leem {len(dados['tasks'])} tasks legadas sem erro e sem escrever", rc1 == 0 and rc2 == 0 and open(copia, "rb").read() == antes, str(r1)[:100])
        check("closed_without_gate bate com a contagem independente (divida visivel, nao escondida)", r1["divida"]["closed_without_gate"] == vazios,
              f"{r1['divida']['closed_without_gate']} x {vazios}")
    else:
        print("[INFO] sem state.json de operador (repo publico): prova do legado so com a fixture")

    print("\n=== trava de adocao do grafo e do wiki ===")
    cli_arvore = os.path.join(mapa, "clients", "acme", "src")
    rel = os.path.join(mapa, "clients", "acme", "graphify-out", "GRAPH_REPORT.md")

    def varre(sessao, caminho=cli_arvore, host="claude", transcript=""):
        return alia.run(["graph", "check", "--session", sessao, "--tool", "Grep", "--path", caminho, "--host", host, "--transcript", transcript])

    arq = os.path.join(mapa, "clients", "acme", "src", "um.txt")
    os.makedirs(os.path.dirname(arq), exist_ok=True); open(arq, "w").write("x")
    rc, res = varre("g0", arq)
    check("Grep em UM arquivo nao e varredura: libera sem ler o mapa", rc == 0 and res["acao"] == "libera", str(res)[:160])
    rc, res = varre("g1")
    check("Grep em codigo de Client sem ler o mapa e BLOQUEADO", rc == 1 and res["regra"] == "grafo_nao_lido" and res["mapa"].endswith("GRAPH_REPORT.md"), str(res)[:160])
    alia.run(["graph", "read", "--session", "g1", "--path", rel])
    rc, res = varre("g1")
    check("depois de ler o GRAPH_REPORT a mesma varredura passa", rc == 0 and res["acao"] == "libera", str(res))
    rc, res = varre("g2")
    check("outra sessao continua barrada (leitura e por sessao)", rc == 1, str(res)[:100])
    tr = os.path.join(sandbox, "transcript.jsonl")
    open(tr, "w", encoding="utf-8").write(json.dumps({"message": {"content": [{"type": "tool_use", "name": "Read", "input": {"file_path": rel}}]}}) + "\n")
    rc, res = varre("g3", transcript=tr)
    check("host sem hook de Read: a leitura achada no transcript libera", rc == 0, str(res)[:100])
    check("a medida registra graph_scan (barrada) e graph_read", any(e.get("event") == "graph_scan" and e.get("session_id") == "g1" and e.get("lido_antes") is False for e in eventos())
          and any(e.get("event") == "graph_read" for e in eventos()))
    os.environ["ALIA_GRAPH_GATE_OFF"] = "1"
    rc, res = varre("g4")
    check("interruptor ALIA_GRAPH_GATE_OFF=1: vira aviso, nao bloqueio", rc == 0 and res["acao"] == "avisa" and "aviso" in res, str(res)[:120])
    check("com o bloqueio desligado a medida continua (graph_scan com bloqueio_desligado)",
          any(e.get("event") == "graph_scan" and e.get("session_id") == "g4" and e.get("bloqueio_desligado") for e in eventos()))
    del os.environ["ALIA_GRAPH_GATE_OFF"]
    os.makedirs(os.path.join(work, ".claude"), exist_ok=True)
    open(os.path.join(work, ".claude", "graph-gate.off"), "w").write("x")
    rc, res = varre("g5")
    check("interruptor por arquivo .claude/graph-gate.off tambem desliga so o bloqueio", rc == 0 and res["acao"] == "avisa", str(res)[:100])
    os.remove(os.path.join(work, ".claude", "graph-gate.off"))
    check("caminho de infra (memory/) nunca entra", varre("g6", os.path.join(work, "memory", "clients", "acme", "x"))[0] == 0)  # TASK-867: infra ancorada na raiz do studio
    check("caminho sem mapa e fallback: nunca bloqueia", varre("g6", os.path.join(sandbox, "sem-mapa"))[0] == 0)
    check("host sem modo declarado so avisa (matriz)", varre("g7", host="host-desconhecido")[1].get("acao") == "avisa")
    wiki = os.path.join(mapa, "vault", "wiki", "paginas")
    rc, res = varre("w1", wiki)
    check("varrer o vault sem ler wiki/index.md e bloqueado", rc == 1 and res["mapa"].endswith("index.md"), str(res)[:120])
    alia.run(["graph", "read", "--session", "w1", "--path", os.path.join(mapa, "vault", "wiki", "index.md")])
    check("depois de ler o index.md o vault libera", varre("w1", wiki)[0] == 0)

    print("\n=== adaptador Claude Code: eventos reais de hook no dispatch.py ===")
    dispatch = os.path.join(V2, "hooks", "dispatch.py")
    src_dispatch = open(dispatch, encoding="utf-8").read()
    check("dispatch.py nao le state.json (a espinha le)", "paths.state_path" not in src_dispatch and "_load_state_for_stop" not in src_dispatch)

    def hook(evento, env_extra=None):
        env = {k: v for k, v in os.environ.items()}
        env.update(env_extra or {})
        p = subprocess.run([sys.executable, dispatch], input=json.dumps(evento).encode("utf-8"), stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        try:
            return json.loads(p.stdout.decode("utf-8") or "{}")
        except ValueError:
            return {"_raw": p.stdout.decode("utf-8", "replace")}

    def nega(out, regra=None):
        h = out.get("hookSpecificOutput", {})
        return h.get("permissionDecision") == "deny" and (regra is None or regra in h.get("permissionDecisionReason", ""))

    run("task", "open", "--brief", json.dumps(brief), "--session", "sc")
    ag = lambda tipo: {"hook_event_name": "PreToolUse", "tool_name": "Agent", "session_id": "sc", "tool_input": {"subagent_type": tipo, "prompt": "x"}}
    check("Claude: Agent de Specialist sem gateway_ack e NEGADO", nega(hook(ag("acme-bruno")), "dispatch_sem_gateway_ack"))
    check("Claude: Agent do Gateway passa (e grava o ack)", not nega(hook(ag("acme-gw"))))
    check("Claude: Agent de Specialist depois do ack passa", not nega(hook(ag("acme-bruno"))))
    check("Claude: ALIA_SPINE_OFF=1 desliga so o dispatch da espinha", not nega(hook(ag("acme-rex"), {"ALIA_SPINE_OFF": "1"})))
    gp = {"hook_event_name": "PreToolUse", "tool_name": "Grep", "session_id": "sgrep", "cwd": cli_arvore, "tool_input": {"pattern": "x", "path": cli_arvore}}
    check("Claude: Grep em Client sem ler o mapa e NEGADO (grafo_nao_lido)", nega(hook(gp), "grafo_nao_lido"))
    check("Claude: Grep depois da leitura (no transcript) passa", not nega(hook(dict(gp, transcript_path=tr))))
    check("Claude: ALIA_GRAPH_GATE_OFF=1 vira aviso (additionalContext), nao negacao",
          not nega(hook(dict(gp, session_id="sgrep2"), {"ALIA_GRAPH_GATE_OFF": "1"})))
    out = hook({"hook_event_name": "SessionStart", "source": "startup", "session_id": "ss1"})
    check("Claude: SessionStart startup chama `alia open`, grava session_opened e, em dia, fica em SILENCIO",
          "[ESPINHA]" not in json.dumps(out) and any(e.get("event") == "session_opened" and e.get("session_id") == "ss1" for e in eventos()), str(out)[:160])
    dados = json.load(open(st, encoding="utf-8"))
    dados["tasks"].append({"id": "TASK-900", "client": "acme", "project": "Nome Antigo", "status": "open", "title": "legada"})
    json.dump(dados, open(st, "w", encoding="utf-8"))
    out = hook({"hook_event_name": "SessionStart", "source": "startup", "session_id": "ss2"})
    check("Claude: SessionStart so AVISA quando ha Task aberta com projeto fora do cadastro", "[ESPINHA] 1 Tasks" in json.dumps(out), str(out)[:160])
    sett = os.path.join(V2, "..", ".claude", "settings.json")
    if os.path.isfile(sett):
        m = json.load(open(sett, encoding="utf-8"))["hooks"]["PreToolUse"][0]["matcher"]
        check("hook LIGADO de verdade: o matcher do PreToolUse cobre Agent, Task, Grep e Glob",
              all(re.fullmatch(m, t) for t in ("Agent", "Task", "Grep", "Glob")), m)

    print("\n=== adaptador Codex: traducao evento -> CLI (unidade) ===")
    sys.path.insert(0, os.path.join(V2, "adapters", "codex"))
    import codex_hook  # noqa: E402
    ev = lambda cmd: {"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "cx", "cwd": cli_arvore, "tool_input": {"command": cmd}}
    check("Codex: rg PADRAO caminho -> graph check com o caminho", codex_hook.traduzir(ev(f"rg foo {cli_arvore}"))
          == [["graph", "check", "--session", "cx", "--tool", "Bash", "--path", cli_arvore, "--cwd", cli_arvore, "--host", "codex"]])
    check("Codex: ls nao tem nada a ver com a espinha", codex_hook.traduzir(ev("ls -la")) == [])
    check("Codex: cat do GRAPH_REPORT vira graph read (so registra)", codex_hook.traduzir(ev(f"cat {rel}"))[0][:2] == ["graph", "read"])
    _cr = codex_hook.traduzir(ev(f"cat {rel}"))
    check("Codex: cat do GRAPH_REPORT registra por --path (o gate novo nao aceita --command de cat)",
          _cr == [["graph", "read", "--session", "cx", "--path", rel, "--cwd", cli_arvore]], str(_cr))
    check("Codex: ls/echo citando GRAPH_REPORT nao registra", codex_hook.traduzir(ev(f"echo {rel}")) == [] and codex_hook.traduzir(ev(f"ls {rel}")) == [])
    check("Codex: python -m graphify query registra por --command", codex_hook.traduzir(ev("python -m graphify query x"))[0][:2] == ["graph", "read"])
    check("Codex: SessionStart vira alia open", codex_hook.traduzir({"hook_event_name": "SessionStart", "session_id": "cx"}) == [["open", "--session", "cx"]])
    check("Codex: com a CLI real, busca sem mapa lido e NEGADA", codex_hook.decidir(ev(f"rg foo {cli_arvore}")).get("hookSpecificOutput", {}).get("permissionDecision") == "deny")
    check("Codex: adaptador nao tem regra - CLI que libera => libera", codex_hook.decidir(ev(f"rg foo {cli_arvore}"), lambda a: (0, {"ok": True})) == {})
    check("Codex: CLI sem voto (state_ausente) => falha aberta", codex_hook.decidir(ev(f"rg foo {cli_arvore}"), lambda a: (1, {"ok": False, "regra": "state_ausente"})) == {})
    p = subprocess.run([sys.executable, os.path.join(V2, "adapters", "codex", "codex_hook.py")], input=json.dumps(ev(f"grep -rn foo {cli_arvore}")).encode(), stdout=subprocess.PIPE)
    check("Codex: o script de hook (stdin -> stdout) nega pelo processo real", b'"deny"' in p.stdout, p.stdout.decode()[:120])

    print("\n=== adaptadores OpenCode e Pi: traducao evento -> CLI (unidade, node) ===")
    node = shutil.which("node")
    if not node:
        SKIPS.append("node ausente: OpenCode e Pi sem teste de unidade")
        print("[SKIP] node ausente: adaptadores OpenCode e Pi NAO foram provados")
    else:
        run("task", "open", "--brief", json.dumps(brief), "--session", "sj")  # Task nova, sem gateway_ack, para o plugin
        fake_ok = os.path.join(sandbox, "fake_ok.py")
        fake_no = os.path.join(sandbox, "fake_no.py")
        open(fake_ok, "w").write('import json;print(json.dumps({"ok": True}))\n')
        open(fake_no, "w").write('import json,sys;print(json.dumps({"ok": False, "regra": "regra_inventada", "error": "do CLI"}));sys.exit(1)\n')
        base = os.path.join(V2, "adapters").replace("\\", "/")
        js = """
import { pathToFileURL } from 'node:url';
const B = %r;
const t = await import(pathToFileURL(B + '/traducao.mjs').href);
const oc = await import(pathToFileURL(B + '/opencode/alia-espinha.mjs').href);
const pi = await import(pathToFileURL(B + '/pi/alia-espinha.mjs').href);
const out = {};
out.oc_task = t.traduzir('opencode', 'task', {subagent_type: 'acme-bruno'}, 'sc', '/w');
out.oc_grep = t.traduzir('opencode', 'grep', {path: '/x'}, 'sc', '/w');
out.oc_bash = t.traduzir('opencode', 'bash', {command: 'ls'}, 'sc', '/w');
out.oc_sem_sessao = t.traduzir('opencode', 'task', {subagent_type: 'acme-bruno'}, '', '/w');
out.pi_task = t.traduzir('pi', 'task', {subagent_type: 'acme-bruno'}, 'sc', '/w');
out.pi_find = t.traduzir('pi', 'find', {path: '/x'}, 'sc', '/w');
out.decl = [oc.DECLARA.host, pi.DECLARA.host];
const plug = await oc.AliaEspinha({directory: %r});
const tenta = async (a) => { try { await plug['tool.execute.before']({tool: 'task', sessionID: 'sj'}, {args: {subagent_type: a}}); return null; } catch (e) { return String(e.message); } };
out.oc_real = await tenta('acme-rex');
const handlers = {};
pi.default({on: (n, f) => { handlers[n] = f; }});
const piCall = (ctx) => handlers.tool_call({toolName: 'grep', input: {path: %r}}, ctx);
out.pi_real = await piCall({sessionId: 'sp1', cwd: %r});
process.env.ALIA_BIN = %r; out.oc_fake_ok = await tenta('acme-rex'); out.pi_fake_ok = (await piCall({sessionId: 'sp2'})) ?? null;
process.env.ALIA_BIN = %r; out.oc_fake_no = await tenta('acme-rex'); out.pi_fake_no = await piCall({sessionId: 'sp3'});
console.log(JSON.stringify(out));
""" % (base, work.replace("\\", "/"), cli_arvore.replace("\\", "/"), cli_arvore.replace("\\", "/"), fake_ok.replace("\\", "/"), fake_no.replace("\\", "/"))
        p = subprocess.run([node, "--input-type=module", "-e", js], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=os.environ.copy())
        try:
            o = json.loads(p.stdout.decode("utf-8").strip().splitlines()[-1])
        except (ValueError, IndexError):
            o = {}
            print(p.stderr.decode("utf-8", "replace")[-400:])
        check("node rodou os dois adaptadores", bool(o))
        check("OpenCode: task -> alia task dispatch", o.get("oc_task") == ["task", "dispatch", "--specialist", "acme-bruno", "--session", "sc"], str(o.get("oc_task")))
        check("OpenCode: grep -> graph check; bash e chamada sem sessao nao tem nada a ver", o.get("oc_grep", [""])[:2] == ["graph", "check"]
              and o.get("oc_bash") is None and o.get("oc_sem_sessao") is None)
        check("Pi: grep|find -> graph check; Pi nao tem subagente (task nao traduz)", o.get("pi_find", [""])[:2] == ["graph", "check"] and o.get("pi_task") is None)
        check("OpenCode: tool.execute.before LANCA erro quando a CLI recusa (gateway_ack)", "dispatch_sem_gateway_ack" in str(o.get("oc_real")), str(o.get("oc_real")))
        check("Pi: tool_call devolve block quando a CLI recusa (grafo_nao_lido)", (o.get("pi_real") or {}).get("block") is True and "grafo_nao_lido" in str(o.get("pi_real")), str(o.get("pi_real")))
        check("NEGATIVO sem regra propria: CLI que libera => nenhum dos dois barra", o.get("oc_fake_ok") is None and o.get("pi_fake_ok") is None, f"{o.get('oc_fake_ok')} {o.get('pi_fake_ok')}")
        check("NEGATIVO sem regra propria: CLI que recusa com regra inventada => os dois barram com o texto dela",
              "regra_inventada" in str(o.get("oc_fake_no")) and (o.get("pi_fake_no") or {}).get("block") is True)

    print("\n=== matriz de adaptadores: cada host declara o que bloqueia e o que so avisa ===")
    matriz = json.load(open(os.path.join(V2, "adapters", "matriz.json"), encoding="utf-8"))
    for host in ("claude", "opencode", "codex", "pi"):
        h = matriz.get(host, {})
        arq = h.get("adaptador", "").split(" ")[0]
        check(f"matriz {host}: bloqueia/avisa declarados, graph_gate valido e adaptador existe",
              bool(h.get("bloqueia")) and bool(h.get("avisa")) and h.get("graph_gate") in ("bloqueia", "avisa", "nao_alcanca")
              and os.path.exists(os.path.join(V2, "..", arq)), arq)
    check("Pi: o aviso de --no-extensions (host que comanda o Pi) esta documentado no adaptador e na matriz",
          "no-extensions" in open(os.path.join(V2, "adapters", "pi", "alia-espinha.mjs"), encoding="utf-8").read() and "no-extensions" in matriz["pi"]["lacuna"])


    print("\n=== C1/C3: 2 processos abrindo Task em paralelo (5 rodadas); state truncado nega ===")
    FILHO = (
        "import sys,os,json,time\nv2,tag,brief=sys.argv[1:4]\n"
        "for s in ('flow','lib','bin'): sys.path.insert(0,os.path.join(v2,s))\n"
        "import alia, task\norig=task._next_task_id\n"
        "def lento(st):\n    r=orig(st); time.sleep(0.06); return r\n"
        "task._next_task_id=lento\n"
        "print(json.dumps(alia.run(['task','open','--brief',brief,'--session',tag])[1]))\n")

    def paralelo(mutacao, rodadas):
        tmp = tempfile.mkdtemp(prefix="alia-espinha-par-")
        atexit.register(shutil.rmtree, tmp, ignore_errors=True)
        raiz = _copia_do_motor(os.path.join(tmp, "motor"), mutacao)
        w = os.path.join(tmp, "w")
        montar(w, os.path.join(tmp, "mapa"))
        env = dict(os.environ, ALIA_LEDGER_PATH=os.path.join(w, "led.jsonl"), ALIA_STATE_PATH=os.path.join(w, "state.json"),
                   ALIA_CURRENT_TASK_PATH=os.path.join(w, "cur.json"), CLAUDE_PROJECT_DIR=w)
        b = json.dumps({"client": "acme", "project": "p", "objetivo": "provar a trava ate o fim", "paths": os.path.join(w, "artefato.md"),
                        "consumidor": "WARDEN", "destino": "interno", "exemplo_falha": "id repetido"})
        for r in range(rodadas):
            ps = [subprocess.Popen([sys.executable, "-c", FILHO, raiz, f"s{r}-{k}", b], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                  for k in range(2)]
            for p in ps:
                p.communicate()
        d = json.load(open(os.path.join(w, "state.json"), encoding="utf-8"))
        ids = [t["id"] for t in d["tasks"]]
        cur = json.load(open(os.path.join(w, "cur.json"), encoding="utf-8")) if os.path.exists(os.path.join(w, "cur.json")) else {}
        return ids, cur, os.listdir(w)

    ids, cur, arqs = paralelo(None, 5)
    check("2 processos x 5 rodadas: 11 ids, todos unicos (nenhuma Task some)", len(ids) == 11 and len(set(ids)) == 11, str(ids))
    check("Task corrente por sessao: as 10 sessoes gravadas, sem perda (C3)", sum(1 for k in cur if k != "_last") == 10, str(cur)[:120])
    check("sem tmp nem lock sobrando", not [a for a in arqs if a.endswith((".tmp", ".lock"))], str(arqs))
    ids_m, _, _ = paralelo(("lib/trava.py", "os.O_CREAT | os.O_EXCL | os.O_WRONLY", "os.O_CREAT | os.O_WRONLY"), 1)
    check("mutante sem trava (O_EXCL fora) REPETE id - a prova pega o defeito", len(ids_m) < 3 or len(set(ids_m)) < len(ids_m), str(ids_m))

    trunc = os.path.join(sandbox, "trunc.json")
    open(trunc, "w", encoding="utf-8").write('{"clients": [{"id": "acme"')
    rc, res = alia.run(["--state", trunc, "task", "pending"])
    check("state truncado: CLI sai 1 com state_corrompido", rc == 1 and res.get("regra") == "state_corrompido", str(res)[:140])
    rc, res = alia.run(["--state", trunc, "task", "open", "--brief", "{}"])
    check("state truncado: task open tambem nega (nao sobrescreve)", rc == 1 and res.get("regra") == "state_corrompido"
          and open(trunc, encoding="utf-8").read() == '{"clients": [{"id": "acme"', str(res)[:140])
    check("state_corrompido NAO e voto-livre nos adaptadores (o gate nega)",
          "state_corrompido" not in codex_hook.SEM_VOTO)
    rc, res = alia.run(["--state", st, "task", "open", "--brief", "[1]"])
    check("brief que nao e objeto: recusa com regra", rc == 1 and res.get("regra") == "brief_invalido", str(res)[:120])

    print("\n=== C8/C9: adaptador falha aberto registra; Codex barra encadeado; fatia relativa ===")
    alvo_c = cli_arvore
    for cmd in (f"cd x && rg foo {alvo_c}", f"Select-String -Pattern foo -Path {alvo_c}", f"git grep foo {alvo_c}",
                f"findstr /s foo {alvo_c}", f"ls; grep -rn foo {alvo_c}"):
        got = [c for c in codex_hook.traduzir(ev(cmd)) if c[:2] == ["graph", "check"]]
        check(f"Codex barra: {cmd[:34]}", bool(got) and got[0][got[0].index("--path") + 1].strip("'\"") == alvo_c, str(got)[:100])
    src = open(os.path.join(V2, "adapters", "codex", "codex_hook.py"), encoding="utf-8").read()
    velho = "for alvo in _alvos_da_busca(comando):"
    assert velho in src
    import importlib.util as _iu
    mut = os.path.join(sandbox, "codex_hook_mut.py")
    open(mut, "w", encoding="utf-8").write(src.replace(velho, "for alvo in _alvos_da_busca(comando)[:0]:"))
    spec = _iu.spec_from_file_location("codex_hook_mut", mut)
    m = _iu.module_from_spec(spec)
    spec.loader.exec_module(m)
    check("mutante do Codex (nao varre trechos) NAO barra - a prova pega o defeito",
          not [c for c in m.traduzir(ev(f"cd x && rg foo {alvo_c}")) if c[:2] == ["graph", "check"]])
    codex_hook.decidir(ev(f"rg foo {alvo_c}"), lambda a: (1, {"ok": False, "regra": "erro_interno", "error": "boom"}))
    rc, res = run("task", "pending", "--session", "cx")
    check("Codex falha aberto registra no ledger e task pending avisa o host sem trava",
          rc == 0 and res.get("hosts_sem_trava") == ["codex"] and "aviso" in res, str(res)[:160])
    if shutil.which("node"):
        led_js = os.path.join(sandbox, "led-js.jsonl")
        url = "file:///" + os.path.join(V2, "adapters", "traducao.mjs").replace("\\", "/")
        prog = (f"import {{recusa}} from '{url}'; "
                "console.log(String(recusa({code:1,json:{},argv:['task','dispatch','--session','js-sess']},'pi')));")
        p = subprocess.run(["node", "--input-type=module", "-e", prog], env=dict(os.environ, ALIA_LEDGER_PATH=led_js),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        linhas = open(led_js, encoding="utf-8").read() if os.path.exists(led_js) else ""
        check("Pi/OpenCode (JS): sem JSON da CLI libera mas registra adapter_falha_aberta",
              p.stdout.decode().strip() == "null" and "adapter_falha_aberta" in linhas and '"pi"' in linhas, linhas[:120] + p.stderr.decode()[-120:])
    else:
        SKIPS.append("node ausente: registro de falha aberta do adaptador JS nao provado")
    check("fatia relativa resolve pela raiz do estudio (C9)", task_model.validar_fatias("artefato.md#L1", [work]) == [])
    check("fatia `#L9` sem faixa alem do arquivo e problema (C9)", len(task_model.validar_fatias("artefato.md#L9", [work])) == 1)

    for s in SKIPS:
        print(f"[SKIP] {s}")
    print(f"\n{'FALHOU: ' + str(len(FAILS)) + ' prova(s)' if FAILS else 'espinha: tudo verde'}")
    return 1 if FAILS else 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--cenario")
    ap.add_argument("--v2")
    ap.add_argument("--work")
    a = ap.parse_args()
    if a.cenario:
        print(json.dumps(cenario(a.cenario, a.v2, a.work), ensure_ascii=False))
        raise SystemExit(0)
    raise SystemExit(principal())
