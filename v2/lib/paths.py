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

def project_dir() -> str:
    """CLAUDE_PROJECT_DIR explicito primeiro, senao a ancestral mais proxima do cwd com
    state.json, senao o cwd (ultimo recurso) - NUNCA a posicao deste arquivo no disco (mesma
    regra de studio_root(), que e so outro nome para esta funcao)."""
    return studio_root()


def find_ancestor_with_state_json(start: str | None = None) -> str | None:
    """Sobe a arvore de pastas a partir de `start` (default cwd) procurando a ancestral MAIS
    PROXIMA que tenha state.json. Nunca deriva de onde o ARQUIVO deste modulo mora em disco -
    o motor (v2/) e copiado para profundidades diferentes (oficina em clients/alia-flow-lab/v2,
    raiz do studio em v2/, produto publico em v2/), e a posicao do script no disco nunca diz
    onde o studio vive (achado do CEO, 24/09/2026: client.py apontava squads_dir para
    C:\\Users\\<usuario>\\.claude\\squads depois de uma migracao, porque a conta era feita a
    partir de __file__)."""
    d = os.path.abspath(start or os.getcwd())
    for _ in range(20):
        if os.path.isfile(os.path.join(d, "state.json")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return None


def studio_root() -> str:
    """Raiz do studio: CLAUDE_PROJECT_DIR explicito primeiro, senao a ancestral mais proxima
    do cwd com state.json, senao o cwd (ultimo recurso) - NUNCA a posicao do script no disco."""
    project = os.environ.get("CLAUDE_PROJECT_DIR")
    if project:
        return project
    found = find_ancestor_with_state_json()
    if found:
        return found
    return os.getcwd()


def ledger_path() -> str:
    """Caminho unico do activity.jsonl. Ordem: ALIA_LEDGER_PATH explicito (provas e sandboxes)
    -> CLAUDE_PROJECT_DIR/activity.jsonl (uso real) -> studio/activity.jsonl relativo a este
    arquivo (fallback quando nem CLAUDE_PROJECT_DIR existe)."""
    explicit = os.environ.get("ALIA_LEDGER_PATH")
    if explicit:
        return explicit
    return os.path.join(project_dir(), "activity.jsonl")


def state_path() -> str:
    """Caminho do state.json real (so leitura por default; quem escreve sempre recebe --state
    explicito de uma COPIA, nunca este caminho direto)."""
    explicit = os.environ.get("ALIA_STATE_PATH")
    if explicit:
        return explicit
    return os.path.join(project_dir(), "state.json")


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
