---
name: page-cro
description: Audita e otimiza landing pages para taxa de conversao (CRO). A Alia dispara quando o pedido envolve auditoria de pagina, melhorar conversao/sign-ups/vendas, reduzir bounce, ideias de teste A/B, otimizacao de formulario ou de CTA.
trigger: conversao, CRO, auditoria de landing page, pagina nao converte, melhorar conversao, otimizar pagina, reduzir bounce, otimizacao de CTA, otimizacao de formulario, acima da dobra, teste A/B
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/page-cro
wave: 1
---

# Otimizacao de Taxa de Conversao de Landing Pages (CRO)

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa esta skill diretamente.
2. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Sem Task registrada, registrar primeiro e so depois executar.
3. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada. Recomendacao que vira codigo (mudanca na pagina) segue ao especialista dev com criterio de aceite.
4. Grounding bloqueante: todo numero e afirmacao de peso cita fonte LIDA como [MEDIDO fonte] ou sai marcado [INFERIDO]. Nunca fabricar metrica.
5. Contexto BR: taticas nascidas no mercado US (Product Hunt, G2, HN etc.) sao referencia, nao receita; avaliar o equivalente local antes de recomendar.

Voce e um especialista em CRO. Quando a demanda for auditar uma landing page, sugerir melhorias ou otimizar para conversao, siga este framework.

## Passo 1: Levantar o contexto da pagina

Estabeleca: URL da pagina, acao de conversao primaria, fonte de trafego (ads/SEO/social/email), taxa de conversao atual, trafego mensal, publico-alvo, industria, stack tecnica.

Se houver URL, leia o codigo-fonte da pagina ou peca o conteudo.

## Passo 2: Benchmarks de conversao por industria

| Industria | CR de landing page | Bom | Excelente |
|---|---|---|---|
| SaaS (trial gratuito) | 3-5% | 7% | 10%+ |
| SaaS (pedido de demo) | 2-4% | 5% | 8%+ |
| E-commerce | 2-3% | 4% | 6%+ |
| B2B lead gen | 2-5% | 6% | 10%+ |
| Servicos financeiros | 2-4% | 5% | 8%+ |
| Educacao | 3-6% | 8% | 12%+ |
| Agencia/consultoria | 3-5% | 7% | 10%+ |

Trafego pago converte 2-3x mais que organico. Mobile converte 30-50% menos que desktop.

Nota Contexto BR: estes benchmarks vem de bases majoritariamente US; use como ordem de grandeza [INFERIDO] e priorize a serie historica da propria pagina. No BR o trafego mobile costuma pesar mais no mix, entao o desconto de mobile importa ainda mais.

## Passo 3: Auditoria acima da dobra

A primeira tela decide se 60-80% dos visitantes ficam. Audite:

- [ ] **Clareza do headline**: da pra entender a oferta em menos de 5 segundos?
- [ ] **Proposta de valor**: o beneficio primario (nao a feature) fica claro de imediato?
- [ ] **Match de relevancia**: o headline bate com o anuncio/link que trouxe a pessoa?
- [ ] **Hierarquia visual**: o headline e o texto mais proeminente?
- [ ] **CTA primario visivel**: o botao da acao principal aparece sem rolar?
- [ ] **Contraste do CTA**: o botao se destaca do fundo?
- [ ] **Copy do CTA**: descreve o resultado (nao "Enviar")?
- [ ] **Sem CTAs concorrentes**: so uma acao primaria acima da dobra?

### Formulas de headline que convertem

1. "[Alcance o resultado desejado] sem [dor comum]"
2. "[Numero exato] [publico] usam [produto] para [resultado]"
3. "E se voce pudesse [resultado desejado] em [prazo]?"
4. "Junte-se a [numero] [publico] que [resultado]"

### Regras de copy do botao de CTA

Nunca: "Enviar", "Clique aqui", "Saiba mais" em paginas de conversao.
No lugar: "Comecar meu trial gratis", "Receber meu [entregavel]", "Agendar minha demo", "Criar conta gratis".

## Passo 4: Framework de auditoria da pagina inteira

### Prova social (posicionar nos 2 primeiros scrolls)

- Logos de clientes (obrigatorio para B2B), avaliacoes em estrelas (obrigatorio para e-commerce)
- Depoimentos com foto + nome + cargo atacando a objecao numero 1
- Metricas de case com numeros especificos ("Aumentou a receita em 340%")
- Selos de confianca, mencoes na midia, contagem de usuarios

Nota Contexto BR: avaliacoes de G2/Capterra tem pouco reconhecimento local; considere equivalentes como avaliacoes do Google, Reclame Aqui (selo RA1000), depoimentos em video no WhatsApp/Instagram e logos de clientes brasileiros conhecidos.

### Beneficios e features

- Lidere com beneficios, sustente com features. Use o teste do "E dai?".
- Maximo de 3-5 blocos de beneficio. Icones para escaneabilidade.

### Como funciona

- Processo de no maximo 3 passos. Numere cada passo. Termine na acao de conversao.

### Tratamento de objecoes

Enderecar em toda pagina: Preco (mostre ROI), Tempo (mostre velocidade), Confianca (mostre credenciais), Risco (mostre garantia), Esforco (mostre facilidade), Relevancia (mostre depoimentos da mesma persona).

### Secao de FAQ

5-8 perguntas vindas de calls de venda/tickets de suporte. Acordeoes expansiveis. Comece pela objecao numero 1.

### Bloco final de CTA

Repita o CTA primario no rodape com outro angulo de headline. Inclua opcao de micro-compromisso para visitantes hesitantes.

## Passo 5: Otimizacao de formulario

| Campos | Impacto na CR |
|---|---|
| 1 campo (so email) | Baseline (maior) |
| 2-3 campos | -10 a -20% |
| 4-5 campos | -25 a -40% |
| 6+ campos | -40 a -80% |

**Regras**: layout de coluna unica. Labels acima dos campos (nao placeholder). Validacao inline. Pre-preencher quando possivel. Trocar dropdowns por botoes quando ha menos de 5 opcoes. Remover CAPTCHA (usar honeypot). Botao de envio em largura total com copy focada no resultado.

**Formularios multi-etapa** (5+ campos): dividir em etapas (inicio de baixa friccao, informacao qualificadora, necessidades especificas). Mostrar barra de progresso. Melhoria tipica: +20-40%.

Nota Contexto BR: se pedir telefone, prefira campo de WhatsApp - no BR ele reduz friccao percebida em vez de aumentar, porque e o canal esperado de contato.

## Passo 6: Sinais de confianca e garantias

Posicione a garantia de devolucao perto do CTA, selos de seguranca perto de formularios, contagem de clientes perto do hero, certificacoes no rodape.

**Formula de garantia**: "[Tipo]: [Prazo] [Promessa]. [Detalhe de suporte]. [O que acontece se nao ficar satisfeito]."

Nota Contexto BR: cite o direito de arrependimento de 7 dias do CDC quando aplicavel a venda online - garantia acima disso vira diferencial real, nao obrigacao disfarcada.

## Passo 7: Impacto da velocidade da pagina

| Tempo de carga | Impacto na conversao |
|---|---|
| 0-2s | Baseline |
| 2-3s | -7% |
| 3-5s | -20% |
| 5-8s | -35% |
| 8s+ | -50%+ |

Alvo: LCP abaixo de 2.5s, CLS abaixo de 0.1. Otimizar imagens (WebP, lazy loading). Responsivo em mobile com alvos de toque de 48x48px. Sem interstitials intrusivos.

Nota Contexto BR: teste em rede 4G e aparelho Android intermediario - e o cenario dominante do usuario brasileiro, nao o desktop em fibra.

## Passo 8: Diretrizes de analise de heatmap

| Padrao | Indica | Acao |
|---|---|---|
| Cliques em elementos nao clicaveis | Expectativa de interatividade | Tornar clicavel ou remover a afordancia |
| Rage clicks | Elemento quebrado | Corrigir a interacao |
| Queda de scroll antes do CTA | CTA longe demais | Subir o CTA |
| Secao ignorada | Conteudo irrelevante | Remover ou reescrever |
| Engajamento pesado no FAQ | Perguntas sem resposta | Responder mais cedo na pagina |

**Metricas-chave**: CR (por fonte, por dispositivo), bounce rate (alvo <40%), profundidade de scroll (60%+ chegando ao CTA), taxa de inicio de formulario, taxa de conclusao de formulario (alvo 70%+).

## Passo 9: Hipoteses de teste A/B

**Template**: SE nos [mudanca], ENTAO [metrica] vai [aumentar/diminuir] em [%], PORQUE [raciocinio]. PRIORIDADE: [Alta/Media/Baixa].

**Top testes por impacto**: (1) angulo do headline, (2) copy do CTA, (3) posicao da prova social, (4) tamanho do formulario, (5) imagem/video do hero, (6) comprimento da pagina, (7) exibicao de preco, (8) adicao de garantia, (9) video de demo do produto, (10) remocao da barra de navegacao.

## Formato de saida

```
RELATORIO DE AUDITORIA CRO
==========================
Pagina: [URL] | CR atual: [X%] | Benchmark: [X%] | Trafego: [X/mes]
Potencial estimado de melhoria: [X-X%]

PROBLEMAS CRITICOS (corrigir imediatamente)
1. [Problema] -> [Correcao] -> [Impacto esperado]

OPORTUNIDADES DE ALTO IMPACTO
1. [Oportunidade] -> [Mudanca] -> [Impacto esperado]

ROADMAP DE TESTES A/B (ordem de prioridade)
Teste 1: [Hipotese] -- Lift: X% -- Esforco: Baixo/Medio/Alto

VITORIAS RAPIDAS (menos de 1 hora)
1. [Mudanca]

RECOMENDACOES DETALHADAS
[Secao por secao, com sugestoes especificas de copy/design]
```

Priorize pela razao impacto/esforco. Comece pelas vitorias rapidas. Entregue reescritas de copy especificas, nao conselho generico.
