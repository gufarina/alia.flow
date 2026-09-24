"""Decide - a porta de decisao do kernel (modulo 1, I7, TASK-801 E5).

decide(ponto, entrada) devolve {"resposta": ..., "confianca": ...} ou None (abstem).

Contrato (v2/AGENTS.md, secao "A porta de decisao"): sem motor de decisao instalado, a porta
SEMPRE abstem (None) e a regra escrita decide sozinha - nenhuma prova do sistema depende da porta
responder. Adaptador NULO por padrao: e o unico adaptador que existe nesta build.

Deteccao preguicosa: so na PRIMEIRA chamada de decide() no processo, verifica se o venv da Laya
existe em disco (os.path.isdir, nunca abre nem importa nada) e cacheia o resultado pro resto do
processo - nenhuma chamada depois disso paga o custo de checar de novo. Caminho configuravel por
ALIA_LAYA_ROOT (padrao: <home>/Projetos/laya-teste, o venv medido em 21/09/2026 e citado em
e4-laya-desempenho.md).

Com Laya presente: decide() faz UM import tardio de `laya` (nunca no topo do modulo, entao um
processo sem Laya jamais paga esse custo) e roda em modo SOMBRA - grava a decisao (resposta e
confianca reais, ou o erro se a chamada falhar) num ledger PROPRIO de teste, nunca em studio/
real. O RETORNO de decide() continua None sempre: esta entrega (I7) nunca promove a Laya a
decisora, so prova o encanamento e comeca a medir se ela merece confianca (mesmo padrao do teste
"relevancia de nota de memoria" do modulo 6). Ver e4-laya-desempenho.md: nenhum gancho por evento
deve pagar o aquecimento de ~17s de um processo novo; quem chamar decide() faz isso em ponto de
lote (fechar Task, curar memoria), nunca em PreToolUse/UserPromptSubmit.
"""
from __future__ import annotations

import json
import os
import tempfile
import time

_LAYA_CHECKED = False
_LAYA_PRESENT = False
_ROUTER = None  # cacheado 1x por processo, so quando alguma chamada REAL precisar dele


def _laya_root() -> str:
    return os.environ.get(
        "ALIA_LAYA_ROOT",
        os.path.join(os.path.expanduser("~"), "Projetos", "laya-teste"),
    )


def _detect_laya() -> bool:
    """Deteccao preguicosa, 1x por processo. So confere se a pasta do venv existe -
    NUNCA importa torch nem laya aqui. Isso e o que garante < 5 ms e zero import
    quando a Laya nao esta instalada (prova negativa do I7)."""
    global _LAYA_CHECKED, _LAYA_PRESENT
    if _LAYA_CHECKED:
        return _LAYA_PRESENT
    root = _laya_root()
    _LAYA_PRESENT = os.path.isdir(os.path.join(root, ".venv"))
    _LAYA_CHECKED = True
    return _LAYA_PRESENT


def _get_router():
    """Import tardio e cache do Router - so chamado depois que _detect_laya() achou o
    venv em disco. Paga o aquecimento (~17s) 1 vez por processo, nunca por chamada."""
    global _ROUTER
    if _ROUTER is None:
        from laya import Router  # import aqui de proposito, nunca no topo do arquivo

        _ROUTER = Router(preload=True)
    return _ROUTER


def _predict_sombra(ponto: str, entrada: dict) -> dict:
    router = _get_router()
    criteria = entrada.get("criteria") if isinstance(entrada, dict) else None
    corpo = ""
    if isinstance(entrada, dict):
        corpo = str(entrada.get("texto") or entrada.get("contexto") or entrada)
    else:
        corpo = str(entrada)
    pergunta = (entrada.get("pergunta") if isinstance(entrada, dict) else None) or ponto
    state = {"from": "decide", "subject": ponto, "body": corpo}
    if criteria:
        questions = {"q": {"type": "choice", "instructions": pergunta, "criteria": criteria}}
        ans = router.predict(state, questions)["answers"]["q"]
        return {"resposta": ans.get("choice"), "confianca": ans.get("confidence", 0.0)}
    questions = {"q": {"type": "noul", "instructions": pergunta}}
    ans = router.predict(state, questions)["answers"]["q"]
    return {"resposta": ans.get("noul"), "confianca": ans.get("confidence", 0.0)}


def _shadow_ledger_path() -> str:
    # ledger de SOMBRA, proprio de teste - NUNCA studio/ real (regra da Task).
    return os.environ.get(
        "ALIA_DECIDE_SHADOW_LEDGER",
        os.path.join(tempfile.gettempdir(), "alia-v2-decide-shadow.jsonl"),
    )


def _write_shadow(ponto: str, entrada: dict, resposta: dict) -> None:
    path = os.path.normpath(_shadow_ledger_path())
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    linha = {"ts": time.time(), "ponto": ponto, "entrada": entrada, "resposta": resposta}
    with open(path, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(linha, ensure_ascii=False, sort_keys=True) + "\n")


def decide(ponto: str, entrada: dict) -> dict | None:
    """Porta de decisao unica do kernel. Adaptador nulo por padrao.

    Sem Laya instalada: devolve None, sem importar nada alem deste modulo.
    Com Laya instalada: grava a decisao dela em modo sombra e AINDA ASSIM devolve None -
    esta build nunca deixa a Laya decidir por ninguem, so mede.
    """
    if not _detect_laya():
        return None
    try:
        resposta = _predict_sombra(ponto, entrada)
    except Exception as exc:  # fail-soft: erro na Laya nunca derruba quem chamou decide()
        resposta = {"resposta": None, "confianca": 0.0, "erro": str(exc)[:200]}
    _write_shadow(ponto, entrada, resposta)
    return None
