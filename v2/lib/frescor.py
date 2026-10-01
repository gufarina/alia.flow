#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""frescor.py - conferencia de FRESCOR do conhecimento de cada Client (TASK-856).

Motivo medido: a 2.0 nao roda nada que diga se o mapa/indice de um Client ficou velho. O sensor
1.x (graph-usage-sensor.ps1) morreu (LAW-MAP L27); L26/L67 apontavam para "memoria | graph-check",
codigo que a 2.0 nunca chamava. Um Client real ficou 45 dias com mapa velho sem nenhum aviso.

So biblioteca padrao, UTF-8 explicito. Funcao pura: recebe a raiz do estudio + o id do Client e
devolve um dict; nunca imprime, nunca decide o que fazer com o resultado (isso e do CLI/hook).
"""
from __future__ import annotations

import hashlib
import json
import os
import re
from datetime import datetime, timezone

CURADOS_EXT = (".md", ".yaml", ".yml", ".json")
DIAS_VELHO = 21
MUDARAM_VELHO = 10  # mudaram > 10 vira VELHO sozinho, sem depender da idade
STATUS_FORA = ("arquivado", "pontual")
INDICE_GERADO = ("MAP.md", "edges.json")
PRAZO_MAX_DIAS = 14  # divida com prazo maior que isto nao cala: prazo longo e o mesmo que sem prazo
MAX_LINHAS_DIVIDA = 2  # 1 registro + 1 renovacao. A 3a linha do mesmo Client nao cala (renovar sem fim = aviso nunca volta)


def _mtime(path: str) -> float | None:
    try:
        return os.path.getmtime(path)
    except OSError:
        return None


def _iter_curados(knowledge_dir: str):
    """Todo .md/.yaml/.yml/.json sob knowledge_dir, fora graphify-out/cache/loop-reports."""
    for root, dirs, files in os.walk(knowledge_dir):
        dirs[:] = [d for d in dirs if d not in ("graphify-out", "cache", "loop-reports")]
        for fn in files:
            # MAP.md e edges.json sao gerados pelo indice, nao curados: refazer o indice nao envelhece o mapa
            if fn.endswith(CURADOS_EXT) and fn not in INDICE_GERADO:
                yield os.path.join(root, fn)


def _checar_mapa(client_dir: str, knowledge_dir: str, client_md: str) -> dict:
    candidatos = [
        os.path.join(knowledge_dir, "graphify-out", "graph.json"),
        os.path.join(client_dir, "graphify-out", "graph.json"),
    ]
    mapa_path = next((c for c in candidatos if os.path.isfile(c)), None)
    if mapa_path is None:
        return {"veredito": "AUSENTE", "path": None, "mtime": None, "data": None, "dias": None, "mudaram": 0}
    mtime_mapa = _mtime(mapa_path) or 0.0
    agora = datetime.now(timezone.utc).timestamp()
    dias_float = (agora - mtime_mapa) / 86400.0
    dias = int(dias_float)  # arredondado para baixo (piso), nunca para cima
    data_mapa = datetime.fromtimestamp(mtime_mapa).strftime("%Y-%m-%d")
    fontes = list(_iter_curados(knowledge_dir)) if os.path.isdir(knowledge_dir) else []
    if os.path.isfile(client_md):
        fontes.append(client_md)
    mudaram = sum(1 for f in fontes if (_mtime(f) or 0) > mtime_mapa)
    veredito = "OK"
    if mudaram > MUDARAM_VELHO:
        veredito = "VELHO"
    elif dias_float > DIAS_VELHO and mudaram >= 1:
        veredito = "VELHO"
    return {"veredito": veredito, "path": mapa_path, "mtime": mtime_mapa, "data": data_mapa,
            "dias": dias, "mudaram": mudaram}


def _checar_indice(knowledge_dir: str) -> dict:
    indice_path = os.path.join(knowledge_dir, "edges.json")
    if not os.path.isfile(indice_path):
        return {"veredito": "AUSENTE", "path": None}
    mtime_indice = _mtime(indice_path) or 0.0
    mais_novo = False
    if os.path.isdir(knowledge_dir):
        for fn in os.listdir(knowledge_dir):
            full = os.path.join(knowledge_dir, fn)
            # MAP.md nasce na mesma chamada que o edges.json, milissegundos depois: nao conta
            if fn.endswith(".md") and fn not in INDICE_GERADO and os.path.isfile(full) and (_mtime(full) or 0) > mtime_indice:
                mais_novo = True
                break
    return {"veredito": "VELHO" if mais_novo else "OK", "path": indice_path}


def _checar_entregas(client_dir: str) -> dict:
    """Cada subpasta de artifacts/ conta 1, cada arquivo solto conta 1, fora nomes comecando
    com '.' ou '_'. Data do mais recente: para subpasta, o mtime mais novo de arquivo dentro
    dela (2 niveis no maximo)."""
    artifacts_dir = os.path.join(client_dir, "artifacts")
    if not os.path.isdir(artifacts_dir):
        return {"quantidade": 0, "mais_recente": None}
    quantidade = 0
    mais_recente = None
    for nome in os.listdir(artifacts_dir):
        if nome.startswith((".", "_")):
            continue
        full = os.path.join(artifacts_dir, nome)
        quantidade += 1
        if os.path.isfile(full):
            mt = _mtime(full)
        else:
            mt = None
            for root, dirs, files in os.walk(full):
                nivel = root[len(full):].count(os.sep)
                if nivel >= 2:
                    dirs[:] = []
                for fn in files:
                    m = _mtime(os.path.join(root, fn))
                    if m and (mt is None or m > mt):
                        mt = m
        if mt and (mais_recente is None or mt > mais_recente):
            mais_recente = mt
    return {"quantidade": quantidade, "mais_recente": mais_recente}


_VERSAO_CH_RE = re.compile(
    r"^##\s*\[(\d+\.\d+\.\d+)\]\s*-\s*(\d{4}-\d{2}-\d{2})"
    r"|^##\s*(\d+\.\d+\.\d+)\s*-\s*(\d{4}-\d{2}-\d{2})"
)
_CODEPATH_RE = re.compile(r"-\s*\*\*codePath:\*\*\s*(.+)")


def _checar_produto(client_md: str) -> dict | None:
    if not os.path.isfile(client_md):
        return None
    with open(client_md, "r", encoding="utf-8") as fh:
        texto = fh.read()
    m = _CODEPATH_RE.search(texto)
    if not m:
        return None
    # aceita codePath com crase (` `) e/ou barra final (/ ou \) - achado da coordenacao
    code_path = m.group(1).strip().strip("`").rstrip("/\\").strip()
    changelog = os.path.join(code_path, "CHANGELOG.md")
    if not os.path.isdir(code_path) or not os.path.isfile(changelog):
        return None
    # a MAIOR versao do arquivo, nao a primeira: CHANGELOG fora de ordem existe e ja enganou a medida
    achadas = []
    with open(changelog, "r", encoding="utf-8") as fh:
        for linha in fh:
            m2 = _VERSAO_CH_RE.match(linha.strip())
            if m2:
                achadas.append((m2.group(1) or m2.group(3), m2.group(2) or m2.group(4)))
    if not achadas:
        return None
    versao, data_versao = max(achadas, key=lambda vd: tuple(int(x) for x in vd[0].split(".")))
    # fronteira de numero: "1.0.1" nao pode ser achada dentro de "1.0.10"
    citada = re.search(r"(?<![0-9.])" + re.escape(versao) + r"(?![0-9])", texto)
    ficha = "OK" if citada else "ATRASADA"
    return {"ficha": ficha, "versao": versao, "data": data_versao}


def _checar_divida(studio_root: str, client_id: str) -> dict:
    """valida: data (str) so quando >= hoje. vencida: data (str) quando a linha existe mas
    esta no passado. Linha sem data reconhecivel nunca cala nada (nem entra em nenhum dos 2)."""
    resultado: dict = {"valida": None, "vencida": None, "esgotada": False}
    path = os.path.join(studio_root, "studio", "conhecimento-dividas.txt")
    if not os.path.isfile(path):
        return resultado
    hoje = datetime.now(timezone.utc).date()
    linhas_do_client = 0  # linhas com data do Client, vencidas ou nao: a historia conta, renovar = nova linha
    with open(path, "r", encoding="utf-8") as fh:
        for linha in fh:
            linha = linha.strip()
            if not linha or linha.startswith("#"):
                continue
            partes = linha.split(None, 2)
            if len(partes) < 2 or partes[0] != client_id:
                continue
            m = re.match(r"^(\d{4})-(\d{2})-(\d{2})$", partes[1])
            if not m:
                continue
            data_divida = datetime(int(m.group(1)), int(m.group(2)), int(m.group(3))).date()
            linhas_do_client += 1
            if linhas_do_client > MAX_LINHAS_DIVIDA:
                resultado["esgotada"] = True  # renovada mais de 1 vez: nunca mais cala
                resultado["valida"] = None
                continue
            if (data_divida - hoje).days > PRAZO_MAX_DIAS:
                continue  # prazo longo demais nao cala nada
            if data_divida >= hoje:
                resultado["valida"] = partes[1]
            else:
                resultado["vencida"] = partes[1]
    return resultado


def clientes_ativos(studio_root: str) -> list[str]:
    """Ids de state.json (clients[].id) cujo status nao e arquivado/pontual."""
    state_path = os.path.join(studio_root, "state.json")
    if not os.path.isfile(state_path):
        return []
    try:
        with open(state_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError):
        return []
    out = []
    for c in data.get("clients", []):
        if not isinstance(c, dict):
            continue
        status = str(c.get("status") or "").lower()
        if status in STATUS_FORA:
            continue
        cid = c.get("id")
        if cid:
            out.append(cid)
    return out


def recibo_de_fechamento(studio_root: str, client_id: str) -> dict:
    """Recibo de conhecimento para fechar uma entrega do Client (pedido do CEO, 28/09): sem ele,
    o conhecimento envelhece em silencio enquanto as Tasks fecham. Devolve {"ok": bool, "recibo"
    ou "falta"}. Client sem pasta no estudio nao tem o que conferir (ok, sem recibo)."""
    client_dir = os.path.join(studio_root, "clients", client_id)
    if not os.path.isdir(client_dir):
        return {"ok": True, "recibo": None}
    r = avaliar_client(studio_root, client_id)
    falta = []
    if r["veredito"] == "VELHO":
        falta.append(linha_humana(r))
    if os.path.isdir(os.path.join(client_dir, "squad", "knowledge")) and r["indice"]["veredito"] == "AUSENTE":
        falta.append(client_id + ": indice do segundo cerebro ausente")
    if falta:
        return {"ok": False, "falta": falta}
    produto = r["produto"] or {}
    return {"ok": True, "recibo": {
        "veredito": r["veredito"], "mapa": r["mapa"].get("data") or r["mapa"]["veredito"],
        "indice": r["indice"]["veredito"], "produto": produto.get("versao"), "ficha": produto.get("ficha"),
    }}


def avaliar_client(studio_root: str, client_id: str) -> dict:
    """Funcao pura principal: devolve mapa/indice/entregas/produto/divida_vencida/veredito
    para 1 Client. Nunca lanca excecao por dado ausente - tudo em disco e opcional."""
    client_dir = os.path.join(studio_root, "clients", client_id)
    knowledge_dir = os.path.join(client_dir, "squad", "knowledge")
    client_md = os.path.join(client_dir, "client.md")

    mapa = _checar_mapa(client_dir, knowledge_dir, client_md)
    indice = _checar_indice(knowledge_dir)
    entregas = _checar_entregas(client_dir)
    produto = _checar_produto(client_md)
    divida = _checar_divida(studio_root, client_id)

    bruto_velho = (
        mapa["veredito"] == "VELHO"
        or indice["veredito"] == "VELHO"
        or (produto is not None and produto.get("ficha") == "ATRASADA")
    )
    if bruto_velho and divida["valida"] and not divida["esgotada"]:
        veredito = f"CALADO_ATE {divida['valida']}"
    elif bruto_velho:
        veredito = "VELHO"
    else:
        veredito = "OK"

    return {
        "client": client_id,
        "mapa": mapa,
        "indice": indice,
        "entregas": entregas,
        "produto": produto,
        "divida_vencida": divida["vencida"],
        "divida_esgotada": divida["esgotada"],
        "veredito": veredito,
    }


def _data_br(data_iso: str | None) -> str:
    """AAAA-MM-DD -> DD/MM (formato humano da casa). Sem data reconhecivel, devolve '?'."""
    if not data_iso:
        return "?"
    partes = data_iso.split("-")
    if len(partes) != 3:
        return data_iso
    return f"{partes[2]}/{partes[1]}"


def linha_humana(resultado: dict) -> str:
    """1 linha em portugues de gente para `resultado` (saida de avaliar_client). Reusada pelo
    CLI (bin/frescor.py), pelo hook (SessionStart) e pelo brief (bin/brief.py)."""
    partes: list[str] = []
    mapa = resultado["mapa"]
    if mapa["veredito"] == "AUSENTE":
        partes.append("mapa ausente")
    elif mapa["veredito"] == "VELHO":
        partes.append(
            f"mapa de {_data_br(mapa['data'])} ({mapa['dias']} dias, {mapa['mudaram']} "
            "arquivos mudaram depois)"
        )
    indice = resultado["indice"]
    if indice["veredito"] == "AUSENTE":
        partes.append("indice ausente")
    elif indice["veredito"] == "VELHO":
        partes.append("indice desatualizado")
    produto = resultado["produto"]
    if produto and produto.get("ficha") == "ATRASADA":
        partes.append(
            f"ficha atras, produto na {produto['versao']} ({_data_br(produto.get('data'))})"
        )
    entregas = resultado["entregas"]
    if resultado.get("divida_esgotada"):
        partes.append("divida ja renovada 1 vez, nao cala mais: refazer o mapa")
    partes.append(f"{entregas['quantidade']} entregas")
    corpo = "; ".join(partes)
    return f"{resultado['client']}: {resultado['veredito']} - {corpo}"


_SOURCE_HASH_RE = re.compile(r"<!--\s*source_hash:\s*([0-9a-f]{16})\s*-->")


def _hash_fonte(studio_root: str, client: str, agente: str) -> str | None:
    """sha256(bytes de <id>.md + <id>.yaml + squad.yaml)[:16] da fonte do agente (macro: sem
    squad.yaml, em engine/macro/agents). Mesma regra da bridge (v2/squad/bridge.ps1). None se a
    fonte nao existe (agente orfao: nao e 'velho', e outro problema)."""
    if client == "macro":
        base, extra = os.path.join(studio_root, "engine", "macro", "agents"), []
    else:
        sq = os.path.join(studio_root, "clients", client, "squad")
        base, extra = os.path.join(sq, "agents"), [os.path.join(sq, "squad.yaml")]
    partes = [os.path.join(base, agente + ".md"), os.path.join(base, agente + ".yaml")] + extra
    if not all(os.path.isfile(p) for p in partes):
        return None
    h = hashlib.sha256()
    for p in partes:
        with open(p, "rb") as fh:
            h.update(fh.read())
    return h.hexdigest()[:16]


def agentes_velhos(studio_root: str, agents_dir: str | None = None) -> list[dict]:
    """[AGENTE VELHO]: bundle em .claude/agents cujo `source_hash` difere do hash atual da
    fonte (persona editada depois de gerar). Mesma regra de divida com prazo do mapa:
    `studio/conhecimento-dividas.txt` cala o Client, no maximo 1 renovacao. Devolve
    [{client, agente, arquivo, esperado, gravado}], so os NAO calados."""
    agents_dir = agents_dir or os.path.join(studio_root, ".claude", "agents")
    clients_dir = os.path.join(studio_root, "clients")
    ids = ["macro"] + (sorted(os.listdir(clients_dir)) if os.path.isdir(clients_dir) else [])
    ids = sorted(ids, key=len, reverse=True)
    if not os.path.isdir(agents_dir):
        return []
    velhos: list[dict] = []
    for nome in sorted(os.listdir(agents_dir)):
        if not nome.endswith(".md"):
            continue
        dono = next((c for c in ids if nome.lower().startswith(c.lower() + "-")), None)
        if dono is None:
            continue
        with open(os.path.join(agents_dir, nome), "r", encoding="utf-8", errors="replace") as fh:
            achados = _SOURCE_HASH_RE.findall(fh.read())
        if not achados:
            continue  # bundle sem hash: gerado antes do hash, nao ha o que comparar
        agente = nome[len(dono) + 1:-3]
        # a fonte guarda o id em minusculas ou no case da pasta: tenta os dois
        esperado = _hash_fonte(studio_root, dono, agente) or _hash_fonte(studio_root, dono, agente.lower())
        if esperado is None or esperado == achados[-1]:
            continue
        div = _checar_divida(studio_root, dono)
        if div["valida"] and not div["esgotada"]:
            continue
        velhos.append({"client": dono, "agente": agente, "arquivo": nome, "esperado": esperado, "gravado": achados[-1]})
    return velhos
