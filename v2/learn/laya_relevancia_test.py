# -*- coding: utf-8 -*-
"""Teste da Laya em sombra: relevancia de nota de memoria para uma Task (uso B, condicao 4 do
Gate, e4-laya-cetico.md secao 2). 50 pares (Task, nota), rotulados a mao neste arquivo,
comparados contra grep por palavra-chave e contra o rotulo humano. Roda via v2/lib/decide.py com
a Laya em modo SOMBRA - nunca troca decisao de ninguem, so mede. Sem rede.

Fonte dos pares: modelados no formato real de Tasks de state.json e de notas do indice de
MEMORY.md (linha-resumo de cada nota, como o contrato pede), mas anonimizados - todo Client
citado na lista PARES abaixo e o Client de exemplo publico (acme-saas), nunca Client real
(regra da Task: nada de identidade real gravada na prova).
"""
from __future__ import annotations

import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))

PISO_CONFIANCA = 0.70
STOPWORDS = {
    "a", "o", "de", "da", "do", "e", "em", "para", "com", "na", "no", "que", "as", "os",
    "um", "uma", "por", "se", "ao", "aos", "das", "dos", "nao", "mais", "ja", "so", "vs",
}

PARES = [
    ('LP canonica com 2 vetos vivos e publico superado', 'landing v15 organismo: LP CANONICA, versao aprovada em uso', 'relevante'),
    ('Copy completa da LP a partir do BrandScript aprovado', 'LP da Alia refazer: copy APROVADA em 8 blocos', 'relevante'),
    ('Direcao de arte da LP: inventario de icones e animacoes', 'marca Alia fontes e paleta: SpockPro + Instrument Serif', 'relevante'),
    ('Direcao de arte da LP: inventario de icones e animacoes', 'estetica dither/misterio: gravura/dithering, sensual', 'relevante'),
    ('Prompt opus magnus da LP (pesquisa + copy + direcao de arte)', 'landing v15 organismo: LP CANONICA, versao aprovada em uso', 'relevante'),
    ('Assets verbais e copys por superficie', 'tagline-mae da Alia: Voce diz o que quer, a Alia faz acontecer', 'relevante'),
    ('Consolidacao editorial + Gate de peca publica da narrativa', 'veto de palavra vira arquivo do Client: veto so em briefing nao sobrevive a proxima delegacao', 'relevante'),
    ('Consolidacao editorial + Gate de peca publica da narrativa', 'peca reprovada vira regua, nao proibicao', 'relevante'),
    ('Guarda de vetos estendido a superficie publica + benchmarks', 'superficie publica vaza pelo registro honesto: varrer a ENTRADA INTEIRA', 'relevante'),
    ('Numero unico anti-apodrecimento na copy (135/143/152)', 'README escrito para versao que nao saiu: numero fossil no README', 'relevante'),
    ('Big numbers medidos para anuncio de marketing (benchmarks)', 'bump de versao vence os selos de capacidade: recertificar entra no custo fixo', 'relevante'),
    ('PRFAQ definitivo da Alia (working backwards)', 'fatos do produto da Alia: Alia e protagonista', 'relevante'),
    ('PRFAQ definitivo da Alia (working backwards)', 'posicionamento braco direito: COO de IA foi DERRUBADO', 'relevante'),
    ('BrandScript StoryBrand 7 definitivo (heroi corrigido)', 'Alia tem alma/protagonista: investir em alma na LP', 'relevante'),
    ('Pesquisa profunda: extrair o maximo do Claude em design/frontend', 'preferencia de pesquisa: Perplexity Pro primeiro, NotebookLM se precisar', 'relevante'),
    ('Validacao do graphify em maquina limpa', 'guarda do mapa: furos consertados, resta adocao 12,2% vs meta 70%', 'relevante'),
    ('Validacao do graphify em maquina limpa', 'mapa: o caro e a doc e o cano, 1.201 mencoes de caminho', 'relevante'),
    ('Updater diff-only com -Check e backup por arquivo', 'hash do bundle nao prova deploy: conferir o marcador de versao', 'relevante'),
    ('Updater diff-only com -Check e backup por arquivo', 'mtime nao prova propagacao, hash prova: a copia preserva a data', 'relevante'),
    ('Discovery da proxima versao (features + debitos tecnicos)', 'Alia RSI e pilar: a Alia e o prototipo de auto-melhoria', 'relevante'),
    ('Discovery da proxima versao (features + debitos tecnicos)', 'RSI sensor ligado, atuador parado: 77 sessoes e zero melhoria', 'relevante'),
    ('Revisao especialista dos scripts da 1.39.0 (register-task tipado)', 'incidente: ID de Task colidido: criar Task e SEMPRE via mecanismo unico', 'relevante'),
    ('Revisao especialista de docs/skill da 1.39.0 (AGENTS, MAP, CHANGELOG)', 'CHANGELOG publico comeca do zero na v1.79.0: decisao do CEO', 'relevante'),
    ('Validacao independente completa da 1.39.0 (Gate + trilho + pacote)', 'versao publicada e imutavel: correcao gera numero novo ANTES do proximo passo', 'relevante'),
    ('Infografico HTML/CSS 3D explicando AI/LLM/Harness para leigos', 'publico da Alia: nao-tecnico que quer ENTRAR na IA', 'relevante'),
    ('LP canonica com 2 vetos vivos e publico superado', 'Client acme-saas: a maquina do CEO, squad de 4 para o PC dele', 'irrelevante'),
    ('Copy completa da LP a partir do BrandScript aprovado', 'CLI da Vercel: nunca login interativo, OAuth entrou na conta errada', 'irrelevante'),
    ('Direcao de arte da LP: inventario de icones e animacoes', 'CV do CEO: fidelidade e voz propria, copywriter inventou dado', 'irrelevante'),
    ('Prompt opus magnus da LP (pesquisa + copy + direcao de arte)', 'acme-saas: widget novo na taskbar, Client novo e squad', 'irrelevante'),
    ('Assets verbais e copys por superficie', 'acme-saas: canal de mensagem decidido, gratis quando o app responde', 'irrelevante'),
    ('Consolidacao editorial + Gate de peca publica da narrativa', 'indice do Client acme-saas (25 notas): abrir ANTES de trabalhar no acme-saas', 'irrelevante'),
    ('Guarda de vetos estendido a superficie publica + benchmarks', 'indice do Client acme-saas (10 notas): abrir ANTES de trabalhar no acme-saas', 'irrelevante'),
    ('Numero unico anti-apodrecimento na copy (135/143/152)', 'Client acme-saas: identidade fechada pela diretoria', 'irrelevante'),
    ('Big numbers medidos para anuncio de marketing (benchmarks)', 'CEO odeia travessao: em/en dash proibido, reescrever a frase', 'irrelevante'),
    ('PRFAQ definitivo da Alia (working backwards)', 'Laya instalado e medido na maquina: 56ms na GPU, confianca do noul', 'irrelevante'),
    ('BrandScript StoryBrand 7 definitivo (heroi corrigido)', 'sentinela: o especialista de seguranca, criado apos vazamento de identidade', 'irrelevante'),
    ('Pesquisa profunda: extrair o maximo do Claude em design/frontend', 'agente tem ID unico e ledger proprio: apelido nao prova quem trabalhou', 'irrelevante'),
    ('Validacao do graphify em maquina limpa', 'CEO tem TDAH: aprovacao visual, decisao sempre com artefato', 'irrelevante'),
    ('Updater diff-only com -Check e backup por arquivo', 'acme-saas: Client novo e onboarding medido, humanizacao e casca vazia', 'irrelevante'),
    ('Discovery da proxima versao (features + debitos tecnicos)', 'imagem em conversa custa quadratico: conferir por texto', 'irrelevante'),
    ('Revisao especialista dos scripts da 1.39.0 (register-task tipado)', 'acme-saas: widget novo na taskbar, Client novo e squad', 'irrelevante'),
    ('Revisao especialista de docs/skill da 1.39.0 (AGENTS, MAP, CHANGELOG)', 'acme-saas: produto regrediu, leads mortos, LP nao calcula mapa', 'irrelevante'),
    ('Validacao independente completa da 1.39.0 (Gate + trilho + pacote)', 'Client acme-saas: a maquina do CEO, squad de 4 para o PC dele', 'irrelevante'),
    ('Infografico HTML/CSS 3D explicando AI/LLM/Harness para leigos', 'CLI da Vercel: nunca login interativo, OAuth entrou na conta errada', 'irrelevante'),
    ('Auditoria tecnica + plano de upgrade da LP v26', 'indice do Client acme-saas (25 notas): abrir ANTES de trabalhar no acme-saas', 'irrelevante'),
    ('Auditoria de gargalos do fluxo agentico + contrato de task tipado', 'Client acme-saas: identidade fechada pela diretoria', 'irrelevante'),
    ('Auditoria de gargalos do fluxo agentico + contrato de task tipado', 'incidente: ID de Task colidido: criar Task e SEMPRE via mecanismo unico', 'relevante'),
    ('Auditoria tecnica + plano de upgrade da LP v26', 'landing v15 organismo: LP CANONICA, versao aprovada em uso', 'relevante'),
    ('Guarda de vetos estendido a superficie publica + benchmarks', 'numero unico anti-apodrecimento: bump de versao vence os selos de capacidade', 'relevante'),
    ('Numero unico anti-apodrecimento na copy (135/143/152)', 'README publico com benchmarks: numero unico vence numeros divergentes', 'relevante'),
]


def _palavras(texto):
    return {w for w in re.findall(r"[a-zA-Z0-9]+", texto.lower()) if w not in STOPWORDS and len(w) > 2}


def grep_baseline(task_topico, nota_resumo):
    comuns = _palavras(task_topico) & _palavras(nota_resumo)
    return "relevante" if comuns else "irrelevante"


def rodar(shadow_ledger_path):
    os.environ["ALIA_DECIDE_SHADOW_LEDGER"] = shadow_ledger_path
    if os.path.exists(shadow_ledger_path):
        os.remove(shadow_ledger_path)
    import decide

    for task_topico, nota_resumo, _rotulo in PARES:
        entrada = {
            "criteria": ["relevante", "irrelevante"],
            "pergunta": "Esta nota de memoria e relevante para esta Task?",
            "texto": "Task: " + task_topico + chr(10) + "Nota: " + nota_resumo,
        }
        resp = decide.decide("relevancia-nota-memoria", entrada)
        assert resp is None

    linhas = []
    with open(shadow_ledger_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip()
            if raw:
                linhas.append(json.loads(raw))

    n = len(PARES)
    assert len(linhas) == n

    laya_decide = 0
    laya_certo = 0
    base_certo = 0
    for par, linha in zip(PARES, linhas):
        task_topico, nota_resumo, rotulo = par
        resp = linha["resposta"]
        base = grep_baseline(task_topico, nota_resumo)
        if base == rotulo:
            base_certo += 1
        conf = resp.get("confianca") or 0.0
        if resp.get("resposta") is not None and conf >= PISO_CONFIANCA:
            laya_decide += 1
            if resp["resposta"] == rotulo:
                laya_certo += 1

    resultado = {
        "n": n,
        "laya_cobertura": laya_decide / n,
        "laya_abstencao": 1 - (laya_decide / n),
        "laya_precisao": (laya_certo / laya_decide) if laya_decide else None,
        "baseline_cobertura": 1.0,
        "baseline_precisao": base_certo / n,
        "piso_confianca": PISO_CONFIANCA,
    }
    return resultado


if __name__ == "__main__":
    padrao = os.path.join(tempfile.gettempdir(), "alia-v2-laya-shadow-i8.jsonl")
    caminho = sys.argv[1] if len(sys.argv) > 1 else padrao
    resultado = rodar(os.path.abspath(caminho))
    print(json.dumps(resultado, ensure_ascii=False, indent=1))
