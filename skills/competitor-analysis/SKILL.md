---
name: competitor-analysis
description: Analise competitiva completa de concorrentes cobrindo SEO, anuncios pagos, social, email, preco e posicionamento, com SWOT, matriz competitiva e recomendacoes estrategicas fundamentadas. A Alia dispara quando o operador pede para analisar concorrentes, mapear o cenario competitivo, comparar precos ou construir matriz competitiva.
trigger: analise de concorrentes, analise competitiva, concorrencia, benchmark, cenario competitivo, matriz competitiva, SWOT, preco dos concorrentes, SEO dos concorrentes, anuncios dos concorrentes
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/competitor-analysis
wave: 1
---

# Framework de Analise de Concorrentes

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa esta skill diretamente.
2. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Sem Task registrada, registre primeiro e so depois execute.
3. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada.
4. Grounding bloqueante: todo numero e toda afirmacao de peso citam fonte LIDA como [MEDIDO fonte] ou saem marcados [INFERIDO]. Nunca fabricar metrica.
5. Contexto BR: taticas nascidas no mercado US (Product Hunt, G2, HN etc.) sao referencia, nao receita; avalie o equivalente local (Reclame Aqui, comunidades BR, marketplaces locais) antes de recomendar.

## Visao Geral

Voce e um analista especialista em inteligencia competitiva. Quando o pedido for analisar concorrentes, construir matrizes competitivas ou identificar vantagens competitivas, siga este framework.

## Integracoes opcionais

As chaves de API abaixo habilitam coleta de dados mais rica. Todas sao opcionais - a skill roda 100% sem elas, usando busca web e fontes gratuitas.

- `SEMRUSH_API_KEY` - Visao geral de dominio, keywords organicas, descoberta de concorrentes, estimativas de trafego
- `SERPAPI_API_KEY` - Analise competitiva de SERP em tempo real, extracao de copy de anuncios
- `SCRAPINGBEE_API_KEY` - Raspar paginas de concorrentes que bloqueiam fetch direto

### API SemRush (se SEMRUSH_API_KEY disponivel)

**Visao Geral de Dominio** - Trafego, keywords e autoridade de qualquer concorrente:
```bash
curl -s "https://api.semrush.com/?type=domain_ranks&key=${SEMRUSH_API_KEY}&export_columns=Db,Dn,Rk,Or,Ot,Oc,Ad,At,Ac&domain={dominio_concorrente}"
```
Colunas: Db=Base, Dn=Dominio, Rk=Rank, Or=Keywords Organicas, Ot=Trafego Organico, Oc=Custo Organico, Ad=Keywords Adwords, At=Trafego Adwords, Ac=Custo Adwords.

**Keywords Organicas** - Para quais keywords o concorrente rankeia:
```bash
curl -s "https://api.semrush.com/?type=domain_organic&key=${SEMRUSH_API_KEY}&domain={dominio_concorrente}&database=us&export_columns=Ph,Po,Nq,Cp,Ur,Tr&display_limit=50&display_sort=tr_desc"
```
Colunas: Ph=Keyword, Po=Posicao, Nq=Volume de Busca, Cp=CPC, Ur=URL, Tr=% de Trafego.

> Contexto BR: para concorrentes brasileiros, troque `database=us` por `database=br` - o indice US subestima muito o mercado local.

**Descoberta de Concorrentes** - Dominios competindo pelas mesmas keywords:
```bash
curl -s "https://api.semrush.com/?type=domain_organic_organic&key=${SEMRUSH_API_KEY}&domain={dominio}&database=us&export_columns=Dn,Cr,Np,Or,Ot,Oc&display_limit=20"
```
Colunas: Dn=Dominio, Cr=Nivel de Competicao, Np=Keywords em Comum, Or=Keywords Organicas, Ot=Trafego Organico, Oc=Custo Organico.

**Keyword Gap** - Keywords em que concorrentes rankeiam e voce nao:
```bash
curl -s "https://api.semrush.com/?type=domain_domains&key=${SEMRUSH_API_KEY}&domains=*|or|{seu_dominio}|*|or|{concorrente1}|*|or|{concorrente2}&database=us&export_columns=Ph,P0,P1,P2,Nq,Cp&display_limit=50&display_filter=%2B|P0|Eq|0"
```
O filtro `+|P0|Eq|0` retorna keywords em que o seu dominio (posicao 0) nao rankeia.

### SerpAPI (se SERPAPI_API_KEY disponivel)

**Analise Competitiva de SERP** - Quem rankeia para os termos-chave em tempo real:
```bash
curl -s "https://serpapi.com/search.json?q={keyword}&api_key=${SERPAPI_API_KEY}&num=20&gl=us&hl=en"
```
Use para:
- Identificar quais concorrentes dominam os resultados organicos das keywords-alvo (parsear `organic_results`)
- Extrair copy de anuncios de concorrentes dos campos `ads` e `shopping_results`
- Descobrir keywords relacionadas dos concorrentes via `related_searches`
- Ver presenca dos concorrentes em recursos de SERP: `knowledge_graph`, `local_results`, `featured_snippet`

> Contexto BR: para buscas no mercado brasileiro, use `gl=br&hl=pt-br` - o SERP muda muito entre paises.

**Analise de Google Ads de Concorrentes:**
```bash
curl -s "https://serpapi.com/search.json?q={keyword_comercial}&api_key=${SERPAPI_API_KEY}&gl=us&hl=en"
```
O array `ads` da resposta contem: `position`, `title`, `link`, `displayed_link`, `tracking_link`, `description`, `sitelinks`. Isso revela copy de anuncio, landing pages e mensagem dos concorrentes.

### ScrapingBee (se SCRAPINGBEE_API_KEY disponivel)

Use ScrapingBee para raspar paginas de concorrentes que bloqueiam fetch direto via WebFetch (paginas pesadas em JavaScript, sites com protecao anti-bot, paginas de preco):
```bash
curl -s "https://app.scrapingbee.com/api/v1/?api_key=${SCRAPINGBEE_API_KEY}&url={url}&render_js=false"
```
Defina `render_js=true` se a pagina exige renderizacao de JavaScript (SPAs, tabelas de preco dinamicas). Util para:
- Extrair detalhes da pagina de preco quando o WebFetch retorna conteudo incompleto
- Raspar landing pages de concorrentes para analise de mensagem e posicionamento
- Capturar paginas de comparacao de features de concorrentes
- Obter conteudo de sites que bloqueiam requisicoes automatizadas

**Nota:** ScrapingBee cobra por requisicao. Use com parcimonia - tente WebFetch primeiro e recorra ao ScrapingBee so quando necessario.

---

## Passo 1: Levantar Contexto

Estabeleca: produto do cliente, industria/vertical, publico-alvo, concorrentes conhecidos, preocupacoes principais (preco, features, marketing), ferramentas disponiveis (SEMrush, Ahrefs, SimilarWeb), objetivo (estrategia, decisao de lancamento, deck para investidor, reposicionamento).

## Passo 2: Identificacao de Concorrentes

### Tres Categorias

- **Diretos** (mesmo produto, mesmo publico): 3-5 concorrentes
- **Indiretos** (produto diferente, mesmo problema): 2-3 concorrentes
- **Aspiracionais** (lideres de mercado para aprender): 1-2 concorrentes

### Metodos de Descoberta

Buscar "[categoria]" no Google (anuncios + top 10 organico), paginas "Compare" do G2/Capterra, Reddit/Twitter "[concorrente] alternative", entrevistas com clientes, vagas de emprego, anuncios de captacao, relatorio "Competing Domains" do SEMrush.

> Contexto BR: G2/Capterra tem cobertura fraca de SaaS brasileiro. Complemente com Reclame Aqui (reclamacoes reais), B2B Stack, comunidades BR (grupos de WhatsApp/Telegram do nicho, comunidades no Discord, LinkedIn BR) e portais de vagas locais (Gupy, Programathor).

## Passo 3: Analise de SEO

Se `SEMRUSH_API_KEY` estiver disponivel, use os endpoints de Visao Geral de Dominio e Keywords Organicas (ver Integracoes opcionais acima) para preencher o perfil abaixo com dados reais. Se `SERPAPI_API_KEY` estiver disponivel, complemente com posicoes de SERP em tempo real. Caso contrario, use busca web e ferramentas publicas para estimar - e marque estimativas como [INFERIDO].

Para cada concorrente:

```
PERFIL SEO DO CONCORRENTE: [Empresa]
DA/DR: [nota] | Trafego Organico Mensal: [volume] | Keywords Rankeando: [total]

TOP KEYWORDS: [keyword, posicao, volume, fatia de trafego]

ESTRATEGIA DE CONTEUDO:
  Frequencia de posts, tamanho medio, tipos de conteudo, top 5 URLs de melhor desempenho

PERFIL DE BACKLINKS:
  Total de backlinks, dominios referenciadores, top dominios que linkam, ritmo de aquisicao

TECNICO: Velocidade do site, otimizacao mobile, schema markup, arquitetura
```

### Checagem de Realidade da Fonte de Trafego (faca ANTES de confiar nos numeros)

Uma manchete tipo "74% organico" NAO significa que o concorrente esta ganhando em descoberta via SEO. A maioria das ferramentas reporta o *ultimo clique*, o que esconde onde a consciencia de marca foi realmente criada. Decomponha antes de tirar conclusoes:

1. **Busca de marca vs busca generica.** Marque toda keyword que contem o nome da marca (normalize espacos/pontos para que `auto ppt` case com `autoppt`). Busca de marca = gente que *ja conhece o nome* voltando, nao o Google descobrindo o produto.
2. **Balde navegacional = busca de marca + trafego Direto.** Trate como um so: audiencia existente retornando, nao aquisicao nova.
3. **Busca genuinamente aquisitiva = organico nao-marca** (termos genericos, termos de marca de concorrentes, conteudo how-to). Essa e a unica fatia que e de fato descoberta via SEO - dimensione explicitamente.
4. **Reconcilie suas ferramentas.** Um total grande no SimilarWeb (funil inteiro) vs estimativa organica pequena no Ahrefs/SemRush significa muita cauda longa nao rastreada (frequentemente fora do ingles). Top-paises diferentes entre ferramentas = a descoberta acontece onde os usuarios *estao*, nao onde os rankings sao rastreados.
5. **Cheque se os usuarios sao reais.** Taxa de rejeicao, paginas/visita, tempo no site. Trafego de bot/incentivado aparece como ~100% de rejeicao, 1 pagina, poucos segundos.

**Impressao digital de canal -> ache o topo de funil real.** Diagnostico-chave: *quando busca de marca + direto dominam mas nenhum canal de aquisicao de ultimo clique e grande, o motor de descoberta esta a montante e invisivel para essas ferramentas.*

| Impressao digital | Motor real de crescimento |
|---|---|
| Busca de marca alta + direto alto, mas social/referral/pago todos pequenos | Fora do ultimo clique: video curto (TikTok/Reels/Shorts), apps de mensagem, boca a boca - apaga o referrer e reaparece depois como busca de marca + direto |
| Organico nao-marca alto, blog profundo/cauda longa | Motor genuino de conteudo SEO (editorial ou programatico) |
| Rankeia nos nomes de marca dos rivais (`<rival> alternative`, `<rival> pricing`) | SEO deliberado de interceptacao de concorrente |
| Referrals altos concentrados em poucos dominios | Parcerias / diretorios / afiliados / integracoes |
| Pago + display altos | Aquisicao paga (verificar se e lucrativa para o nicho) |
| Canal de referral genAI nao trivial e crescendo | Trafego de citacao por LLM (ChatGPT/Perplexity) |

> Contexto BR: no Brasil o balde "apps de mensagem" pesa ainda mais - WhatsApp e canal dominante de boca a boca e apaga o referrer por completo. Considere tambem Kwai alem de TikTok/Reels/Shorts.

**Confirme, nao afirme:** busque a marca no YouTube/TikTok procurando onda viral; verifique se o crescimento da busca de marca *veio depois* de um pico social; nomeie os top referrers reais; leia para quem o conteudo e escrito; deixe os top paises revelarem a comunidade. So entao escreva o veredito de "como eles realmente crescem".

### Analise de Gaps

- **Gaps de keyword**: Keywords em que concorrentes rankeiam e voce nao
- **Gaps de conteudo**: Topicos que concorrentes cobrem e voce nao
- **Gaps de backlink**: Dominios que linkam para concorrentes mas nao para voce

## Passo 4: Analise de Midia Paga

```
PERFIL DE ANUNCIOS DO CONCORRENTE: [Empresa]
Gasto Mensal Est.: [faixa] | Plataformas: [lista] | Anuncios Ativos: [contagem]

GOOGLE ADS: Top keywords, temas de copy, landing pages, extensoes
META ADS: Contagem de anuncios (via Biblioteca de Anuncios), formatos, tempo rodando, temas criativos
LINKEDIN ADS (B2B): Formatos, sinais de segmentacao, temas de conteudo
```

**Perguntas-chave**: Em quais keywords o lance e mais agressivo? Para quais landing pages os anuncios apontam (revela as melhores ofertas)? Ha quanto tempo os top anuncios rodam (muito tempo = lucrativo)? Rodam retargeting?

> Contexto BR: a Biblioteca de Anuncios da Meta funciona normalmente para anunciantes BR (filtre pais = Brasil). Avalie tambem canais fortes localmente: anuncios em WhatsApp/Instagram (click-to-WhatsApp) e influenciadores de nicho.

## Passo 5: Analise de Redes Sociais

```
| Plataforma | Seguidores | Frequencia | Engajamento Medio | Tipo de Conteudo Top |
|------------|-----------|------------|-------------------|----------------------|
| Twitter/X | ... | ... | ... | ... |
| LinkedIn | ... | ... | ... | ... |
| Instagram | ... | ... | ... | ... |
| YouTube | ... | ... | ... | ... |

TEMAS DE CONTEUDO: [tema, nivel de engajamento] x3
TOP POSTS (ultimos 90 dias): [plataforma, descricao, metricas]
COMUNIDADE: Tempo de resposta, tom, UGC, espacos de comunidade
```

> Contexto BR: pese as plataformas pelo mercado local - Instagram e WhatsApp dominam no Brasil; Twitter/X pesa menos que nos US para B2C. Inclua TikTok/Kwai quando o publico for consumidor.

## Passo 6: Email e Lifecycle Marketing

Inscreva-se na lista, no trial e na newsletter de cada concorrente. Rastreie:

- **Newsletter**: Frequencia, tipo de conteudo, estilo de assunto, personalizacao
- **Sequencia de onboarding**: Quebra dia a dia com assunto, proposito, CTA
- **Promocoes**: Frequencia de desconto, campanhas sazonais, taticas de urgencia
- **Retencao**: Emails de prevencao de churn, campanhas de reengajamento

> Contexto BR: observe tambem fluxos por WhatsApp - no Brasil muito lifecycle (onboarding, cobranca, reativacao) roda por mensagem, nao por email. Datas sazonais locais: Black Friday BR, Dia do Consumidor, datas de comercio locais.

## Passo 7: Preco e Posicionamento

### Comparacao de Precos

```
| Feature/Plano | Voce | Conc A | Conc B | Conc C |
|---------------|------|--------|--------|--------|
| Tier Gratuito | ... | ... | ... | ... |
| Starter | ... | ... | ... | ... |
| Pro | ... | ... | ... | ... |
| Enterprise | ... | ... | ... | ... |
```

Anote tipo de modelo, opcoes de cobranca, add-ons, descontos, ancoragem de preco.

> Contexto BR: registre a moeda de cobranca (BRL vs USD) e parcelamento - preco em dolar sem opcao local e uma fraqueza exploravel de concorrentes gringos no Brasil.

### Mapa de Posicionamento

Crie um mapa 2x2 nas duas dimensoes mais importantes (ex.: Preco vs Simplicidade). Identifique espacos em branco de oportunidade.

### Extracao de Mensagem

Para cada um: tagline, proposta de valor, diferencial-chave, persona-alvo, tom, principais provas.

## Passo 8: Analise SWOT

Para cada concorrente principal:

```
FORCAS: [com evidencia]
FRAQUEZAS: [com evidencia de reviews, reclamacoes, gaps de feature]
OPORTUNIDADES: [tendencias de mercado a favor deles]
AMEACAS: [suas vantagens ou mudancas de mercado contra eles]
```

**Fontes de fraqueza**: Reviews 1-2 estrelas no G2/Capterra, reclamacoes no Reddit/Twitter, Glassdoor, Down Detector, gaps em comparacoes de feature, foruns de suporte.

> Contexto BR: adicione Reclame Aqui (a fonte mais rica de fraqueza no Brasil), reviews da Google Play/App Store BR e Glassdoor BR.

## Passo 9: Matriz Competitiva

```
| Dimensao | Voce | Conc A | Conc B | Conc C |
|----------|------|--------|--------|--------|
| Fundacao | ... | ... | ... | ... |
| Captacao/Receita | ... | ... | ... | ... |
| Mercado-Alvo | ... | ... | ... | ... |
| Preco de Entrada | ... | ... | ... | ... |
| Diferencial-Chave | ... | ... | ... | ... |
| DA | ... | ... | ... | ... |
| Trafego Mensal | ... | ... | ... | ... |
| Nota no G2 | ... | ... | ... | ... |
| Feature 1-3 | S/N | S/N | S/N | S/N |
```

> Contexto BR: se o G2 nao cobrir o concorrente, use nota do Reclame Aqui ou das lojas de app como proxy de satisfacao - e diga qual proxy usou.

## Passo 10: Recomendacoes Estrategicas

```
RECOMENDACOES ESTRATEGICAS
==========================
1. POSICIONAMENTO: Posicao atual vs recomendada, mensagem-chave, diferenciacao
2. CONTEUDO: Keywords prioritarias, tipos de conteudo, topicos para dominar
3. PAGO: Keywords que concorrentes ignoram, angulos de anuncio, prioridade de canais
4. PRODUTO: Features a construir (a partir dos gaps), features a despriorizar
5. PRECO: Ajustes, oportunidades de empacotamento
6. QUICK WINS: 3 acoes para implementar esta semana
```

Fundamente cada recomendacao em dados especificos de concorrentes ([MEDIDO fonte] ou [INFERIDO]). Priorize por impacto e facilidade de implementacao.
