# -*- coding: utf-8 -*-
"""Prova do CICLO (2.1.2, TASK-862): cada acao do ciclo de trabalho tem pelo menos UM ator
liberado pelo guard (dispatch.py), SEM interruptores. Pasta temporaria sem git e com git.
Acoes: abrir task, delegar, escrever entrega, fechar, gravar memoria, publicar, propagar.
Atores: sessao principal (sem agent_id) e sub-agente (com agent_id). Zero ator = deadlock = FAIL.
Prova pelo negativo: cada mutante do dispatch que reintroduz um deadlock tem que dar FAIL. Publicar so existe com git (marcador exige
HEAD): sem git, publicar e inalcancavel por construcao e fica fora da matriz.
Uso: python test_ciclo.py
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
DISPATCH = os.path.join(V2, "hooks", "dispatch.py")
FAILS: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    print(f"[{'PASS' if cond else 'FAIL'}] {name} {detail}")
    if not cond:
        FAILS.append(name)


def _env(root: str, extra: dict | None = None) -> dict:
    env = {k: v for k, v in os.environ.items() if not (k.startswith("ALIA_") and k.endswith("_OFF"))}
    env.update({"CLAUDE_PROJECT_DIR": root, "ALIA_LEDGER_PATH": os.path.join(root, "activity.jsonl")})
    env.update(extra or {})
    return env


_MODS: dict = {}


def _mod(dispatch: str):
    import importlib.util
    mod = _MODS.get(dispatch)
    if mod is None:
        spec = importlib.util.spec_from_file_location("ciclo_d%d" % len(_MODS), dispatch)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        _MODS[dispatch] = mod
    return mod


def _run_inproc(dispatch: str, root: str, event: dict, extra: dict | None = None) -> dict:
    """Mesmo handler que o main() chama, sem subir um processo por evento (o check.py roda perto do
    teto de 30 s e dezenas de processos disputavam CPU com as outras baterias)."""
    mod = _mod(dispatch)
    antes = dict(os.environ)
    novo = _env(root, extra)
    os.environ.clear()
    os.environ.update(novo)
    try:
        if event.get("hook_event_name") == "PostToolUse":
            mod.handle_post_write_artifact_marker(event)
            return {}
        return mod.handle_pretooluse_guard(event)
    finally:
        os.environ.clear()
        os.environ.update(antes)


def _run(dispatch: str, root: str, event: dict, extra: dict | None = None) -> dict:
    if event.get("tool_name") != "Agent":
        return _run_inproc(dispatch, root, event, extra)
    p = subprocess.run([sys.executable, dispatch], input=json.dumps(event).encode("utf-8"),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=_env(root))
    try:
        return json.loads(p.stdout.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return {"_raw": p.stdout.decode("utf-8", "replace")}


def _nega(out: dict) -> bool:
    return (out.get("hookSpecificOutput") or {}).get("permissionDecision") == "deny"


def _ev(tool: str, ti: dict, sub: bool) -> dict:
    ev = {"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": ti,
          "session_id": "ciclo-s"}
    if sub:
        ev["agent_id"] = "x-1"
    return ev


def _head(repo: str) -> str:
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, stdout=subprocess.PIPE
                          ).stdout.decode().strip()


def _fixture(com_git: bool) -> tuple[str, str]:
    root = tempfile.mkdtemp(prefix="alia-ciclo-")
    for d in ("memory", "artifacts", os.path.join("clients", "demo", "artifacts")):
        os.makedirs(os.path.join(root, d), exist_ok=True)
    with open(os.path.join(root, "state.json"), "w", encoding="utf-8") as fh:
        json.dump({"clients": [{"id": "demo", "squad": {}}],
                   "tasks": [{"id": "TASK-9", "client": "demo", "status": "open"}]}, fh)
    with open(os.path.join(root, ".alia-current-task.json"), "w", encoding="utf-8") as fh:
        json.dump({"_last": "TASK-9", "ciclo-s": "TASK-9"}, fh)
    with open(os.path.join(root, "clients", "demo", "artifacts", "e.md"), "w", encoding="utf-8") as fh:
        fh.write("entrega")
    prod = os.path.join(root, "produto")
    os.makedirs(prod)
    if com_git:
        g = ["git", "-c", "user.email=t@t.local", "-c", "user.name=t"]
        subprocess.run(["git", "init", "-q"], cwd=prod)
        with open(os.path.join(prod, "f.txt"), "w", encoding="utf-8") as fh:
            fh.write("x")
        subprocess.run(g + ["add", "f.txt"], cwd=prod)
        subprocess.run(g + ["commit", "-q", "-m", "x"], cwd=prod)
        os.makedirs(os.path.join(root, ".alia"), exist_ok=True)
        with open(os.path.join(root, ".alia", "check-ok.json"), "w", encoding="utf-8") as fh:
            json.dump({"ts": "agora", "head": _head(prod), "repo": prod}, fh)
    return root, prod


def _acoes(root: str, com_git: bool) -> dict:
    pub = "powershell -ExecutionPolicy Bypass -File clients/alia-flow-lab/scripts/publish-release.ps1"
    upd = "powershell -ExecutionPolicy Bypass -File scripts/update-engine.ps1 -SemMerge"
    a = {
        "abrir task": ("Bash", {"command": "python v2/bin/task.py open TASK-9 demo teste"}),
        "delegar": ("Agent", {"subagent_type": "Explore", "prompt": "faz"}),
        "escrever entrega": ("Write", {"file_path": os.path.join(root, "clients", "demo", "artifacts", "TASK-9", "e.md"),
                                       "content": "entrega"}),
        "fechar": ("Bash", {"command": "python v2/bin/task.py close TASK-9 --artifact "
                                       + os.path.join(root, "clients", "demo", "artifacts", "e.md")}),
        "gravar memoria": ("Write", {"file_path": os.path.join(root, "memory", "nota.md"), "content": "nota"}),
        "propagar": ("Bash", {"command": upd}),
    }
    if com_git:
        a["publicar"] = ("Bash", {"command": pub})
    return a


def _matriz(dispatch: str, root: str, com_git: bool) -> dict[str, list[str]]:
    """acao -> atores liberados."""
    acoes = _acoes(root, com_git)
    jobs = [(n, ator, sub) for n in acoes for ator, sub in (("principal", False), ("subagente", True))]
    negou = [_nega(_run(dispatch, root, _ev(*acoes[j[0]], j[2]))) for j in jobs]
    res = {n: [] for n in acoes}
    for (n, ator, _s), nv in zip(jobs, negou):
        if not nv:
            res[n].append(ator)
    return res


_MUT_BASE: list = []


def _mutante(nome: str, velho: str, novo: str) -> str:
    src = open(DISPATCH, encoding="utf-8").read()
    assert velho in src, "mutante '" + nome + "': trecho nao achado no dispatch"
    # o dispatch importa lib/ ao lado da pasta dele: UMA copia de lib/ compartilhada (<base>/lib) e cada
    # mutante mora em <base>/hN/dispatch.py (a copia da lib por mutante custava ~30 mutantes x copytree)
    if not _MUT_BASE:
        _MUT_BASE.append(tempfile.mkdtemp(prefix="alia-ciclo-mut-"))
        shutil.copytree(os.path.join(V2, "lib"), os.path.join(_MUT_BASE[0], "lib"),
                        ignore=shutil.ignore_patterns("__pycache__"))
    d = os.path.join(_MUT_BASE[0], "h%d" % len(os.listdir(_MUT_BASE[0])))
    os.makedirs(d)
    out = os.path.join(d, "dispatch.py")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(src.replace(velho, novo, 1))
    return out


for com_git in (False, True):
    rot = "com git" if com_git else "sem git"
    root, prod = _fixture(com_git)
    try:
        print(f"\n=== ciclo {rot}: cada acao tem >= 1 ator liberado ===")
        for acao, livres in _matriz(DISPATCH, root, com_git).items():
            check(f"{rot}: '{acao}' tem ator liberado", bool(livres), "atores=" + (",".join(livres) or "NENHUM"))
        if com_git:
            m = _matriz(DISPATCH, root, True)
            check("com git: publicar e so da sessao principal (L70)", m["publicar"] == ["principal"], str(m["publicar"]))
    finally:
        shutil.rmtree(root, ignore_errors=True)

print("\n=== prova pelo negativo: mutante que reintroduz o deadlock tem que dar FAIL ===")
_MUT = [
    ("A guard ignora o repo gravado no marcador", 'repo_dir = dados.get("repo") or os.path.dirname(os.path.dirname(marker))',
     "repo_dir = os.path.dirname(os.path.dirname(marker))", "publicar"),
]
root, prod = _fixture(True)
try:
    for nome, velho, novo, acao in _MUT:
        mut = _mutante(nome, velho, novo)
        tool, ti = _acoes(root, True)[acao]
        base = _nega(_run(DISPATCH, root, _ev(tool, ti, False)))
        mutou = _nega(_run(mut, root, _ev(tool, ti, False)))
        check(f"negativo {nome}: real libera a sessao principal", not base)
        check(f"negativo {nome}: mutante e pego (principal passa a ser negada)", mutou)

finally:
    shutil.rmtree(root, ignore_errors=True)

# ---------------------------------------------------------------------------
# 2.1.3 (TASK-862, frente A): furos do deep review dos hooks. Cada conserto: o real acerta E o mutante que
# reabre o furo inverte o resultado (prova pelo negativo). Tudo em processo (barato).
# ---------------------------------------------------------------------------
print("\n=== 2.1.3 hooks: P0/P1 e falsos positivos, cada conserto com mutante ===")
import threading  # noqa: E402
import time  # noqa: E402


def _motivo(out: dict) -> str:
    return str((out.get("hookSpecificOutput") or {}).get("permissionDecisionReason", ""))


def _git_repo(pasta: str) -> str:
    os.makedirs(pasta, exist_ok=True)
    g = ["git", "-c", "user.email=t@t.local", "-c", "user.name=t"]
    subprocess.run(["git", "init", "-q"], cwd=pasta)
    with open(os.path.join(pasta, "f.txt"), "w", encoding="utf-8") as fh:
        fh.write("x")
    subprocess.run(g + ["add", "f.txt"], cwd=pasta)
    subprocess.run(g + ["commit", "-q", "-m", "x"], cwd=pasta)
    return pasta


root, prod = _fixture(True)
outro = _git_repo(os.path.join(root, "outro"))
RAIZ = root.replace("\\", "/")
try:
    def _par(rotulo: str, ev: dict, nega: bool, velho: str, novo: str, extra: dict | None = None,
             fonte: str = "dispatch") -> None:
        """real acerta (nega ou libera) E o mutante inverte."""
        real = _nega(_run(DISPATCH, root, ev, extra))
        check(f"{rotulo}: real {'NEGA' if nega else 'LIBERA'}", real == nega, _motivo(_run(DISPATCH, root, ev, extra)))
        mut = _mutante(rotulo, velho, novo)
        check(f"negativo {rotulo}: mutante reabre o furo (resultado inverte)", _nega(_run(mut, root, ev, extra)) != nega)

    # P1-1: comando quebrado por linha nova
    _par("P1-1 linha nova esconde o kernel", _ev("Bash", {"command": "echo hi\ncp a engine/x.md"}, True), True,
         "for clausula in _SPLIT_CLAUSULAS_RE.split(command):  # inclui linha nova (P1-1)",
         'for clausula in re.split(r"[;&|]+", command):  # ')
    # P1-2: engine/ relativo e kernel
    _par("P1-2 engine/ relativo", _ev("Bash", {"command": "echo x > engine/y.md"}, True), True,
         'if "/engine/" in pn or pn.endswith("/engine"):', 'if "/engine/" in p or p.endswith("/engine"):')
    # P1-3: `..` normalizado
    _par("P1-3 .. no caminho", _ev("Write", {"file_path": RAIZ + "/clients/alia-flow-lab/../../engine/a.md", "content": "x"}, True),
         True, "return posixpath.normpath(_nome_longo(p))", "return _nome_longo(p)")
    # cwd do evento resolve o relativo: dentro da fonte, `engine/a.md` NAO e kernel
    _ev_cwd = {**_ev("Bash", {"command": "echo x > engine/a.md"}, True), "cwd": RAIZ + "/clients/alia-flow-lab"}
    _par("cwd resolve relativo (dentro da fonte do motor)", _ev_cwd, False,
         r'return cwd.replace("\\", "/").rstrip("/") + "/" + n', "return p")
    _pm = _mod(DISPATCH)

    # P1-7: ninguem forja check-ok.json; o repo do push tem que ser o do marcador
    _par("P1-7 Write em .alia/check-ok.json", _ev("Write", {"file_path": RAIZ + "/.alia/check-ok.json", "content": "{}"}, True),
         True, "if _e_marcador_proprio(_fp):", "if False:")
    _par("P1-7 Bash forja check-ok.json (subagente)", _ev("Bash", {"command": "echo {} > .alia/check-ok.json"}, True), True,
         'if _comando_forja_marcador(str(tool_input.get("command") or ""), cwd):', "if False:")
    check("P1-7 positivo: ler o marcador por Bash passa",
          not _nega(_run(DISPATCH, root, _ev("Bash", {"command": "cat .alia/check-ok.json"}, True))))
    _par("P1-7 push de OUTRO repo com marcador do produto", _ev("Bash", {"command": f'git -C "{outro}" push origin main'}, False),
         True, "if topo and not _mesmo_caminho(topo, repo_dir):", "if False:")
    check("P1-7 positivo: push do repo do marcador passa",
          not _nega(_run(DISPATCH, root, _ev("Bash", {"command": f'git -C "{prod}" push origin main'}, False))))

    # marcador com VERSION: repo uma versao atras publica; repo a frente nega (o repo so recebe a nova pelo publicar)
    _mkp = os.path.join(root, ".alia", "check-ok.json")
    _mk = json.load(open(_mkp, encoding="utf-8"))
    _mk["version"] = "2.1.3"
    json.dump(_mk, open(_mkp, "w", encoding="utf-8"))
    _push_prod = _ev("Bash", {"command": f'git -C "{prod}" push origin main'}, False)
    _velho_v = 'if tuple(int(x) for x in ver_repo.split(".")) > tuple(int(x) for x in str(ver_marc).split(".")):'
    for _vr, _nega_v in (("2.1.2", False), ("2.1.3", False), ("2.1.4", True)):
        open(os.path.join(prod, "VERSION"), "w", encoding="utf-8").write(_vr + "\n")
        if _nega_v:
            _par(f"marcador 2.1.3 x repo em {_vr} (a frente)", _push_prod, True, _velho_v, "if False:")
        else:
            check(f"marcador 2.1.3 x repo em {_vr} (atras ou igual) publica", not _nega(_run(DISPATCH, root, _push_prod)))
    os.remove(os.path.join(prod, "VERSION"))

    # P1-8 e P2-10: publicacao em posicao de comando
    _old_pub = 'if re.search(r"(?i)\\b(git push|npm publish|package-release|publish-release)\\b", command):'
    for _c in ("git -C r push origin main", "git  push", "gh release create v1", "pnpm publish"):
        _par("P1-8 L70 ve `" + _c + "`", _ev("Bash", {"command": _c}, True), True, "if _comando_publica(command):", _old_pub)
    _par("P2-10 ler o script de publicar nao e publicar", _ev("Bash", {"command": "cat scripts/publish-release.ps1"}, True), False,
         "if _comando_publica(command):", _old_pub)

    # P2-9: `>` so e redirecionamento fora de aspas/seta/heredoc; `2>arq` conta
    _velho9 = 'elif ch == ">" and not (i and texto[i - 1] in "-="):'
    _par("P2-9 seta `->` nao e redirecionamento", _ev("Bash", {"command": "echo ok -> engine/readme.md"}, True), False,
         _velho9, 'elif ch == ">" and not (i and texto[i - 1] in "XX"):')
    _par("P2-9 `2>arq` e redirecionamento", _ev("Bash", {"command": "ls 2>engine/z.md"}, True), True,
         _velho9, 'elif ch == ">" and not (i and texto[i - 1] in "-=0123456789"):')
    _par("P2-9 corpo de heredoc e texto, nao comando",
         _ev("Bash", {"command": "cat <<EOF > docs/f.md\ncp a engine/x.md\nEOF"}, True), False,
         "command = _sem_corpo_heredoc(command)  # o corpo do heredoc e TEXTO, nao comando (P2-9)", "pass")
    check("P2-9 `<a>` entre aspas nao e redirecionamento", _pm._extract_write_targets("echo '<a>x</a>' ; ls") == [])

    # segredo: minusculo, Bearer, `sk-` com fronteira
    _fake = lambda t: _ev("Write", {"file_path": RAIZ + "/docs/n.md", "content": t}, True)
    _tok = 'token = "' + "a1" * 12 + '"'
    _par("segredo minusculo `token = \"...\"`", _fake(_tok), True, r"(?i)\b\w*(?:key|token|secret", r"(?i)\bQQ\w*(?:key|token|secret")
    _par("segredo Bearer", _fake("Authorization: Bearer " + "Z" * 30), True, r'r"(?i)\bbearer\s+', r'r"(?i)\bQbearer\s+')
    _par("`task-<20 letras>` nao e segredo", _fake("ver task-" + "abcdefghij" * 3 + " ok"), False,
         r'r"(?<![A-Za-z0-9_\-])sk-[A-Za-z0-9]{20,}"', r'r"sk-[A-Za-z0-9]{20,}"')
    check("segredo: `cache_key = nome_de_variavel_comprido` (codigo) nao e segredo",
          not _nega(_run(DISPATCH, root, _fake("cache_key = nome_de_variavel_comprido_qualquer"))))

    # MultiEdit tem guard
    _me = lambda fp, ns: _ev("MultiEdit", {"file_path": fp, "edits": [{"old_string": "a", "new_string": ns}]}, True)
    _velho_me = 'if tool_name in ("Write", "Edit", "NotebookEdit", "MultiEdit"):\n        path = tool_input'
    _novo_me = 'if tool_name in ("Write", "Edit", "NotebookEdit"):\n        path = tool_input'
    _par("MultiEdit com segredo no texto novo", _me(RAIZ + "/docs/a.md", "sk-" + "B" * 24), True, _velho_me, _novo_me)
    _par("MultiEdit no kernel", _me(RAIZ + "/engine/x.md", "x"), True, _velho_me, _novo_me)

    # nome 8.3 (so onde o volume gera nome curto)
    if os.name == "nt":
        import ctypes
        _longo = os.path.join(root, "clients", "demo-cliente-comprido", "squad")
        os.makedirs(_longo, exist_ok=True)
        _buf = ctypes.create_unicode_buffer(1024)
        ctypes.windll.kernel32.GetShortPathNameW(_longo, _buf, 1024)
        _curto = _buf.value.replace("\\", "/")
        if "~" in _curto.split("clients/", 1)[-1]:
            _par("8.3: nome curto da pasta do Client nao escapa da guarda 4",
                 _ev("Write", {"file_path": _curto + "/a.md", "content": "x"}, False), True,
                 'if os.name != "nt" or "~" not in p:\n        return p', "return p")
        else:
            print("[INFO] volume sem nomes 8.3: prova do nome curto nao se aplica nesta maquina")

    # marcador de artifact so de sub-agente
    _led = os.path.join(root, "activity.jsonl")
    _post = {"hook_event_name": "PostToolUse", "tool_name": "Write", "session_id": "ciclo-s",
             "tool_input": {"file_path": RAIZ + "/clients/demo/artifacts/TASK-77/e.md", "content": "x"}}
    _run(DISPATCH, root, _post)
    _n_marc = lambda: sum(1 for l in open(_led, encoding="utf-8") if '"artifact_write"' in l) if os.path.exists(_led) else 0
    check("marcador artifact_write: a sessao principal (sem agent_id) nao grava", _n_marc() == 0)
    _run(DISPATCH, root, {**_post, "agent_id": "ag-9"})
    check("marcador artifact_write: o sub-agente grava", _n_marc() == 1)
    _mm = _mutante("marcador de qualquer ator", "    if not event.get(\"agent_id\"):\n        return  # 2.1.3", "    if False:\n        return  # 2.1.3")
    _run(_mm, root, _post)
    check("negativo marcador: mutante deixa a sessao principal gravar", _n_marc() == 2)

    # corridas: o lock segura o 2o escritor; escrita atomica; PermissionError do O_EXCL e retry
    def _espera_lock(dispatch: str, chamada, lock: str, arquivo: str) -> tuple[bool, bool]:
        """(escreveu enquanto o lock estava preso, escreveu depois de solto)."""
        os.makedirs(os.path.dirname(lock), exist_ok=True)
        open(lock, "w").close()  # "outro processo" segura o lock
        th = threading.Thread(target=chamada)
        th.start()
        time.sleep(0.15)
        durante = os.path.exists(arquivo)
        os.remove(lock)
        th.join(10)
        return durante, os.path.exists(arquivo)

    def _cenario_lock(dispatch: str, qual: str) -> tuple[bool, bool]:
        d = tempfile.mkdtemp(prefix="alia-ciclo-lock-")
        antes = dict(os.environ)
        os.environ.update({"ALIA_LEDGER_PATH": os.path.join(d, "activity.jsonl"), "CLAUDE_PROJECT_DIR": d})
        try:
            if qual == "contador":
                m = _mod(dispatch)
                alvo = os.path.join(d, "activity.jsonl.subagentes.json")
                return _espera_lock(dispatch, lambda: m._subagent_cap_check({"session_id": "L"}), alvo + ".lock", alvo)
            import importlib.util
            sys.path.insert(0, os.path.join(V2, "lib"))
            spec = importlib.util.spec_from_file_location("gg_" + str(abs(hash(dispatch))), dispatch)
            g = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(g)
            import ledger as _l
            alvo = os.path.join(d, "activity.jsonl.grafo.json")
            os.makedirs(os.path.join(d, "graphify-out"), exist_ok=True)  # TASK-867: a consulta grava o escopo do cwd (precisa de mapa)
            open(os.path.join(d, "graphify-out", "GRAPH_REPORT.md"), "w").write("# God Nodes\n")
            return _espera_lock(dispatch, lambda: g.registrar_leitura(_l, "L", command="python -m graphify query x", cwd=d), alvo + ".lock", alvo)
        finally:
            os.environ.clear()
            os.environ.update(antes)

    _GG = os.path.join(V2, "lib", "grafo_gate.py")

    def _mut_gg(velho: str, novo: str) -> str:
        d = tempfile.mkdtemp(prefix="alia-ciclo-mutgg-")
        out = os.path.join(d, "grafo_gate.py")
        src = open(_GG, encoding="utf-8").read()
        assert velho in src, "mutante do grafo_gate: trecho nao achado"
        open(out, "w", encoding="utf-8").write(src.replace(velho, novo, 1))
        return out

    for _qual, _fonte, _velho, _novo in (
            ("contador", DISPATCH, "with trava.trava(path):", "if True:"),
            ("grafo", _GG, "with trava.trava(_sidecar()):  # 2.1.3: ler-alterar-gravar sob lock (duas", "if True:  # (duas")):
        _durante, _depois = _cenario_lock(_fonte, _qual)
        check(f"corrida {_qual}: com o lock preso o escritor ESPERA e grava quando solta", not _durante and _depois,
              f"durante={_durante} depois={_depois}")
        _mutf = _mutante("corrida " + _qual, _velho, _novo) if _fonte == DISPATCH else _mut_gg(_velho, _novo)
        _durante_m, _ = _cenario_lock(_mutf, _qual)
        check(f"negativo corrida {_qual}: mutante sem lock grava por cima (o teste acima o pega)", _durante_m)

    # grafo_gate: `tool_use_id` de um RESULTADO e qualquer mencao ao relatorio nao sao leitura do mapa
    def _lido(fonte: str, linhas: list[str]) -> bool:
        spec = _iu_gg.spec_from_file_location("gg_t%d" % abs(hash(fonte)), fonte)
        g = _iu_gg.module_from_spec(spec)
        spec.loader.exec_module(g)
        tr = os.path.join(tempfile.mkdtemp(prefix="alia-ciclo-tr-"), "t.jsonl")
        open(tr, "w", encoding="utf-8").write("\n".join(linhas) + "\n")
        return g._lido_no_transcript(tr, "C:/x/clients/c1/graphify-out/GRAPH_REPORT.md", "clients/c1")
    import importlib.util as _iu_gg
    sys.path.insert(0, os.path.join(V2, "lib"))
    _l_res = '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"existe C:/x/clients/c1/graphify-out/GRAPH_REPORT.md"}]}}'
    _l_uso = '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"C:/x/clients/c1/graphify-out/GRAPH_REPORT.md"}}]}}'
    check("grafo: resultado de ferramenta (tool_use_id) que cita o relatorio NAO conta como leitura", not _lido(_GG, [_l_res]))
    check("grafo: o tool_use que le o relatorio conta", _lido(_GG, [_l_uso]))
    # TASK-867: so tool_use Read com file_path == mapa conta (um Edit/Grep sobre o relatorio nao e leitura)
    _l_edit = _l_uso.replace('"name":"Read"', '"name":"Edit"')
    check("grafo: Edit do relatorio NAO conta como leitura", not _lido(_GG, [_l_edit]))
    check("negativo grafo: mutante que aceita qualquer ferramenta como leitura do mapa",
          _lido(_mut_gg('if it.get("name") == "Read":', 'if True:'), [_l_edit]))

    # trava.py: PermissionError na disputa do O_EXCL tambem e retry (Windows) e escrita atomica
    import importlib.util as _iu
    _TV = os.path.join(V2, "lib", "trava.py")

    def _carrega_trava(path: str):
        sp = _iu.spec_from_file_location("trava_t%d" % abs(hash(path)), path)
        mo = _iu.module_from_spec(sp)
        sp.loader.exec_module(mo)
        return mo

    def _lock_sob_permission_error(mod) -> bool:
        d = tempfile.mkdtemp(prefix="alia-ciclo-tv-")
        alvo = os.path.join(d, "x.json")
        real_open, n = os.open, {"i": 0}

        def _falso(p, *a, **k):
            if str(p).endswith(".lock") and n["i"] < 3:
                n["i"] += 1
                raise PermissionError(13, "disputa")
            return real_open(p, *a, **k)
        os.open = _falso
        try:
            with mod.trava(alvo, espera_s=3):
                return os.path.exists(alvo + ".lock")
        finally:
            os.open = real_open
    check("trava: PermissionError na disputa do O_EXCL e retry e o lock e obtido", _lock_sob_permission_error(_carrega_trava(_TV)))
    _tm = os.path.join(tempfile.mkdtemp(prefix="alia-ciclo-tvm-"), "trava.py")
    open(_tm, "w", encoding="utf-8").write(open(_TV, encoding="utf-8").read().replace(
        "except (FileExistsError, PermissionError):", "except FileExistsError:", 1))
    check("negativo trava: mutante que nao trata PermissionError segue SEM lock",
          not _lock_sob_permission_error(_carrega_trava(_tm)))
    _tv = _carrega_trava(_TV)
    _arq = os.path.join(tempfile.mkdtemp(prefix="alia-ciclo-at-"), "d.json")
    _tv.gravar_atomico(_arq, '{"a": 1}')
    _tv.gravar_atomico(_arq, '{"a": 2}')
    check("trava: gravar_atomico troca o conteudo inteiro e nao deixa tmp", json.load(open(_arq, encoding="utf-8")) == {"a": 2}
          and not [f for f in os.listdir(os.path.dirname(_arq)) if f.endswith(".tmp")])
    _soma = os.path.join(os.path.dirname(_arq), "soma.json")
    _tv.gravar_atomico(_soma, "0")

    def _incrementa() -> None:
        for _ in range(40):
            with _tv.trava(_soma):
                _tv.gravar_atomico(_soma, str(int(open(_soma, encoding="utf-8").read()) + 1))
    _ths = [threading.Thread(target=_incrementa) for _ in range(5)]
    for _t in _ths:
        _t.start()
    for _t in _ths:
        _t.join()
    check("trava: 5 escritores x 40 incrementos sob lock somam 200 (nenhum se perde)", int(open(_soma, encoding="utf-8").read()) == 200)
finally:
    shutil.rmtree(root, ignore_errors=True)

if FAILS:
    print(f"FALHOU: {len(FAILS)} prova(s): {FAILS}")
    sys.exit(1)
print("TODAS AS PROVAS DO CICLO PASSARAM")
