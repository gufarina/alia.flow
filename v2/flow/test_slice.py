"""test_slice.py - modulo flow, TASK-812 (Shopify 02).

Roda os 12 casos de cases.json contra slice.is_tarefa_grande()/fatiar(): os 2 com 2+ frentes
(TASK-577, TASK-603) tem que sair "grande" com 1 fatia por frente; os outros 10 tem que sair
"pequeno" (1 fatia so, o brief inteiro - inclusive INV-06, que nao tem frentes/modulos_tocados
declarados e brief incompleto: slice.py nao valida campo obrigatorio, so risk.py faz isso).
Mais provas isoladas, fora do arquivo de casos:
negativo do separador solto (TASK-717 tem " e " no exemplo_falha e NAO pode virar 2 oracoes),
negativo do ";" de verdade dentro de exemplo_falha (NAO pode fatiar, so objetivo fatia),
regressao TASK-826 (exemplo_falha com "; ou" - 1 Task so, titulo = objetivo, criterio_aceite com
o exemplo_falha inteiro), positivo do ";" de verdade no objetivo (fatia por oracao, titulo = a
oracao) e a regra 3 (pode_comecar_fatia). So biblioteca padrao (json, sys, os).
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

    # prova negativa isolada: ";" de verdade dentro do exemplo_falha (nao so "e" solto) TAMBEM nao
    # pode fatiar - e o defeito medido no TASK-826 (fatiador tratando alternativa de UMA entrega
    # que falha como se fossem varias entregas)
    brief_falha_composta = {
        'client': 'alia-flow-lab', 'project': 'engine',
        'objetivo': 'ajustar o modulo de log',
        'paths': 'v2/flow', 'consumidor': 'Warden', 'destino': 'interno',
        'exemplo_falha': 'linha sem timestamp; nivel de log errado; arquivo nao gira',
        'modulos_tocados': ['flow'], 'frentes': ['flow'],
    }
    av_falha_composta = is_tarefa_grande(brief_falha_composta)
    if 'criterio_composto' in av_falha_composta['motivos']:
        falhas.append("exemplo_falha com ';' nao pode virar criterio_composto (so objetivo fatia)")
    fatias_falha_composta = fatiar(brief_falha_composta)
    if len(fatias_falha_composta) != 1:
        falhas.append(f"exemplo_falha composto: esperado 1 fatia (objetivo sem ';'), veio {len(fatias_falha_composta)}")

    # regressao TASK-826: brief real do CEO, exemplo_falha com "; ou" (alternativas de UMA
    # entrega que falha, nao entregas separadas) tem que virar 1 Task so, titulo = objetivo
    brief_826 = {
        'client': 'alia-flow-lab', 'project': 'alia-2.0',
        'objetivo': 'Registrar a entrada [2.0.1] no CHANGELOG da oficina, identica a ja escrita no CHANGELOG do produto, no estilo breve e direto que o CEO pediu',
        'paths': 'clients/alia-flow-lab/CHANGELOG.md',
        'consumidor': 'CEO e quem instala o Alia Flow (le o historico de versoes)',
        'destino': 'publico',
        'exemplo_falha': 'VERSION diz 2.0.1 e o topo do CHANGELOG da oficina segue em 2.0.0; ou o texto da oficina diverge do produto; ou arquivo gravado com BOM ou acento corrompido',
    }
    av_826 = is_tarefa_grande(brief_826)
    if av_826['grande']:
        falhas.append(f"TASK-826: nao pode sair grande, motivos={av_826['motivos']}")
    fatias_826 = fatiar(brief_826)
    if len(fatias_826) != 1:
        falhas.append(f"TASK-826: esperado 1 fatia (brief inteiro), veio {len(fatias_826)}")
    if fatias_826 and fatias_826[0]['objetivo'] != brief_826['objetivo']:
        falhas.append("TASK-826: titulo da fatia tem que ser o objetivo inteiro, nunca texto de exemplo_falha")
    if fatias_826 and brief_826['exemplo_falha'] not in fatias_826[0]['criterio_aceite']:
        falhas.append("TASK-826: criterio_aceite tem que citar o exemplo_falha inteiro")

    # prova positiva isolada: ";" de verdade no OBJETIVO (nao no exemplo_falha) DEVE fatiar por
    # oracao, e o titulo de cada fatia tem que ser a oracao do objetivo, nunca texto de falha
    brief_objetivo_composto = {
        'client': 'alia-flow-lab', 'project': 'engine',
        'objetivo': 'corrigir timestamp do log; corrigir nivel do log; corrigir rotacao do arquivo',
        'paths': 'v2/flow', 'consumidor': 'Warden', 'destino': 'interno',
        'exemplo_falha': 'log sai errado',
        'modulos_tocados': ['flow'], 'frentes': ['flow'],
    }
    fatias_comp = fatiar(brief_objetivo_composto)
    if len(fatias_comp) != 3:
        falhas.append(f"brief_objetivo_composto: esperado 3 fatias (';' x2 no objetivo), veio {len(fatias_comp)}")
    if fatias_comp and fatias_comp[0]['objetivo'] != 'corrigir timestamp do log':
        falhas.append("brief_objetivo_composto: titulo da fatia tem que ser a oracao do objetivo")

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
