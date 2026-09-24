"""task_model.py - Entidade Task (modulo lib, TASK-804 E7 - correcao da revisao independente).

Camada anticorrupcao sobre o state.json legado: absorve flow/risk.py (classificacao pura,
mantida como funcao separada - modulo I6 do CONTRACTS.md) e a logica de abrir/fechar Task que
antes vivia solta em bin/task.py. Normaliza os apelidos do legado (ordem_operator x
operator_order, gate_verdict texto livre, budget_exceeded booleano ou contagem, destino) e
aplica as transicoes validas: open -> review -> done. done NUNCA reabre por cima.

So biblioteca padrao. Toda funcao publica e pura o bastante para testar sem I/O alem da leitura
de arquivo que a propria validacao de fatia exige.
"""
from __future__ import annotations

import os
import re
import sys
from typing import Optional

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "..", "flow"))
import risk as _risk  # noqa: E402 (v2/flow/risk.py, I6 - funcao pura, so chamada daqui)

DESTINOS_VALIDOS = ("publico", "interno")
VEREDITOS_VALIDOS = ("PASS", "FAIL", "CONCERN")
MAX_LINHAS_FATIA = 120

# Transicoes validas por status atual. None = Task ainda nao existe (abertura).
TRANSICOES_VALIDAS = {
    None: {"open"},
    "open": {"review", "done"},
    "review": {"review", "done"},
    "done": set(),  # done nao reabre por cima - a Task de correcao seguinte e uma Task NOVA
}


class TaskError(Exception):
    """Erro de dominio da entidade Task. `extra` vira campos soltos no JSON de erro (o
    chamador - bin/task.py - decide o que completar, como clients_validos)."""

    def __init__(self, msg: str, **extra):
        super().__init__(msg)
        self.msg = msg
        self.extra = extra


def _ordem_operator(d: dict) -> bool:
    """Le ordem_operator OU operator_order (apelido legado). A divergencia entre os dois nomes
    era o motivo medido de 146 Tasks com o campo true nunca dispararem R2."""
    return bool(d.get("ordem_operator") or d.get("operator_order"))


def budget_exceeded_count(task: dict) -> int:
    """budget_exceeded no legado aparece como booleano OU como contagem (budget_exceeded_count).
    Normaliza os dois formatos para um inteiro unico."""
    v = task.get("budget_exceeded_count")
    if isinstance(v, int):
        return v
    v = task.get("budget_exceeded")
    if isinstance(v, bool):
        return 1 if v else 0
    if isinstance(v, int):
        return v
    return 0


def gate_verdict_normalizado(task: dict) -> Optional[str]:
    """gate_verdict legado e texto livre (comparado igual string em learn/reflector.py).
    Normaliza para PASS/FAIL/CONCERN (maiusculo, sem espaco nas pontas) ou None."""
    v = task.get("gate_verdict")
    if not isinstance(v, str) or not v.strip():
        return None
    v2 = v.strip().upper()
    return v2 if v2 in VEREDITOS_VALIDOS else None


_FATIA_RE = re.compile(r"^(.*?)#L(\d+)-(\d+)$")


def validar_fatias(paths_field: str) -> list[str]:
    """Recusa fatia de contexto que nao resolve no disco. Cada trecho no formato
    `caminho#L10-40` precisa: arquivo existir, faixa nao invertida, ate MAX_LINHAS_FATIA
    linhas, e o fim da faixa nao passar do total de linhas do arquivo. Trecho sem `#Lx-y`
    (caminho solto, sem fatia declarada) nunca e checado aqui - so quem declara fatia
    assume o contrato dela. Devolve a lista de problemas (vazia = tudo ok)."""
    problemas: list[str] = []
    partes = [p.strip() for p in re.split(r"[;,]", paths_field or "") if p.strip()]
    for parte in partes:
        m = _FATIA_RE.match(parte)
        if not m:
            continue
        caminho, ini, fim = m.group(1), int(m.group(2)), int(m.group(3))
        if fim < ini:
            problemas.append(f"{parte}: faixa invertida (fim antes do inicio)")
            continue
        if (fim - ini + 1) > MAX_LINHAS_FATIA:
            problemas.append(f"{parte}: {fim - ini + 1} linhas, teto e {MAX_LINHAS_FATIA}")
            continue
        if not os.path.isfile(caminho):
            problemas.append(f"{parte}: arquivo nao existe no disco")
            continue
        with open(caminho, "r", encoding="utf-8", errors="replace") as fh:
            n_linhas = sum(1 for _ in fh)
        if fim > n_linhas:
            problemas.append(f"{parte}: arquivo tem {n_linhas} linhas, fatia pede ate L{fim}")
    return problemas


def classificar_risco(brief: dict) -> dict:
    """Ponto unico de classificacao de risco: normaliza o apelido ordem_operator/operator_order
    ANTES de delegar a flow/risk.py (funcao pura, I6), para nao repetir o bug medido pela
    revisao independente."""
    brief_normalizado = dict(brief)
    brief_normalizado["ordem_operator"] = _ordem_operator(brief)
    return _risk.classificar(brief_normalizado)


def abrir(brief: dict, clients_validos: list[str]) -> dict:
    """Constroi o registro de uma Task nova (status "open") a partir do brief. Levanta
    TaskError se: checklist incompleto, Client invalido, destino fora do enum, ou fatia de
    contexto (paths) que nao resolve no disco."""
    resultado = classificar_risco(brief)
    if resultado["faltando"]:
        raise TaskError("checklist de brief incompleto", faltando=resultado["faltando"])

    client = brief["client"]
    if client not in clients_validos:
        raise TaskError("client invalido", client_recebido=client)

    if brief.get("destino") not in DESTINOS_VALIDOS:
        raise TaskError(
            "destino precisa ser um dos valores validos",
            destino_recebido=brief.get("destino"),
            destinos_validos=list(DESTINOS_VALIDOS),
        )

    problemas_fatia = validar_fatias(brief.get("paths", ""))
    if problemas_fatia:
        raise TaskError("fatia de contexto declarada em paths nao resolve no disco",
                         problemas=problemas_fatia)

    task = {
        "client": client,
        "project": brief["project"],
        "title": brief["objetivo"],
        "paths": brief["paths"],
        "consumidor": brief["consumidor"],
        "destino": brief["destino"],
        "exemplo_falha": brief["exemplo_falha"],
        "type": brief.get("type", "construcao"),
        "status": "open",
        "risco": resultado["risco"],
        "gatilhos": resultado["gatilhos"],
        "modo": resultado["modo"],
    }
    if brief.get("supersedes"):
        task["supersedes"] = brief["supersedes"]
    if brief.get("criterio_aceite"):
        task["criterio_aceite"] = brief["criterio_aceite"]
    return task


def _fonte_evidencia_veredito(task_id: str, events: list[dict]) -> Optional[str]:
    """Evidencia de veredito = evento de revisor no ledger (`review_verdict` com este
    task_id) OU saida do gate-check para este task_id (`gate_check`). O texto que quem fecha
    digita em --veredito NUNCA basta sozinho - e so o rotulo, nao a prova."""
    for ev in events:
        if ev.get("task_id") != task_id:
            continue
        if ev.get("event") == "review_verdict":
            return "ledger_review"
        if ev.get("event") == "gate_check":
            return "gate_check"
    return None


def fechar(task: dict, veredito: str, artifact: str, events: list[dict],
           root_cause: str = "", criterio_reprovado: str = "") -> dict:
    """Aplica a transicao de fechamento. Levanta TaskError se: a Task ja esta done (nao reabre
    por cima), falta --artifact, veredito fora do enum, Task de correcao sem root_cause, ou
    falta evidencia de veredito no ledger. Devolve uma COPIA da Task com os campos de
    fechamento aplicados - nunca muta o dict recebido."""
    status_atual = task.get("status")
    if status_atual == "done":
        raise TaskError("Task done nao reabre por cima", id=task.get("id"), status_atual="done")

    if not artifact:
        raise TaskError("close exige --artifact (o que resolve o criterio de aceite)")
    if veredito not in VEREDITOS_VALIDOS:
        raise TaskError("close exige --veredito em PASS, FAIL ou CONCERN", veredito_recebido=veredito)
    if task.get("type") == "correcao" and not root_cause:
        raise TaskError("Task de correcao exige --root-cause (5 porques)", id=task.get("id"))

    fonte_evidencia = _fonte_evidencia_veredito(task.get("id"), events)
    if fonte_evidencia is None:
        raise TaskError(
            "close exige evidencia de veredito (evento review_verdict do revisor ou saida do "
            "gate-check no ledger para este task_id) - texto digitado no --veredito nao basta",
            task_id=task.get("id"),
        )

    novo_status = "done" if veredito == "PASS" else "review"
    permitidas = TRANSICOES_VALIDAS.get(status_atual, set())
    if status_atual is not None and novo_status not in permitidas:
        raise TaskError("transicao invalida", de=status_atual, para=novo_status)

    nova = dict(task)
    nova["artifact"] = artifact
    nova["gate_verdict"] = veredito
    nova["status"] = novo_status
    nova["evidencia_veredito"] = fonte_evidencia
    if root_cause:
        nova["root_cause"] = root_cause
    if veredito != "PASS" and criterio_reprovado:
        nova["gate_criteria_failed"] = [criterio_reprovado]
    return nova
