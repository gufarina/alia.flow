"""risk.py - modulo flow, I6 (TASK-801 E5).

Funcao pura, so biblioteca padrao. Recebe o brief (6 campos do checklist do kernel + frentes +
flags de risco) e devolve a classificacao R1/R2, os gatilhos que dispararam, o modo de delegacao
(direto ou gateway) e os campos do checklist que faltam.

Fonte da regra: artifacts/alia-2.0-2026-09-22/e4-arquitetura-v2.md, secao 3, passo 3 (Risco):
R2 se (a) destino publico; (b) irreversivel (dado do operador, producao, deploy, migracao);
(c) kernel, contrato de modulo, ou 3 ou mais modulos; (d) seguranca; (e) ordem do Operator.
Resto e R1. Modo gateway so quando o brief declara 2 ou mais frentes (tese, secao 1, ponto 3).

Contrato do brief (dict):
  client, project, objetivo, paths, consumidor, destino, exemplo_falha  -> os 6 campos do
    checklist (Client/Project conta como 1 item, 2 chaves)
  irreversivel, seguranca, ordem_operator, kernel_tocado, contrato_modulo_tocado -> bool
  modulos_tocados -> lista de nomes de modulo tocados nesta Task
  frentes -> lista de frentes de trabalho independentes declaradas no brief

Regra dura: brief incompleto NUNCA vira R1 silencioso. Falta campo obrigatorio -> risco e modo
saem None, e 'faltando' lista exatamente o que falta.
"""

CAMPOS_OBRIGATORIOS = [
    'client',
    'project',
    'objetivo',
    'paths',
    'consumidor',
    'destino',
    'exemplo_falha',
]


def classificar(brief):
    faltando = [c for c in CAMPOS_OBRIGATORIOS if not brief.get(c)]
    if faltando:
        return {
            'risco': None,
            'gatilhos': [],
            'modo': None,
            'faltando': faltando,
        }

    gatilhos = []

    if brief.get('destino') == 'publico':
        gatilhos.append('destino_publico')

    if brief.get('irreversivel'):
        gatilhos.append('irreversivel')

    modulos_tocados = brief.get('modulos_tocados') or []
    if brief.get('kernel_tocado') or brief.get('contrato_modulo_tocado') or len(modulos_tocados) >= 3:
        gatilhos.append('modulo_ou_kernel')

    if brief.get('seguranca'):
        gatilhos.append('seguranca')

    if brief.get('ordem_operator'):
        gatilhos.append('ordem_operator')

    risco = 'R2' if gatilhos else 'R1'

    frentes = brief.get('frentes') or []
    modo = 'gateway' if len(frentes) >= 2 else 'direto'

    return {
        'risco': risco,
        'gatilhos': gatilhos,
        'modo': modo,
        'faltando': [],
    }
