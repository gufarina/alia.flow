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
BUSCA = {"rg", "grep", "egrep", "fgrep", "find"}
_CONSULTA = re.compile(r"graph_report|graphify\s+(query|path|explain)", re.IGNORECASE)
DECLARA = {"host": "codex", "bloqueia": ["PreToolUse Bash (rg|grep|find)"],
           "avisa": ["SessionStart", "PreToolUse Bash (leitura do mapa)"]}


def _nome(token: str) -> str:
    base = os.path.basename(token.replace("\\", "/")).lower()
    return base[:-4] if base.endswith(".exe") else base


def _alvo_da_busca(command: str) -> str | None:
    """Primeiro argumento de caminho de um rg/grep/find (ou None se o comando nao e busca)."""
    try:
        toks = shlex.split(command, posix=False)
    except ValueError:
        toks = command.split()
    if not toks or _nome(toks[0]) not in BUSCA:
        return None
    resto = [t.strip("'\"") for t in toks[1:] if not t.startswith("-")]
    if _nome(toks[0]) != "find":  # grep/rg: o 1o argumento solto e o padrao; find: o 1o ja e o caminho
        resto = resto[1:]
    return resto[0] if resto else ""


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
    alvo = _alvo_da_busca(comando)
    if alvo is not None:
        chamadas.append(["graph", "check", "--session", sid, "--tool", "Bash", "--path", alvo, "--cwd", cwd,
                         "--host", "codex"])
    return chamadas


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
        fora = (res.get("divida") or {}).get("abertas_com_projeto_fora_do_cadastro", 0)
        if evento.get("hook_event_name") == "SessionStart" and fora:  # so avisa quando ha o que fazer
            return {"hookSpecificOutput": {"hookEventName": "SessionStart",
                                           "additionalContext": f"[ESPINHA] {fora} Tasks abertas com projeto fora do cadastro (alia project add)."}}
    return {}


def main() -> int:
    try:
        evento = json.loads(sys.stdin.buffer.read().decode("utf-8", errors="replace"))
        saida = decidir(evento)
    except Exception:  # noqa: BLE001 - adaptador nunca derruba o host (falha aberta)
        saida = {}
    sys.stdout.write(json.dumps(saida, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
