#!/usr/bin/env python3
"""brief.py - CLI open do brief de fatias exatas (TASK-804, revisao e7, mudanca 3).

Problema medido (e7-revisao-ddd-independente.md, linha 29 e achado da tabela): o brief que
chegava ao Specialist carregava texto da COORDENACAO (saida do risk, justificativa, nota de
protocolo) e mandava abrir secao sem ancora ("abra a secao de design system do DESIGN.md",
212 KB, sem linha). Prescricao: o Specialist recebe SO os 6 campos do checklist (client,
project, objetivo, paths, consumidor, destino, exemplo_falha) mais fatias no formato exato
`caminho#Lx-Ly`, validadas contra o disco. Fatia sem ancora (sem #Lx-Ly) e RECUSADA - e
exatamente a falha que gerou o achado.

Le a Task pelos campos que existirem no state (`--state` + `--id`, mesmo arquivo que
`bin/task.py` opera) OU por um brief cru (`--brief`, JSON so com os 6 campos) - nunca importa
`flow/risk.py` nem `lib/ledger.py`: fica desacoplado da entidade Task (mudanca 4, fora deste
escopo, territorio do Warden) e le com `.get()` defensivo, tolerante a schema antigo ou novo.

Fatia (`--fatia caminho#Lstart-Lend`, repetivel):
  - exige ancora (#Lstart-Lend); sem ancora, RECUSADA (o problema medido era exatamente isso).
  - teto de 120 linhas por fatia; acima, RECUSADA (fatia grande demais - fracione).
  - caminho tem que existir e o range tem que caber no arquivo; senao, RECUSADA.
  - fatia com menos de 2 KB vem EMBUTIDA no brief (`conteudo`); 2 KB ou mais, so a referencia
    (`ref`) - o Specialist abre com Read(offset, limit), nunca o arquivo inteiro.

Qualquer fatia recusada falha o `open` inteiro (mesma disciplina do checklist: campo invalido
nao abre a Task pela metade). Saida sempre 1 objeto JSON em stdout; exit 0 sucesso, 1 erro.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(V2, "flow"))
import slice as slice_mod  # noqa: E402  (v2/flow/slice.py - so pure/stdlib, nao quebra o
# desacoplamento de lib/ e risk.py que este arquivo mantem de proposito)

TETO_LINHAS = 120
TETO_EMBUTIR_BYTES = 2048
CAMPOS_CHECKLIST = ("client", "project", "objetivo", "paths", "consumidor", "destino", "exemplo_falha")

FATIA_RE = re.compile(r"^(?P<path>[^#]+)#L(?P<start>\d+)-L?(?P<end>\d+)$")


def _err(msg: str, **extra) -> dict:
    return {"ok": False, "error": msg, **extra}


def _ok(**extra) -> dict:
    return {"ok": True, **extra}


def _brief_from_task(task: dict) -> dict:
    """So os 6 campos do checklist, com .get() defensivo (tolerante a schema antigo/novo)."""
    return {
        "client": task.get("client"),
        "project": task.get("project"),
        "objetivo": task.get("objetivo") or task.get("title"),
        "paths": task.get("paths"),
        "consumidor": task.get("consumidor"),
        "destino": task.get("destino"),
        "exemplo_falha": task.get("exemplo_falha"),
    }


def _resolve_fatia(raw: str, repo_root: str) -> dict:
    m = FATIA_RE.match(raw)
    if not m:
        return {"ref": raw, "ok": False, "erro": "sem ancora #Lstart-Lend - fatia recusada"}

    path, start, end = m.group("path"), int(m.group("start")), int(m.group("end"))
    if end < start:
        return {"ref": raw, "ok": False, "erro": "fim antes do inicio"}
    n_linhas = end - start + 1
    if n_linhas > TETO_LINHAS:
        return {"ref": raw, "ok": False, "erro": f"{n_linhas} linhas > teto {TETO_LINHAS} - fracione"}

    full = path if os.path.isabs(path) else os.path.join(repo_root, path)
    if not os.path.isfile(full):
        return {"ref": raw, "ok": False, "erro": "caminho nao existe no disco"}

    with open(full, "r", encoding="utf-8", errors="replace") as fh:
        linhas = fh.readlines()

    if end > len(linhas):
        return {"ref": raw, "ok": False, "erro": f"arquivo tem {len(linhas)} linhas, range pede ate {end}"}

    trecho = "".join(linhas[start - 1:end])
    tamanho = len(trecho.encode("utf-8"))
    resultado = {"ref": raw, "ok": True, "bytes": tamanho}
    if tamanho < TETO_EMBUTIR_BYTES:
        resultado["conteudo"] = trecho
    else:
        resultado["conteudo"] = None
        resultado["nota"] = "fatia >= 2 KB - abra com Read(offset, limit), nao o arquivo inteiro"
    return resultado


def cmd_open(args: argparse.Namespace) -> dict:
    if args.brief:
        try:
            raw_brief = json.loads(args.brief)
        except json.JSONDecodeError as exc:
            return _err(f"--brief nao e JSON valido: {exc}")
        brief = {k: raw_brief.get(k) for k in CAMPOS_CHECKLIST}
    elif args.state and args.id:
        with open(args.state, "r", encoding="utf-8") as fh:
            state = json.load(fh)
        task = next((t for t in state.get("tasks", []) if t.get("id") == args.id), None)
        if task is None:
            return _err("Task nao encontrada", id_recebido=args.id,
                        ids_abertos=[t.get("id") for t in state.get("tasks", []) if t.get("status") == "open"])
        brief = _brief_from_task(task)
        # TASK-812 item B: fatia que depende da anterior so abre brief depois do Gate da
        # anterior dar PASS (slice.pode_comecar_fatia) - le so o que a propria Task ja carrega
        # (fatia_id, fatia_de), nunca importa risk.py/ledger.py (desacoplamento de proposito).
        if task.get("depende_da_anterior"):
            fatia_id = str(task.get("fatia_id") or "")
            m_fatia = re.match(r"^fatia-(\d+)$", fatia_id)
            indice = (int(m_fatia.group(1)) - 1) if m_fatia else 0
            grupo_id = task.get("fatia_de")
            num_atual = None
            m_num = re.match(r"^TASK-(\d+)$", str(task.get("id") or ""))
            if m_num:
                num_atual = int(m_num.group(1))
            anterior = None
            if num_atual is not None:
                id_anterior = f"TASK-{num_atual - 1:03d}"
                anterior = next((t for t in state.get("tasks", [])
                                  if t.get("id") == id_anterior
                                  and (t.get("fatia_de") == grupo_id or t.get("id") == grupo_id)), None)
            veredito_anterior = anterior.get("gate_verdict") if anterior else None
            if not slice_mod.pode_comecar_fatia(indice, veredito_anterior):
                return _err("fatia anterior sem PASS ainda",
                             fatia_anterior=anterior.get("id") if anterior else None,
                             veredito_anterior=veredito_anterior)
    else:
        return _err("informe --brief <json> OU --state <path> + --id <task_id>")

    faltando = [k for k in CAMPOS_CHECKLIST if not brief.get(k)]
    if faltando:
        return _err("checklist de brief incompleto", faltando=faltando)

    repo_root = args.repo_root or os.getcwd()
    fatias = [_resolve_fatia(f, repo_root) for f in (args.fatia or [])]
    recusadas = [f for f in fatias if not f["ok"]]
    if recusadas:
        return _err("fatia recusada - brief nao abre pela metade", recusadas=recusadas)

    return _ok(brief=brief, fatias=fatias)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="brief.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_open = sub.add_parser("open")
    p_open.add_argument("--state", help="copia do state.json (junto com --id)")
    p_open.add_argument("--id", help="id da Task no --state")
    p_open.add_argument("--brief", help="JSON cru so com os 6 campos (alternativa a --state/--id)")
    p_open.add_argument("--fatia", action="append", help="caminho#Lstart-Lend, repetivel")
    p_open.add_argument("--repo-root", default="", help="raiz para resolver caminho relativo de fatia")
    p_open.set_defaults(func=cmd_open)

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
