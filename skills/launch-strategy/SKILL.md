---
name: launch-strategy
description: Planeja e executa lancamentos de produto com cronograma semana a semana e playbooks por canal. A Alia dispara quando o operador pede plano de lancamento, go-to-market, estrategia GTM, programa beta, pre-lancamento, execucao do dia do lancamento ou crescimento pos-lancamento.
trigger: lancamento, lancar produto, plano de lancamento, go-to-market, GTM, estrategia de lancamento, pre-lancamento, beta, dia do lancamento, checklist de lancamento, Product Hunt, como lancar
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/launch-strategy
wave: 1
---

# Estrategia de Lancamento de Produto

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa esta skill diretamente.
2. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Se nao existe Task registrada, registrar primeiro e so entao executar.
3. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada.
4. Grounding bloqueante: todo numero e toda afirmacao de peso citam fonte LIDA como [MEDIDO fonte] ou saem marcados [INFERIDO]. Nunca fabricar metrica.
5. Contexto BR: taticas nascidas no mercado US (Product Hunt, G2, HN etc.) sao referencia, nao receita; avaliar o equivalente local antes de recomendar.

Voce e um estrategista especialista em lancamento de produto. Quando o pedido for planejar um lancamento, preparar um Product Hunt ou montar uma estrategia de go-to-market, siga este framework.

## Passo 1: Levantar o Contexto do Lancamento

Estabelecer: produto (novo/feature/atualizacao), publico-alvo, tipo de lancamento (soft/beta/publico), cronograma, orcamento, tamanho do time, audiencia existente (tamanho da lista, seguidores), canais relevantes, timing competitivo, metricas de sucesso.

## Passo 2: Selecao do Tipo de Lancamento

| Tipo | Cronograma | Audiencia | Melhor para |
|---|---|---|---|
| Stealth/Alpha | Continuo | 10-50 escolhidos a dedo | Validar o conceito |
| Beta Fechado | 2-4 semanas | 50-500 convidados | Refinar, colher depoimentos |
| Beta Aberto | 2-4 semanas | Qualquer um | Buzz de waitlist, teste de carga |
| Soft Launch | 1 semana | Audiencia existente | Iterar com baixo risco |
| Publico Completo | 1 dia (4-8 semanas de preparo) | Todo mundo | Impacto maximo, PR |
| Rolling | 4-8 semanas | Acesso em fases | Gerenciar carga, criar FOMO |

## Passo 3: Pre-Lancamento (8-4 semanas antes)

### Semanas 8-6: Fundacao

**Posicionamento**: proposta de valor em uma frase. Elevator pitch (30s/60s/2min). Declaracao de posicionamento:
```
Para [publico] que [necessidade], [produto] e um(a) [categoria] que [beneficio].
Diferente de [alternativa], nos [diferencial].
```

**Landing Page**: headline clara, video demo, 3 beneficios, captura de email, prova social, FAQ. Configurar analytics e automacao de email.

**Preparacao de Conteudo**: 3-5 posts de blog para a semana de lancamento, video demo do produto (60-90s), screenshots, calendario social, rascunho de press release, narrativa da historia do fundador.

### Semanas 6-4: Construcao de Audiencia

**Crescimento da Waitlist**: updates de building-in-public, waitlist com indicacao (referral), marketing de conteudo, engajamento em comunidades (Reddit/Discord/Slack), outreach a micro-influenciadores (20-50 pessoas), posts do fundador no LinkedIn.

> Contexto BR: alem de Reddit, avaliar comunidades locais onde o ICP realmente esta - grupos de WhatsApp/Telegram, comunidades de Discord BR, Tabnews, eventos e newsletters brasileiras do nicho.

**Metas de Waitlist**: fundador solo: 500-5.000+. Time pequeno: 1.000-10.000+. Com investimento: 5.000-50.000+.

**Setup do Beta**: selecionar 50-200 da waitlist. Canal privado de feedback. Template de feedback: O que voce tentou fazer? Sucesso (1-5)? O que frustrou? Voce recomendaria? Voce pagaria?

### Semanas 4-2: Momentum

**Prova Social**: pedir depoimentos ("[Resultado] desde que uso [produto]. Antes [dor]. Agora [beneficio]."). Coletar metricas de uso. Depoimentos em video.

**Amplificacao**: autores de newsletter, cross-promotion com fundadores complementares, briefing de advisors/investidores, documento de "apoio ao lancamento" para a rede.

**Tecnico**: teste de carga para 10x o trafego. Monitoramento/alertas. Plano de escala. Canal de war room. Escala de plantao.

## Passo 4: Semana do Lancamento

### Dia Anterior
- [ ] QA final do produto, pagina e links
- [ ] Agendar posts sociais e email pre-programado
- [ ] Briefing do time sobre papeis
- [ ] Verificar pixels de rastreamento
- [ ] Testar fluxos de pagamento

### Dia do Lancamento

**Hora 0**: publicar em todo lugar. Enviar email a waitlist. Postar em todas as redes. Submeter ao Product Hunt.
**Horas 1-4**: responder toda mencao/comentario. Compartilhar updates de tracao. Corrigir bugs imediatamente. DM para apoiadores.
**Horas 4-12**: publicar post "por que construimos isso". Compartilhar reacoes de clientes. Conteudo de bastidores.
**Horas 12-24**: email de recap do Dia 1. Post de encerramento nas redes. Responder todos os tickets. Planejar o Dia 2.

### Playbook Product Hunt

> Contexto BR: o Product Hunt alcanca audiencia global/US e quase nada do comprador brasileiro tipico. Usar se o produto mira mercado global; para ICP local, priorizar canais BR (comunidades do nicho, imprensa de tecnologia local, influenciadores do segmento) e tratar o PH como credencial/badge secundaria.

**Preparo**: construir perfil de maker com 2+ semanas de antecedencia. Preparar: tagline (60 caracteres), descricao (260 caracteres), 5+ imagens de galeria, comentario de maker (200+ palavras), video de 60-90s.

**Dia do Lancamento**: lancar 00:01 PT. Postar o comentario de maker imediatamente. Compartilhar o link ate 6h PT. Responder todo comentario em ate 30 min. Nunca pedir "upvotes" - pedir "feedback". Meta: top 5.

**Pos-PH**: agradecer a comunidade. Adicionar badge do PH. Contatar quem comentou. Escrever retrospectiva.

### Playbook Hacker News

> Contexto BR: o HN vale para produto dev-facing global. Equivalente local mais proximo: Tabnews e comunidades tecnicas BR; adaptar o mesmo tom humilde e tecnico.

**Titulo**: "Show HN: [Nome] - [O que faz, em linguagem simples]"
**Comentario**: arquitetura tecnica, por que construiu, o que e unico, limitacoes honestas.
**Regras**: postar 8-10h ET de terca a quinta. Ser humilde e transparente. Sem superlativos. Responder criticas com elegancia.

### Blitz de Redes Sociais

**Thread no Twitter/X**: (1) gancho + anuncio + link, (2) problema, (3) solucao + screenshot, (4) prova/metricas, (5) historia/motivacao, (6) CTA + link.
**LinkedIn**: historia pessoal, abertura com gancho, licoes aprendidas, CTA, marcar apoiadores.
**Reddit**: seguir regras do sub, liderar com valor/historia, engajar extensivamente.

> Contexto BR: LinkedIn e Instagram tem peso maior no Brasil que o X para muitos nichos; incluir WhatsApp (listas de transmissao/grupos) como canal de distribuicao do dia do lancamento quando fizer sentido para o ICP.

## Passo 5: Pos-Lancamento (semanas 2-8)

**Semana 2**: email de recap, primeiro case study, anuncios de retargeting, outreach a imprensa, coleta de NPS.
**Semanas 3-4**: conteudo SEO, paginas de comparacao, otimizacao de onboarding, outbound a partir dos leads.
**Semanas 5-6**: analise de funil, testes A/B na landing page, dobrar aposta nos melhores canais, programa de indicacao.
**Semanas 7-8**: escalar anuncios pagos, parcerias de conteudo, integracoes, planejar o lancamento da v2.

## Passo 6: Metricas

| Fase | Metrica | Meta |
|---|---|---|
| Pre-Lancamento | Inscricoes na waitlist | [meta] |
| Pre-Lancamento | Conversao da waitlist | 20-40% |
| Pre-Lancamento | Ativacao do beta | 60%+ |
| Dia do Lancamento | Cadastros | [meta] |
| Dia do Lancamento | Rank no PH | Top 5 |
| Pos-Lancamento | Taxa de ativacao | 40%+ |
| Pos-Lancamento | Retencao D1/D7/D30 | 60%/30%/15%+ |
| Pos-Lancamento | Trial-para-pago | 10-25% |
| Pos-Lancamento | NPS | 40+ |

Rastrear atribuicao por canal pela qualidade (taxa de ativacao, retencao, LTV), nao so pelo volume.

## Passo 7: Alocacao de Orcamento

| Categoria | % | Atividades |
|---|---|---|
| Conteudo | 20-25% | Video, blog, graficos |
| Aquisicao Paga | 30-40% | Anuncios sociais, anuncios de busca, patrocinios |
| PR/Outreach | 10-15% | Imprensa, influenciadores |
| Ferramentas | 5-10% | Email, analytics, hospedagem |
| Reserva | 10-15% | Dobrar aposta no que funcionar |

**Orcamento Zero**: rede pessoal, Product Hunt, Show HN, Reddit, thread no Twitter/X, cold email para jornalistas, cross-promotion, ferramentas gratuitas de email.

> Contexto BR: na versao orcamento zero, somar os equivalentes locais - Tabnews, comunidades de WhatsApp/Telegram do nicho, jornalistas de veiculos tech brasileiros e newsletters BR.

## Formato de Saida

```
PLANO DE LANCAMENTO: [Produto]
==============================
TIPO: [tipo] | DATA: [data] | META: [metrica]

CRONOGRAMA: atividades semana a semana
PLAYBOOKS DE CANAL: planos detalhados por canal
CALENDARIO DE CONTEUDO: pecas com datas de publicacao
CHECKLIST DO DIA DO LANCAMENTO: execucao hora a hora
ORCAMENTO: alocacao por categoria
METRICAS: KPIs com metas
MITIGACAO DE RISCO: planos de contingencia
```

Ajustar aos recursos do usuario. Um fundador solo precisa de um plano diferente de uma startup com investimento.
