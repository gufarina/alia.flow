"""Reflector - le 1 Task e devolve ate 5 itens de aprendizado candidatos (modulo 6, I8).

Contrato (CONTRACTS.md modulo 6 + e4-arquitetura-v2.md secao 4, "RSI em ciclo fechado"):
sinais estruturados aceitos sao 4, cada um com uma causa CLARA. Item sem causa e descartado -
nunca "eu acho que" ou inferencia livre.

Schema de ENTRADA que este modulo exige (documentado aqui porque e novo, sem precedente em
v2/lib): caminhos passam por argumento, nunca hardcoded (regra da Task - nada de caminho real
nas provas).

  activity.jsonl: eventos do schema v1 de v2/lib/ledger.py, filtrados por
    ev.get("task_id") == task_id.

  state.json: dict com chave "tasks" (lista). O record da Task (por "id") pode trazer:
    - gate_verdict: "FAIL" dispara causa 1 SE houver tambem gate_criteria_failed (lista de
      strings) ou "gate" (string) com o nome do criterio. Sem nenhum dos dois, gate_verdict FAIL
      sozinho NAO basta (FAIL sem criterio nomeado nao e causa estruturada, e so um veredito).
    - supersedes: string (task_id anterior) -> causa 2.
    - budget_exceeded_count (int) >= 2 -> causa 3. Aceita tambem contar pre_agent/post_agent com
      flag "budget_exceeded": true no ledger (ver _budget_estourado_no_ledger).
    - root_cause: string nao vazia, escrita pelo Operator -> causa 4.

Cada causa vira NO MAXIMO 1 item (a Task pode gerar ate 4 itens fundamentados, o teto de 5 do
contrato nunca aperta na pratica com so 4 tipos de causa - existe para nao deixar a lista crescer
se um novo tipo de causa nascer depois).
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
from ledger import read_events  # noqa: E402


def _load_state_task(state_path: str, task_id: str) -> dict | None:
    if not os.path.exists(state_path):
        return None
    with open(state_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    for t in data.get("tasks", []):
        if t.get("id") == task_id:
            return t
    return None


def _budget_estourado_no_ledger(events: list[dict]) -> int:
    """Conta eventos do ledger que marcam budget_exceeded para a Task (fonte alternativa ao
    campo do state.json, quando o ledger e quem registrou o estouro)."""
    n = 0
    for ev in events:
        if ev.get("budget_exceeded") is True:
            n += 1
    return n


def collect(task_id: str, activity_path: str, state_path: str) -> list[dict]:
    """Devolve ate 5 itens candidatos para a Task `task_id`. Funcao pura: mesma entrada,
    mesma saida - roda 2 vezes e nao duplica (o id de cada item e deterministico por task_id
    + tipo de causa, nunca por timestamp)."""
    events = [ev for ev in read_events(activity_path) if ev.get("task_id") == task_id]
    task = _load_state_task(state_path, task_id) or {}
    client = task.get("client") or "desconhecido"

    itens: list[dict] = []

    # causa 1: Gate FAIL com criterio nomeado
    criterio = None
    if task.get("gate_verdict") == "FAIL":
        criterios_lista = task.get("gate_criteria_failed")
        if isinstance(criterios_lista, list) and criterios_lista:
            criterio = str(criterios_lista[0])
        elif task.get("gate"):
            criterio = str(task["gate"])
    if criterio:
        itens.append({
            "id": f"{task_id}:gate_fail:{criterio}",
            "task_id": task_id,
            "client": client,
            "pattern_key": f"gate_fail:{criterio}",
            "polaridade": "nocivo",
            "causa": {"tipo": "gate_fail", "criterio": criterio},
            "texto": f"Gate FAIL na Task {task_id}: criterio '{criterio}' nao passou.",
        })

    # causa 2: supersedes (esta Task substitui outra - a anterior nao bastou)
    supersedes = task.get("supersedes")
    if supersedes:
        itens.append({
            "id": f"{task_id}:supersedes:{supersedes}",
            "task_id": task_id,
            "client": client,
            "pattern_key": "supersedes",
            "polaridade": "nocivo",
            "causa": {"tipo": "supersedes", "supersedes": str(supersedes)},
            "texto": f"Task {task_id} substituiu {supersedes} (a primeira tentativa nao bastou).",
        })

    # causa 3: budget estourado 2 ou mais vezes (campo do state.json OU contagem no ledger)
    n_budget = task.get("budget_exceeded_count")
    if not isinstance(n_budget, int):
        n_budget = 0
    n_budget = max(n_budget, _budget_estourado_no_ledger(events))
    if n_budget >= 2:
        itens.append({
            "id": f"{task_id}:budget_estourado",
            "task_id": task_id,
            "client": client,
            "pattern_key": "budget_estourado",
            "polaridade": "nocivo",
            "causa": {"tipo": "budget_estourado", "vezes": n_budget},
            "texto": f"Task {task_id} estourou o orcamento {n_budget} vezes.",
        })

    # causa 4: root_cause do Operator (correcao registrada)
    root_cause = task.get("root_cause")
    if isinstance(root_cause, str) and root_cause.strip():
        rc = root_cause.strip()
        itens.append({
            "id": f"{task_id}:root_cause:{rc[:40]}",
            "task_id": task_id,
            "client": client,
            "pattern_key": f"root_cause:{rc[:40]}",
            "polaridade": "nocivo",
            "causa": {"tipo": "root_cause", "texto": rc},
            "texto": f"Operator corrigiu a Task {task_id}: {rc}",
        })

    return itens[:5]


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("uso: python reflector.py <task_id> [activity.jsonl] [state.json]")
        sys.exit(1)
    # activity.jsonl e state.json continuam por argumento quando o chamador os tem (regra da
    # Task: nada de caminho hardcoded); se omitidos, cai no resolvedor unico (TASK-804).
    import paths  # noqa: E402 (v2/lib/paths.py, ja no sys.path por causa do import de ledger)
    activity_arg = sys.argv[2] if len(sys.argv) > 2 else paths.ledger_path()
    state_arg = sys.argv[3] if len(sys.argv) > 3 else paths.state_path()
    result = collect(sys.argv[1], activity_arg, state_arg)
    print(json.dumps(result, ensure_ascii=False, indent=1))
