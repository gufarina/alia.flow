#!/usr/bin/env python3
"""gate.py - o produtor do modulo gate (I5, TASK-825). Valida um parecer contra o contrato do
Gate e grava o evento `gate_check` no ledger - o unico jeito de fechar Task sem `review_verdict`
manual de revisor.

Contrato usado (a v2 nao declara os 6 criterios em prosa propria - so cita "gate: 6 criterios +
goal-backward" em v2/CONTRACTS.md e v2/LAW-MAP.md L11 "nucleo do modulo", sem listar): os 6
minimos vem de `engine/governance/quality-gate.md` linhas 16-30 (Funciona, Aderente ao DDD,
Frugal, Rastreavel, Simplicidade/Atrito, Fundamentada). O setimo, goal-backward (confere se a
entrega atingiu o OBJETIVO/criterio de aceite da Task, nao so se rodou sem erro), vem de
v2/CONTRACTS.md linha "gate | 6 criterios + goal-backward" e do estudo que originou a 2.0
(artifacts/alia-2.0-2026-09-22/e3-concorrentes-e-estudos.md linha 127, e4-arquitetura-v2.md
linha 54).

Parecer valido (formato): cada um dos 7 rotulos abaixo numa linha propria `rotulo: RESULTADO`
(RESULTADO em PASS, FAIL ou CONCERN, sem distincao de maiusculas), com uma linha `evidencia: ...`
logo na sequencia (pode pular linha em branco, nunca outro texto no meio). No fim do arquivo, uma
linha `veredito: PASS|FAIL|CONCERN` (se aparecer mais de uma vez, vale a ultima). Zero travessao
(U+2014) e zero meia-risca (U+2013) em qualquer ponto do arquivo.

Uso: python gate.py --task TASK-N --parecer <arquivo.md> [--session <id>] [--ledger <caminho>]

So biblioteca padrao. Saida sempre 1 objeto JSON em stdout; exit 0 quando o parecer e valido
(evento gravado), 1 quando invalido (nenhum evento, mensagem lista o que falta).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(V2, "lib"))
import ledger  # noqa: E402  (v2/lib/ledger.py)
import paths  # noqa: E402  (v2/lib/paths.py - resolvedor unico de ledger)
from task_model import VEREDITOS_VALIDOS  # noqa: E402  (PASS/FAIL/CONCERN, mesmo enum da Task)

TRAVESSAO = chr(0x2014)  # em-dash, banido por lei da casa (chr() pra nunca ter o char no fonte)
MEIA_RISCA = chr(0x2013)  # en-dash, mesma lei

CRITERIOS_MINIMOS = ("funciona", "aderente-ddd", "frugal", "rastreavel", "simplicidade", "fundamentada")
CRITERIO_GOAL_BACKWARD = "goal-backward"
TODOS_CRITERIOS = CRITERIOS_MINIMOS + (CRITERIO_GOAL_BACKWARD,)


def _linha_rotulo(rotulo: str, linhas: list[str]) -> tuple[int | None, str | None]:
    padrao = re.compile(r"^\s*" + re.escape(rotulo) + r"\s*:\s*(.*)$", re.IGNORECASE)
    for i, linha in enumerate(linhas):
        m = padrao.match(linha)
        if m:
            return i, m.group(1).strip()
    return None, None


def _evidencia_logo_apos(idx: int, linhas: list[str]) -> str | None:
    """A linha de evidencia precisa ser a proxima linha NAO-VAZIA depois do rotulo - pula
    linha em branco, mas para na primeira linha com conteudo que nao seja `evidencia:`."""
    padrao = re.compile(r"^\s*evidencia\s*:\s*(.+\S)\s*$", re.IGNORECASE)
    for linha in linhas[idx + 1:]:
        if not linha.strip():
            continue
        m = padrao.match(linha)
        return m.group(1).strip() if m else None
    return None


def validar_parecer(texto: str) -> dict:
    """Confere o parecer contra o contrato do gate. Devolve {problemas, criterios, veredito}.
    `problemas` vazio = parecer valido (pode gravar o evento)."""
    problemas: list[str] = []
    if TRAVESSAO in texto:
        problemas.append("travessao (em-dash, U+2014) encontrado no parecer")
    if MEIA_RISCA in texto:
        problemas.append("meia-risca (en-dash, U+2013) encontrada no parecer")

    linhas = texto.splitlines()
    criterios: dict[str, str] = {}
    for rotulo in TODOS_CRITERIOS:
        idx, valor = _linha_rotulo(rotulo, linhas)
        if idx is None:
            problemas.append(f"criterio '{rotulo}' ausente (linha 'rotulo: RESULTADO' nao encontrada)")
            continue
        if valor.upper() not in VEREDITOS_VALIDOS:
            problemas.append(f"criterio '{rotulo}' com resultado invalido: '{valor}' (precisa PASS, FAIL ou CONCERN)")
            continue
        evidencia = _evidencia_logo_apos(idx, linhas)
        if not evidencia:
            problemas.append(f"criterio '{rotulo}' sem linha de evidencia logo abaixo")
            continue
        criterios[rotulo] = valor.upper()

    veredito = None
    padrao_veredito = re.compile(r"^\s*veredito\s*:\s*(.*)$", re.IGNORECASE)
    for linha in linhas:
        m = padrao_veredito.match(linha)
        if m:
            veredito = m.group(1).strip().upper()  # ultima ocorrencia vence
    if veredito is None:
        problemas.append("linha 'veredito: PASS|FAIL|CONCERN' ausente")
    elif veredito not in VEREDITOS_VALIDOS:
        problemas.append(f"veredito invalido: '{veredito}' (precisa PASS, FAIL ou CONCERN)")
    elif veredito != "FAIL" and any(v == "FAIL" for v in criterios.values()):
        # conserto B2: quality-gate.md diz "reprovar um reprova o Artifact" - criterio FAIL
        # nunca pode conviver com veredito PASS/CONCERN.
        problemas.append("parecer tem criterio(s) em FAIL mas o veredito nao e FAIL "
                          "(reprovar um criterio reprova o Artifact, quality-gate.md)")
    elif veredito == "PASS" and any(v == "CONCERN" for v in criterios.values()):
        # conserto B2: mesma regra de agregacao de quality-gate.md:119-120 (qualquer SKIP vira
        # CONCERN) aplicada ao gate - CONCERN nunca some dentro de um veredito PASS.
        problemas.append("parecer tem criterio(s) em CONCERN mas o veredito e PASS "
                          "(CONCERN nunca vira PASS, quality-gate.md)")

    return {"problemas": problemas, "criterios": criterios, "veredito": veredito}


def _print(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False))
    sys.stdout.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(prog="gate.py")
    parser.add_argument("--task", required=True)
    parser.add_argument("--parecer", required=True, help="caminho do arquivo .md com o parecer")
    parser.add_argument("--session", default="", help="session_id do host, se conhecido")
    parser.add_argument("--ledger", default="", help="caminho do ledger (teste); default = paths.ledger_path()")
    args = parser.parse_args()

    if not os.path.isfile(args.parecer):
        _print({"ok": False, "error": "parecer nao encontrado no disco", "parecer": args.parecer})
        return 1

    with open(args.parecer, "rb") as fh:
        bruto = fh.read()
    texto = bruto.decode("utf-8", errors="replace")

    avaliacao = validar_parecer(texto)
    if avaliacao["problemas"]:
        _print({"ok": False, "error": "parecer invalido contra o contrato do gate",
                "problemas": avaliacao["problemas"]})
        return 1

    ledger_path = args.ledger or paths.ledger_path()
    evento = {
        "event": "gate_check",
        "task_id": args.task,
        "veredito": avaliacao["veredito"],
        "parecer_sha256": hashlib.sha256(bruto).hexdigest(),
        "parecer_path": os.path.abspath(args.parecer),
        "criterios": avaliacao["criterios"],
    }
    if args.session:
        evento["session_id"] = args.session

    gravado = ledger.append_event(ledger_path, evento)
    _print({"ok": True, "event": gravado})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
