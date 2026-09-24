#!/usr/bin/env python3
"""task.py - CLI open/close/context do modulo flow+kernel (I2, TASK-801 E5; TASK-804 E7).

Contrato: `artifacts/alia-2.0-2026-09-22/e4-arquitetura-v2.md`, secao 3 (passos 2 e 6) e
secao 7 (I2). Opera SEMPRE sobre o `--state` que o chamador passar - nunca resolve um
caminho padrao, nunca toca `state.json` real por conta propria. Quem prova (proof/) e
quem opera de verdade decide qual copia usar.

Camada anticorrupcao (TASK-804): abrir e fechar Task delegam a lib/task_model.py (a
entidade Task), que absorveu flow/risk.py e a logica solta que morava aqui.

open:    exige o checklist de brief de 6 campos (client, project, objetivo, paths,
         consumidor, destino, exemplo_falha), destino valido, e (se declarada) fatia de
         contexto que resolve no disco. Erro (campo faltando ou client invalido) lista
         Clients, Projects e ids de squad validos, nunca so "invalido". Grava a Task
         aberta como a Task corrente da sessao (lib/paths.py) - e o que hooks/dispatch.py
         le no lugar do ALIA_TASK_ID que nunca era definido.
close:   exige --artifact (o que resolve o criterio de aceite), --veredito
         (PASS/FAIL/CONCERN) E evidencia de veredito no ledger (evento review_verdict ou
         gate_check para este task_id) - o texto digitado sozinho nao fecha mais. Soma
         custo pelo ledger (eventos post_agent com este task_id). Task type == "correcao"
         sem --root-cause e erro. Task done nao reabre por cima.
context: le a Task pelo id e devolve o registro (a continuidade) sem mutar nada.

So biblioteca padrao. UTF-8 explicito. Saida sempre 1 objeto JSON em stdout; exit 0 em
sucesso, 1 em erro de validacao (nunca stack trace crua).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(V2, "flow"))
sys.path.insert(0, os.path.join(V2, "lib"))
import ledger  # noqa: E402  (v2/lib/ledger.py)
import paths  # noqa: E402  (v2/lib/paths.py - resolvedor unico de ledger/Task corrente)
import task_model  # noqa: E402  (v2/lib/task_model.py - a entidade Task)
import slice as slice_mod  # noqa: E402  (v2/flow/slice.py - fatiar tarefa grande, TASK-812 B)


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _load_state(state_path: str) -> dict:
    with open(state_path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def _save_state(state_path: str, state: dict) -> None:
    with open(state_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(state, fh, ensure_ascii=False, indent=2)
        fh.write("\n")


def _valid_values(state: dict) -> tuple[list[str], dict[str, list[str]], dict[str, list[str]]]:
    """Clients, projects ja usados por Client (dica, nao enum fechado) e ids de squad
    (agente completo `{client}-{papel}`, gateway incluso) por Client."""
    clients = sorted(c.get("id") for c in state.get("clients", []) if c.get("id"))
    squad_by_client: dict[str, list[str]] = {}
    for c in state.get("clients", []):
        cid = c.get("id")
        if not cid:
            continue
        squad = c.get("squad") or {}
        ids = []
        gw = squad.get("gateway")
        if gw:
            ids.append(f"{cid}-{gw}")
        for s in squad.get("specialists") or []:
            ids.append(f"{cid}-{s}")
        squad_by_client[cid] = ids
    projects_by_client: dict[str, set[str]] = {}
    for t in state.get("tasks", []):
        cid, proj = t.get("client"), t.get("project")
        if cid and proj:
            projects_by_client.setdefault(cid, set()).add(proj)
    projects_by_client_sorted = {k: sorted(v) for k, v in projects_by_client.items()}
    return clients, projects_by_client_sorted, squad_by_client


def _next_task_id(state: dict) -> str:
    nums = []
    for t in state.get("tasks", []):
        tid = str(t.get("id") or "")
        if tid.startswith("TASK-"):
            try:
                nums.append(int(tid.split("-", 1)[1]))
            except ValueError:
                continue
    return f"TASK-{(max(nums) + 1) if nums else 1:03d}"


def _err(msg: str, **extra) -> dict:
    return {"ok": False, "error": msg, **extra}


def _ok(**extra) -> dict:
    return {"ok": True, **extra}


def cmd_open(args: argparse.Namespace) -> dict:
    state = _load_state(args.state)
    try:
        brief = json.loads(args.brief)
    except json.JSONDecodeError as exc:
        return _err(f"brief nao e JSON valido: {exc}")
    if not isinstance(brief, dict):
        return _err("brief precisa ser um objeto JSON")

    clients, projects_by_client, squad_by_client = _valid_values(state)
    try:
        task_fields = task_model.abrir(brief, clients)
    except task_model.TaskError as exc:
        extra = dict(exc.extra)
        extra["clients_validos"] = clients
        if "client_recebido" in extra:
            extra["projects_validos"] = projects_by_client
            extra["squad_valido"] = squad_by_client
        return _err(exc.msg, **extra)

    # TASK-812 item B (Shopify 02, flow/slice.py): tarefa grande nao abre 1 Task so - fatia
    # em pedacos com criterio de aceite proprio, cada fatia (exceto a 1a) so comeca depois do
    # Gate da anterior passar (slice.pode_comecar_fatia, checado por bin/brief.py).
    avaliacao = slice_mod.is_tarefa_grande(brief)
    if avaliacao["grande"]:
        fatias = slice_mod.fatiar(brief)
        primeiro_num = int(_next_task_id(state).split("-", 1)[1])
        grupo_id = f"TASK-{primeiro_num:03d}"
        novas_tasks = []
        for i, fatia in enumerate(fatias):
            campos_fatia = dict(task_fields)
            campos_fatia["title"] = fatia["objetivo"]
            campos_fatia["criterio_aceite"] = fatia["criterio_aceite"]
            campos_fatia["fatia_id"] = fatia["id"]
            campos_fatia["depende_da_anterior"] = fatia["depende_da_anterior"]
            campos_fatia["fatia_de"] = grupo_id
            nova = {"id": f"TASK-{primeiro_num + i:03d}", "created": _now(), **campos_fatia}
            novas_tasks.append(nova)
        state.setdefault("tasks", []).extend(novas_tasks)
        _save_state(args.state, state)
        paths.write_current_task(novas_tasks[0]["id"], session_id=args.session or None)
        return _ok(tasks=novas_tasks, fatiada=True, motivos=avaliacao["motivos"])

    task_id = _next_task_id(state)
    new_task = {"id": task_id, "created": _now(), **task_fields}
    state.setdefault("tasks", []).append(new_task)
    _save_state(args.state, state)
    # Task corrente da sessao (lib/paths.py): o que hooks/dispatch.py le no lugar do
    # ALIA_TASK_ID que nunca era definido (achado da revisao independente).
    paths.write_current_task(task_id, session_id=args.session or None)
    return _ok(task=new_task)


def cmd_close(args: argparse.Namespace) -> dict:
    state = _load_state(args.state)
    tasks = state.get("tasks", [])
    task = next((t for t in tasks if t.get("id") == args.id), None)
    if task is None:
        return _err("Task nao encontrada", id_recebido=args.id,
                     ids_abertos=[t.get("id") for t in tasks if t.get("status") == "open"])

    ledger_path = args.ledger or paths.ledger_path()
    events = ledger.read_events(ledger_path) if os.path.exists(ledger_path) else []

    try:
        task_fechada = task_model.fechar(
            task, args.veredito, args.artifact, events,
            root_cause=args.root_cause, criterio_reprovado=args.criterio_reprovado,
        )
    except task_model.TaskError as exc:
        return _err(exc.msg, **exc.extra)

    cost = 0
    for ev in events:
        if ev.get("event") == "post_agent" and ev.get("task_id") == args.id:
            tt = ev.get("tokens_total")
            if isinstance(tt, (int, float)):
                cost += tt

    task_fechada["closed_at"] = _now()
    task_fechada["tokens"] = cost
    task_fechada["tokens_source"] = "ledger"

    idx = tasks.index(task)
    tasks[idx] = task_fechada
    _save_state(args.state, state)
    return _ok(task=task_fechada, custo_somado_do_ledger=cost)


def cmd_context(args: argparse.Namespace) -> dict:
    state = _load_state(args.state)
    task = next((t for t in state.get("tasks", []) if t.get("id") == args.id), None)
    if task is None:
        return _err("Task nao encontrada", id_recebido=args.id)
    return _ok(task=task)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="task.py")
    p.add_argument("--state", required=True, help="caminho da COPIA do state.json (nunca o original)")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_open = sub.add_parser("open")
    p_open.add_argument("--brief", required=True, help="JSON com os 6 campos do checklist")
    p_open.add_argument("--session", default="", help="session_id do host, se conhecido (Task corrente por sessao)")
    p_open.set_defaults(func=cmd_open)

    p_close = sub.add_parser("close")
    p_close.add_argument("--id", required=True)
    p_close.add_argument("--artifact", default="")
    p_close.add_argument("--veredito", default="")
    p_close.add_argument("--root-cause", dest="root_cause", default="")
    p_close.add_argument("--criterio-reprovado", dest="criterio_reprovado", default="",
                          help="criterio do gate que reprovou (exigido quando veredito != PASS)")
    p_close.add_argument("--ledger", default="")
    p_close.set_defaults(func=cmd_close)

    p_context = sub.add_parser("context")
    p_context.add_argument("--id", required=True)
    p_context.set_defaults(func=cmd_context)

    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        result = args.func(args)
    except Exception as exc:  # noqa: BLE001 - fronteira: nunca deixa crua
        result = _err(f"erro interno: {exc}")
    sys.stdout.write(json.dumps(result, ensure_ascii=False))
    sys.stdout.write("\n")
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
