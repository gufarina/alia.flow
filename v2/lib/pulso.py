"""pulso.py - PULSO: estado dinamico Alia-operador e Specialist/Gateway (modulo lib, Operacao
Deep, TASK-847). Calculo deterministico (sem chamada de modelo), decaimento por meia-vida,
`ledger.read_events_from()` (fatia por offset, nunca o ledger inteiro a cada chamada) como unica
fonte de evento. Escreve SO este modulo (chamado de dentro de `hooks/dispatch.py` no Stop); a
Alia nunca escreve o arquivo via Write/Edit - o guard em dispatch.py nega isso (ver
`_is_pulso_write_target`).

Arquivo em disco: `pulso.json` (nao `pulso.yaml` como o desenho original propos - YAML exigiria
dependencia nova fora da biblioteca padrao; JSON e a troca registrada aqui, mesmo formato usado
por `state.json`/`pulso.json` no resto do motor). Caminho resolvido por `paths.pulso_path()`.

Funcoes publicas (assinatura fixa, o GAUGE monta cenario com elas sem tocar ledger):

    render(agent_id: str, state: dict) -> str
        Monta o bloco de texto FIXO (template, nunca prosa livre) para `agent_id` a partir de
        `state` (o dict no formato de pulso.json, com a chave "entidades"). agent_id == "alia"
        usa o template longo (teto 600 caracteres); qualquer outro agent_id (formato
        "{client}-{specialist}", o mesmo de register-task.ps1/squad-bridge) usa o template curto
        de sub-agente (teto 400 caracteres). agent_id ausente de state["entidades"] devolve ""
        (nada a injetar - "agente sem entrada no PULSO = nada injetado"). Levanta ValueError se o
        template montado ultrapassar o teto do agente (nunca trunca calado - a prova negativa em
        proof/check.py quebra isso de proposito).

    from_facts(fatos: dict) -> dict
        Monta um `state` (mesmo formato de pulso.json) direto de numeros prontos, sem ledger, para
        o GAUGE montar cenario de teste sem depender de eventos sinteticos. Formato de `fatos`:
        {"alia": {"pressao": 6.4, "calor": 2.1, "confianca_acumulada": 41,
                   "historia": [{"nota": "arquivo.md", "frase": "..."}]},
         "cliente-especialista": {"pressao": 8.0, "calor": 1.0}}
        Todo campo numerico vira {"valor": N, "origem": {}} - from_facts nao reconstroi origem,
        so o valor final (suficiente para render() e para a bateria de cenario da Fase 4).

Decisao de escopo (Gateway, pedida pela extensao do CEO - 1 linha, TASK-847): hoje o ledger nao
tem um jeito deterministico de saber que um `agent_id` E o Gateway de um squad (isso mora no
squad-bridge/persona, fora do ledger) - por isso todo agent_id (Specialist OU Gateway) recebe o
MESMO calculo direto (eventos das Tasks em que ele aparece como `agent_type` executor); a
agregacao "maximo dos Specialists do Client" fica disponivel como `squad_pressure()` (testada com
lista sintetica de membros) para quem SOUBER a lista de agent_ids do squad usar - dispatch.py hoje
nao chama essa funcao automaticamente, para nunca inventar um mapeamento agent_id->Client que
nao existe no ledger.
"""
from __future__ import annotations

import datetime
import json
import os
import sys
import time
from collections import defaultdict

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
import ledger  # noqa: E402

VERSAO = 1

# meia-vida em horas por dimensao (spec Operacao Deep, secao A). confianca_acumulada nunca decai.
MEIA_VIDA_HORAS = {"pressao": 4.0, "calor": 1.0}

# pesos por evento novo (decisao deste modulo, documentada aqui - nao ha peso "oficial" no
# desenho original, so a formula de decaimento; os valores abaixo sao os primeiros usados e
# ficam sujeitos a recalibragem pela bateria de medida da Fase 4, GAUGE/TASK-848).
PESO_GATE_FAIL = 2.0
PESO_GATE_CONCERN = 1.0
PESO_TASK_SEM_VEREDITO = 1.0
PESO_ENTREGA_APROVADA = 1.0  # gate_check veredito PASS -> fonte de "calor" (entrega aprovada)

VALOR_MAX_ESCALA = 10.0

EVENTO_TASK_SEM_VEREDITO = "task_fechado_sem_veredito"

TETO_ALIA = 600
TETO_SUBAGENTE = 400

LIMIAR_PRESSAO_ALTA = 7.0
LIMIAR_CALOR_ALTO = 6.0

MAX_HISTORIA_ITENS = 5
MAX_HISTORIA_FRASE = 140


# ---------------------------------------------------------------------------
# Persistencia (JSON simples - a troca de yaml registrada no topo do arquivo)
# ---------------------------------------------------------------------------

def load_state(pulso_path: str) -> dict:
    """Le pulso.json. Ausente ou corrompido devolve o estado vazio (nunca lanca) - a Alia/
    sub-agente sem PULSO ainda nao tem nada a injetar, nunca um erro."""
    if not os.path.exists(pulso_path):
        return {"versao": VERSAO, "atualizado_em": None, "entidades": {}}
    try:
        with open(pulso_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError):
        return {"versao": VERSAO, "atualizado_em": None, "entidades": {}}
    if not isinstance(data, dict):
        return {"versao": VERSAO, "atualizado_em": None, "entidades": {}}
    data.setdefault("entidades", {})
    return data


def save_state(pulso_path: str, state: dict) -> None:
    os.makedirs(os.path.dirname(pulso_path) or ".", exist_ok=True)
    with open(pulso_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(state, fh, ensure_ascii=False, sort_keys=True)


def _iso(ts: float) -> str:
    return datetime.datetime.fromtimestamp(ts, tz=datetime.timezone.utc).isoformat()


def _parse_iso(texto: str | None) -> float | None:
    if not texto:
        return None
    try:
        return datetime.datetime.fromisoformat(texto.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


# ---------------------------------------------------------------------------
# Calculo (recompute) - le SO ledger.read_events_from(), nunca state.json/transcript
# ---------------------------------------------------------------------------

def _decai(valor_antigo: float, horas_passadas: float, meia_vida: float) -> float:
    if meia_vida <= 0:
        return valor_antigo
    return valor_antigo * (0.5 ** (horas_passadas / meia_vida))


def compute_from_events(events_novos: list[dict], entidades_anteriores: dict,
                         task_agent_anterior: dict, horas_passadas: float) -> tuple[dict, dict]:
    """Funcao PURA (sem I/O): dado SO a FATIA nova de eventos (`events_novos` - o que apareceu no
    ledger depois do offset ja processado, nunca o ledger inteiro), o estado anterior de
    `entidades`, o mapa task_id->agent_type ja conhecido (`task_agent_anterior`, cumulativo entre
    chamadas) e as horas passadas desde a ultima leitura, devolve (entidades_novas,
    task_agent_novo). Separada de `recompute()` (que cuida so de offset/load/save) para o GAUGE e
    a prova positiva chamarem sem tocar disco nem ledger.

    Ler so a fatia nova (em vez do ledger inteiro a cada chamada) e o que faz `recompute()` achar
    a mesma resposta com ledger de 50 mil ou 50 milhoes de linhas: o offset em pulso.json (ver
    `recompute()`) garante que cada evento e contado exatamente 1 vez, nunca reprocessado."""
    task_agent = dict(task_agent_anterior)
    for ev in events_novos:
        if ev.get("event") in ("pre_agent", "post_agent"):
            tid = ev.get("task_id")
            agente = ev.get("agent_type")
            if tid and agente:
                task_agent[tid] = agente

    pressao_peso: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    calor_peso: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))

    def _soma_pressao(agent_id: str, categoria: str, peso: float) -> None:
        pressao_peso[agent_id][categoria] += peso

    def _soma_calor(agent_id: str, categoria: str, peso: float) -> None:
        calor_peso[agent_id][categoria] += peso

    for ev in events_novos:
        etype = ev.get("event")
        tid = ev.get("task_id")
        agente_tarefa = task_agent.get(tid) if tid else None
        if etype == "gate_check":
            veredito = str(ev.get("veredito") or "").upper()
            if veredito == "FAIL":
                _soma_pressao("alia", "gate_fail", PESO_GATE_FAIL)
                if agente_tarefa:
                    _soma_pressao(agente_tarefa, "gate_fail", PESO_GATE_FAIL)
            elif veredito == "CONCERN":
                _soma_pressao("alia", "gate_concern", PESO_GATE_CONCERN)
                if agente_tarefa:
                    _soma_pressao(agente_tarefa, "gate_concern", PESO_GATE_CONCERN)
            elif veredito == "PASS":
                _soma_calor("alia", "entregas_aprovadas", PESO_ENTREGA_APROVADA)
                if agente_tarefa:
                    _soma_calor(agente_tarefa, "entregas_aprovadas", PESO_ENTREGA_APROVADA)
        elif etype == EVENTO_TASK_SEM_VEREDITO:
            _soma_pressao("alia", "task_sem_veredito", PESO_TASK_SEM_VEREDITO)
            if agente_tarefa:
                _soma_pressao(agente_tarefa, "task_sem_veredito", PESO_TASK_SEM_VEREDITO)

    agent_ids = set(entidades_anteriores) | set(pressao_peso) | set(calor_peso) | {"alia"}

    entidades_novas: dict = {}
    for agent_id in agent_ids:
        anterior = entidades_anteriores.get(agent_id, {})
        pressao_antigo = float(anterior.get("pressao", {}).get("valor", 0.0))
        calor_antigo = float(anterior.get("calor", {}).get("valor", 0.0))

        pressao_decaido = _decai(pressao_antigo, horas_passadas, MEIA_VIDA_HORAS["pressao"])
        calor_decaido = _decai(calor_antigo, horas_passadas, MEIA_VIDA_HORAS["calor"])

        origem_pressao = dict(pressao_peso.get(agent_id, {}))
        origem_calor = dict(calor_peso.get(agent_id, {}))
        pressao_valor = max(0.0, min(VALOR_MAX_ESCALA, pressao_decaido + sum(origem_pressao.values())))
        calor_valor = max(0.0, min(VALOR_MAX_ESCALA, calor_decaido + sum(origem_calor.values())))

        entidade = {
            "pressao": {"valor": round(pressao_valor, 2), "origem": origem_pressao},
            "calor": {"valor": round(calor_valor, 2), "origem": origem_calor},
        }

        if agent_id == "alia":
            confianca_anterior = anterior.get("confianca_acumulada", {})
            confianca_valor = int(confianca_anterior.get("valor", 0))
            recomputes_sem_falha = int(confianca_anterior.get("origem", {}).get("recomputes_sem_falha", 0))
            teve_falha = bool(origem_pressao.get("gate_fail") or origem_pressao.get("gate_concern"))
            # confianca_acumulada NUNCA decai sozinha (spec, secao A) - so cresce em ciclo limpo
            # (sem FAIL/CONCERN novo) e so reset explicito do CEO (fora deste modulo).
            if not teve_falha:
                confianca_valor += 1
                recomputes_sem_falha += 1
            entidade["confianca_acumulada"] = {
                "valor": confianca_valor,
                "origem": {"recomputes_sem_falha": recomputes_sem_falha},
            }
            entidade["historia"] = list(anterior.get("historia", []))[:MAX_HISTORIA_ITENS]

        entidades_novas[agent_id] = entidade

    return entidades_novas, task_agent


def recompute(ledger_path: str, pulso_path: str, agora: float | None = None) -> dict:
    """So I/O: le pulso.json + a FATIA nova do ledger (por offset, nunca o arquivo inteiro),
    chama compute_from_events (funcao pura) e regrava pulso.json. Chamado do Stop em
    hooks/dispatch.py a cada sessao; nunca bloqueia (quem chama envolve em try/except - um PULSO
    quebrado nunca prende o operador).

    Primeira chamada (pulso.json ainda nao existe): NUNCA le o ledger inteiro so pra descartar -
    so marca o offset atual (os.path.getsize, O(1)) como ponto de partida e comeca do zero.
    Decisao documentada (topo do arquivo): o PULSO reage so DAQUI PRA FRENTE, nunca reconstroi
    retroativamente um ledger que ja existia antes dele - o mesmo motivo evita o gargalo de ler
    um ledger de 50 mil+ linhas na primeira sessao depois de ligar o PULSO."""
    agora = agora if agora is not None else time.time()
    estado_anterior = load_state(pulso_path)
    ja_existia = bool(estado_anterior.get("atualizado_em"))

    if not ja_existia:
        offset_inicial = os.path.getsize(ledger_path) if os.path.exists(ledger_path) else 0
        novo_estado = {"versao": VERSAO, "atualizado_em": _iso(agora), "entidades": {},
                        "_ledger_offset": offset_inicial, "_task_agent_map": {}}
        save_state(pulso_path, novo_estado)
        return novo_estado

    ts_anterior = _parse_iso(estado_anterior.get("atualizado_em"))
    offset_anterior = int(estado_anterior.get("_ledger_offset", 0) or 0)
    task_agent_anterior = estado_anterior.get("_task_agent_map", {})
    eventos_novos, novo_offset = ledger.read_events_from(ledger_path, offset_anterior)
    horas_passadas = max(0.0, (agora - ts_anterior) / 3600.0) if ts_anterior else 0.0
    entidades, task_agent_novo = compute_from_events(
        eventos_novos, estado_anterior.get("entidades", {}), task_agent_anterior, horas_passadas)
    novo_estado = {"versao": VERSAO, "atualizado_em": _iso(agora), "entidades": entidades,
                    "_ledger_offset": novo_offset, "_task_agent_map": task_agent_novo}
    save_state(pulso_path, novo_estado)
    return novo_estado


def squad_pressure(state: dict, agent_ids_do_squad: list[str]) -> float:
    """Maximo de pressao entre os `agent_ids_do_squad` informados (decisao documentada no topo
    do arquivo: MAXIMO, nao media - um squad com 1 Specialist sob pressao alta conta como squad
    sob pressao alta, nunca diluido pela media dos outros). Quem chama precisa SABER a lista de
    agent_ids do squad (fora do escopo deste modulo hoje - nao ha registro agent_id->Client
    deterministico no ledger)."""
    entidades = state.get("entidades", {})
    valores = [float(entidades.get(aid, {}).get("pressao", {}).get("valor", 0.0)) for aid in agent_ids_do_squad]
    return max(valores) if valores else 0.0


# ---------------------------------------------------------------------------
# from_facts - monta state sem ledger, para cenario de teste (GAUGE)
# ---------------------------------------------------------------------------

def from_facts(fatos: dict) -> dict:
    entidades = {}
    for agent_id, campos in fatos.items():
        entidade: dict = {}
        for dimensao in ("pressao", "calor"):
            if dimensao in campos:
                entidade[dimensao] = {"valor": float(campos[dimensao]), "origem": {}}
        if agent_id == "alia":
            if "confianca_acumulada" in campos:
                entidade["confianca_acumulada"] = {"valor": campos["confianca_acumulada"], "origem": {}}
            entidade["historia"] = list(campos.get("historia", []))[:MAX_HISTORIA_ITENS]
        entidades[agent_id] = entidade
    return {"versao": VERSAO, "atualizado_em": _iso(time.time()), "entidades": entidades}


# ---------------------------------------------------------------------------
# render - template FIXO, nunca prosa livre
# ---------------------------------------------------------------------------

def _efeito_pressao(pressao: float, curto: bool) -> str:
    if pressao >= LIMIAR_PRESSAO_ALTA:
        if curto:
            return " Pressao alta: mais uma conferencia com ponteiro antes de dizer pronto, uma frente so."
        return (" Pressao alta: mais uma conferencia com ponteiro verificavel antes de dizer "
                "pronto; nunca reduzir a bateria de prova; uma frente por vez, nunca atalho.")
    return ""


def _efeito_calor(calor: float, curto: bool) -> str:
    if calor >= LIMIAR_CALOR_ALTO:
        if curto:
            return " Calor alto: trava anti-bajulacao ativa."
        return (" Calor alto: trava anti-bajulacao ativa - crenca do operador dita com emocao "
                "positiva forte nunca e so confirmada, sempre conferida contra a fonte.")
    return ""


def render(agent_id: str, state: dict) -> str:
    entidades = (state or {}).get("entidades", {})
    entidade = entidades.get(agent_id)
    if not entidade:
        return ""

    pressao = float(entidade.get("pressao", {}).get("valor", 0.0))
    calor = float(entidade.get("calor", {}).get("valor", 0.0))

    if agent_id == "alia":
        confianca = entidade.get("confianca_acumulada", {}).get("valor", 0)
        partes = [f"PULSO: pressao {pressao:.1f} de 10, calor {calor:.1f} de 10, confianca {confianca}."]
        efeito = _efeito_pressao(pressao, curto=False) + _efeito_calor(calor, curto=False)
        if efeito:
            partes.append(efeito.strip())
        else:
            partes.append("Estado dentro da faixa normal, sem regra extra.")
        historia = entidade.get("historia", [])[:2]
        for item in historia:
            frase = str(item.get("frase", ""))[:MAX_HISTORIA_FRASE]
            nota = str(item.get("nota", ""))
            if frase and nota:
                partes.append(f'Aprendi que {frase} ({nota}).')
        texto = " ".join(partes)
        teto = TETO_ALIA
    else:
        partes = [f"PULSO ({agent_id}): pressao {pressao:.1f}, calor {calor:.1f}."]
        efeito = _efeito_pressao(pressao, curto=True) + _efeito_calor(calor, curto=True)
        partes.append(efeito.strip() if efeito else "Dentro da faixa normal.")
        texto = " ".join(partes)
        teto = TETO_SUBAGENTE

    if len(texto) > teto:
        raise ValueError(f"pulso.render: bloco de '{agent_id}' passou do teto ({len(texto)} > {teto})")
    return texto
