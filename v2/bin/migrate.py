#!/usr/bin/env python3
"""migrate.py - aplica a Alia Flow 2.0 numa pasta alvo, com backup datado e undo.

Modulo release (COURIER). Nunca toca a fonte (a pasta v2/ do laboratorio); so LE dela e
ESCREVE no alvo. Todo apply grava um manifest.json dentro do backup, para o undo saber
exatamente o que restaurar e o que apagar (arquivo que nao existia antes do apply).

Uso (rode de qualquer lugar):
  python migrate.py apply  --source <pasta v2 de origem> --target <pasta da instancia alvo>
  python migrate.py undo   --target <pasta da instancia alvo> [--backup <pasta do backup>]
                             (sem --backup, usa o backup mais recente em <target>/_backups/)

O que o apply copia para dentro de <target>:
  AGENTS.md (raiz)          <- <source>/AGENTS.md
  CLAUDE.md (raiz)          <- sempre "@AGENTS.md" (contrato do kernel)
  VERSION (raiz)            <- dirname(<source>)/VERSION, quando existe (a linha de status le daqui)
  v2/                       <- <source> inteira (exceto __pycache__ e proof/_sandbox*)
  .claude/settings.json     <- hooks do despachante amarrados (PreToolUse/PostToolUse/SubagentStop/Stop)

Backup: <target>/_backups/v2-migrate-<timestamp>/ recebe copia de CADA arquivo/pasta que
o apply for sobrescrever ou criar, mais manifest.json com a lista completa (criados vs
sobrescritos). Nada e apagado sem antes estar no backup.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time

SETTINGS_HOOKS = {
    "hooks": {
        "PreToolUse": [
            {
                "matcher": "Write|Edit|Bash|Agent|Task",
                "hooks": [{
                    "type": "command",
                    "command": "python \"${CLAUDE_PROJECT_DIR}/v2/hooks/dispatch.py\"",
                    "timeout": 10,
                }],
            }
        ],
        "PostToolUse": [
            {
                "matcher": "Agent|Task",
                "hooks": [{
                    "type": "command",
                    "command": "python \"${CLAUDE_PROJECT_DIR}/v2/hooks/dispatch.py\"",
                    "timeout": 10,
                }],
            }
        ],
        "SubagentStop": [
            {
                "matcher": "",
                "hooks": [{
                    "type": "command",
                    "command": "python \"${CLAUDE_PROJECT_DIR}/v2/hooks/dispatch.py\"",
                    "timeout": 10,
                }],
            }
        ],
        "Stop": [
            {
                "matcher": "",
                "hooks": [{
                    "type": "command",
                    "command": "python \"${CLAUDE_PROJECT_DIR}/v2/hooks/dispatch.py\"",
                    "timeout": 10,
                }],
            }
        ],
    }
}


def _iter_source_files(source: str):
    for root, dirs, files in os.walk(source):
        dirs[:] = [d for d in dirs if d != "__pycache__" and not d.startswith("_sandbox")]
        for name in files:
            full = os.path.join(root, name)
            rel = os.path.relpath(full, source)
            yield rel.replace("\\", "/")


def cmd_apply(source: str, target: str) -> int:
    source = os.path.abspath(source)
    target = os.path.abspath(target)
    if not os.path.isdir(source):
        print(f"erro: source nao existe: {source}", file=sys.stderr)
        return 1
    os.makedirs(target, exist_ok=True)

    ts = time.strftime("%Y%m%d-%H%M%S")
    backup_dir = os.path.join(target, "_backups", f"v2-migrate-{ts}")
    os.makedirs(backup_dir, exist_ok=True)

    manifest = {"ts": ts, "source": source, "target": target, "created": [], "overwritten": []}

    def _backup_and_note(rel_target_path: str) -> None:
        full = os.path.join(target, rel_target_path)
        if os.path.exists(full):
            dest_bak = os.path.join(backup_dir, rel_target_path)
            os.makedirs(os.path.dirname(dest_bak), exist_ok=True)
            shutil.copy2(full, dest_bak)
            manifest["overwritten"].append(rel_target_path)
        else:
            manifest["created"].append(rel_target_path)

    # AGENTS.md + CLAUDE.md na raiz
    _backup_and_note("AGENTS.md")
    shutil.copy2(os.path.join(source, "AGENTS.md"), os.path.join(target, "AGENTS.md"))

    # VERSION (TASK-813, achado do CEO 24/09/2026): a linha de status ficava presa na versao
    # velha porque o apply nunca gravava VERSION no alvo. Mora um nivel ACIMA de <source>
    # (source = <repo>/v2; VERSION = <repo>/VERSION) - so copia quando existe na fonte.
    version_src = os.path.join(os.path.dirname(source), "VERSION")
    if os.path.isfile(version_src):
        _backup_and_note("VERSION")
        shutil.copy2(version_src, os.path.join(target, "VERSION"))

    claude_path = os.path.join(target, "CLAUDE.md")
    if os.path.exists(claude_path):
        # CLAUDE.md do alvo carrega as leis da INSTANCIA (nunca do motor) - preservado, nunca
        # sobrescrito. So cria "@AGENTS.md" quando o alvo ainda nao tem CLAUDE.md proprio.
        manifest["preserved"] = manifest.get("preserved", []) + ["CLAUDE.md"]
    else:
        _backup_and_note("CLAUDE.md")
        with open(claude_path, "w", encoding="utf-8") as fh:
            fh.write("@AGENTS.md\n")

    # v2/ inteira
    for rel in _iter_source_files(source):
        rel_target = f"v2/{rel}"
        _backup_and_note(rel_target)
        dst = os.path.join(target, rel_target)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(os.path.join(source, rel), dst)

    # .claude/settings.json
    settings_rel = ".claude/settings.json"
    _backup_and_note(settings_rel)
    settings_path = os.path.join(target, settings_rel)
    os.makedirs(os.path.dirname(settings_path), exist_ok=True)
    with open(settings_path, "w", encoding="utf-8") as fh:
        json.dump(SETTINGS_HOOKS, fh, ensure_ascii=False, indent=2)

    with open(os.path.join(backup_dir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)

    print(f"apply ok. backup: {backup_dir}")
    print(f"criados: {len(manifest['created'])} sobrescritos: {len(manifest['overwritten'])}")
    return 0


def _find_latest_backup(target: str) -> str | None:
    backups_root = os.path.join(target, "_backups")
    if not os.path.isdir(backups_root):
        return None
    candidates = sorted(
        d for d in os.listdir(backups_root) if d.startswith("v2-migrate-")
    )
    if not candidates:
        return None
    return os.path.join(backups_root, candidates[-1])


def cmd_undo(target: str, backup: str | None) -> int:
    target = os.path.abspath(target)
    backup_dir = os.path.abspath(backup) if backup else _find_latest_backup(target)
    if not backup_dir or not os.path.isdir(backup_dir):
        print(f"erro: backup nao encontrado para {target}", file=sys.stderr)
        return 1

    manifest_path = os.path.join(backup_dir, "manifest.json")
    if not os.path.isfile(manifest_path):
        print(f"erro: manifest.json ausente em {backup_dir}", file=sys.stderr)
        return 1
    with open(manifest_path, "r", encoding="utf-8") as fh:
        manifest = json.load(fh)

    restored, removed = 0, 0
    for rel in manifest.get("overwritten", []):
        src = os.path.join(backup_dir, rel)
        dst = os.path.join(target, rel)
        if os.path.isfile(src):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            restored += 1

    for rel in manifest.get("created", []):
        dst = os.path.join(target, rel)
        if os.path.isfile(dst):
            os.remove(dst)
            removed += 1

    print(f"undo ok. restaurados: {restored} removidos: {removed} (backup: {backup_dir})")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Migracao reversivel da Alia Flow 2.0.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_apply = sub.add_parser("apply")
    p_apply.add_argument("--source", required=True)
    p_apply.add_argument("--target", required=True)

    p_undo = sub.add_parser("undo")
    p_undo.add_argument("--target", required=True)
    p_undo.add_argument("--backup", default=None)

    args = parser.parse_args()
    if args.cmd == "apply":
        return cmd_apply(args.source, args.target)
    if args.cmd == "undo":
        return cmd_undo(args.target, args.backup)
    parser.error("comando desconhecido")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
