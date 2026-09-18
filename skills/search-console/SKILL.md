---
name: search-console
description: Puxa dados do Google Search Console e analisa performance de busca organica: queries, clicks, impressions, CTR, posicao media, cobertura de indice e sitemaps. A Alia dispara quando o operador pergunta sobre ranking, trafego organico, SEO, index coverage ou quer uma auditoria de busca de um site de Cliente.
trigger: search console, gsc, seo, busca organica, ranking, clicks, impressions, ctr, posicao, index coverage, sitemap, url inspection, keywords, auditoria seo
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/search-console
wave: 3
requires_api: google-oauth (Search Console)
---

# Search Console

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa a analise diretamente.
2. PRE-REQUISITO: acesso a propriedade no Google Search Console (OAuth). SEM a chave, a skill NAO finge dado: declara o pre-requisito e degrada para modo manual - o operador exporta os relatorios do painel do GSC e a skill analisa o export.
3. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Sem Task registrada, registrar primeiro.
4. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada.
5. Grounding bloqueante: TODO numero reportado cita a fonte lida [MEDIDO relatorio/export] ou sai [INFERIDO]. Metrica sem export ou API = nao existe.
6. Contexto BR: buscas em portugues tem volume e concorrencia proprios; nao transplantar benchmark US. CTR e posicao de referencia de mercados em ingles nao valem como meta para queries em portugues.

## Visao geral

Esta skill integra a analise de dados do Google Search Console (GSC) ao fluxo do especialista growth. Ela permite extrair e analisar metricas de performance de busca organica de propriedades verificadas.

## Capacidades

**Analise de performance de busca**: puxa dados de queries, ranking de paginas, clicks, impressions, CTR e posicao media em intervalos de datas configuraveis.

**Inspecao de cobertura de indice**: verifica se URLs especificas estao indexadas, revisa status de crawl e conformidade com robots.txt via URL Inspection API.

**Gestao de sitemaps**: lista sitemaps enviados e acompanha a contagem de URLs indexadas em cada sitemap.

**Identificacao de oportunidades**: descobre melhorias de SEO por tres analises - queries com alta visibilidade mas baixa conversao de click, keywords em posicao 5-20 com potencial de otimizacao, e deteccao de paginas competindo pelo mesmo termo de busca (cannibalization).

## Requisitos tecnicos

A implementacao exige credenciais OAuth com os scopes adequados: `https://www.googleapis.com/auth/webmasters.readonly`.

**Pre-requisitos:** `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` e um access token OAuth valido com o scope acima. Se qualquer um faltar, ativar o modo manual do Contrato (ponto 2) - nunca inventar numero.

### Geracao de token

```bash
# URL de autorizacao
echo "https://accounts.google.com/o/oauth2/v2/auth?client_id=${GOOGLE_CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/webmasters.readonly&response_type=code&access_type=offline"

# Trocar o authorization code por token
curl -s -X POST "https://oauth2.googleapis.com/token" \
  -d "code={AUTH_CODE}" \
  -d "client_id=${GOOGLE_CLIENT_ID}" \
  -d "client_secret=${GOOGLE_CLIENT_SECRET}" \
  -d "redirect_uri=urn:ietf:wg:oauth:2.0:oob" \
  -d "grant_type=authorization_code"

# Renovar token expirado
curl -s -X POST "https://oauth2.googleapis.com/token" \
  -d "refresh_token={REFRESH_TOKEN}" \
  -d "client_id=${GOOGLE_CLIENT_ID}" \
  -d "client_secret=${GOOGLE_CLIENT_SECRET}" \
  -d "grant_type=refresh_token"
```

## Endpoints principais

- Search Analytics Query: `https://www.googleapis.com/webmasters/v3/sites/{siteUrl}/searchAnalytics/query`
- URL Inspection: `https://searchconsole.googleapis.com/v1/urlInspection/index:inspect`
- Sitemaps: `https://www.googleapis.com/webmasters/v3/sites/{siteUrl}/sitemaps`

## Listar propriedades disponiveis

```bash
curl -s -H "Authorization: Bearer ${GSC_ACCESS_TOKEN}" \
  "https://www.googleapis.com/webmasters/v3/sites" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for site in data.get('siteEntry', []):
    print(f\"{site['siteUrl']}  |  Permission: {site['permissionLevel']}\")
"
```

## Dimensoes disponiveis em searchAnalytics/query

| Dimensao | Descricao |
|-----------|-----------|
| `query` | Termo de busca |
| `page` | URL |
| `country` | Codigo do pais (ISO 3166-1 alpha-3; BR para Brasil) |
| `device` | `DESKTOP`, `MOBILE`, `TABLET` |
| `date` | Data individual |
| `searchAppearance` | Tipo de rich result |

## Exemplos de consulta

**Top queries:**

```bash
curl -s -X POST \
  "https://www.googleapis.com/webmasters/v3/sites/sc-domain%3Aexample.com/searchAnalytics/query" \
  -H "Authorization: Bearer ${GSC_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "startDate": "2024-01-01",
    "endDate": "2024-03-31",
    "dimensions": ["query"],
    "rowLimit": 50,
    "startRow": 0
  }'
```

**Top paginas:**

```bash
curl -s -X POST \
  "https://www.googleapis.com/webmasters/v3/sites/sc-domain%3Aexample.com/searchAnalytics/query" \
  -H "Authorization: Bearer ${GSC_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "startDate": "2024-01-01",
    "endDate": "2024-03-31",
    "dimensions": ["page"],
    "rowLimit": 50
  }'
```

**Combinacao query + page com filtros:**

```bash
curl -s -X POST \
  "https://www.googleapis.com/webmasters/v3/sites/sc-domain%3Aexample.com/searchAnalytics/query" \
  -H "Authorization: Bearer ${GSC_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "startDate": "2024-01-01",
    "endDate": "2024-03-31",
    "dimensions": ["query", "page"],
    "rowLimit": 100,
    "dimensionFilterGroups": [{
      "filters": [{
        "dimension": "page",
        "operator": "contains",
        "expression": "/blog/"
      }]
    }]
  }'
```

**Performance de busca por data:**

```bash
curl -s -X POST \
  "https://www.googleapis.com/webmasters/v3/sites/sc-domain%3Aexample.com/searchAnalytics/query" \
  -H "Authorization: Bearer ${GSC_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "startDate": "2024-01-01",
    "endDate": "2024-03-31",
    "dimensions": ["date"],
    "rowLimit": 1000
  }'
```

**Acompanhar uma query especifica no tempo:**

```bash
curl -s -X POST \
  "https://www.googleapis.com/webmasters/v3/sites/sc-domain%3Aexample.com/searchAnalytics/query" \
  -H "Authorization: Bearer ${GSC_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "startDate": "2024-01-01",
    "endDate": "2024-03-31",
    "dimensions": ["date"],
    "dimensionFilterGroups": [{
      "filters": [{
        "dimension": "query",
        "operator": "equals",
        "expression": "sua keyword alvo"
      }]
    }]
  }'
```

## URL Inspection

```bash
curl -s -X POST \
  "https://searchconsole.googleapis.com/v1/urlInspection/index:inspect" \
  -H "Authorization: Bearer ${GSC_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "inspectionUrl": "https://example.com/pagina-para-checar",
    "siteUrl": "sc-domain:example.com"
  }'
```

## Listar sitemaps

```bash
curl -s -H "Authorization: Bearer ${GSC_ACCESS_TOKEN}" \
  "https://www.googleapis.com/webmasters/v3/sites/sc-domain%3Aexample.com/sitemaps" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for sm in data.get('sitemap', []):
    print(f\"URL: {sm['path']}\")
    print(f\"  Type: {sm.get('type','')}  |  Submitted: {sm.get('lastSubmitted','')}\")
    print(f\"  URLs discovered: {sm.get('contents',[{}])[0].get('submitted','?')}  |  Indexed: {sm.get('contents',[{}])[0].get('indexed','?')}\")
    print()
"
```

## Auditoria completa em nove passos

Ao conduzir uma auditoria completa de GSC:

1. **Metricas gerais**: total de clicks, impressions, CTR medio e posicao media dos ultimos 90 dias vs 90 dias anteriores
2. **Top 30 queries**: por clicks, com CTR e posicao
3. **Top 20 paginas**: por clicks, com CTR e posicao
4. **Quebra por device**: performance desktop vs mobile (no Brasil o mobile costuma dominar o trafego - checar o dado real da propriedade, nao assumir)
5. **Low-hanging fruit**: oportunidades de alta impression com CTR baixo
6. **Striking distance**: keywords em posicao 5-20 com potencial de otimizacao
7. **Cannibalization**: queries com multiplas paginas competindo
8. **Index coverage**: spot-check das URLs importantes
9. **Saude dos sitemaps**: verificar que os sitemaps estao enviados e indexados

## Criterios de identificacao de oportunidades

**Low-hanging fruit:** impressions > 100 E CTR < 0.03 E posicao < 20

**Striking distance:** posicao entre 5 e 20 com impressions > 50

**Cannibalization:** multiplas paginas rankeando para a mesma query com impressions combinadas > 100

Nota BR: os limiares acima vem do upstream e servem de ponto de partida; para nichos em portugues com volume menor, calibrar o corte de impressions pelo volume real da propriedade antes de descartar oportunidades.

## Formato do relatorio (Artifact)

```
## Auditoria Search Console: {dominio}
### Periodo: {intervalo de datas}

### Resumo
| Metrica | Atual | Anterior | Variacao |
|---------|-------|----------|----------|
| Clicks | X | Y | +Z% |
| Impressions | X | Y | +Z% |
| CTR medio | X% | Y% | +Z pp |
| Posicao media | X | Y | +Z |

### Top queries
| Query | Clicks | Impressions | CTR | Posicao |
|-------|--------|-------------|-----|---------|
| ...   | ...    | ...         | ... | ...     |

### Oportunidades de otimizacao

#### Otimizacao de title/description (alta impression, CTR baixo)
1. "{query}" - {impressions} impressions, {ctr}% CTR, posicao {pos}
   - Pagina: {url}
   - Recomendacao: ...

#### Otimizacao de conteudo (striking distance)
1. "{query}" - posicao {pos}, {impressions} impressions
   - Acao: adicionar {query} em H2, expandir a secao sobre {topico}

#### Correcoes de cannibalization
1. "{query}" aparece em {n} paginas
   - Consolidar em: {melhor_url}
   - Redirect/noindex: {outras_urls}
```

Todo numero preenchido no relatorio segue o ponto 5 do Contrato: marcado [MEDIDO relatorio/export] com a origem, ou [INFERIDO] quando for projecao.

## Limites e frescor dos dados

- Search Analytics API: 1.200 queries por minuto
- URL Inspection API: 2.000 inspecoes por dia por propriedade
- Frescor dos dados: tipicamente 2-3 dias de atraso
- As datas devem estar dentro dos ultimos 16 meses

## Dicas adicionais

- O formato de siteUrl e `https://example.com/` (URL prefix) ou `sc-domain:example.com` (domain property)
- Ao analisar propriedades BR, filtrar `country` = `BRA` quando o site atende mais de um pais, para nao diluir a leitura com trafego de fora
