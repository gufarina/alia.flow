"""paths.py - resolvedor UNICO de caminhos (ledger e Task corrente por sessao). Modulo lib,
TASK-804 (revisao independente E7): antes deste arquivo, hooks/dispatch.py resolvia o ledger
como `v2-activity.jsonl` e bin/task.py resolvia como `activity.jsonl` - a mesma sessao gravava
custo num arquivo e fechava a Task somando de outro (o "custo sai 0" medido na revisao).

Toda ferramenta que precisa do ledger ou da Task corrente (dispatch, task, learn) chama daqui.
Nenhum outro modulo monta o nome do arquivo a mao.
"""
from __future__ import annotations

import json
import os

_HERE = os.path.dirname(os.path.abspath(__file__))


def project_dir() -> str:
    return os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())


def ledger_path() -> str:
    """Caminho unico do activity.jsonl. Ordem: ALIA_LEDGER_PATH explicito (provas e sandboxes)
    -> CLAUDE_PROJECT_DIR/activity.jsonl (uso real) -> studio/activity.jsonl relativo a este
    arquivo (fallback quando nem CLAUDE_PROJECT_DIR existe)."""
    explicit = os.environ.get("ALIA_LEDGER_PATH")
    if explicit:
        return explicit
    project = os.environ.get("CLAUDE_PROJECT_DIR")
    if project:
        return os.path.join(project, "activity.jsonl")
    return os.path.join(_HERE, "..", "..", "studio", "activity.jsonl")


def state_path() -> str:
    """Caminho do state.json real (so leitura por default; quem escreve sempre recebe --state
    explicito de uma COPIA, nunca este caminho direto)."""
    explicit = os.environ.get("ALIA_STATE_PATH")
    if explicit:
        return explicit
    project = os.environ.get("CLAUDE_PROJECT_DIR")
    if project:
        return os.path.join(project, "state.json")
    return os.path.join(_HERE, "..", "..", "studio", "state.json")


def current_task_path() -> str:
    """Arquivo que guarda a Task corrente por sessao. `task.py open` grava aqui; hooks/dispatch.py
    le daqui no lugar do ALIA_TASK_ID que nunca era definido (achado da revisao independente)."""
    explicit = os.environ.get("ALIA_CURRENT_TASK_PATH")
    if explicit:
        return explicit
    return os.path.join(project_dir(), ".alia-current-task.json")


def _load_current_task_file() -> dict:
    path = current_task_path()
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (json.JSONDecodeError, OSError):
        return {}
    return data if isinstance(data, dict) else {}


def read_current_task(session_id: str | None = None) -> str | None:
    """Task corrente para a sessao. Se a sessao tiver uma entrada propria, ganha; senao cai
    para "_last" (a ultima Task aberta por `task.py open`, quando o chamador nao sabe o
    session_id do host - caso comum, ja que a CLI roda fora do processo do hook)."""
    data = _load_current_task_file()
    if session_id and session_id in data:
        return data[session_id]
    return data.get("_last")


def write_current_task(task_id: str, session_id: str | None = None) -> None:
    path = current_task_path()
    data = _load_current_task_file()
    if session_id:
        data[session_id] = task_id
    data["_last"] = task_id
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, ensure_ascii=False)
