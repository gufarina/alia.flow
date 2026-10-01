#!/usr/bin/env python3
"""client.py - CLI list/use do squad ativo (TASK-804, dieta de token da Alia 2.0).

Problema medido em 23/09/2026: toda sessao carregava .claude\agents inteiro (90 agentes, ~6.900
bytes de description). So o squad do Client ATIVO precisa ficar visivel.

a reserva `.claude/squads/<client>/` NAO existe mais. A fonte unica e `clients/<id>/squad/`
(persona .md + .yaml + squad.yaml) e `engine/macro/`; quem gera o agente e a bridge
(`v2/squad/bridge.ps1`). `use <client>` CHAMA a bridge: ela gera o Client mais os 3 macro em
--agents-dir e so apaga com --prune explicito (nunca padrao - incidente 30/09/2026: `use` apagou
150 agentes dos outros Clients).

list: Clients com `clients/<id>/squad/squad.yaml` e a contagem de agentes (mais o `macro`).
use:  `bridge.ps1 -Only <client> -Target claude [-Prune] [-Keep a,b] [-DryRun]`.
      O squad alia-flow-lab (motor) so entra quando ele MESMO e o ativo ou via --keep.

Aviso honesto: o Claude Code le a lista de sub-agentes na ABERTURA da sessao; `use` no meio
nao muda quem o host ja enxerga - vale a partir da proxima. Ver v2/AGENTS.md, "Squad ativo".

So biblioteca padrao. UTF-8. Saida: 1 objeto JSON em stdout; exit 0 ok, 1 erro de validacao.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(V2, "lib"))
import paths as _paths  # noqa: E402  (raiz do studio via CLAUDE_PROJECT_DIR ou ancestral com state.json)
STUDIO_ROOT = _paths.studio_root()

BRIDGE = os.path.join(V2, "squad", "bridge.ps1")
DEFAULT_AGENTS_DIR = os.path.join(STUDIO_ROOT, ".claude", "agents")


def _err(msg: str, **extra) -> dict:
    return {"ok": False, "error": msg, **extra}


def _ok(**extra) -> dict:
    return {"ok": True, **extra}


def _clients(root: str) -> dict[str, int]:
    """id -> numero de agentes, so Clients com squad/squad.yaml."""
    base = os.path.join(root, "clients")
    out: dict[str, int] = {}
    if not os.path.isdir(base):
        return out
    for c in sorted(os.listdir(base)):
        if os.path.isfile(os.path.join(base, c, "squad", "squad.yaml")):
            ag = os.path.join(base, c, "squad", "agents")
            out[c] = len([f for f in os.listdir(ag) if f.endswith(".yaml")]) if os.path.isdir(ag) else 0
    return out


def cmd_list(args: argparse.Namespace) -> dict:
    return _ok(repo_root=args.repo_root, clients=[{"id": c, "agents": n} for c, n in _clients(args.repo_root).items()])


def cmd_use(args: argparse.Namespace) -> dict:
    known = _clients(args.repo_root)
    if args.client not in known:
        return _err("Client sem squad em clients/<id>/squad/squad.yaml", client_recebido=args.client,
                    clients_conhecidos=sorted(known))
    cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", BRIDGE,
           "-RepoRoot", args.repo_root, "-ClaudeOut", args.agents_dir, "-Only", args.client, "-Target", "claude"]
    if args.prune:
        cmd.append("-Prune")
    if args.keep:
        cmd += ["-Keep", ",".join(args.keep)]
    if args.dry_run:
        cmd.append("-DryRun")
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    linhas = (r.stdout or "").strip().splitlines()
    resumo = [l.strip() for l in linhas if l.split(":")[0] in ("gerados", "atualizados", "inalterados", "erros", "podados")]
    if r.returncode != 0:
        return _err("bridge falhou", exit=r.returncode, saida=(r.stdout + r.stderr).strip()[-1500:])
    return _ok(client=args.client, agents_dir=args.agents_dir, resumo=resumo, dry_run=args.dry_run,
               aviso="host so enxerga agente novo em sessao nova - ver v2/AGENTS.md, secao Squad ativo")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="client.py")
    p.add_argument("--repo-root", default=STUDIO_ROOT, help="raiz com clients/ (default: raiz do studio)")
    p.add_argument("--agents-dir", default=DEFAULT_AGENTS_DIR, help="a pasta que o host le")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list").set_defaults(func=cmd_list)
    p_use = sub.add_parser("use")
    p_use.add_argument("client")
    p_use.add_argument("--keep", default="", help="Clients extra mantidos junto (csv)")
    p_use.add_argument("--dry-run", action="store_true")
    p_use.add_argument("--prune", action="store_true",
                       help="apaga de --agents-dir os agentes dos OUTROS Clients (explicito, nunca padrao)")
    p_use.set_defaults(func=cmd_use)
    return p


def main() -> int:
    args = build_parser().parse_args()
    if args.cmd == "use":
        args.keep = [k.strip() for k in args.keep.split(",") if k.strip()]
    try:
        result = args.func(args)
    except Exception as exc:  # noqa: BLE001 - fronteira: nunca deixa crua
        result = _err(f"erro interno: {exc}")
    sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
