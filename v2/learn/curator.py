"""Curator - aplica itens do reflector a um playbook.md por Client (modulo 6, I8).

Regra dura (CONTRACTS.md modulo 6 + e4-arquitetura-v2.md secao 4): "curador acrescenta com id e
polaridade, atualiza contador ou aposenta com motivo, nunca reescreve tudo". Este arquivo cumpre
isso por BLOCO: cada item vive entre marcadores `<!-- item:ID -->` / `<!-- /item:ID -->`; toda
edicao troca SO o bloco daquele id, nunca reordena nem toca o resto do arquivo.

Fato nunca morre por apagamento (doutrina ARCHIVE) - "descartar" por teto de tokens vira
APOSENTAR: o bloco encolhe para 1 linha com o motivo, o id continua existindo no arquivo (nunca e
removido), so para de contar como item ativo.
"""
from __future__ import annotations

import re
import sys
import os

_ITEM_RE = re.compile(
    r"<!-- item:(?P<id>[^\n]+?) -->\n(?P<body>.*?)<!-- /item:(?P=id) -->\n?",
    re.S,
)
TETO_TOKENS_PADRAO = 2000


def _read(path: str) -> str:
    if not os.path.exists(path):
        return ""
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def _write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def _parse_items(text: str) -> dict:
    """id -> {"status": "ativo"|"aposentado", "contador": int, "block": str (texto inteiro do
    bloco, marcadores inclusos)}."""
    out = {}
    for m in _ITEM_RE.finditer(text):
        item_id = m.group("id")
        body = m.group("body")
        status = "aposentado" if "APOSENTADO" in body else "ativo"
        contador = 1
        cm = re.search(r"- contador:\s*(\d+)", body)
        if cm:
            contador = int(cm.group(1))
        out[item_id] = {"status": status, "contador": contador, "block": m.group(0)}
    return out


def _new_block(item: dict) -> str:
    return (
        f"<!-- item:{item['id']} -->\n"
        f"## {item['id']}\n"
        f"- polaridade: {item['polaridade']}\n"
        f"- pattern_key: {item.get('pattern_key', item['id'])}\n"
        f"- client: {item.get('client', 'desconhecido')}\n"
        f"- contador: 1\n"
        f"- status: ativo\n"
        f"- texto: {item['texto']}\n"
        f"<!-- /item:{item['id']} -->\n"
    )


def _bump_contador(block: str) -> str:
    return re.sub(r"(- contador:\s*)(\d+)", lambda m: m.group(1) + str(int(m.group(2)) + 1), block, count=1)


def _retire_block(item_id: str, contador: int, motivo: str) -> str:
    return (
        f"<!-- item:{item_id} -->\n"
        f"- {item_id}: APOSENTADO (motivo: {motivo}; contador final: {contador})\n"
        f"<!-- /item:{item_id} -->\n"
    )


def _header(client: str) -> str:
    return (
        f"# Playbook - {client}\n\n"
        "Gerado por v2/learn/curator.py a partir de v2/learn/reflector.py. Cada item = 1 causa "
        "estruturada. Nunca reescreve inteiro: acrescenta bloco por bloco, aposenta em vez de "
        "apagar.\n\n"
    )


def apply_items(playbook_path: str, items: list[dict], teto_tokens: int = TETO_TOKENS_PADRAO) -> dict:
    """Aplica os itens (de reflector.collect) ao playbook do Client. Idempotente: rodar com os
    mesmos itens 2 vezes so incrementa o contador, nunca duplica bloco.

    Devolve {"acrescentados": [...ids novos...], "incrementados": [...ids ja existentes...],
    "aposentados": [...ids aposentados por teto...]}.

    Sem sinal (items vazio): nao toca o arquivo, nem para cria-lo. "Sem sinal, nada muda"
    (prova negativa do modulo 6).
    """
    if not items:
        return {"acrescentados": [], "incrementados": [], "aposentados": []}

    text = _read(playbook_path)
    if not text:
        text = _header(items[0]["client"])

    acrescentados, incrementados = [], []
    for item in items:
        existentes = _parse_items(text)
        atual = existentes.get(item["id"])
        if atual is None:
            text += _new_block(item)
            acrescentados.append(item["id"])
        elif atual["status"] == "ativo":
            text = text.replace(atual["block"], _bump_contador(atual["block"]), 1)
            incrementados.append(item["id"])
        # aposentado: nunca revive sozinho (doutrina - estado nao volta atras por acao automatica)

    _write(playbook_path, text)

    aposentados = _enforce_cap(playbook_path, teto_tokens)
    return {"acrescentados": acrescentados, "incrementados": incrementados, "aposentados": aposentados}


def _enforce_cap(playbook_path: str, teto_tokens: int) -> list[str]:
    """Enquanto o arquivo passar do teto (bytes/4 tokens), aposenta o item ATIVO de pior saldo
    (menor contador; empate resolvido pelo id em ordem alfabetica, para ser deterministico)."""
    aposentados = []
    while True:
        text = _read(playbook_path)
        tokens = len(text.encode("utf-8")) / 4
        if tokens <= teto_tokens:
            break
        itens = _parse_items(text)
        ativos = {k: v for k, v in itens.items() if v["status"] == "ativo"}
        if not ativos:
            break
        pior_id = min(ativos, key=lambda k: (ativos[k]["contador"], k))
        motivo = f"teto de {teto_tokens} tokens excedido, saldo mais fraco (contador {ativos[pior_id]['contador']})"
        novo_bloco = _retire_block(pior_id, ativos[pior_id]["contador"], motivo)
        text = text.replace(ativos[pior_id]["block"], novo_bloco, 1)
        _write(playbook_path, text)
        aposentados.append(pior_id)
    return aposentados


def retire(playbook_path: str, item_id: str, motivo: str) -> bool:
    """Aposenta um item explicitamente (fora do fluxo de teto), com motivo. True se existia."""
    text = _read(playbook_path)
    itens = _parse_items(text)
    atual = itens.get(item_id)
    if atual is None or atual["status"] == "aposentado":
        return False
    novo_bloco = _retire_block(item_id, atual["contador"], motivo)
    text = text.replace(atual["block"], novo_bloco, 1)
    _write(playbook_path, text)
    return True


if __name__ == "__main__":
    print("uso programatico: from curator import apply_items, retire", file=sys.stderr)
