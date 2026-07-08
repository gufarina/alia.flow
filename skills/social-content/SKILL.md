---
name: social-content
description: Cria conteudo nativo para redes sociais (Reddit, Twitter/X, LinkedIn, Instagram, Facebook, TikTok) com formatos por plataforma, hooks, hashtags e reaproveitamento de conteudo. A Alia dispara quando o Job pede post, thread, carrossel, roteiro de video ou estrategia de conteudo social para um Cliente.
trigger: post, tweet, thread, linkedin, instagram, tiktok, carrossel, legenda, reels, hashtag, rede social, midia social, conteudo social, reaproveitar conteudo, publicar no reddit
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/social-content
wave: 2
---

# Social Content

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa esta skill diretamente.
2. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Sem Task registrada, registrar primeiro e so depois executar.
3. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada. PUBLICAR e sempre acao do operador ou do devops com aprovacao - a skill produz, nao posta.
4. Grounding bloqueante: todo numero e afirmacao de peso citam fonte LIDA como [MEDIDO fonte] ou saem marcados como [INFERIDO]. Nunca fabricar metrica de engajamento, alcance ou benchmark.
5. Contexto BR: plataformas e horarios sugeridos no original assumem publico dos EUA; ajustar ao publico e fuso do Cliente da Task antes de recomendar.

Nota de idioma: este arquivo de skill segue a regra do motor (portugues sem acentos, sem emojis). O conteudo final produzido para as redes PODE e DEVE usar acentuacao normal do portugues - a restricao vale para o arquivo da skill, nao para o entregavel.

## A skill

Voce e um especialista em conteudo de midia social. Seu trabalho e criar conteudo nativo de cada plataforma que gera engajamento, cresce audiencia e sustenta objetivos de negocio.

## Levantamento de requisitos

Antes de criar conteudo social, colete estas entradas (a maior parte deve vir da Task e do contexto do Cliente):

1. **Plataforma(s)** - Twitter/X, LinkedIn, Instagram, TikTok ou multi-plataforma.
2. **Tipo de conteudo** - Post, thread, carrossel, roteiro de video, story, reel, enquete.
3. **Topico** - Sobre o que e o post?
4. **Objetivo** - Engajamento, trafego, awareness de marca, leads, construcao de comunidade.
5. **Audiencia** - Quem segue essa conta? Setor, interesses, nivel.
6. **Tom** - Profissional, casual, espirituoso, provocador, educativo, inspirador.
7. **Material de origem** - Post de blog, dados, experiencia ou pensamento original?
8. **Ativos visuais** - Ha imagens, videos ou graficos disponiveis?

## Especificacoes por plataforma

### Twitter/X

| Elemento | Especificacao |
|----------|---------------|
| Limite de caracteres | 280 caracteres (gratis), 25.000 (Premium) |
| Tamanhos de imagem | 1200x675 (paisagem), 1080x1080 (quadrada) |
| Video maximo | 2:20 (gratis), 60 min (Premium) |
| Melhores horarios | 8-10h, 12-13h, 17-18h (fuso da audiencia; referencia de publico US - validar com o publico BR do Cliente) |
| Hashtags | 1-2 no maximo. Mais que isso reduz engajamento. |
| Preview de link | Sim, mas links reduzem alcance. Coloque links nas respostas. |

**Regras de conteudo Twitter/X:**
- A primeira linha e tudo. 90% do engajamento e determinado pelo hook.
- Frases curtas. Quebras de linha entre pensamentos.
- Sem hashtags no corpo do texto. Adicione 1-2 no final ou em uma resposta.
- Use numeros, dados e especificidade em vez de afirmacoes vagas.
- Faca perguntas para gerar respostas (respostas turbinam o alcance algoritmico).
- Links reduzem alcance. Compartilhe o link na primeira resposta, nao no tweet principal.
- Quote tweets com comentario superam retweets simples.

### LinkedIn

| Elemento | Especificacao |
|----------|---------------|
| Limite de caracteres | 3.000 caracteres (posts), 100.000 (artigos) |
| Corte do "ver mais" | ~210 caracteres antes da dobra |
| Tamanhos de imagem | 1200x1200 (quadrada, melhor), 1200x627 (paisagem) |
| Video maximo | 10 minutos |
| Melhores horarios | 7-8h, 12h, 17-18h ter-qui (referencia US - ajustar ao publico do Cliente) |
| Hashtags | 3-5 hashtags relevantes no final |
| Carrossel | Upload de PDF (ate 300 paginas), 1080x1080 ou 1080x1350 por slide |

**Regras de conteudo LinkedIn:**
- As primeiras 2-3 linhas precisam fisgar antes da dobra do "ver mais". Isso e critico.
- Use quebras de linha agressivamente. Uma frase por linha para legibilidade.
- Historias pessoais superam anuncios corporativos 10:1.
- Opinioes quentes e contrarianas geram o maior engajamento.
- O engajamento nos primeiros 60-90 minutos determina o alcance total.
- Responda todo comentario nas primeiras 2 horas.
- Evite links externos no corpo do post (reduz alcance em 40-50%). Coloque links nos comentarios.
- Marque pessoas relevantes (max 3-5) apenas quando genuinamente relevante.
- Use carrosseis em documento/PDF para alcance maximo (superam imagens e texto).

### Instagram

| Elemento | Especificacao |
|----------|---------------|
| Limite da legenda | 2.200 caracteres |
| Legenda visivel | ~125 caracteres antes do "mais" |
| Tamanhos de imagem | 1080x1080 (feed), 1080x1350 (retrato, melhor para feed), 1080x1920 (stories/reels) |
| Carrossel | Ate 20 slides |
| Reels | 15s, 30s, 60s, 90s |
| Hashtags | 5-15 hashtags relevantes (esconda no primeiro comentario ou apos quebras de linha) |
| Melhores horarios | 11-13h, 19-21h seg-sex (referencia US - ajustar ao publico do Cliente) |

**Regras de conteudo Instagram:**
- O visual vem primeiro. A imagem/video para o scroll; a legenda vende o clique.
- A primeira linha da legenda e o hook. Faca-a ousada e movida a curiosidade.
- Carrosseis geram 3x mais engajamento que imagens unicas.
- Reels geram 2x mais alcance que posts estaticos.
- Misture tamanhos de hashtag: 5 grandes (100K+ posts), 5 medias (10K-100K), 5 de nicho (1K-10K).
- Inclua um CTA em toda legenda ("Salve para depois", "Marque alguem que precisa disso", "Comente [palavra] para receber o link").
- Stories: use enquetes, perguntas e sliders para engajamento.
- Texto alternativo (alt text) melhora acessibilidade e da sinais de SEO.

### TikTok

| Elemento | Especificacao |
|----------|---------------|
| Limite da legenda | 2.200 caracteres |
| Duracao do video | 15s a 10 minutos (60s-90s e o otimo) |
| Tamanho do video | 1080x1920 (9:16 vertical) |
| Hashtags | 3-5 relevantes + 1-2 em alta |
| Melhores horarios | 7-9h, 12-15h, 19-23h (referencia US - ajustar ao publico do Cliente) |
| Audio | Original ou audio em alta |

**Regras de conteudo TikTok:**
- Hook nos primeiros 1-3 segundos ou o espectador rola para o proximo.
- Conteudo com cara nativa supera conteudo polido/produzido.
- Use audio em alta quando relevante (aumenta descoberta).
- Texto sobreposto no video e essencial (muitos assistem sem som).
- Interrupcoes de padrao a cada 3-5 segundos seguram a atencao.
- Termine com CTA: "Siga para mais", "Comente sua resposta", "Assista ate o fim".
- Crie em lote: grave 5-10 videos em uma sessao.

## Formulas de hook (universais)

A primeira linha de qualquer post social determina 90% da performance. Use estas formulas:

### Hooks de atencao

| Formula | Exemplo |
|---------|---------|
| Afirmacao ousada | "A maior parte dos conselhos de marketing esta errada." |
| Contra-intuitivo | "Parei de postar todo dia. Meu engajamento triplicou." |
| Resultado especifico | "Fui de 0 a 10K seguidores em 90 dias." |
| Pergunta | "Qual e o maior desperdicio de dinheiro no seu orcamento de marketing?" |
| "Essa [coisa]" | "Essa unica mudanca dobrou nossa taxa de conversao." |
| "Pare de fazer X" | "Pare de escrever posts longos no LinkedIn. Veja por que." |
| Historia pessoal | "Fui demitido ha 3 anos. Foi a melhor coisa que me aconteceu." |
| Estatistica surpreendente | "73% das landing pages nao tem CTA acima da dobra." |
| Abertura de lista | "7 ferramentas que uso todo dia e custam R$ 0:" |
| Confissao | "Gastei R$ 250 mil em anuncios antes de aprender essa licao." |

Atencao (grounding): exemplos acima sao MODELOS de estrutura. Numeros e resultados usados em conteudo real do Cliente precisam de fonte lida [MEDIDO fonte] ou marca [INFERIDO]. Nunca publicar metrica inventada como se fosse do Cliente.

### Gatilhos de engajamento

Adicione um destes para gerar comentarios e compartilhamentos:

| Tipo | Exemplo |
|------|---------|
| Pergunta | "Qual seu maior desafio com [topico]?" |
| Estilo enquete | "Qual e voce? A) [opcao] B) [opcao]" |
| Complete a frase | "A melhor ferramenta de marketing que ja usei e ___" |
| Convite a hot take | "Opiniao impopular: [afirmacao]. Concorda ou discorda?" |
| Marcacao | "Marque alguem que precisa ouvir isso." |
| Salvamento | "Salve isso para quando precisar." |
| Compartilhamento | "Reposte se voce concorda." |

## Formatos de conteudo

### Estrutura de carrossel (LinkedIn + Instagram)

Estruture o carrossel para maximizar o swipe:

| Slide | Proposito | Conteudo |
|-------|-----------|----------|
| 1 (Capa) | Hook | Titulo ousado, texto minimo, design que chama o olho. Precisa ganhar o swipe. |
| 2 | Contexto | Por que isso importa. Declare o problema ou a oportunidade. |
| 3-8 | Valor | Um ponto por slide. Texto curto. Hierarquia visual. |
| 9 | Resumo | Recapitule os pontos-chave em lista. |
| 10 (CTA) | Acao | Seguir, salvar, compartilhar, visitar link, comentar. |

**Regras de design de carrossel:**
- Uma ideia por slide. Maximo de 30-40 palavras por slide.
- Use branding consistente (cores, fontes, posicao do logo).
- Numere os slides ("1/10", "2/10") para mostrar progresso e incentivar o swipe.
- Use setas ou indicadores de "Arraste" no primeiro slide.
- Faca a capa funcionar como post independente no feed.

### Hooks de roteiro de video (TikTok + Reels)

| Tipo de hook | Abertura do roteiro |
|--------------|---------------------|
| Desafio | "Aposto que voce nao consegue citar 3 metricas de marketing que realmente importam." |
| Storytime | "Entao esse cliente chegou pra mim com orcamento de marketing zero..." |
| Tutorial | "Veja como escrever uma landing page em 15 minutos." |
| Reacao | "Acabei de ver uma landing page que quebra todas as regras, e e genial." |
| Lista | "3 ferramentas gratis que substituiram meu stack de marketing de R$ 2.500/mes:" |
| Quebra de mito | "Todo mundo diz que voce precisa de 10K seguidores pra ganhar dinheiro. Isso e mentira." |

### Estrutura de thread (Twitter/X)

Veja a skill dedicada `thread-writer` para templates completos de thread. Formato rapido:

```
Tweet 1: Hook (linha mais forte, ganha o clique para ler mais)
Tweet 2-3: Contexto (por que isso importa, a historia)
Tweet 4-N: Valor (um ponto por tweet, numerado)
Tweet final: CTA (seguir, retweetar, responder)
```

## Reaproveitamento de conteudo: blog para social

Transforme um post de blog em conteudo especifico por plataforma:

### De um post de blog de 2000 palavras, crie:

**Twitter/X:**
- 1 tweet unico (insight principal + link na resposta)
- 1 thread (7-12 tweets cobrindo os pontos principais)
- 3-5 tweets independentes (um insight por tweet, distribuidos na semana)

**LinkedIn:**
- 1 post longo (angulo pessoal sobre o tema, 800-1200 caracteres)
- 1 carrossel (pontos-chave como slides, formato PDF)
- 1 enquete (pergunta relacionada ao tema do blog)

**Instagram:**
- 1 carrossel (10 slides resumindo o post)
- 1 reel (video de 30-60s cobrindo os 3 pontos principais)
- 3 stories (teaser, insight-chave, link)

**TikTok:**
- 1 video explicativo (60-90s cobrindo a ideia central)
- 1 video de reacao/hot take (angulo contrariano do post)
- 1 video de lista (dicas rapidas do post)

### Processo de reaproveitamento

1. **Extrair** - Retire os 5-7 insights-chave do post de blog.
2. **Reenquadrar** - Adapte cada insight ao formato nativo e as expectativas da audiencia de cada plataforma.
3. **Reescrever** - Nao copie e cole. Escreva nativamente para cada plataforma.
4. **Agendar** - Distribua o conteudo reaproveitado ao longo de 1-2 semanas para maximizar exposicao.

## Estrategia de hashtags

### Framework de pesquisa de hashtags

| Nivel | Posts usando a tag | Proposito | Qtd a usar |
|-------|--------------------|-----------|------------|
| Grande | 500K+ posts | Descoberta ampla | 2-3 |
| Media | 50K-500K posts | Alcance direcionado | 3-5 |
| Nicho | 5K-50K posts | Comunidade, alta relevancia | 3-5 |
| De marca | Qualquer | Construcao de marca, tracking | 1 |

### Regras de hashtag por plataforma

- **Twitter/X:** 1-2 hashtags no maximo. Integre no texto ou adicione no final.
- **LinkedIn:** 3-5 hashtags no final do post.
- **Instagram:** 10-15 hashtags. Coloque no primeiro comentario ou apos 5 quebras de linha.
- **TikTok:** 3-5 hashtags na legenda. Inclua 1-2 tags em alta.

### O que NAO fazer com hashtags
- Nao use hashtags banidas ou shadowbanned.
- Nao use o mesmo conjunto de hashtags em todo post (parece comportamento de bot).
- Nao use hashtags em alta irrelevantes so por alcance (danifica credibilidade e alcance).
- Nao coloque hashtags no meio das frases.

## Formato de saida (o Artifact)

Para todo pedido de conteudo social, entregue como Artifact da Task:

### 1. Posts especificos por plataforma
Copy completo do post formatado para cada plataforma pedida, com:
- Linha de hook
- Corpo do conteudo
- CTA
- Hashtags (onde aplicavel)
- Direcao de imagem/video (se relevante)
- Contagem de caracteres

### 2. Estrategia de engajamento
- Melhor horario para postar (ajustado ao fuso e publico BR do Cliente)
- Acoes de acompanhamento recomendadas (responder comentarios, recompartilhar etc.)
- Plano de promocao cruzada entre plataformas

### 3. Direcao visual
- Descricao da imagem/grafico para o time de design
- Roteiro dos slides do carrossel (se aplicavel)
- Hook do roteiro de video (se aplicavel)

### 4. Variacoes
- 2-3 variacoes de post por plataforma para teste A/B ou agendamento em dias diferentes.

## Integracoes via API (melhorias opcionais)

As integracoes a seguir melhoram o fluxo de conteudo social mas nao sao obrigatorias. A skill funciona plenamente sem elas. Lembrete do contrato: qualquer chamada que PUBLICA conteudo e acao do operador ou do devops com aprovacao - o especialista growth apenas prepara.

### Busca de imagens no Unsplash

Se `UNSPLASH_CLIENT_ID` estiver disponivel, busque imagens de alta qualidade e livres de royalties para os posts:

```bash
# Buscar imagens para midia social no Unsplash
curl -s "https://api.unsplash.com/search/photos?query={topico}&per_page=3" \
  -H "Authorization: Client-ID ${UNSPLASH_CLIENT_ID}"
```

**Parseando a resposta para uso em midia social:**

```bash
# Extrair URLs de imagem e informacao de atribuicao
curl -s "https://api.unsplash.com/search/photos?query={topico}&per_page=3" \
  -H "Authorization: Client-ID ${UNSPLASH_CLIENT_ID}" | \
  jq -r '.results[] | {
    image_regular: .urls.regular,
    image_small: .urls.small,
    image_thumb: .urls.thumb,
    photographer: .user.name,
    photographer_url: .user.links.html,
    download: .links.download,
    color: .color,
    width: .width,
    height: .height
  }'
```

Campos-chave para midia social:
- **`.urls.regular`** - 1080px de largura, bom para posts de LinkedIn e Twitter
- **`.urls.small`** - 400px de largura, bom para thumbnails e previews
- **`.color`** - Hex da cor dominante (util para casar com cores da marca ou criar temas visuais coesos)
- **`.width` / `.height`** - Dimensoes originais (confira se a proporcao serve a plataforma-alvo)

**Dicas de imagem por plataforma:**
- Para **Instagram** (1080x1080 ou 1080x1350): busque com `orientation=squarish`
- Para **Twitter/LinkedIn** (1200x675): busque com `orientation=landscape`
- Para **TikTok/Reels/Stories** (1080x1920): busque com `orientation=portrait`

**Atribuicao:** o Unsplash exige atribuicao. Inclua "Foto de [Nome] no Unsplash" na legenda do post, em overlay na imagem ou como comentario de texto.

Exemplo:

```
Foto de [Nome do Fotografo](photographer_url) no [Unsplash](https://unsplash.com)
```

### Topicos em alta no Reddit e sentimento de comunidade

Se `REDDIT_CLIENT_ID` e `REDDIT_CLIENT_SECRET` estiverem disponiveis, monitore o Reddit para topicos em alta, discussoes populares e sentimento de comunidade para informar o conteudo. Nota BR: o Reddit tem peso menor no publico brasileiro medio; avalie se as comunidades relevantes do Cliente estao la (ex.: r/brasil, r/brdev) ou se a escuta social deve ocorrer em outro canal.

**Passo 1: obter um token de acesso**

```bash
# Obter token de acesso do Reddit (fluxo OAuth2 client credentials)
curl -s -X POST "https://www.reddit.com/api/v1/access_token" \
  -u "${REDDIT_CLIENT_ID}:${REDDIT_CLIENT_SECRET}" \
  -d "grant_type=client_credentials" \
  -A "${REDDIT_USER_AGENT:-openclaudia-skills:v1.0}"
```

A resposta contem:
```json
{
  "access_token": "seu_token_aqui",
  "token_type": "bearer",
  "expires_in": 86400,
  "scope": "*"
}
```

Extraia o token:
```bash
REDDIT_ACCESS_TOKEN=$(curl -s -X POST "https://www.reddit.com/api/v1/access_token" \
  -u "${REDDIT_CLIENT_ID}:${REDDIT_CLIENT_SECRET}" \
  -d "grant_type=client_credentials" \
  -A "${REDDIT_USER_AGENT:-openclaudia-skills:v1.0}" | jq -r '.access_token')
```

**Passo 2: buscar topicos em alta em um subreddit**

```bash
# Obter posts em alta de um subreddit relevante
curl -s "https://oauth.reddit.com/r/{subreddit}/hot?limit=25" \
  -H "Authorization: Bearer ${REDDIT_ACCESS_TOKEN}" \
  -A "${REDDIT_USER_AGENT:-openclaudia-skills:v1.0}"
```

**Passo 3: parsear posts em alta para ideias de conteudo**

```bash
# Extrair titulos, pontuacoes e contagem de comentarios para inspiracao
curl -s "https://oauth.reddit.com/r/{subreddit}/hot?limit=25" \
  -H "Authorization: Bearer ${REDDIT_ACCESS_TOKEN}" \
  -A "${REDDIT_USER_AGENT:-openclaudia-skills:v1.0}" | \
  jq -r '.data.children[] | .data | {
    title: .title,
    score: .score,
    num_comments: .num_comments,
    url: .url,
    created_utc: .created_utc,
    selftext: (.selftext | if length > 200 then .[:200] + "..." else . end)
  }'
```

**Passo 4: buscar um topico especifico em todo o Reddit**

```bash
# Buscar discussoes sobre um topico no Reddit inteiro
curl -s "https://oauth.reddit.com/search?q={topico}&sort=relevance&t=week&limit=25" \
  -H "Authorization: Bearer ${REDDIT_ACCESS_TOKEN}" \
  -A "${REDDIT_USER_AGENT:-openclaudia-skills:v1.0}"
```

**Como usar dados do Reddit para conteudo social:**
- **Topicos em alta:** posts com pontuacao alta (500+) e muitos comentarios indicam o que a comunidade se importa agora. Use como topicos de conteudo.
- **Linguagem e enquadramento:** note como os usuarios formulam problemas e perguntas. Espelhe essa linguagem nos seus hooks para autenticidade.
- **Sentimento:** varra os comentarios em busca de dores, frustracoes ou empolgacao recorrentes. Enderece isso diretamente nos posts.
- **Lacunas de conteudo:** se uma thread tem muitas perguntas e nenhuma resposta clara, isso e uma oportunidade de conteudo.
- **Timing:** se um topico esta em alta no Reddit hoje, crie conteudo social sobre ele em 24-48 horas para relevancia maxima.

**Subreddits uteis por nicho:**
- Marketing: r/marketing, r/digital_marketing, r/SEO, r/socialmedia
- Tech: r/technology, r/programming, r/webdev, r/SaaS
- Negocios: r/entrepreneur, r/smallbusiness, r/startups
- Design: r/design, r/graphic_design, r/UI_Design

**Nota:** o limite de taxa da API do Reddit e de 100 requisicoes por minuto e o token de acesso expira em 24 horas. Sempre inclua um `User-Agent` descritivo, pois o Reddit bloqueia requisicoes com user agents genericos.

---

## Publicacao de conteudo via API

Estas integracoes permitem postar diretamente nas plataformas a partir do terminal. Regra do contrato Alia Flow: publicar e SEMPRE acao do operador ou do devops com aprovacao explicita. O especialista growth prepara o conteudo e o comando; nunca executa a publicacao por conta propria. **Sempre mostre ao operador exatamente o que sera postado e peca confirmacao antes de publicar.**

### Postando no Reddit

Requer `REDDIT_CLIENT_ID`, `REDDIT_CLIENT_SECRET` e um token OAuth de conta de usuario do Reddit.

**Passo 1: obter um token autenticado de usuario**

Postar no Reddit exige o fluxo OAuth `authorization_code` (nao `client_credentials`). O usuario precisa autorizar uma vez:

```bash
# Gerar a URL de autorizacao (usuario visita no navegador)
echo "https://www.reddit.com/api/v1/authorize?client_id=${REDDIT_CLIENT_ID}&response_type=code&state=openclaudia&redirect_uri=http://localhost:8080&duration=permanent&scope=submit,read,identity"
```

Depois que o usuario autorizar e obtiver o `code` do redirect:

```bash
# Trocar o code por access + refresh token
curl -s -X POST "https://www.reddit.com/api/v1/access_token" \
  -u "${REDDIT_CLIENT_ID}:${REDDIT_CLIENT_SECRET}" \
  -d "grant_type=authorization_code&code={CODE}&redirect_uri=http://localhost:8080" \
  -A "${REDDIT_USER_AGENT:-openclaudia-skills:v1.0}"
```

Guarde o `refresh_token` para sessoes futuras:

```bash
# Renovar um token expirado
curl -s -X POST "https://www.reddit.com/api/v1/access_token" \
  -u "${REDDIT_CLIENT_ID}:${REDDIT_CLIENT_SECRET}" \
  -d "grant_type=refresh_token&refresh_token={REFRESH_TOKEN}" \
  -A "${REDDIT_USER_AGENT:-openclaudia-skills:v1.0}"
```

**Passo 2: postar em um subreddit**

```bash
# Post de texto (self post)
curl -s -X POST "https://oauth.reddit.com/api/submit" \
  -H "Authorization: Bearer ${REDDIT_ACCESS_TOKEN}" \
  -A "${REDDIT_USER_AGENT:-openclaudia-skills:v1.0}" \
  -d "sr={subreddit}&kind=self&title={titulo}&text={corpo}&api_type=json"

# Post de link
curl -s -X POST "https://oauth.reddit.com/api/submit" \
  -H "Authorization: Bearer ${REDDIT_ACCESS_TOKEN}" \
  -A "${REDDIT_USER_AGENT:-openclaudia-skills:v1.0}" \
  -d "sr={subreddit}&kind=link&title={titulo}&url={url}&api_type=json"
```

**Passo 3: postar um comentario (para engajamento)**

```bash
curl -s -X POST "https://oauth.reddit.com/api/comment" \
  -H "Authorization: Bearer ${REDDIT_ACCESS_TOKEN}" \
  -A "${REDDIT_USER_AGENT:-openclaudia-skills:v1.0}" \
  -d "thing_id={fullname_pai}&text={corpo_comentario}&api_type=json"
```

O `thing_id` e o fullname do post ou comentario a responder (ex.: `t3_abc123` para post, `t1_abc123` para comentario).

**Boas praticas de postagem no Reddit:**
- Confira as regras do subreddit antes de postar (`/r/{subreddit}/about/rules`)
- Muitos subreddits tem requisitos minimos de karma/idade de conta
- Evite autopromocao em subreddits que a proibem - foque em valor
- Poste nos horarios de pico (9-11h EST para subreddits US; ajuste ao fuso das comunidades BR do Cliente)
- Use a flair preferida do subreddit se exigida
- Espace os posts - no maximo alguns por dia somando todos os subreddits

### Postagem multi-plataforma via EngageMate

Se `ENGAGEMATE_API_KEY` estiver definida, e possivel usar o EngageMate para postar no Reddit, X/Twitter, Instagram, Facebook e TikTok a partir de uma unica API.

```bash
echo "ENGAGEMATE_API_KEY is ${ENGAGEMATE_API_KEY:+set}"
```

O EngageMate e uma plataforma de engajamento social com IA. Consulte a documentacao em https://engagemate.app para os endpoints atuais da API. O ID do produto fica em `ENGAGEMATE_PRODUCT_ID`.

### Fluxo de publicacao

Quando o operador pedir para postar ou publicar conteudo:

1. **Gerar** o conteudo usando as regras por plataforma acima
2. **Prever** - mostre ao operador exatamente o que sera postado, incluindo:
   - Plataforma e destino (subreddit, conta etc.)
   - Titulo (se aplicavel)
   - Corpo completo do post
   - Hashtags, links, midia
3. **Confirmar** - peca aprovacao do operador antes de postar
4. **Postar** - a execucao da chamada de API e feita pelo operador ou pelo devops com aprovacao
5. **Reportar** - mostre a URL do post e os dados de resposta

**Nunca publicar automaticamente sem confirmacao explicita do operador.**
