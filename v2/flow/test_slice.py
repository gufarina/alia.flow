"""test_slice.py - modulo flow, TASK-812 (Shopify 02).

Roda os 12 casos de cases.json contra slice.is_tarefa_grande()/fatiar(): os 2 com 2+ frentes
(TASK-577, TASK-603) tem que sair "grande" com 1 fatia por frente; os outros 10 tem que sair
"pequeno" (1 fatia so, o brief inteiro - inclusive INV-06, que nao tem frentes/modulos_tocados
declarados e brief incompleto: slice.py nao valida campo obrigatorio, so risk.py faz isso).
Mais 3 provas isoladas, fora do arquivo de casos:
negativo do separador solto (TASK-717 tem " e " no exemplo_falha e NAO pode virar 2 oracoes),
positivo do separador ";" (brief sintetico) e a regra 3 (pode_comecar_fatia). So biblioteca
padrao (json, sys, os).
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from slice import is_tarefa_grande, fatiar, pode_comecar_fatia

GRANDES_ESPERADOS = {'TASK-577': 2, 'TASK-603': 7}


def carregar_casos():
    caminho = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'cases.json')
    with open(caminho, 'r', encoding='utf-8') as f:
        return json.load(f)


def main():
    falhas = []
    casos = carregar_casos()
    if len(casos) != 12:
        falhas.append(f"cases.json tem {len(casos)} casos, esperado 12")

    for caso in casos:
        cid = caso['id']
        brief = caso['brief']
        avaliacao = is_tarefa_grande(brief)
        fatias = fatiar(brief)

        if cid in GRANDES_ESPERADOS:
            n = GRANDES_ESPERADOS[cid]
            if not avaliacao['grande']:
                falhas.append(f"{cid}: esperado grande=True, veio False (motivos vazio)")
            if len(fatias) != n:
                falhas.append(f"{cid}: esperado {n} fatia(s), veio {len(fatias)}")
            if fatias and fatias[0]['depende_da_anterior'] is not False:
                falhas.append(f"{cid}: fatia-1 nao pode depender da anterior (nao existe)")
            if len(fatias) > 1 and any(not f['depende_da_anterior'] for f in fatias[1:]):
                falhas.append(f"{cid}: toda fatia depois da primeira tem que depender da anterior")
        else:
            if avaliacao['grande']:
                falhas.append(f"{cid}: esperado grande=False (pequeno), veio True, motivos={avaliacao['motivos']}")
            if len(fatias) != 1:
                falhas.append(f"{cid}: Task pequena tem que devolver 1 fatia so, veio {len(fatias)}")

    # prova negativa isolada: "e" solto dentro de uma oracao (TASK-717, exemplo_falha real) NUNCA
    # vira 2 fatias - e o defeito que a regra ";" existe para evitar
    caso_717 = next(c for c in casos if c['id'] == 'TASK-717')
    av_717 = is_tarefa_grande(caso_717['brief'])
    if 'criterio_composto' in av_717['motivos']:
        falhas.append("TASK-717: 'e' solto no exemplo_falha nao pode virar criterio_composto")

    # prova positiva isolada: ";" de verdade no exemplo_falha DEVE fatiar por oracao
    brief_composto = {
        'client': 'alia-flow-lab', 'project': 'engine',
        'objetivo': 'ajustar o modulo de log',
        'paths': 'v2/flow', 'consumidor': 'Warden', 'destino': 'interno',
        'exemplo_falha': 'linha sem timestamp; nivel de log errado; arquivo nao gira',
        'modulos_tocados': ['flow'], 'frentes': ['flow'],
    }
    fatias_comp = fatiar(brief_composto)
    if len(fatias_comp) != 3:
        falhas.append(f"brief_composto: esperado 3 fatias (';' x2), veio {len(fatias_comp)}")

    # regra 3: pode_comecar_fatia
    if pode_comecar_fatia(0, None) is not True:
        falhas.append("fatia 0 tem que poder comecar sempre (nao tem anterior)")
    if pode_comecar_fatia(1, 'PASS') is not True:
        falhas.append("fatia 1 com anterior PASS tem que poder comecar")
    if pode_comecar_fatia(1, 'FAIL') is not False:
        falhas.append("fatia 1 com anterior FAIL nao pode comecar")
    if pode_comecar_fatia(1, 'CONCERN') is not False:
        falhas.append("fatia 1 com anterior CONCERN nao pode comecar")
    if pode_comecar_fatia(1, None) is not False:
        falhas.append("fatia 1 sem veredito da anterior nao pode comecar")

    if falhas:
        print(f"FALHOU: {len(falhas)} divergencia(s)")
        for f in falhas:
            print(f"  - {f}")
        sys.exit(1)

    print(f"OK: {len(casos)} casos + provas isoladas (separador ';', regra 3), tudo bateu")
    sys.exit(0)


if __name__ == '__main__':
    main()
