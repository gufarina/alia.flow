---
name: write-blog
description: Gera um post de blog completo e otimizado para SEO, seguindo E-E-A-T, com outline, meta tags, FAQ e checklist de qualidade. A Alia dispara quando o Job pede conteudo de blog, artigo SEO ou texto para ranquear uma palavra-chave de um Cliente.
trigger: post de blog, artigo, escrever sobre, conteudo SEO, artigo SEO, blog, texto para ranquear, palavra-chave
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/write-blog
wave: 2
---

# Skill: Escrever Post de Blog

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa por conta propria.
2. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Sem Task registrada, registrar primeiro e so depois executar.
3. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada.
4. Grounding bloqueante: todo numero e afirmacao de peso cita fonte LIDA como [MEDIDO fonte] ou sai marcado [INFERIDO]. Nunca fabricar metrica, estatistica ou citacao no post.
5. Contexto BR: escrever para o publico do Cliente da Task; referencias US viram equivalentes locais quando existirem.

Nota de idioma: este arquivo de skill segue a regra do motor (portugues sem acentos, sem emojis). O CONTEUDO FINAL que a skill produz - o post de blog entregue ao Cliente - PODE e DEVE usar acentuacao normal do portugues do Brasil.

## Papel

Voce e um redator especialista em conteudo SEO. Crie posts de blog abrangentes, bem pesquisados e otimizados tanto para mecanismos de busca quanto para leitores. Siga o framework E-E-A-T (Experience, Expertise, Authoritativeness, Trustworthiness - experiencia, especializacao, autoridade e confiabilidade).

## Processo de Escrita do Blog

### Passo 1: Pesquisa e Briefing

Antes de escrever uma unica palavra, colete inteligencia:

**1A. Entenda a palavra-chave**
Pergunte ou infira (priorize o que ja esta na Task/Projeto do Cliente):
- **Palavra-chave alvo:** palavra-chave primaria para ranquear
- **Palavras-chave secundarias:** 3-5 termos relacionados para incluir naturalmente
- **Intencao de busca:** o que o buscador quer? (Resposta, comparacao, tutorial, lista)
- **Publico-alvo:** quem le isto? (Iniciante/intermediario/especialista, cargo, setor) - puxar do perfil do Cliente da Task
- **Objetivo de negocio:** o que o leitor deve fazer depois? (Cadastrar, comprar, compartilhar, aprender)

**1B. Obtenha dados de palavra-chave (se a API do SemRush estiver disponivel)**

Se `SEMRUSH_API_KEY` estiver definida, puxe metricas reais de palavra-chave para informar a estrategia de conteudo:

```bash
# Obter dados da palavra-chave alvo (usar database=br para o mercado brasileiro)
curl -s "https://api.semrush.com/?type=phrase_all&key=${SEMRUSH_API_KEY}&phrase={palavra-chave}&database=br&export_columns=Ph,Nq,Cp,Co,Nr"
```

A resposta e delimitada por ponto-e-virgula com as colunas:
- **Ph** - Frase da palavra-chave
- **Nq** - Volume mensal de busca (use para calibrar profundidade: volume maior = artigo mais abrangente)
- **Cp** - CPC em dolares (CPC alto sinaliza forte intencao comercial - enfatize CTAs e mencoes de produto)
- **Co** - Indice de competicao 0-1 (competicao alta exige sinais E-E-A-T mais fortes)
- **Nr** - Numero de resultados organicos (mais resultados = SERP mais competitiva)

Use esses insights para:
- **Calibrar contagem de palavras:** palavras-chave com volume >5.000 costumam pedir artigos de 2.500+ palavras
- **Ajustar angulo comercial:** CPC > $5 indica intencao de compra - inclua recomendacoes de produto, comparacoes ou precos
- **Identificar dificuldade:** competicao > 0.8 exige mais links externos, pesquisa original e citacoes de especialistas

Todo dado puxado da API entra no post citado como [MEDIDO SemRush database=br data-da-consulta]. Sem API, estimativas saem marcadas [INFERIDO].

**1C. Analise a SERP (se as ferramentas estiverem disponiveis)**
Use WebSearch para verificar o que ranqueia atualmente (busca em portugues, no Google BR):
- Que tipo de conteudo domina? (Listicle, como-fazer, guia, comparacao)
- Qual a contagem media de palavras do top 5?
- Que topicos todos os resultados do topo cobrem?
- O que falta no conteudo existente?

**1D. Construa o outline a partir da inteligencia da SERP**
Seu outline deve cobrir tudo que os resultados do topo cobrem, mais secoes unicas que eles nao trazem.

### Passo 2: Crie o Outline

Monte um outline detalhado antes de escrever. Todo post segue esta estrutura mestra:

```markdown
# [H1: Titulo - inclui palavra-chave primaria, atraente, 50-60 caracteres para a title tag]

Meta Titulo: [50-60 caracteres, palavra-chave primaria no inicio]
Meta Descricao: [150-160 caracteres, inclui palavra-chave, tem CTA, gera curiosidade]
Slug da URL: [palavra-chave-primaria-curta-descritiva]

## Introducao (100-150 palavras)
- Gancho: abra com estatistica surpreendente, pergunta ou problema com que o leitor se identifica
- Contexto: por que este tema importa AGORA
- Promessa: o que o leitor vai aprender/ganhar
- Palavra-chave primaria aparece nas primeiras 100 palavras

## [H2: Primeira secao principal - inclui palavra-chave secundaria]
### [H3: Subsecao se necessario]
- Pontos-chave a cobrir
- Dados ou exemplos a incluir

## [H2: Segunda secao principal]
### [H3: Subsecao]
...

## [H2: Secao pratica/acionavel]
(Passos como-fazer, templates, checklists, frameworks)

## [H2: Dicas de especialista / Secao avancada]
(Conteudo diferenciador - o que os concorrentes nao cobrem)

## [H2: Erros comuns / O que evitar]
(Responde perguntas do "As pessoas tambem perguntam")

## [H2: FAQ]
### [H3: Pergunta 1?]
Resposta (2-4 frases, mira o featured snippet)
### [H3: Pergunta 2?]
...

## Conclusao (100-150 palavras)
- Resuma os aprendizados-chave (3-5 bullets)
- Reafirme o valor principal entregue
- CTA claro: o que o leitor deve fazer a seguir?

## Plano de Links Internos
- Linkar PARA: [3-5 paginas relacionadas do site]
- Linkar DE: [paginas que deveriam apontar para este post]
```

### Passo 3: Escreva o Conteudo

Siga estas regras de escrita a risca:

#### Formula da Title Tag (50-60 caracteres)

Escolha o melhor padrao para a intencao:

| Intencao | Formula | Exemplo |
|----------|---------|---------|
| Como-fazer | "Como {Acao} ({Qualificador})" | "Como Criar um Blog (Guia Passo a Passo)" |
| Listicle | "{Numero} {Adjetivo} {Topico} para {Ano/Publico}" | "15 Melhores Ferramentas de SEO para Pequenas Empresas (2026)" |
| Guia | "{Topico}: O Guia {Adjetivo} para {Ano}" | "Email Marketing: O Guia Completo para 2026" |
| Comparacao | "{A} vs {B}: {Diferenciador}" | "Notion vs Obsidian: Qual e Melhor para Equipes?" |
| Pergunta | "{Pergunta}? {Promessa}" | "SEO Morreu? O Que os Dados Realmente Mostram" |

**Regras de titulo:**
- Palavra-chave primaria nos primeiros 30 caracteres
- Adicione uma power word: Definitivo, Completo, Comprovado, Essencial
- Inclua o ano se o tema for sensivel ao tempo
- Use numeros em listicles (numeros impares performam melhor: 7, 9, 11, 13)
- Nunca passe de 60 caracteres (o Google trunca em ~580px)

#### Formula da Meta Descricao (150-160 caracteres)

```
{O que o artigo cobre} + {Proposta de valor unica} + {CTA ou gancho de curiosidade}
```

Exemplos:
- "Aprenda a criar um blog em 2026 com nosso guia passo a passo. Cobre hospedagem, design, conteudo e monetizacao. Checklist gratuito incluso."
- "Testamos 15 ferramentas de SEO e ranqueamos por recursos, preco e facilidade de uso. Veja qual e a melhor para seu orcamento e objetivos."

**Regras de meta descricao:**
- Inclua a palavra-chave primaria naturalmente
- Inclua um CTA ou elemento de curiosidade
- Use voz ativa
- Mencione uma entrega especifica (checklist, template, comparacao, passos)
- Fique entre 150-160 caracteres

#### Regras de Estilo de Escrita

**Legibilidade:**
- Paragrafos: no maximo 2-4 frases
- Frases: media de 15-20 palavras
- Use frases curtas para enfase. Assim.
- Nivel de leitura acessivel (equivalente a 7o-9o ano do ensino fundamental)
- Use "voce" e "seu" - escreva PARA o leitor
- Voz ativa > voz passiva (mire 90%+ ativa)

**Estrutura e escaneabilidade:**
- H2 a cada 200-300 palavras
- H3 para subsecoes dentro de H2s
- Bullets para listas de 3+ itens
- Listas numeradas para passos sequenciais
- Negrito em termos-chave e conclusoes
- Citacoes destacadas ou caixas de destaque para insights-chave
- Tabelas para comparacoes (o Google adora tabelas para featured snippets)

**Integracao de SEO (natural, nao forcada):**
- Palavra-chave primaria em: H1, primeiras 100 palavras, 1-2 H2s, conclusao, alt text
- Densidade da palavra-chave primaria: 0.5-1.5% (aprox. a cada 200 palavras num post de 2.000)
- Palavras-chave secundarias: cada uma aparece 2-3 vezes ao longo do texto
- Termos LSI/relacionados: espalhe naturalmente
- Nunca faca keyword stuffing - se soa artificial, reescreva

**Sinais E-E-A-T:**
- **Experiencia:** inclua observacoes de primeira mao, "Na minha experiencia...", "Quando testei..." (somente se houver experiencia real registrada do Cliente; caso contrario, marque [INFERIDO] ou corte)
- **Especializacao:** referencie metodologias especificas, use terminologia precisa, demonstre conhecimento profundo
- **Autoridade:** cite fontes autorizadas (estudos, documentacao oficial, lideres do setor)
- **Confiabilidade:** reconheca limitacoes, apresente visoes equilibradas, linke as fontes

#### Metas de Profundidade de Conteudo

| Tipo de artigo | Palavras alvo | Secoes (H2) | Imagens | Links internos | Links externos |
|----------------|---------------|-------------|---------|----------------|----------------|
| Guia como-fazer | 2000-3000 | 6-10 | 5-10 | 5-8 | 3-5 |
| Listicle | 2500-4000 | 1 por item + intro/conclusao | 1 por item | 5-10 | 3-5 |
| Guia definitivo | 3000-5000 | 8-15 | 8-15 | 8-12 | 5-8 |
| Comparacao | 1500-2500 | 5-8 | 3-5 | 3-5 | 2-4 |
| Opiniao/analise | 1000-1500 | 4-6 | 2-3 | 3-5 | 2-3 |
| Noticia/atualizacao | 800-1200 | 3-5 | 1-3 | 3-5 | 3-5 |

### Passo 4: Otimize para Featured Snippets

Mire featured snippets com estes padroes:

**Snippet de paragrafo (definicao/o que e):**
```markdown
## O Que E {Topico}?

{Topico} e {definicao clara de 40-60 palavras que responde diretamente a pergunta}.
{Contexto adicional em mais 1-2 frases}.
```

**Snippet de lista (como-fazer/melhores de):**
```markdown
## Como {Acao}

1. **{Titulo do passo 1}** - Descricao breve
2. **{Titulo do passo 2}** - Descricao breve
3. **{Titulo do passo 3}** - Descricao breve
...
```

**Snippet de tabela (comparacao/dados):**
```markdown
## {Topico da comparacao}

| {Coluna 1} | {Coluna 2} | {Coluna 3} |
|------------|------------|------------|
| {Dado} | {Dado} | {Dado} |
```

### Passo 5: Adicione Elementos de Apoio

**Sugestoes de imagem:**
Para cada secao principal, sugira uma imagem:
```markdown
[IMAGEM: {Descricao do que a imagem deve mostrar}]
Alt text: "{Alt text descritivo com a palavra-chave onde for natural}"
```

**Tipos de imagem a sugerir:**
- Imagem hero (imagem destacada para compartilhamento social)
- Screenshots (para tutoriais)
- Tabelas de comparacao (como imagens para Pinterest)
- Infograficos (para dados-chave)
- Diagramas de processo (para conteudo passo a passo)
- Graficos (para afirmacoes baseadas em dados)

**Buscar imagem destacada no Unsplash (se UNSPLASH_CLIENT_ID estiver disponivel):**

Use a API do Unsplash para encontrar imagens destacadas de alta qualidade e livres de royalties:

```bash
# Buscar no Unsplash uma imagem destacada relevante
curl -s "https://api.unsplash.com/search/photos?query={topico}&per_page=5&orientation=landscape" \
  -H "Authorization: Client-ID ${UNSPLASH_CLIENT_ID}"
```

**Interpretando a resposta:**

O JSON de resposta contem um array `results`. Para cada foto, extraia:

```bash
# Interpretar com jq para obter URLs, dados do fotografo e links de download
curl -s "https://api.unsplash.com/search/photos?query={topico}&per_page=5&orientation=landscape" \
  -H "Authorization: Client-ID ${UNSPLASH_CLIENT_ID}" | \
  jq -r '.results[] | {
    id: .id,
    description: .description,
    image_url: .urls.regular,
    full_url: .urls.full,
    download_link: .links.download,
    photographer_name: .user.name,
    photographer_url: .user.links.html,
    unsplash_url: .links.html
  }'
```

Campos-chave da resposta:
- **`.urls.regular`** - Imagem otimizada (1080px de largura, boa para imagem destacada de blog)
- **`.urls.full`** - Imagem em resolucao total
- **`.urls.small`** - Miniatura (400px de largura, boa para previews de compartilhamento social)
- **`.links.download`** - Aciona um download (o Unsplash rastreia isso para as estatisticas do fotografo)
- **`.user.name`** - Nome do fotografo (obrigatorio para atribuicao)
- **`.user.links.html`** - URL do perfil do fotografo no Unsplash

**Exigencia de atribuicao do Unsplash:**

O Unsplash exige atribuicao sempre que voce usa uma foto. Inclua no post:

```markdown
Foto de [Nome do Fotografo](https://unsplash.com/@username?utm_source=your_app&utm_medium=referral) no [Unsplash](https://unsplash.com/?utm_source=your_app&utm_medium=referral)
```

Coloque a atribuicao em um destes lugares:
- Na legenda da imagem, logo abaixo da imagem destacada
- Em uma secao de creditos de imagem no fim do post
- No alt text ou atributo title da tag da imagem

**Dica:** busque com consultas especificas e descritivas em vez de termos amplos. Por exemplo, use "remote team video call" em vez de "business" (a busca do Unsplash funciona melhor em ingles). Tambem da para filtrar por `color`, `content_filter` (low/high) e `order_by` (relevant/latest).

**Posicionamento de links internos:**
- Links contextuais dentro dos paragrafos do corpo (os mais valiosos)
- Caixas "Leitura relacionada" entre secoes
- Secao "Para ler depois" no final
- Anchor text deve ser descritivo, nunca "clique aqui"

**Regras de links externos:**
- Linke fontes autorizadas (estudos, documentacao oficial, .edu, .gov, .gov.br, orgaos e institutos brasileiros como IBGE quando o dado for local)
- Abra links externos em nova aba
- No-follow em links de afiliado e conteudo patrocinado
- Cite estatisticas com fontes linkadas (e no fluxo Alia: fonte LIDA = [MEDIDO fonte]; sem fonte lida, [INFERIDO] ou corta o numero)

### Passo 6: Secao de FAQ

Todo post deve terminar com uma secao de FAQ mirando o "As pessoas tambem perguntam":

```markdown
## Perguntas Frequentes

### {Pergunta que casa com PAA ou palavra-chave de cauda longa}?

{Resposta direta em 2-4 frases. Comece pela resposta.
Contexto adicional depois da resposta direta.
Este formato otimiza para featured snippets e para rich results de FAQ.}

### {Segunda pergunta}?

{Resposta}
```

**Regras de FAQ:**
- 4-6 perguntas
- Perguntas em linguagem natural (como, o que, por que, quando, pode, funciona)
- Responda a pergunta na primeira frase
- Mantenha cada resposta abaixo de 100 palavras
- Inclua schema markup (ver skill schema-markup, se disponivel na instancia)

### Passo 7: Checagem Final de Qualidade

Antes de entregar o post, verifique (este e o pre-check antes do Artifact passar no quality-gate):

**Checklist de SEO:**
- [ ] Title tag: 50-60 caracteres, palavra-chave no inicio
- [ ] Meta descricao: 150-160 caracteres, inclui palavra-chave, tem CTA
- [ ] Slug da URL: curto, inclui palavra-chave, com hifens
- [ ] H1: um por pagina, inclui a palavra-chave primaria
- [ ] H2s: incluem palavras-chave secundarias onde for natural
- [ ] Palavra-chave primaria nas primeiras 100 palavras
- [ ] Densidade de palavra-chave: 0.5-1.5%
- [ ] Links internos: 5+ links contextuais
- [ ] Links externos: 3+ fontes autorizadas
- [ ] Imagens: alt text em todas, palavra-chave em pelo menos uma
- [ ] Secao de FAQ com 4-6 perguntas
- [ ] Contagem de palavras atinge a meta do tipo de conteudo
- [ ] Sem conteudo duplicado nem secoes rasas

**Checklist de legibilidade:**
- [ ] Paragrafo medio: 2-4 frases
- [ ] Frase media: abaixo de 20 palavras
- [ ] Nivel de leitura acessivel
- [ ] Voz ativa: 90%+
- [ ] Power words nos subtitulos
- [ ] Bullets ou listas numeradas a cada 300 palavras
- [ ] Negrito destacando pontos-chave

**Checklist E-E-A-T:**
- [ ] Byline de autor com credenciais sugerida
- [ ] Fontes citadas e linkadas
- [ ] Experiencia de primeira mao ou especializacao demonstrada
- [ ] Perspectiva equilibrada (pros e contras, nao so hype)
- [ ] Data de publicacao e data de "ultima atualizacao" incluidas
- [ ] Precisao factual verificada (nenhuma estatistica inventada; cada numero com [MEDIDO fonte] ou [INFERIDO])

## Formato de Saida

Entregue o post neste formato (o conteudo do post em portugues normal, COM acentos):

```markdown
---
title: "{Meta titulo - 50-60 caracteres}"
description: "{Meta descricao - 150-160 caracteres}"
slug: "{url-slug}"
keywords: ["{primaria}", "{secundaria1}", "{secundaria2}"]
date: "{AAAA-MM-DD}"
author: "{Nome do autor}"
---

# {Headline H1}

{Conteudo completo do artigo com toda a formatacao, links e placeholders de imagem}
```

Depois do artigo, forneca:
1. **Resumo de metadados SEO** (titulo, descricao, slug, contagem de palavras)
2. **Recomendacoes de linkagem interna** (quais paginas linkar de/para)
3. **Schema markup** (JSON-LD de Article ou BlogPosting)
4. **Compartilhamento social** (sugestao de titulo OG, descricao e conceito de imagem)
5. **Ideias de promocao do conteudo** (2-3 canais de distribuicao e angulos)

## Notas Importantes

- Nunca fabrique estatisticas. Ao citar um numero, inclua a fonte lida como [MEDIDO fonte] ou marque [INFERIDO] / "[Fonte necessaria]".
- Escreva para humanos primeiro, mecanismos de busca depois. Se uma tatica de SEO piora o conteudo para o leitor, pule-a.
- Toda secao deve entregar valor. Sem paragrafos de enchimento. Se uma secao nao ensina, convence ou entretem, corte.
- Siga a voz de marca do Cliente da Task se estiver registrada no Projeto. Se nao estiver clara, registre a duvida na Task antes de assumir.
- Se o tema for YMYL (saude, financas, juridico), redobre o cuidado com afirmacoes e cite fontes autorizadas com peso extra.
- Contexto BR: exemplos, precos, orgaos e datas devem falar com o publico brasileiro do Cliente; referencias US so ficam quando nao houver equivalente local.
