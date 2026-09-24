"""slice.py - modulo flow, TASK-812 (Shopify 02: fatiar tarefa grande em pedacos pequenos).

Funcao pura, so biblioteca padrao. Mesmo contrato de brief que risk.py usa (client, project,
objetivo, paths, consumidor, destino, exemplo_falha, modulos_tocados, frentes) - nao importa
risk.py nem lib/ (o Warden esta mexendo em lib/ e na entidade Task agora, TASK-812/plano-2.0.1
item A; este arquivo fica desacoplado de proposito, so le o dict do brief).

Criterio de "tarefa grande" (qualquer um dispara - ANY, nao AND):

  (a) mais de 1 frente: len(frentes) > 1. Mesmo limiar que risk.py ja usa para modo="gateway"
      (2 frentes ja e trabalho que se divide em maos diferentes).
  (b) mais de 2 modulos/caminhos tocados: len(modulos_tocados) > 2. MESMO numero do gatilho
      "modulo_ou_kernel" de risk.py e da regra R2 do kernel (AGENTS.md: "toca o kernel, o
      contrato de um modulo, ou tres ou mais modulos"). Reusa o limiar que a casa ja aceita em
      vez de inventar um novo - 3 modulos e onde o proprio risco ja escala pra R2.
  (c) criterio de aceite com mais de um resultado verificavel: objetivo OU exemplo_falha com 2+
      oracoes separadas por ";" (so ";", nao "e"/"ou" - texto natural usa "e" para unir duas
      METADES da mesma frase o tempo todo, ex. TASK-717 "muda contrato sem aviso e quebra em
      producao" e UM jeito de falhar, nao dois criterios. Falso negativo (nao fatiar um brief que
      merecia) e mais seguro aqui que falso positivo (fatiar um brief que nao precisava) - por
      isso o separador e estrito).

Task pequena (nenhum criterio dispara): fatiar() devolve 1 fatia so, o brief inteiro.

Fatiamento e SEMPRE sequencial nesta primeira versao, mesmo quando as frentes sao paralelas de
verdade (ex. avaliacao de repositorios independentes, TASK-603) - simplifica a regra 3 ("fatia so
comeca depois da anterior passar no Gate") sem modelar paralelismo aqui; modo=gateway (risk.py)
continua sendo quem executa frentes paralelas de verdade, sem depender deste modulo. Prioridade de
eixo quando mais de um criterio dispara: frentes > modulos_tocados > oracoes (frentes e o eixo
mais concreto - ja vem nomeado no brief pelo Operator).
"""

import re

TETO_FRENTES = 1
TETO_MODULOS = 2
_SEP_ORACAO = re.compile(r'\s*;\s*')


def _oracoes(texto):
    """Oracoes separadas por ';', filtrando fragmento curto demais (< 3 palavras) - evita
    falso positivo em enumeracao curta tipo 'x; y'. So conta se sobrar 2 ou mais."""
    if not texto:
        return []
    partes = [p.strip() for p in _SEP_ORACAO.split(texto) if len(p.strip().split()) >= 3]
    return partes if len(partes) >= 2 else []


def is_tarefa_grande(brief):
    """Devolve {'grande': bool, 'motivos': {eixo: itens}}. 'motivos' so tem a(s) chave(s) do(s)
    criterio(s) que disparou - vazio quando a Task e pequena."""
    frentes = brief.get('frentes') or []
    modulos = brief.get('modulos_tocados') or []
    oracoes = _oracoes(brief.get('objetivo')) or _oracoes(brief.get('exemplo_falha'))

    motivos = {}
    if len(frentes) > TETO_FRENTES:
        motivos['frentes'] = frentes
    if len(modulos) > TETO_MODULOS:
        motivos['modulos_tocados'] = modulos
    if oracoes:
        motivos['criterio_composto'] = oracoes

    return {'grande': bool(motivos), 'motivos': motivos}


def _fatia_unica(brief):
    return {
        'id': 'fatia-1',
        'objetivo': brief.get('objetivo'),
        'criterio_aceite': f"nao falha como: {brief.get('exemplo_falha')}",
        'caminhos': brief.get('paths'),
        'depende_da_anterior': False,
    }


def fatiar(brief):
    """Devolve a lista de fatias em ordem, cada uma com objetivo, criterio de aceite proprio,
    caminhos e depende_da_anterior. Task pequena: lista de 1 fatia so (o brief inteiro, sem
    fatiar de verdade - mantem o contrato uniforme pra quem chama)."""
    avaliacao = is_tarefa_grande(brief)
    if not avaliacao['grande']:
        return [_fatia_unica(brief)]

    motivos = avaliacao['motivos']
    if 'frentes' in motivos:
        itens, eixo = motivos['frentes'], 'frente'
    elif 'modulos_tocados' in motivos:
        itens, eixo = motivos['modulos_tocados'], 'modulo'
    else:
        itens, eixo = motivos['criterio_composto'], 'oracao'

    fatias = []
    for i, item in enumerate(itens):
        objetivo_fatia = item if eixo == 'oracao' else f"{brief.get('objetivo')} - {eixo}: {item}"
        fatias.append({
            'id': f'fatia-{i + 1}',
            'objetivo': objetivo_fatia,
            'criterio_aceite': f"nao falha como: {brief.get('exemplo_falha')} (escopo: {item})",
            'caminhos': brief.get('paths'),
            'depende_da_anterior': i > 0,
        })
    return fatias


def pode_comecar_fatia(indice, veredito_fatia_anterior):
    """Regra 3: fatia so comeca depois da anterior passar no Gate. indice 0 (a primeira) sempre
    pode comecar - nao tem anterior. indice > 0 exige veredito_fatia_anterior == 'PASS'; FAIL ou
    CONCERN trava a proxima fatia ate a correcao da anterior passar."""
    if indice <= 0:
        return True
    return veredito_fatia_anterior == 'PASS'
