---
name: brand-monitor
description: Monitora mencoes de marca, analisa sentimento e encontra oportunidades de PR via API Brand.dev ou busca web. A Alia dispara quando o Job pede monitoramento de marca, rastreio de mencoes, sentimento online ou presenca de logo para um Cliente.
trigger: monitoramento de marca, mencoes, sentimento, oportunidades de PR, deteccao de logo, presenca online, midia, reputacao
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/brand-monitor
wave: 3
requires_api: opcional (APIs de social/mencoes; roda em modo busca web sem elas)
---

# Brand Monitor

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa.
2. Sem APIs configuradas a skill roda em modo busca web (cobertura menor) e DECLARA a cobertura reduzida no Artifact - nunca apresenta amostra parcial como censo.
3. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Sem Task registrada, registrar primeiro.
4. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada.
5. Grounding bloqueante: toda mencao reportada cita a fonte lida [MEDIDO url] ou sai [INFERIDO]. Nunca fabricar mencao ou sentimento.
6. Contexto BR: incluir fontes locais relevantes ao publico do Cliente (portais, comunidades BR), nao so as US do original.

---

Rastreie mencoes de marca, analise sentimento e descubra oportunidades de PR usando a API Brand.dev.

## Pre-requisitos

Requer `BRANDDEV_API_KEY` definida em `.env`, `.env.local` ou `~/.claude/.env.global`.

```bash
echo "BRANDDEV_API_KEY is ${BRANDDEV_API_KEY:+set}"
```

Se a chave nao estiver definida, informe o operador:
> Voce precisa de uma chave da API Brand.dev. Obtenha em https://brand.dev/
> Depois adicione `BRANDDEV_API_KEY=sua_chave` ao seu arquivo `.env`.

Nota Alia Flow: sem a chave, NAO bloquear o Job. Cair para o modo busca web (WebSearch/WebFetch) cobrindo os mesmos passos do playbook, declarando a cobertura reduzida no Artifact (ponto 2 do contrato).

## Base da API

Todas as requisicoes vao para `https://api.brand.dev/v1/` com o header `Authorization: Bearer {BRANDDEV_API_KEY}`.

---

## 1. Busca de Marca

Busque mencoes de um nome de marca pela web.

### Endpoint

```
GET https://api.brand.dev/v1/brand/search
```

### Parametros

| Parametro | Tipo | Descricao |
|-----------|------|-----------|
| `query` | string | Nome da marca ou frase a buscar |
| `limit` | int | Numero de resultados (padrao 20, max 100) |
| `offset` | int | Offset de paginacao |
| `sort` | string | `relevance` ou `date` |
| `from_date` | string | Data inicial (YYYY-MM-DD) |
| `to_date` | string | Data final (YYYY-MM-DD) |

### Exemplo curl

```bash
curl -s -H "Authorization: Bearer ${BRANDDEV_API_KEY}" \
  "https://api.brand.dev/v1/brand/search?query=SuaMarca&limit=20&sort=date"
```

### Parse da resposta

```bash
curl -s -H "Authorization: Bearer ${BRANDDEV_API_KEY}" \
  "https://api.brand.dev/v1/brand/search?query=SuaMarca&limit=20" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for m in data.get('results', []):
    print(f\"Source: {m.get('source','')}  |  Title: {m.get('title','')}  |  Sentiment: {m.get('sentiment','n/a')}  |  Date: {m.get('published_at','')}\")
    print(f\"  URL: {m.get('url','')}\")
    print()
"
```

---

## 2. Consulta de Dados da Marca

Obtenha informacoes estruturadas de qualquer empresa ou produto.

### Endpoint

```
GET https://api.brand.dev/v1/brand/info
```

### Parametros

| Parametro | Tipo | Descricao |
|-----------|------|-----------|
| `domain` | string | Dominio da empresa (ex.: `stripe.com`) |
| `name` | string | Nome da marca (alternativa ao dominio) |

### Exemplo curl

```bash
curl -s -H "Authorization: Bearer ${BRANDDEV_API_KEY}" \
  "https://api.brand.dev/v1/brand/info?domain=stripe.com"
```

### Campos da resposta

- `name`: Nome oficial da marca
- `domain`: Dominio principal
- `description`: Descricao da marca
- `industry`: Classificacao de setor
- `founded`: Ano de fundacao
- `headquarters`: Localizacao
- `social_profiles`: Links de redes sociais
- `logos`: URLs dos logos da marca
- `colors`: Paleta de cores da marca
- `employees_range`: Estimativa de porte da empresa

---

## 3. Deteccao de Logo

Detecte logos da marca em imagens pela web.

### Endpoint

```
GET https://api.brand.dev/v1/logo/search
```

### Parametros

| Parametro | Tipo | Descricao |
|-----------|------|-----------|
| `brand` | string | Nome da marca a buscar |
| `domain` | string | Filtrar por dominio especifico |
| `limit` | int | Numero de resultados |

### Exemplo curl

```bash
curl -s -H "Authorization: Bearer ${BRANDDEV_API_KEY}" \
  "https://api.brand.dev/v1/logo/search?brand=SuaMarca&limit=20"
```

Use a deteccao de logo para encontrar:
- Uso nao autorizado do logo
- Visibilidade de parceiros e patrocinadores
- Cobertura de eventos e presenca em midia
- Anuncios de produtos falsificados

---

## 4. Rastreamento de Mencoes

Configure rastreamento continuo de mencoes da marca.

### Criar um monitor

```
POST https://api.brand.dev/v1/monitors
```

### Corpo

```json
{
  "name": "Monitor da Minha Marca",
  "keywords": ["SuaMarca", "Sua Marca", "suamarca.com.br"],
  "exclude_keywords": ["termo nao relacionado"],
  "sources": ["news", "blogs", "social", "forums", "reviews"],
  "languages": ["pt", "en"],
  "notify_email": "alertas@seudominio.com"
}
```

Nota BR: para Clientes com publico brasileiro, incluir `"pt"` em `languages` e variacoes do nome como os brasileiros escrevem (grafia acentuada ou nao, abreviacoes comuns).

### Exemplo curl

```bash
curl -s -X POST -H "Authorization: Bearer ${BRANDDEV_API_KEY}" \
  -H "Content-Type: application/json" \
  "https://api.brand.dev/v1/monitors" \
  -d '{
    "name": "Alerta de Marca",
    "keywords": ["SuaMarca"],
    "sources": ["news", "blogs", "social"],
    "languages": ["pt", "en"]
  }'
```

### Listar monitores

```bash
curl -s -H "Authorization: Bearer ${BRANDDEV_API_KEY}" \
  "https://api.brand.dev/v1/monitors"
```

### Obter resultados de um monitor

```bash
curl -s -H "Authorization: Bearer ${BRANDDEV_API_KEY}" \
  "https://api.brand.dev/v1/monitors/{monitor_id}/mentions?limit=50&sort=date"
```

---

## 5. Analise de Sentimento

Analise o sentimento das mencoes da marca.

### Endpoint

```
GET https://api.brand.dev/v1/brand/sentiment
```

### Parametros

| Parametro | Tipo | Descricao |
|-----------|------|-----------|
| `query` | string | Nome da marca |
| `from_date` | string | Data inicial |
| `to_date` | string | Data final |
| `granularity` | string | `day`, `week` ou `month` |

### Exemplo curl

```bash
curl -s -H "Authorization: Bearer ${BRANDDEV_API_KEY}" \
  "https://api.brand.dev/v1/brand/sentiment?query=SuaMarca&from_date=2024-01-01&to_date=2024-03-31&granularity=week"
```

### Escores de sentimento

- **Positivo** (> 0.3): Elogios, recomendacoes, avaliacoes positivas
- **Neutro** (-0.3 a 0.3): Mencoes factuais, cobertura de noticias
- **Negativo** (< -0.3): Reclamacoes, criticas, avaliacoes negativas

Lembrete de grounding: escores vindos da API sao [MEDIDO url-do-endpoint]. Sentimento estimado por leitura manual em modo busca web sai marcado como [INFERIDO].

---

## 6. Comparacao de Mencoes com Concorrentes

Compare volume de mencoes e sentimento da marca contra concorrentes.

### Fluxo

1. Busque mencoes da sua marca e de cada concorrente
2. Compare a contagem de mencoes no mesmo periodo
3. Compare as distribuicoes de sentimento
4. Identifique fontes onde os concorrentes sao mencionados e voce nao

```bash
# Para cada marca, obter contagem de mencoes
for brand in "SuaMarca" "Concorrente1" "Concorrente2"; do
  count=$(curl -s -H "Authorization: Bearer ${BRANDDEV_API_KEY}" \
    "https://api.brand.dev/v1/brand/search?query=${brand}&limit=1" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('total',0))")
  echo "${brand}: ${count} mencoes"
done
```

---

## Fluxo: Auditoria Completa de Marca

Quando o Job pedir um relatorio completo de monitoramento de marca:

### Passo 1: Dados da Marca

Puxe os dados estruturados da marca para contexto.

### Passo 2: Volume de Mencoes

Busque mencoes da marca nos ultimos 30/90 dias. Conte o total e quebre por tipo de fonte.

### Passo 3: Analise de Sentimento

Obtenha as tendencias de sentimento. Sinalize picos negativos e investigue a causa raiz.

### Passo 4: Oportunidades de PR

A partir dos dados de mencoes, identifique:
- **Sites de alta autoridade** que mencionam concorrentes mas nao voce
- **Jornalistas** que cobrem o seu setor
- **Topicos em alta** onde a marca pode contribuir
- **Perguntas sem resposta** sobre a marca em foruns

Contexto BR: varrer tambem portais e comunidades brasileiras relevantes ao publico do Cliente (grandes portais de noticia, veiculos do setor, Reclame Aqui, foruns e comunidades locais), nao apenas as fontes US.

### Passo 5: Presenca Visual/Logo

Busque aparicoes do logo. Sinalize usos nao autorizados.

### Passo 6: Relatorio

Apresente os achados como:

```
## Relatorio de Monitoramento de Marca: {Marca}

### Visao Geral
- Total de mencoes (ultimos 30 dias): X
- Distribuicao de sentimento: X% positivo, X% neutro, X% negativo
- Principais fontes: ...

### Tendencia de Sentimento
[Dados de tendencia semanal]

### Principais Mencoes Positivas
1. [Fonte] - [Titulo] - [URL]
2. ...

### Mencoes Negativas que Exigem Atencao
1. [Fonte] - [Titulo] - [URL] - [Resumo do problema]
2. ...

### Oportunidades de PR
1. [Veiculo] cobre [topico] - angulo de pitch: ...
2. [Jornalista] escreveu recentemente sobre [topico] - angulo de pitch: ...

### Comparacao com Concorrentes
| Metrica | Sua Marca | Concorrente A | Concorrente B |
|---------|-----------|---------------|---------------|
| Mencoes | ... | ... | ... |
| % Positivo | ... | ... | ... |
| Fonte Principal | ... | ... | ... |

### Itens de Acao
- [ ] Responder a [mencao negativa]
- [ ] Pitch para [veiculo] sobre [topico]
- [ ] Atualizar cadastro da marca em [plataforma]
```

Nota Alia Flow: este relatorio e o Artifact da Task. Cada mencao listada carrega [MEDIDO url] ou [INFERIDO], e o cabecalho declara o modo de coleta (API ou busca web com cobertura reduzida).

---

## Tratamento de Erros

| Status | Significado |
|--------|-------------|
| 401 | Chave de API invalida ou expirada |
| 403 | Permissoes insuficientes para este endpoint |
| 404 | Recurso nao encontrado (verifique o ID do monitor) |
| 429 | Limite de taxa excedido - aguarde e tente de novo |
| 500 | Erro do servidor - tente de novo em alguns segundos |

## Dicas

- Use o nome exato da marca + erros de grafia comuns como keywords
- Exclua o proprio dominio para evitar auto-mencoes
- Configure monitores tambem para marcas concorrentes
- Verifique mencoes no minimo semanalmente; diariamente em lancamentos ou crises
- Exporte mencoes negativas para uma planilha para follow-up do suporte ao cliente
