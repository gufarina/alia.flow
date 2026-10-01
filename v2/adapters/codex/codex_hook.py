#!/usr/bin/env python3
"""codex_hook.py - ADAPTADOR Codex da espinha Cliente>Projeto>Tarefa. Sem regra propria.

BLOQUEIA (PreToolUse, a doc cobre Bash/apply_patch/MCP): comando de shell que varre Client
(rg|grep|egrep|fgrep|find) -> `alia graph check --host codex`.
SO AVISA/REGISTRA: SessionStart -> `alia open`; shell que le GRAPH_REPORT / roda `graphify query` -> `alia graph read`.
Lacunas declaradas: Codex nao tem Grep/Glob nem ferramenta de subagente nos hooks (task dispatch nao alcanca);
ferramentas hospedadas (WebSearch) ficam fora do PreToolUse. Sem Codex CLI nesta maquina: o formato do payload e
da decisao segue a doc de hooks [X1] e esta provado so por teste de unidade da traducao (test_espinha.py).
Configuracao: hooks.toml ao lado. Falha aberta quando a espinha nao existe (sem state.json) ou quebra por dentro.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import sys

BIN = os.environ.get("ALIA_BIN") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "bin")
SEM_VOTO = ("state_ausente", "erro_interno", "uso_invalido")
BUSCA = {"rg", "grep", "egrep", "fgrep", "find", "select-string", "findstr", "ag", "ack"}
_SEPARADORES = re.compile(r"&&|\|\||[;|&\n]")  # comando encadeado: cada trecho e checado (C8)
_CONSULTA = re.compile(r"graph_report|graphify\s+(query|path|explain)", re.IGNORECASE)
DECLARA = {"host": "codex", "bloqueia": ["PreToolUse Bash (rg|grep|find|Select-String|git grep|findstr, tambem encadeado)"],
           "avisa": ["SessionStart", "PreToolUse Bash (leitura do mapa)"]}


def _nome(token: str) -> str:
    base = os.path.basename(token.replace("\\", "/")).lower()
    return base[:-4] if base.endswith(".exe") else base


def _alvo_do_trecho(trecho: str) -> str | None:
    """Argumento de caminho de UM comando de busca (ou None se o trecho nao e busca)."""
    try:
        toks = shlex.split(trecho, posix=False)
    except ValueError:
        toks = trecho.split()
    if toks and _nome(toks[0]) == "git":  # `git grep`, `git -C x grep`
        i = next((k for k, t in enumerate(toks) if t == "grep"), None)
        toks = ["grep"] + toks[i + 1:] if i is not None else []
    if not toks or _nome(toks[0]) not in BUSCA:
        return None
    nome = _nome(toks[0])
    baixo = [t.lower() for t in toks]
    for flag in ("-path", "-literalpath"):  # Select-String -Path X
        if flag in baixo and baixo.index(flag) + 1 < len(toks):
            return toks[baixo.index(flag) + 1].strip("'\"")
    resto = [t.strip("'\"") for t in toks[1:] if not t.startswith("-") and not (nome == "findstr" and t.startswith("/"))]
    if nome != "find":  # grep/rg/findstr/Select-String: o 1o argumento solto e o padrao; find: o 1o ja e o caminho
        resto = resto[1:]
    return resto[0] if resto else ""


def _alvos_da_busca(command: str) -> list[str]:
    """Um alvo por trecho de busca do comando (encadeado com && || ; | &)."""
    return [a for a in (_alvo_do_trecho(t) for t in _SEPARADORES.split(command)) if a is not None]


def _alvo_da_busca(command: str) -> str | None:
    alvos = _alvos_da_busca(command)
    return alvos[0] if alvos else None


def traduzir(evento: dict) -> list[list[str]]:
    """Evento Codex -> lista de chamadas `alia` (argv), em ordem. Vazio = nada a ver com a espinha."""
    sid = str(evento.get("session_id") or "")
    hook = evento.get("hook_event_name")
    if not sid:
        return []
    if hook == "SessionStart":
        return [["open", "--session", sid]]
    if hook != "PreToolUse" or str(evento.get("tool_name")) != "Bash":
        return []
    comando = str((evento.get("tool_input") or {}).get("command") or "")
    cwd = str(evento.get("cwd") or "")
    chamadas: list[list[str]] = []
    if _CONSULTA.search(comando):
        chamadas.append(["graph", "read", "--session", sid, "--command", comando, "--cwd", cwd])
    for alvo in _alvos_da_busca(comando):
        chamadas.append(["graph", "check", "--session", sid, "--tool", "Bash", "--path", alvo, "--cwd", cwd,
                         "--host", "codex"])
    return chamadas


def _rastro(evento: dict, motivo) -> None:
    try:
        sys.path.insert(0, BIN)
        sys.path.insert(0, os.path.join(BIN, "..", "lib"))
        import espinha  # noqa: E402
        espinha.registrar_falha_aberta("codex", str(motivo), str((evento or {}).get("session_id") or ""))
    except Exception:  # noqa: BLE001 - o rastro nunca derruba o host
        pass


def decidir(evento: dict, alia_run=None) -> dict:
    """Traduz, chama a CLI e devolve a decisao do hook ({} = libera)."""
    if alia_run is None:
        sys.path.insert(0, BIN)
        import alia  # noqa: E402
        alia_run = alia.run
    for argv in traduzir(evento):
        codigo, res = alia_run(argv)
        if codigo != 0 and res.get("regra") not in SEM_VOTO:
            return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                           "permissionDecisionReason": f"espinha: {res.get('error')} [{res.get('regra')}]"}}
        if codigo != 0:  # sem voto: libera, MAS deixa rastro no ledger (C8)
            _rastro(evento, res.get("regra"))
        fora = (res.get("divida") or {}).get("abertas_com_projeto_fora_do_cadastro", 0)
        if evento.get("hook_event_name") == "SessionStart" and fora:  # so avisa quando ha o que fazer
            return {"hookSpecificOutput": {"hookEventName": "SessionStart",
                                           "additionalContext": f"[ESPINHA] {fora} Tasks abertas com projeto fora do cadastro (alia project add)."}}
    return {}


def main() -> int:
    evento = {}
    try:
        evento = json.loads(sys.stdin.buffer.read().decode("utf-8", errors="replace"))
        saida = decidir(evento)
    except Exception as exc:  # noqa: BLE001 - adaptador nunca derruba o host (falha aberta, mas registrada)
        _rastro(evento, f"excecao: {exc}")
        saida = {}
    sys.stdout.write(json.dumps(saida, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
