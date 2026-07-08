---
name: google-analytics
description: Puxa relatorios GA4, dados de trafego e insights da Google Analytics Data API para o Cliente da Task. Alia dispara quando o Job pede analise de trafego do site, aquisicao de usuarios, engajamento, conversoes ou segmentos de audiencia.
trigger: google analytics, GA4, relatorio de trafego, dados de analytics, aquisicao de usuarios, metricas de engajamento, conversao, segmentos de audiencia, page views, sessoes, trafego do site
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/google-analytics
wave: 3
requires_api: google-oauth (GA4)
---

# Google Analytics (GA4)

Puxa relatorios e insights do GA4 usando a Google Analytics Data API.

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa.
2. PRE-REQUISITO: acesso a propriedade GA4 (OAuth Google). SEM a chave configurada, a skill NAO finge dado: declara o pre-requisito e degrada para modo manual - guiar o operador a exportar o relatorio direto do GA4 e analisar o export.
3. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Sem Task registrada, registrar primeiro.
4. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada.
5. Grounding bloqueante: TODO numero reportado cita a fonte lida [MEDIDO relatorio/export] ou sai [INFERIDO]. Metrica sem export ou API = nao existe.
6. Contexto BR: considerar fusos e sazonalidade do publico do Cliente da Task (horario de Brasilia, feriados nacionais, datas de varejo como Black Friday BR e Dia das Maes).

## Pre-requisitos

Requer credenciais Google OAuth:
- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
- Um access token OAuth valido (renovado quando necessario)

Configure as credenciais em `.env`, `.env.local` ou `~/.claude/.env.global`.

### Obtendo um Access Token

```bash
# Passo 1: obter o authorization code (o operador precisa visitar esta URL no navegador)
echo "https://accounts.google.com/o/oauth2/v2/auth?client_id=${GOOGLE_CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/analytics.readonly&response_type=code&access_type=offline"

# Passo 2: trocar o code pelos tokens
curl -s -X POST "https://oauth2.googleapis.com/token" \
  -d "code={AUTH_CODE}" \
  -d "client_id=${GOOGLE_CLIENT_ID}" \
  -d "client_secret=${GOOGLE_CLIENT_SECRET}" \
  -d "redirect_uri=urn:ietf:wg:oauth:2.0:oob" \
  -d "grant_type=authorization_code"

# Passo 3: renovar um token expirado
curl -s -X POST "https://oauth2.googleapis.com/token" \
  -d "refresh_token={REFRESH_TOKEN}" \
  -d "client_id=${GOOGLE_CLIENT_ID}" \
  -d "client_secret=${GOOGLE_CLIENT_SECRET}" \
  -d "grant_type=refresh_token"
```

Guarde o refresh token com seguranca. O access token expira em 1 hora.

### Encontrando o Property ID do GA4

```bash
curl -s -H "Authorization: Bearer ${GA_ACCESS_TOKEN}" \
  "https://analyticsadmin.googleapis.com/v1beta/accountSummaries" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for acct in data.get('accountSummaries', []):
    for prop in acct.get('propertySummaries', []):
        print(f\"{prop['property']}  |  {prop.get('displayName','')}  |  Account: {acct.get('displayName','')}\")
"
```

O formato do property ID e `properties/XXXXXXXXX`.

---

## Base da API

```
POST https://analyticsdata.googleapis.com/v1beta/{property_id}:runReport
```

Todas as requisicoes de relatorio usam POST com corpo JSON. Sempre inclua `Authorization: Bearer {ACCESS_TOKEN}`.

---

## 1. Relatorio de Visao Geral de Trafego

Sessions, usuarios, page views e engagement rate em um intervalo de datas.

### Exemplo curl

```bash
curl -s -X POST \
  "https://analyticsdata.googleapis.com/v1beta/properties/{PROPERTY_ID}:runReport" \
  -H "Authorization: Bearer ${GA_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "dateRanges": [{"startDate": "30daysAgo", "endDate": "today"}],
    "metrics": [
      {"name": "sessions"},
      {"name": "totalUsers"},
      {"name": "newUsers"},
      {"name": "screenPageViews"},
      {"name": "engagementRate"},
      {"name": "averageSessionDuration"},
      {"name": "bounceRate"}
    ]
  }'
```

### Atalhos de Intervalo de Datas

- `today`, `yesterday`
- `7daysAgo`, `14daysAgo`, `28daysAgo`, `30daysAgo`, `90daysAgo`
- Datas especificas: `2024-01-01`
- Compare periodos passando dois dateRanges

Nota BR: os relatorios do GA4 seguem o fuso configurado na propriedade; confirme se e America/Sao_Paulo antes de comparar dias.

---

## 2. Relatorio de Aquisicao de Usuarios

De onde os usuarios vem (canais, fontes, campanhas).

```bash
curl -s -X POST \
  "https://analyticsdata.googleapis.com/v1beta/properties/{PROPERTY_ID}:runReport" \
  -H "Authorization: Bearer ${GA_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "dateRanges": [{"startDate": "30daysAgo", "endDate": "today"}],
    "dimensions": [
      {"name": "sessionDefaultChannelGroup"}
    ],
    "metrics": [
      {"name": "sessions"},
      {"name": "totalUsers"},
      {"name": "engagementRate"},
      {"name": "conversions"}
    ],
    "orderBys": [{"metric": {"metricName": "sessions"}, "desc": true}],
    "limit": 20
  }'
```

### Dimensoes Uteis de Aquisicao

| Dimensao | Descricao |
|----------|-----------|
| `sessionDefaultChannelGroup` | Agrupamento de canais (Organic, Paid, Social, etc.) |
| `sessionSource` | Fonte de trafego (google, facebook, etc.) |
| `sessionMedium` | Medium (organic, cpc, referral, etc.) |
| `sessionCampaignName` | Nome da campanha UTM |
| `firstUserSource` | Fonte de atribuicao first-touch |

---

## 3. Relatorio de Top Paginas

Paginas de maior trafego do site.

```bash
curl -s -X POST \
  "https://analyticsdata.googleapis.com/v1beta/properties/{PROPERTY_ID}:runReport" \
  -H "Authorization: Bearer ${GA_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "dateRanges": [{"startDate": "30daysAgo", "endDate": "today"}],
    "dimensions": [
      {"name": "pagePath"}
    ],
    "metrics": [
      {"name": "screenPageViews"},
      {"name": "totalUsers"},
      {"name": "engagementRate"},
      {"name": "averageSessionDuration"}
    ],
    "orderBys": [{"metric": {"metricName": "screenPageViews"}, "desc": true}],
    "limit": 25
  }'
```

---

## 4. Metricas de Engajamento

Como os usuarios interagem com o conteudo.

```bash
curl -s -X POST \
  "https://analyticsdata.googleapis.com/v1beta/properties/{PROPERTY_ID}:runReport" \
  -H "Authorization: Bearer ${GA_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "dateRanges": [{"startDate": "30daysAgo", "endDate": "today"}],
    "dimensions": [
      {"name": "pagePath"}
    ],
    "metrics": [
      {"name": "engagedSessions"},
      {"name": "engagementRate"},
      {"name": "averageSessionDuration"},
      {"name": "screenPageViewsPerSession"},
      {"name": "eventCount"}
    ],
    "orderBys": [{"metric": {"metricName": "engagedSessions"}, "desc": true}],
    "limit": 20
  }'
```

### Metricas-Chave de Engajamento

| Metrica | O Que Mede |
|---------|------------|
| `engagementRate` | % de sessions engajadas (>10s, 2+ paginas ou conversao) |
| `averageSessionDuration` | Duracao media da session em segundos |
| `screenPageViewsPerSession` | Paginas por session |
| `bounceRate` | % de sessions sem engajamento |
| `eventCount` | Total de eventos disparados |

---

## 5. Rastreamento de Conversoes

Relatorio de eventos de conversao (compras, cadastros, etc.).

```bash
curl -s -X POST \
  "https://analyticsdata.googleapis.com/v1beta/properties/{PROPERTY_ID}:runReport" \
  -H "Authorization: Bearer ${GA_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "dateRanges": [{"startDate": "30daysAgo", "endDate": "today"}],
    "dimensions": [
      {"name": "eventName"}
    ],
    "metrics": [
      {"name": "eventCount"},
      {"name": "totalUsers"},
      {"name": "eventValue"}
    ],
    "dimensionFilter": {
      "filter": {
        "fieldName": "eventName",
        "inListFilter": {
          "values": ["purchase", "sign_up", "generate_lead", "begin_checkout"]
        }
      }
    }
  }'
```

### Conversao por Canal

```bash
curl -s -X POST \
  "https://analyticsdata.googleapis.com/v1beta/properties/{PROPERTY_ID}:runReport" \
  -H "Authorization: Bearer ${GA_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "dateRanges": [{"startDate": "30daysAgo", "endDate": "today"}],
    "dimensions": [
      {"name": "sessionDefaultChannelGroup"}
    ],
    "metrics": [
      {"name": "sessions"},
      {"name": "conversions"},
      {"name": "totalRevenue"}
    ],
    "orderBys": [{"metric": {"metricName": "conversions"}, "desc": true}]
  }'
```

---

## 6. Segmentos de Audiencia

Quebra de trafego por dispositivo, geografia e demografia.

### Por Categoria de Dispositivo

```bash
curl -s -X POST \
  "https://analyticsdata.googleapis.com/v1beta/properties/{PROPERTY_ID}:runReport" \
  -H "Authorization: Bearer ${GA_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "dateRanges": [{"startDate": "30daysAgo", "endDate": "today"}],
    "dimensions": [{"name": "deviceCategory"}],
    "metrics": [
      {"name": "sessions"},
      {"name": "totalUsers"},
      {"name": "engagementRate"},
      {"name": "conversions"}
    ]
  }'
```

### Por Pais

Substitua `deviceCategory` por `country` nas dimensions. Para publico BR, considere tambem `region` e `city` para enxergar concentracao por estado/cidade.

### Por Landing Page + Fonte

```bash
curl -s -X POST \
  "https://analyticsdata.googleapis.com/v1beta/properties/{PROPERTY_ID}:runReport" \
  -H "Authorization: Bearer ${GA_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "dateRanges": [{"startDate": "30daysAgo", "endDate": "today"}],
    "dimensions": [
      {"name": "landingPage"},
      {"name": "sessionSource"}
    ],
    "metrics": [
      {"name": "sessions"},
      {"name": "engagementRate"},
      {"name": "conversions"}
    ],
    "orderBys": [{"metric": {"metricName": "sessions"}, "desc": true}],
    "limit": 30
  }'
```

---

## 7. Comparacao de Periodos

Compare dois periodos para identificar tendencias.

```bash
curl -s -X POST \
  "https://analyticsdata.googleapis.com/v1beta/properties/{PROPERTY_ID}:runReport" \
  -H "Authorization: Bearer ${GA_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "dateRanges": [
      {"startDate": "30daysAgo", "endDate": "today", "name": "current"},
      {"startDate": "60daysAgo", "endDate": "31daysAgo", "name": "previous"}
    ],
    "metrics": [
      {"name": "sessions"},
      {"name": "totalUsers"},
      {"name": "conversions"},
      {"name": "engagementRate"}
    ]
  }'
```

Nota BR: ao comparar periodos, marque na analise feriados e sazonalidades do calendario brasileiro que caem em um periodo e nao no outro (Carnaval, Dia das Maes, Black Friday BR, Natal); queda ou pico pode ser calendario, nao performance.

---

## Parsing da Resposta

A API do GA4 retorna JSON. Faca o parse com python3 ou jq:

```bash
# Transformar o relatorio em tabela
curl -s -X POST "..." | python3 -c "
import json, sys
data = json.load(sys.stdin)
headers = [h['name'] for h in data.get('dimensionHeaders',[])] + [m['name'] for m in data.get('metricHeaders',[])]
print(' | '.join(headers))
print('-' * (len(headers) * 20))
for row in data.get('rows', []):
    dims = [d['value'] for d in row.get('dimensionValues',[])]
    mets = [m['value'] for m in row.get('metricValues',[])]
    print(' | '.join(dims + mets))
"
```

---

## Workflow: Relatorio Mensal de Analytics

Quando a Task pedir um relatorio mensal:

1. Puxe a visao geral de trafego (sessions, usuarios, page views) com comparacao de periodos
2. Puxe a quebra de aquisicao por canal
3. Puxe as top 20 paginas por page views
4. Puxe o resumo de conversoes por canal
5. Puxe a quebra por dispositivo e pais

Apresente como Artifact estruturado com tabelas, tendencias (setas de alta/baixa) e recomendacoes - cada numero com a tag [MEDIDO relatorio/export] apontando a chamada ou export de origem:

```
## Relatorio Mensal de Analytics: {Nome da Propriedade}
### Periodo: {intervalo} vs {periodo anterior}

### Resumo de Trafego
| Metrica | Atual | Anterior | Variacao |
|---------|-------|----------|----------|
| Sessions | X | Y | +Z% |
| ...

### Top Canais
...

### Top Paginas
...

### Resumo de Conversoes
...

### Recomendacoes
- [Baseadas nos padroes dos dados]
```

## Modo Manual (sem OAuth configurado)

Quando nao houver credencial GA4 configurada, NAO simule dados. Declare o pre-requisito na resposta e guie o operador a exportar do proprio GA4 (Relatorios > compartilhar > exportar CSV, ou Explorar > exportar) os relatorios equivalentes aos itens 1-7 acima. Analise o export recebido aplicando as mesmas metricas e o mesmo formato de relatorio, marcando os numeros como [MEDIDO export].

## Problemas Comuns

- **403 Forbidden**: o usuario nao tem acesso a propriedade GA4
- **Linhas vazias**: sem dados para o intervalo ou filtros pedidos
- **Quota excedida**: a API do GA4 tem quotas diarias; reduza intervalos ou agrupe requisicoes
- **Property not found**: verifique o formato do property ID (`properties/XXXXXXXXX`)
