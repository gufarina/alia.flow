"""test_risk.py - modulo flow, I6 (TASK-801 E5; TASK-804 E7: passa a rodar pela entidade Task).

Roda os 12 casos de cases.json contra lib/task_model.classificar_risco() (a entidade que
absorveu flow/risk.py, TASK-804) e sai com codigo 1 se algum divergir. Roda tambem uma prova
negativa isolada (fora do arquivo de casos): brief vazio nunca vira R1 silencioso. So
biblioteca padrao (json, sys, os).
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

from task_model import classificar_risco as classificar


def carregar_casos():
    caminho = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'cases.json')
    with open(caminho, 'r', encoding='utf-8') as f:
        return json.load(f)


def comparar(atual, esperado):
    return (
        atual.get('risco') == esperado.get('risco')
        and sorted(atual.get('gatilhos') or []) == sorted(esperado.get('gatilhos') or [])
        and atual.get('modo') == esperado.get('modo')
        and sorted(atual.get('faltando') or []) == sorted(esperado.get('faltando') or [])
    )


def main():
    falhas = []

    casos = carregar_casos()
    if len(casos) != 12:
        falhas.append(f"cases.json tem {len(casos)} casos, esperado 12")

    for caso in casos:
        atual = classificar(caso['brief'])
        if not comparar(atual, caso['esperado']):
            falhas.append(
                f"{caso['id']}: esperado {caso['esperado']}, obtido {atual}"
            )

    # prova negativa isolada, fora do arquivo de casos: brief vazio NUNCA vira R1 silencioso
    atual_vazio = classificar({})
    if atual_vazio['risco'] == 'R1':
        falhas.append("brief vazio classificado como R1 - isto e o defeito que este teste existe para pegar")
    if not atual_vazio['faltando']:
        falhas.append("brief vazio nao listou nenhum campo faltando")
    if atual_vazio['risco'] is not None:
        falhas.append(f"brief vazio deveria devolver risco None, devolveu {atual_vazio['risco']!r}")

    if falhas:
        print(f"FALHOU: {len(falhas)} divergencia(s)")
        for f in falhas:
            print(f"  - {f}")
        sys.exit(1)

    print(f"OK: {len(casos)} casos + prova negativa isolada, tudo bateu")
    sys.exit(0)


if __name__ == '__main__':
    main()
