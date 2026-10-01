"""espinha.py - o NUCLEO da espinha Cliente > Projeto > Tarefa.

Independente de host. Quem fala com ele e a CLI `alia` (bin/alia.py); os adaptadores (Claude Code,
OpenCode, Codex, Pi) so traduzem evento em chamada `alia`, sem regra propria. Toda recusa levanta
`Recusa` com um codigo `regra` estavel (a lista esta em state.schema.json, x-recusas) e vira exit 1 + JSON.

O que mora aqui: cadastro de projeto, dispatch (gateway_ack, coordenacao), pendencias, abertura de
sessao, validador do schema. As transicoes e o fechamento de Task seguem em task_model.py (nucleo
da entidade); o veredito segue em bin/gate.py (parecer validado).

So biblioteca padrao.
"""
from __future__ import annotations

import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
SCHEMA_PATH = os.path.join(V2, "state.schema.json")
ID_CANONICO = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
GENERICOS = ("alia",)  # specialist que nao e do squad de ninguem; so com coordenacao:true


class Recusa(Exception):
    def __init__(self, regra: str, msg: str, **extra):
        super().__init__(msg)
        self.regra, self.msg, self.extra = regra, msg, extra

    def como_json(self) -> dict:
        return {"ok": False, "regra": self.regra, "error": self.msg, **self.extra}


def agora() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


# --- dado ------------------------------------------------------------------

def carregar(state_path: str) -> dict:
    if not os.path.isfile(state_path):
        raise Recusa("state_ausente", "state.json nao encontrado", state=state_path)
    with open(state_path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def gravar(state_path: str, state: dict) -> None:
    """Escrita atomica: arquivo temporario ao lado + os.replace (queda no meio nunca deixa meio JSON)."""
    tmp = state_path + ".alia-tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(state, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(tmp, state_path)


# --- schema (subconjunto) --------------------------------------------------

def schema() -> dict:
    with open(SCHEMA_PATH, "r", encoding="utf-8") as fh:
        return json.load(fh)


def _tipo_ok(v, t: str) -> bool:
    return {"object": isinstance(v, dict), "array": isinstance(v, list), "string": isinstance(v, str),
            "boolean": isinstance(v, bool), "integer": isinstance(v, int) and not isinstance(v, bool),
            "number": isinstance(v, (int, float)) and not isinstance(v, bool)}.get(t, True)


def validar(valor, sch: dict, raiz: dict, onde: str = "$") -> list[str]:
    """Erros de `valor` contra `sch` (subconjunto: $ref, allOf, enum, type, pattern, required,
    properties, items, uniqueItems). Lista vazia = valido."""
    erros: list[str] = []
    if "$ref" in sch:
        alvo = raiz
        for parte in sch["$ref"].lstrip("#/").split("/"):
            alvo = alvo[parte]
        erros += validar(valor, alvo, raiz, onde)
    for sub in sch.get("allOf", []):
        erros += validar(valor, sub, raiz, onde)
    if "enum" in sch and valor not in sch["enum"]:
        erros.append(f"{onde}: {valor!r} fora de {sch['enum']}")
    if "type" in sch and not _tipo_ok(valor, sch["type"]):
        return erros + [f"{onde}: esperado {sch['type']}"]
    if isinstance(valor, str) and "pattern" in sch and not re.search(sch["pattern"], valor):
        erros.append(f"{onde}: {valor!r} nao casa {sch['pattern']}")
    if isinstance(valor, dict):
        for k in sch.get("required", []):
            if k not in valor or valor[k] in (None, ""):
                erros.append(f"{onde}.{k}: obrigatorio")
        for k, sub in (sch.get("properties") or {}).items():
            if k in valor and valor[k] is not None:
                erros += validar(valor[k], sub, raiz, f"{onde}.{k}")
    if isinstance(valor, list):
        for i, item in enumerate(valor):
            if "items" in sch:
                erros += validar(item, sch["items"], raiz, f"{onde}[{i}]")
        if sch.get("uniqueItems") and len({json.dumps(x, sort_keys=True) for x in valor}) != len(valor):
            erros.append(f"{onde}: itens repetidos")
    return erros


def validar_task_nova(task: dict, so_status: bool = False) -> list[str]:
    """Task escrita agora: `task_nova` inteira, ou so a regra do status (done exige artifact + veredito
    PASS) quando `so_status` - o fechamento de Task legada nao herda o formato do projeto antigo."""
    raiz = schema()
    alvo = raiz["$defs"]["task_nova"]
    erros = [] if so_status else validar(task, alvo, raiz, "task")
    extra = (alvo.get("x-por-status") or {}).get(task.get("status"))
    if extra:
        erros += validar(task, extra, raiz, "task")
    return erros


# --- squad -----------------------------------------------------------------

def _cliente(state: dict, cid: str) -> dict:
    for c in state.get("clients", []):
        if c.get("id") == cid:
            return c
    raise Recusa("client_invalido", "client nao existe", client=cid,
                 clients_validos=sorted(c["id"] for c in state.get("clients", []) if c.get("id")))


def squad_ids(cliente: dict) -> tuple[str, list[str]]:
    """(id do Gateway, ids dos Specialists), no formato do agente gerado `{client}-{papel}`."""
    sq = cliente.get("squad") or {}
    cid = cliente["id"]
    gw = f"{cid}-{sq['gateway']}" if sq.get("gateway") else ""
    return gw, [f"{cid}-{s}" for s in sq.get("specialists") or []]


def _dono_do_specialist(state: dict, specialist: str) -> str | None:
    for c in state.get("clients", []):
        gw, specs = squad_ids(c)
        if specialist == gw or specialist in specs:
            return c["id"]
    return None


# --- comandos --------------------------------------------------------------

def project_add(state_path: str, client: str, pid: str | None = None, das_tasks: bool = False) -> dict:
    """Unico jeito de criar projeto. `das_tasks` semeia o cadastro com os ids que as Tasks do Client
    ja usam, quando ja canonicos (migracao das tasks antigas: projetos-mapa.md virou o campo project)."""
    state = carregar(state_path)
    cliente = _cliente(state, client)
    projetos = cliente.setdefault("projects", [])
    if das_tasks:
        novos = sorted({t["project"] for t in state.get("tasks", [])
                        if t.get("client") == client and ID_CANONICO.match(str(t.get("project") or ""))})
    else:
        if not pid or not ID_CANONICO.match(pid):
            raise Recusa("projeto_id_invalido", "id de projeto: minusculas ASCII com hifen (ex.: camada-alia)",
                         projeto_recebido=pid)
        if pid in projetos:
            raise Recusa("projeto_ja_cadastrado", "projeto ja cadastrado neste Client", client=client, projeto=pid)
        novos = [pid]
    adicionados = [p for p in novos if p not in projetos]
    projetos.extend(adicionados)
    erros = validar(cliente, schema()["$defs"]["client"], schema(), "client")
    if erros:
        raise Recusa("schema_invalido", "client fora do schema", erros=erros)
    gravar(state_path, state)
    return {"ok": True, "client": client, "adicionados": adicionados, "projects": projetos}


def task_dispatch(state_path: str, ledger_mod, ledger_path: str, task_id: str, specialist: str,
                  session: str = "") -> dict:
    """Aciona um agente na Task. Dispatch do Gateway do squad GRAVA o gateway_ack; o de Specialist
    exige o ack antes. `alia` so com coordenacao:true. Agente que nao e de squad nenhum (Explore,
    general-purpose...) nao e assunto da espinha: passa sem registrar."""
    state = carregar(state_path)
    task = next((t for t in state.get("tasks", []) if t.get("id") == task_id), None)
    if task is None:
        raise Recusa("task_inexistente", "Task nao encontrada", id_recebido=task_id)
    if task.get("status") not in ("open", "review"):
        raise Recusa("task_fechada", "Task fora de open/review nao recebe dispatch", id=task_id, status=task.get("status"))
    cliente = _cliente(state, task["client"])
    gateway, specialists = squad_ids(cliente)
    dono = _dono_do_specialist(state, specialist)
    if specialist in GENERICOS:
        if task.get("coordenacao") is not True:
            raise Recusa("alia_sem_coordenacao", "specialist alia so em Task com coordenacao:true "
                         "(a Alia delega, nao executa dominio)", id=task_id)
    elif dono is None:
        return {"ok": True, "registrado": False, "motivo": "agente fora de qualquer squad"}
    elif dono != task["client"]:
        raise Recusa("specialist_de_outro_client", "Specialist e do squad de outro Client", id=task_id,
                     specialist=specialist, client_da_task=task["client"], client_do_specialist=dono)
    elif specialist == gateway:
        task["gateway_ack"] = {"by": specialist, "at": agora(), "session": session}
    elif not task.get("gateway_ack"):
        raise Recusa("dispatch_sem_gateway_ack", "Specialist antes do Gateway: aciono o Gateway do squad "
                     "primeiro (ele grava o gateway_ack da Task)", id=task_id, gateway=gateway, specialist=specialist)
    task.setdefault("dispatches", []).append({"specialist": specialist, "at": agora(), "session": session})
    raiz = schema()
    erros = validar(task, raiz["$defs"]["task"], raiz, "task")
    if erros:
        raise Recusa("schema_invalido", "task fora do schema", erros=erros)
    gravar(state_path, state)
    ledger_mod.append_event(ledger_path, {"event": "alia_dispatch", "session_id": session or None,
                                          "task_id": task_id, "specialist": specialist})
    return {"ok": True, "registrado": True, "task": task_id, "specialist": specialist,
            "gateway_ack": bool(task.get("gateway_ack"))}


def divida(state: dict) -> dict:
    """Divida visivel (nunca recusa): Tasks fechadas sem veredito e Tasks com projeto fora do cadastro."""
    import task_model
    cad = {c["id"]: set(c.get("projects") or []) for c in state.get("clients", []) if c.get("id")}
    tasks = state.get("tasks", [])
    sem_gate = [t["id"] for t in tasks if t.get("status") in ("done", "review") and not str(t.get("gate_verdict") or "").strip()]
    nao_normalizado = sum(1 for t in tasks if str(t.get("gate_verdict") or "").strip() and not task_model.gate_verdict_normalizado(t))
    fora = [t["id"] for t in tasks if t.get("status") in ("open", "review") and t.get("project") not in cad.get(t.get("client"), set())]
    return {"closed_without_gate": len(sem_gate), "closed_without_gate_ids": sem_gate[:20],
            "veredito_legado_nao_normalizado": nao_normalizado,
            "abertas_com_projeto_fora_do_cadastro": len(fora)}


def task_pending(state_path: str, ledger_mod, ledger_path: str, session: str = "", task_id: str = "",
                 com_divida: bool = True) -> dict:
    """Tasks que pedem veredito: a Task dada, ou as tocadas pela sessao (ledger) / abertas por ela
    (Task corrente). `closed_without_gate` e a divida historica, so contada."""
    state = carregar(state_path)
    por_id = {t.get("id"): t for t in state.get("tasks", []) if t.get("id")}
    alvo: set[str] = set()
    if task_id:
        alvo.add(task_id)
    if session:
        alvo.update(ev["task_id"] for ev in ledger_mod.read_events(ledger_path)
                    if ev.get("session_id") == session and ev.get("task_id"))
    pendentes = [i for i in sorted(alvo) if i in por_id and not por_id[i].get("gate_verdict")
                 and por_id[i].get("status") in ("open", "review")]
    return {"ok": True, "pendentes": pendentes, **({"divida": divida(state)} if com_divida else {})}


def open_session(state_path: str, ledger_mod, ledger_path: str, session: str, client: str = "") -> dict:
    """Le o estado e grava session_opened: a prova de que a sessao abriu a espinha (34,5% nao liam)."""
    state = carregar(state_path)
    ledger_mod.append_event(ledger_path, {"event": "session_opened", "session_id": session or None,
                                          "client": client or None})
    clientes = [{"id": c["id"], "status": c.get("status"), "gateway": squad_ids(c)[0], "projects": c.get("projects") or []}
                for c in state.get("clients", []) if c.get("id") and (not client or c["id"] == client)]
    abertas = [{"id": t["id"], "client": t.get("client"), "project": t.get("project"), "title": str(t.get("title") or "")[:60],
                "status": t.get("status")}
               for t in state.get("tasks", []) if t.get("status") in ("open", "review")
               and (not client or t.get("client") == client)]
    return {"ok": True, "session_opened": True, "session": session or None, "clients": clientes,
            "tasks_abertas": abertas[-40:], "total_abertas": len(abertas), "divida": divida(state)}
