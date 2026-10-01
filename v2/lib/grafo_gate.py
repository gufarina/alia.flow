"""grafo_gate.py - trava de ADOCAO do grafo e do wiki.

Reconstroi na 2.0 o gate do grafo que existia na 1.x: varrer codigo/docs de um Client com Grep/Glob
sem ter lido, NA SESSAO, o `GRAPH_REPORT.md` do mapa (ou o `wiki/index.md` do vault) e recusado ou
avisado, conforme a matriz do host (adapters/matriz.json: graph_gate). A regra mora aqui; o adaptador
so traduz o evento do host em `alia graph check` / `alia graph read`.

Escopo (igual ao ledger da 1.x): dentro do studio `clients/<id>`; fora, `external:<pasta que contem o
graphify-out>`; vault, `wiki:<pasta wiki>`. Sem mapa achado = fallback, NUNCA bloqueia. Caminho de
infra (memory/, _backups/, .claude/, node_modules, scratchpad, temp) nunca entra.

Interruptor de emergencia (desliga so o BLOQUEIO; a medida continua): ALIA_GRAPH_GATE_OFF=1 ou o
arquivo `.claude/graph-gate.off` na raiz do estudio. Evidencia de leitura: sidecar `<ledger>.grafo.json`
(O(1), nunca reler o ledger) + eventos graph_read / graph_scan no ledger (insumo da medida de adocao).
"""
from __future__ import annotations

import json
import os
import re

import espinha
import paths
import trava

INFRA = ("/node_modules/", "/scratchpad/", "/.git/")  # em qualquer ponto
INFRA_RAIZ = ("memory", "_backups", ".claude")  # so na raiz do estudio (um /memory/ de codebase externo e codigo)
RELATORIOS = ("graph_report.md", "graph.json")
# Consulta ao grafo = comando que COMECA por `python -m graphify query|path|explain` (nao qualquer menção)
_CONSULTA_GRAPHIFY = re.compile(r"^\s*(?:py|python3?)(?:\.exe)?\s+-m\s+graphify\s+(?:query|path|explain)\b", re.IGNORECASE)
_GRAPH_ARG = re.compile(r"--graph(?:=|\s+)(\"[^\"]+\"|'[^']+'|\S+)")
_TOOL_USE_LINHA = re.compile(r'"type"\s*:\s*"tool_use"')


def _n(p: str) -> str:
    return (p or "").replace("\\", "/")


def _infra(ap: str) -> bool:
    low = _n(ap).lower() + "/"
    if any(m in low for m in INFRA):
        return True
    raiz = _n(paths.studio_root()).lower().rstrip("/") + "/"
    return any(low.startswith(raiz + d + "/") for d in INFRA_RAIZ)


def _mesmo_arquivo(a: str, b: str) -> bool:
    """normcase + realpath: trata nome 8.3 e letra de drive maiuscula/minuscula."""
    try:
        return os.path.normcase(os.path.realpath(a)) == os.path.normcase(os.path.realpath(b))
    except (OSError, ValueError):
        return False


def _escopo_da_consulta(command: str, cwd: str) -> str | None:
    """Escopo de um `python -m graphify query|path|explain`: o do --graph, senao o do cwd. None = nao e
    consulta (ou sem mapa no escopo)."""
    if not command or not _CONSULTA_GRAPHIFY.search(command):
        return None
    m = _GRAPH_ARG.search(command)
    alvo = m.group(1).strip("\"'") if m else ""
    achado = achar_escopo(os.path.dirname(os.path.dirname(alvo)) if alvo else "", cwd) if alvo else achar_escopo("", cwd)
    return achado["escopo"] if achado else None


def achar_escopo(path: str, cwd: str = "") -> dict | None:
    """{"escopo","mapa","tipo"} do mapa que cobre `path`, ou None (sem mapa = nunca bloqueia)."""
    if not path:
        path = cwd
    if not path:
        return None
    ap = _n(os.path.abspath(path if os.path.isabs(path) else os.path.join(cwd or os.getcwd(), path)))
    if _infra(ap):
        return None
    # wiki: ancestral chamada wiki com index.md, ou o vault raiz (pasta que tem wiki/index.md)
    d = ap
    for _ in range(25):
        if os.path.basename(d) == "wiki" and os.path.isfile(d + "/index.md"):
            return {"escopo": f"wiki:{d.lower()}", "mapa": d + "/index.md", "tipo": "wiki"}
        if d == ap and os.path.isfile(d + "/wiki/index.md"):
            return {"escopo": f"wiki:{d.lower()}/wiki", "mapa": d + "/wiki/index.md", "tipo": "wiki"}
        pai = os.path.dirname(d)
        if pai == d:
            break
        d = pai
    m = re.search(r"^(.*?/clients/([a-z0-9._-]+))(/|$)", ap, re.IGNORECASE)
    if m:
        base = m.group(1)
        for cand in (base + "/squad/knowledge/graphify-out/GRAPH_REPORT.md", base + "/graphify-out/GRAPH_REPORT.md"):
            if os.path.isfile(cand):
                return {"escopo": f"clients/{m.group(2).lower()}", "mapa": cand, "tipo": "grafo"}
    d = ap
    for _ in range(25):
        cand = d + "/graphify-out/GRAPH_REPORT.md"
        if os.path.isfile(cand):
            return {"escopo": ("clients/" + m.group(2).lower()) if m else f"external:{d.lower()}", "mapa": cand,
                    "tipo": "grafo"}
        pai = os.path.dirname(d)
        if pai == d:
            break
        d = pai
    return None


def _sidecar() -> str:
    return paths.ledger_path() + ".grafo.json"


def _ler() -> dict:
    try:
        with open(_sidecar(), "r", encoding="utf-8") as fh:
            d = json.load(fh)
        return d if isinstance(d, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def _gravar(d: dict) -> None:
    try:
        trava.gravar_atomico(_sidecar(), json.dumps(d))  # 2.1.3: atomica (leitor nunca ve JSON pela metade)
    except OSError:
        pass


def gate_desligado() -> bool:
    if os.environ.get("ALIA_GRAPH_GATE_OFF") == "1":
        return True
    return os.path.exists(os.path.join(paths.studio_root(), ".claude", "graph-gate.off"))


def modo_do_host(host: str) -> str:
    try:
        with open(os.path.join(espinha.V2, "adapters", "matriz.json"), "r", encoding="utf-8") as fh:
            return str((json.load(fh).get(host) or {}).get("graph_gate") or "avisa")
    except (OSError, json.JSONDecodeError):
        return "avisa"


def registrar_leitura(ledger_mod, session: str, path: str = "", command: str = "", cwd: str = "") -> dict:
    """Marca que a sessao CONSULTOU o mapa/indice. So conta: GRAPH_REPORT.md, graph.json, wiki/index.md,
    ou comando `graphify query|path|explain` (esse vale para qualquer escopo: escopo `*`)."""
    if not session:
        return {"ok": True, "registrado": False, "motivo": "sem session"}
    escopo = None
    if command:
        escopo = _escopo_da_consulta(command, cwd)
    elif path:
        base = os.path.basename(_n(path)).lower()
        if base in RELATORIOS or (base == "index.md" and os.path.basename(os.path.dirname(_n(path))).lower() == "wiki"):
            achado = achar_escopo(path, cwd)
            escopo = achado["escopo"] if achado else None
    if not escopo:
        return {"ok": True, "registrado": False}
    with trava.trava(_sidecar()):  # 2.1.3: ler-alterar-gravar sob lock (duas sessoes nao se apagam)
        d = _ler()
        ent = d.setdefault(session, {}).setdefault(escopo, {})
        primeira = not ent.get("lido")
        if primeira:
            ent["lido"] = True
            _gravar(d)
    if primeira:
        ledger_mod.append_event(paths.ledger_path(), {"event": "graph_read", "session_id": session, "scope": escopo})
    return {"ok": True, "registrado": True, "escopo": escopo}


def _lido_no_transcript(transcript: str, mapa: str, escopo: str = "") -> bool:
    """Host que nao hooka Read (Claude Code: matcher so Grep|Glob, de proposito): a leitura do mapa esta
    no transcript da propria sessao. Conta SO tool_use Read com file_path == mapa, ou tool_use Bash cujo
    comando comeca por `python -m graphify query|path|explain` no escopo (--graph ou cwd da linha)."""
    if not transcript or not os.path.isfile(transcript):
        return False
    try:
        with open(transcript, "r", encoding="utf-8", errors="replace") as fh:
            for linha in fh:
                if not _TOOL_USE_LINHA.search(linha):  # `tool_use_id` de um resultado nao e uma leitura
                    continue
                try:
                    obj = json.loads(linha)
                except json.JSONDecodeError:
                    continue
                if not isinstance(obj, dict):  # 2.1.4: linha JSON valida mas nao-objeto (lista, numero) nao tem .get
                    continue
                cwd = str(obj.get("cwd") or "")
                conteudo = (obj.get("message") or {}).get("content") if isinstance(obj.get("message"), dict) else None
                for it in conteudo if isinstance(conteudo, list) else []:
                    if not isinstance(it, dict) or it.get("type") != "tool_use":
                        continue
                    inp = it.get("input") if isinstance(it.get("input"), dict) else {}
                    if it.get("name") == "Read":
                        fp = str(inp.get("file_path") or "")
                        if fp and _mesmo_arquivo(fp if os.path.isabs(fp) else os.path.join(cwd, fp), mapa):
                            return True
                    elif it.get("name") == "Bash" and escopo:
                        if _escopo_da_consulta(str(inp.get("command") or ""), cwd) == escopo:
                            return True
    except OSError:
        return False
    return False


def alvo_da_varredura(path: str, pattern: str = "") -> str:
    """Glob com pattern absoluto e sem path varre o prefixo fixo do pattern; senao o proprio path."""
    if path or not pattern or not os.path.isabs(pattern):
        return path
    fixo = re.split(r"[*?\[{]", pattern, maxsplit=1)[0]
    return fixo if fixo.endswith(("/", "\\")) else os.path.dirname(fixo)


def _escopos_da_raiz() -> list[dict]:
    """Varredura sem path na raiz do estudio: todos os Clients que tem mapa."""
    base = os.path.join(paths.studio_root(), "clients")
    achados = []
    try:
        nomes = sorted(os.listdir(base))
    except OSError:
        return achados
    for nome in nomes:
        a = achar_escopo(os.path.join(base, nome))
        if a:
            achados.append(a)
    return achados


def checar(ledger_mod, session: str, tool: str, path: str, cwd: str, host: str, transcript: str = "") -> dict:
    """Varredura (Grep/Glob) de `path`. Levanta Recusa('grafo_nao_lido') quando o host bloqueia e a
    sessao nao leu o mapa do escopo; senao devolve {"ok":True,"acao":"libera"|"avisa"}."""
    if not session:
        return {"ok": True, "acao": "libera", "motivo": "sem session"}
    if path and os.path.isfile(path if os.path.isabs(path) else os.path.join(cwd or os.getcwd(), path)):
        return {"ok": True, "acao": "libera", "motivo": "alvo e um arquivo, nao varredura"}
    achado = achar_escopo(path, cwd)
    if achado is None and not path:
        achados = _escopos_da_raiz() if _n(os.path.abspath(cwd or os.getcwd())).lower().rstrip("/") == _n(paths.studio_root()).lower().rstrip("/") else []
        res = None
        for a in achados:  # varredura da raiz = varredura de TODOS os escopos com mapa (o 1o nao lido barra/avisa)
            r = _checar_escopo(ledger_mod, session, tool, a, host, transcript)
            if res is None or r.get("acao") == "avisa" and res.get("acao") != "avisa":
                res = r
        return res or {"ok": True, "acao": "libera", "motivo": "sem mapa neste escopo"}
    if achado is None:
        return {"ok": True, "acao": "libera", "motivo": "sem mapa neste escopo"}
    return _checar_escopo(ledger_mod, session, tool, achado, host, transcript)


def _checar_escopo(ledger_mod, session: str, tool: str, achado: dict, host: str, transcript: str) -> dict:
    escopo = achado["escopo"]
    with trava.trava(_sidecar()):  # 2.1.3: ler-alterar-gravar sob lock
        d = _ler()
        sess = d.setdefault(session, {})
        ent = sess.setdefault(escopo, {})
        lido = bool(ent.get("lido") or (sess.get("*") or {}).get("lido"))
        if not lido and _lido_no_transcript(transcript, achado["mapa"], escopo):
            lido = ent["lido"] = True
            ledger_mod.append_event(paths.ledger_path(), {"event": "graph_read", "session_id": session, "scope": escopo,
                                                          "fonte": "transcript"})
        if lido and ent.get("varreu"):
            return {"ok": True, "acao": "libera", "escopo": escopo}
        desligado = gate_desligado()
        modo = modo_do_host(host)
        acao = "libera" if lido else ("bloqueia" if (modo == "bloqueia" and not desligado) else "avisa")
        if not (ent.get("varreu") or ent.get("barrado")):  # a medida: 1 evento por (sessao, escopo), mesmo com o bloqueio desligado
            ledger_mod.append_event(paths.ledger_path(), {"event": "graph_scan", "session_id": session, "scope": escopo,
                                                          "tool": tool, "lido_antes": lido, "acao": acao,
                                                          "bloqueio_desligado": desligado})
        ent["varreduras"] = int(ent.get("varreduras", 0)) + 1
        ent["barrado" if acao == "bloqueia" else "varreu"] = True
        _gravar(d)
    if lido:
        return {"ok": True, "acao": "libera", "escopo": escopo}
    msg = (f"Antes de varrer {escopo}, leia {achado['mapa']} (God Nodes / Community Hubs; "
           f"{'indice do wiki' if achado['tipo'] == 'wiki' else 'mapa do grafo'}). "
           "Interruptor de emergencia: ALIA_GRAPH_GATE_OFF=1 ou .claude/graph-gate.off.")
    if acao == "bloqueia":
        raise espinha.Recusa("grafo_nao_lido", msg, escopo=escopo, mapa=achado["mapa"], ferramenta=tool, host=host)
    return {"ok": True, "acao": "avisa", "aviso": msg, "escopo": escopo, "mapa": achado["mapa"]}
