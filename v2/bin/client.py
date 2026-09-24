#!/usr/bin/env python3
"""client.py - CLI list/use do squad ativo (TASK-804, dieta de token da Alia 2.0).

Problema medido pela coordenacao em 23/09/2026: toda sessao carregava .claude\\agents inteiro
(90 agentes, ~6.900 bytes de description) - os 79 especialistas dos 12 Clients do studio ao
mesmo tempo, mais os 11 do pacote GSD. So o squad do Client ATIVO precisa ficar visivel.

Contrato: a GERACAO (v2/squad/squad-bridge.ps1 -Client <c> -Reserve) grava cada squad numa
pasta de reserva por Client (--squads-dir, default .claude/squads/<client>/) que o host NUNCA
le sozinho. Este CLI sincroniza .claude/agents (--agents-dir) com SO os arquivos da reserva do
Client escolhido mais a lista de sempre-mantidos (--keep, default vazio: nada alem do proprio
Client). O squad alia-flow-lab (o motor) NAO entra mais por padrao (Ajuste 0, TASK-804,
23/09/2026) - so fica visivel quando ele MESMO e o Client ativo (`use alia-flow-lab`), ou quando
o operador pede explicitamente `--keep alia-flow-lab` porque a sessao vai precisar delegar
trabalho de engine no meio do Client. Custa 9 agentes a mais sempre ligados; a dieta so funciona
se o motor tambem for opt-in.

list: mostra os Clients com squad na reserva e a contagem de agentes de cada um.
use:  copia da reserva os arquivos do Client + --keep para --agents-dir, e REMOVE de
      --agents-dir qualquer arquivo que pertenca a um Client conhecido pela reserva mas que
      nao esta no conjunto mantido desta chamada. Arquivo cujo dono nao e nenhum Client
      conhecido da reserva (ex.: um squad que nunca rodou -Reserve) fica intocado - o CLI so
      arruma o que sabe que e seu.

Idempotente: rodar `use <client>` duas vezes seguidas devolve added=[] removed=[] na segunda.
Reversivel: nada e apagado da reserva, so da pasta ao vivo; `use` outro Client restaura o
anterior a qualquer momento, direto da reserva.

Aviso honesto (nao resolvido por este CLI): o Claude Code le a lista de sub-agentes na ABERTURA
da sessao. Rodar `use` no MEIO de uma sessao nao muda quem o host ja enxerga nesta sessao - so
vale a partir da proxima. Ver v2/AGENTS.md, secao "Squad ativo".

So biblioteca padrao. UTF-8 explicito. Saida sempre 1 objeto JSON em stdout; exit 0 em
sucesso, 1 em erro de validacao (nunca stack trace crua).
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
ALIA_FLOW_LAB = os.path.dirname(V2)
STUDIO_ROOT = os.path.dirname(os.path.dirname(ALIA_FLOW_LAB))

DEFAULT_SQUADS_DIR = os.path.join(STUDIO_ROOT, ".claude", "squads")
DEFAULT_AGENTS_DIR = os.path.join(STUDIO_ROOT, ".claude", "agents")
DEFAULT_KEEP: list[str] = []  # Ajuste 0 (TASK-804): motor nao entra mais por padrao


def _err(msg: str, **extra) -> dict:
    return {"ok": False, "error": msg, **extra}


def _ok(**extra) -> dict:
    return {"ok": True, **extra}


def _known_clients(squads_dir: str) -> list[str]:
    if not os.path.isdir(squads_dir):
        return []
    return sorted(
        d for d in os.listdir(squads_dir)
        if os.path.isdir(os.path.join(squads_dir, d))
    )


def _client_bundles(squads_dir: str, client: str) -> dict[str, str]:
    """nome do arquivo -> caminho completo, so *.md da reserva daquele Client."""
    cdir = os.path.join(squads_dir, client)
    if not os.path.isdir(cdir):
        return {}
    return {
        f: os.path.join(cdir, f)
        for f in os.listdir(cdir)
        if f.endswith(".md") and os.path.isfile(os.path.join(cdir, f))
    }


def _owner_of(filename: str, known_clients: list[str]) -> str | None:
    """A qual Client conhecido este arquivo pertence, pelo prefixo `{client}-`.
    Client mais longo primeiro (evita 'acme' casar com 'acme-saas')."""
    for c in sorted(known_clients, key=len, reverse=True):
        if filename.startswith(f"{c}-"):
            return c
    return None


def cmd_list(args: argparse.Namespace) -> dict:
    clients = _known_clients(args.squads_dir)
    out = []
    for c in clients:
        out.append({"id": c, "agents": len(_client_bundles(args.squads_dir, c))})
    return _ok(squads_dir=args.squads_dir, clients=out)


def cmd_use(args: argparse.Namespace) -> dict:
    known = _known_clients(args.squads_dir)
    if args.client not in known:
        return _err(
            "Client sem squad na reserva - rode antes: "
            "squad-bridge.ps1 -Client <id> -Mode spawn -Reserve",
            client_recebido=args.client,
            clients_na_reserva=known,
        )

    keep_extra = [k for k in args.keep if k in known and k != args.client]
    keep = [args.client] + keep_extra
    skipped_keep = [k for k in args.keep if k not in known and k != args.client]

    desired: dict[str, str] = {}
    for c in keep:
        desired.update(_client_bundles(args.squads_dir, c))

    os.makedirs(args.agents_dir, exist_ok=True)
    existing = {
        f for f in os.listdir(args.agents_dir)
        if f.endswith(".md") and os.path.isfile(os.path.join(args.agents_dir, f))
    }

    added, updated, unchanged, removed = [], [], [], []

    for name, src in sorted(desired.items()):
        dst = os.path.join(args.agents_dir, name)
        with open(src, "rb") as fh:
            src_bytes = fh.read()
        if name in existing:
            with open(dst, "rb") as fh:
                dst_bytes = fh.read()
            if dst_bytes == src_bytes:
                unchanged.append(name)
                continue
            if not args.dry_run:
                with open(dst, "wb") as fh:
                    fh.write(src_bytes)
            updated.append(name)
        else:
            if not args.dry_run:
                shutil.copyfile(src, dst)
            added.append(name)

    for name in sorted(existing):
        if name in desired:
            continue
        owner = _owner_of(name, known)
        if owner is None or owner in keep:
            continue  # nao e de um Client conhecido, ou o dono ja esta mantido: nao mexe
        if not args.dry_run:
            os.remove(os.path.join(args.agents_dir, name))
        removed.append(name)

    return _ok(
        client=args.client,
        squad_ativo=keep,
        agents_dir=args.agents_dir,
        added=added,
        updated=updated,
        unchanged=unchanged,
        removed=removed,
        keep_pedido_mas_sem_reserva=skipped_keep,
        aviso="host so enxerga agente novo em sessao nova - ver v2/AGENTS.md, secao Squad ativo",
        dry_run=args.dry_run,
    )


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="client.py")
    p.add_argument("--squads-dir", default=DEFAULT_SQUADS_DIR, help="a reserva por Client")
    p.add_argument("--agents-dir", default=DEFAULT_AGENTS_DIR, help="a pasta que o host le")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_list = sub.add_parser("list")
    p_list.set_defaults(func=cmd_list)

    p_use = sub.add_parser("use")
    p_use.add_argument("client")
    p_use.add_argument("--keep", default=",".join(DEFAULT_KEEP),
                        help="Clients extra mantidos junto (csv), default: vazio - use "
                             "'--keep alia-flow-lab' so quando a sessao precisar do motor")
    p_use.add_argument("--dry-run", action="store_true")
    p_use.set_defaults(func=cmd_use)

    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.cmd == "use":
        args.keep = [k.strip() for k in args.keep.split(",") if k.strip()]
    try:
        result = args.func(args)
    except Exception as exc:  # noqa: BLE001 - fronteira: nunca deixa crua
        result = _err(f"erro interno: {exc}")
    sys.stdout.write(json.dumps(result, ensure_ascii=False))
    sys.stdout.write("\n")
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
