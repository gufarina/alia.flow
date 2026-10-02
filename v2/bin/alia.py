#!/usr/bin/env python3
"""alia.py - a CLI UNICA da espinha Cliente > Projeto > Tarefa.

Por que um arquivo novo e nao so o task.py: o task.py exige --state explicito e so conhece
open/close/context; `alia` resolve o estado sozinho (lib/paths.py), e e a porta unica de todo host.
A logica de dominio mora em lib/espinha.py e lib/task_model.py (nucleo); task.py segue como
implementacao de open/close que esta CLI reaproveita (uma so regra, nao duas).

  alia open [--session ID] [--client C]                      grava session_opened, devolve o estado
  alia project add --client C (--id P | --from-tasks)        unico jeito de criar projeto
  alia task open (--brief JSON | --brief-file ARQ) [--session ID]
  alia task dispatch --specialist {client}-{papel} [--id T] [--session ID]
  alia task close --id T --artifact A --veredito PASS|FAIL|CONCERN
  alia task retire --id T --motivo superada|abandonada [--nota TXT]
  alia task pending [--session ID] [--id T]
  alia gate record --task T --parecer ARQUIVO.md [--session ID]
  alia graph check --session ID --tool Grep --path P [--host claude]     trava de adocao do grafo/wiki
  alia graph read  --session ID (--path P | --command CMD)               registra a consulta

Opcoes globais: --state, --ledger (padrao: lib/paths.py: ALIA_STATE_PATH / CLAUDE_PROJECT_DIR).
Toda recusa sai com exit 1 e UM objeto JSON {"ok": false, "regra": ..., "error": ...}. Sucesso: exit 0.
Interruptor so do dispatch: ALIA_SPINE_OFF=1 ou .claude/spine.off. So biblioteca padrao.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import sys
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
for _p in (os.path.join(V2, "lib"), os.path.join(V2, "flow"), HERE):
    if _p not in sys.path:
        sys.path.insert(0, _p)
import espinha  # noqa: E402
import grafo_gate  # noqa: E402
import ledger  # noqa: E402
import paths  # noqa: E402


class _Parser(argparse.ArgumentParser):
    def error(self, message):  # argparse sairia com exit 2 e texto cru
        raise espinha.Recusa("uso_invalido", message)


def _parser() -> argparse.ArgumentParser:
    p = _Parser(prog="alia")
    p.add_argument("--state", default="")
    p.add_argument("--ledger", default="")
    sub = p.add_subparsers(dest="grupo", required=True, parser_class=_Parser)

    s = sub.add_parser("open")
    s.add_argument("--session", default="")
    s.add_argument("--client", default="")

    s = sub.add_parser("project").add_subparsers(dest="acao", required=True, parser_class=_Parser).add_parser("add")
    s.add_argument("--client", required=True)
    s.add_argument("--id", default="")
    s.add_argument("--from-tasks", dest="das_tasks", action="store_true")

    t = sub.add_parser("task").add_subparsers(dest="acao", required=True, parser_class=_Parser)
    s = t.add_parser("open")
    s.add_argument("--brief", default="")
    s.add_argument("--brief-file", dest="brief_file", default="", help="le o brief JSON de um arquivo (PowerShell 5.1 estraga aspas em argumento)")
    s.add_argument("--session", default="")
    s = t.add_parser("dispatch")
    s.add_argument("--specialist", required=True)
    s.add_argument("--id", default="")
    s.add_argument("--session", default="")
    s = t.add_parser("close")
    s.add_argument("--id", required=True)
    s.add_argument("--artifact", default="")
    s.add_argument("--veredito", default="")
    s.add_argument("--root-cause", dest="root_cause", default="")
    s.add_argument("--criterio-reprovado", dest="criterio_reprovado", default="")
    s.add_argument("--studio-root", dest="studio_root", default="")
    s = t.add_parser("retire")
    s.add_argument("--id", required=True)
    s.add_argument("--motivo", default="")
    s.add_argument("--nota", default="")
    s = t.add_parser("pending")
    s.add_argument("--session", default="")
    s.add_argument("--id", default="")
    s.add_argument("--sem-divida", dest="sem_divida", action="store_true")

    g = sub.add_parser("gate").add_subparsers(dest="acao", required=True, parser_class=_Parser).add_parser("record")
    g.add_argument("--task", required=True)
    g.add_argument("--parecer", required=True)
    g.add_argument("--session", default="")

    gr = sub.add_parser("graph").add_subparsers(dest="acao", required=True, parser_class=_Parser)
    s = gr.add_parser("check")
    s.add_argument("--session", default="")
    s.add_argument("--tool", default="Grep")
    s.add_argument("--path", default="")
    s.add_argument("--cwd", default="")
    s.add_argument("--host", default="claude")
    s.add_argument("--transcript", default="", help="transcript da sessao (host que nao hooka Read): a leitura do mapa e achada nele")
    s = gr.add_parser("read")
    s.add_argument("--session", default="")
    s.add_argument("--path", default="")
    s.add_argument("--command", default="")
    s.add_argument("--cwd", default="")
    return p


def spine_desligada() -> bool:
    if os.environ.get("ALIA_SPINE_OFF") == "1":
        return True
    return os.path.exists(os.path.join(paths.studio_root(), ".claude", "spine.off"))


def _task_cli(fn, state: str, **kw) -> dict:
    """Chama cmd_open/cmd_close do task.py (que ja devolve o objeto de erro/sucesso)."""
    return fn(argparse.Namespace(state=state, **kw))


def _executar(a: argparse.Namespace) -> dict:
    state = a.state or paths.state_path()
    led = a.ledger or paths.ledger_path()
    if a.grupo == "open":
        return espinha.open_session(state, ledger, led, a.session, a.client)
    if a.grupo == "project":
        return espinha.project_add(state, a.client, a.id, a.das_tasks)
    if a.grupo == "gate":
        if not any(t.get("id") == a.task for t in espinha.carregar(state).get("tasks", [])):
            raise espinha.Recusa("task_inexistente", "gate record: Task nao encontrada", id_recebido=a.task)
        import gate  # import tardio: so o `gate record` paga o custo
        codigo, obj = gate.registrar(a.task, a.parecer, a.session, led)
        if codigo:
            raise espinha.Recusa("parecer_invalido", obj.get("error", "parecer invalido"), **{k: v for k, v in obj.items() if k not in ("ok", "error")})
        return obj
    if a.grupo == "graph":
        if a.acao == "read":
            return grafo_gate.registrar_leitura(ledger, a.session, a.path, a.command, a.cwd)
        return grafo_gate.checar(ledger, a.session, a.tool, a.path, a.cwd, a.host, a.transcript)
    # grupo == task
    import task as task_cli  # import tardio (bin/task.py: open/close com fatiamento e recibo)
    if a.acao == "open":
        brief = a.brief
        if a.brief_file:
            with open(a.brief_file, "r", encoding="utf-8-sig") as fh:
                brief = fh.read()
        if not brief:
            raise espinha.Recusa("uso_invalido", "task open exige --brief ou --brief-file")
        return _task_cli(task_cli.cmd_open, state, brief=brief, session=a.session)
    if a.acao == "close":
        return _task_cli(task_cli.cmd_close, state, id=a.id, artifact=a.artifact, veredito=a.veredito,
                         root_cause=a.root_cause, criterio_reprovado=a.criterio_reprovado, ledger=led,
                         studio_root=a.studio_root)
    if a.acao == "retire":
        return _task_cli(task_cli.cmd_retire, state, id=a.id, motivo=a.motivo, nota=a.nota)
    if a.acao == "pending":
        return espinha.task_pending(state, ledger, led, a.session, a.id, not a.sem_divida)
    # dispatch
    if spine_desligada():
        return {"ok": True, "registrado": False, "motivo": "espinha desligada (ALIA_SPINE_OFF / .claude/spine.off)"}
    tid = a.id or (paths.read_current_task(a.session) if a.session else None)
    if not tid:
        raise espinha.Recusa("dispatch_sem_task", "nenhuma Task aberta nesta sessao: abra com `alia task open` "
                             "antes de acionar um agente de squad", session=a.session or None)
    res = espinha.task_dispatch(state, ledger, led, tid, a.specialist, a.session)
    if a.id and a.session:  # dispatch explicito de uma sessao tambem fixa a Task corrente dela (so `open` gravava)
        paths.write_current_task(tid, session_id=a.session)
    return res


def run(argv: list[str]) -> tuple[int, dict]:
    """Ponto unico de entrada (CLI e adaptadores em processo): (exit, objeto). Nunca levanta."""
    try:
        args = _parser().parse_args(argv)
        # task.py imprime nada; mas qualquer print perdido de uma lib nao pode sujar o JSON
        with redirect_stdout(io.StringIO()):
            res = _executar(args)
    except espinha.Recusa as r:
        return 1, r.como_json()
    except Exception as exc:  # noqa: BLE001 - fronteira: nunca stack trace crua
        return 1, {"ok": False, "regra": "erro_interno", "error": f"erro interno: {exc}"}
    return (0 if res.get("ok") else 1), res


def main() -> int:
    codigo, obj = run(sys.argv[1:])
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    return codigo


if __name__ == "__main__":
    raise SystemExit(main())
