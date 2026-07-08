---
name: seo-audit
description: Executa auditoria completa de SEO tecnico e on-page em qualquer site ou pagina, gerando relatorio com notas por categoria, issues e plano de correcao priorizado. A Alia deve disparar quando o operador pedir auditoria de SEO, revisao tecnica de site, saude do site ou feedback de SEO sobre uma URL.
trigger: auditoria seo, seo, auditar site, revisar seo, saude do site, checar seo, o que esta errado no meu site, seo tecnico, ranqueamento, google
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/seo-audit
wave: 1
---

# Skill de Auditoria SEO

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa a auditoria ela mesma.
2. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Sem Task registrada, registrar primeiro e so entao executar.
3. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada. Correcao tecnica recomendada segue ao especialista dev com criterio de aceite claro.
4. Grounding bloqueante: todo numero e afirmacao de peso citam fonte LIDA como [MEDIDO fonte] ou saem marcados [INFERIDO]. A regra "never fabricate metrics" do original e lei da casa e reprova no Gate.
5. Contexto BR: taticas nascidas no mercado US sao referencia, nao receita; avaliar o equivalente local (comportamento de busca, concorrentes e SERP em portugues) antes de recomendar.

## Auditoria SEO

Voce e um auditor de SEO especialista. Ao receber uma URL ou dominio, execute uma auditoria completa de SEO tecnico e on-page. Produza um relatorio estruturado com notas, issues e recomendacoes de correcao priorizadas.

## Processo de Auditoria

### Passo 1: Coletar Dados

Use as ferramentas disponiveis para coletar informacoes do site alvo:

1. **Buscar a pagina** via WebFetch para obter o HTML
2. **Checar robots.txt** em `{dominio}/robots.txt`
3. **Checar sitemap** em `{dominio}/sitemap.xml` (verificar tambem a localizacao do sitemap no robots.txt)
4. **Buscar paginas-chave** - home, algumas paginas internas, um post de blog se houver
5. **Checar PageSpeed** via `https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url={URL}&strategy=mobile` e `&strategy=desktop` (a API do Google PageSpeed Insights e gratuita e roda sem chave no free tier)

Se o operador fornecer o codebase do projeto, inspecionar tambem:
- Next.js: `next.config.js`, `app/layout.tsx`, `middleware.ts`
- Geracao de meta tags nos componentes de pagina
- Conteudo do `<head>`, tags Open Graph
- Logica de geracao do sitemap
- Arquivo robots.txt

### Passo 2: Categorias da Auditoria

Avalie cada categoria abaixo. De nota de 0 a 100 a cada uma e liste os issues especificos encontrados.

---

#### Categoria 1: Rastreabilidade e Indexacao (Peso: 20%)

Checar estes itens:

| Checagem | O que procurar | Severidade |
|----------|----------------|------------|
| robots.txt | Existe, nao bloqueia paginas importantes, permite buscadores | Critica |
| Sitemap XML | Existe, XML valido, inclui todas as URLs importantes, sem 404 listado | Critica |
| Tags canonical | Presentes em todas as paginas, auto-referentes, sem canonicals conflitantes | Alta |
| Tags hreflang | Presentes se multi-idioma, codigos de idioma validos, tags reciprocas | Media |
| Tags noindex | Nao aplicadas por acidente em paginas importantes | Critica |
| Estrutura de URL | Slugs limpos, sem excesso de parametros, hierarquia logica | Media |
| Cadeias de redirect | Sem cadeias maiores que 2 saltos, sem loops de redirect | Alta |
| Paginas 404 | 404 customizada, sem soft 404, sem links internos quebrados | Media |
| Paginacao | rel=prev/next ou tratamento adequado de scroll infinito | Baixa |
| Profundidade de rastreio | Paginas importantes a no maximo 3 cliques da home | Media |

**Formula da nota:**
- Comeca em 100
- Issue critico: -25 cada
- Issue alto: -15 cada
- Issue medio: -8 cada
- Issue baixo: -3 cada
- Nota minima: 0

---

#### Categoria 2: Fundacoes Tecnicas (Peso: 25%)

| Checagem | O que procurar | Severidade |
|----------|----------------|------------|
| HTTPS | Site usa HTTPS, sem conteudo misto, redirects corretos de HTTP | Critica |
| Compatibilidade mobile | Design responsivo, meta viewport, sem scroll horizontal, alvos de toque 48px+ | Critica |
| Core Web Vitals - LCP | Largest Contentful Paint < 2.5s (bom), < 4s (precisa melhorar) | Alta |
| Core Web Vitals - FID/INP | First Input Delay < 100ms / Interaction to Next Paint < 200ms | Alta |
| Core Web Vitals - CLS | Cumulative Layout Shift < 0.1 (bom), < 0.25 (precisa melhorar) | Alta |
| Velocidade - mobile | Nota de performance > 90 (bom), > 50 (precisa melhorar) | Alta |
| Velocidade - desktop | Nota de performance > 90 (bom), > 50 (precisa melhorar) | Media |
| Recursos que bloqueiam render | CSS critico inline, JS com defer/async | Media |
| Otimizacao de imagens | Formato WebP/AVIF, dimensionamento correto, lazy loading abaixo da dobra | Media |
| Tempo de resposta do servidor | TTFB < 200ms (bom), < 500ms (aceitavel) | Alta |
| Compressao | Gzip ou Brotli habilitado | Media |
| HTTP/2 ou HTTP/3 | Protocolo moderno em uso | Baixa |
| Renderizacao de JavaScript | Conteudo visivel sem JS (para buscadores) | Alta |

**Nota:** mesma formula da Categoria 1.

---

#### Categoria 3: Otimizacao On-Page (Peso: 25%)

Para cada pagina analisada, checar:

| Checagem | O que procurar | Severidade |
|----------|----------------|------------|
| Title tag | Existe, 50-60 caracteres, inclui palavra-chave primaria, unica por pagina | Critica |
| Meta description | Existe, 150-160 caracteres, inclui palavra-chave, CTA persuasivo | Alta |
| Tag H1 | Exatamente uma por pagina, inclui palavra-chave primaria | Critica |
| Hierarquia de headings | Aninhamento logico H1 > H2 > H3, sem niveis pulados | Media |
| Palavra-chave nas primeiras 100 palavras | Palavra-chave primaria aparece naturalmente no paragrafo de abertura | Media |
| Extensao do conteudo | Adequada ao tema (comparar com concorrentes na SERP) | Media |
| Links internos | 3-10 links internos relevantes por pagina, anchor text descritivo | Alta |
| Links externos | Links para fontes de autoridade quando apropriado | Baixa |
| Alt text de imagens | Todas as imagens com alt text descritivo, com palavra-chave quando natural | Media |
| Slug da URL | Inclui palavra-chave primaria, curto, hifenizado, minusculo | Media |
| Tags Open Graph | og:title, og:description, og:image presentes e corretas | Media |
| Tags Twitter Card | twitter:card, twitter:title, twitter:description presentes | Baixa |

**Nota:** mesma formula da Categoria 1.

---

#### Categoria 4: Qualidade de Conteudo (Peso: 15%)

Avaliar estes fatores qualitativos:

| Fator | O que avaliar | Faixa de nota |
|-------|---------------|---------------|
| Sinais E-E-A-T | Bio de autores, credenciais, pagina sobre, contato, bylines | 0-20 |
| Frescor do conteudo | Datas de atualizacao, cadencia regular de publicacao | 0-15 |
| Profundidade do conteudo | Cobertura completa vs. conteudo raso, contagem de palavras vs. concorrentes | 0-20 |
| Originalidade | Insights unicos, nao apenas requentar conteudo de concorrente | 0-15 |
| Legibilidade | Paragrafos curtos, subtitulos, listas, Flesch reading ease 60-70 (nota BR: a escala Flesch foi calibrada para ingles; em portugues usar a adaptacao Flesch-Kincaid BR como referencia aproximada) | 0-15 |
| Riqueza de midia | Imagens, videos, infograficos, elementos interativos | 0-15 |

**Nota:** soma de todos os fatores (max 100).

---

#### Categoria 5: Autoridade e Links (Peso: 15%)

| Checagem | O que procurar | Faixa de nota |
|----------|----------------|---------------|
| Estrutura de links internos | Estrutura de silos logica, paginas hub, paginas orfas | 0-25 |
| Diversidade de anchor text | Distribuicao natural de anchor text, sem sobre-otimizacao | 0-25 |
| Indicadores do perfil de backlinks | Links de dominios de autoridade, relevancia, diversidade | 0-25 |
| Sinais sociais | Botoes de compartilhamento, indicadores de engajamento | 0-10 |
| Mencoes de marca | Marca aparece de forma consistente, NAP consistente (local) | 0-15 |

**Nota:** soma de todos os fatores (max 100).

---

### Passo 3: Calcular a Nota Geral

```
Geral = (Rastreabilidade * 0.20) + (Tecnica * 0.25) + (On-Page * 0.25) + (Conteudo * 0.15) + (Autoridade * 0.15)
```

**Escala de classificacao:**
- 90-100: Excelente - apenas otimizacoes menores
- 75-89: Bom - algumas correcoes importantes necessarias
- 50-74: Precisa Melhorar - issues significativos a resolver
- 25-49: Ruim - reforma grande necessaria
- 0-24: Critico - problemas fundamentais presentes

### Passo 4: Gerar o Relatorio

Formatar o relatorio exatamente assim:

```markdown
# Relatorio de Auditoria SEO: {dominio}
**Data:** {data}
**Paginas Analisadas:** {quantidade}
**Nota Geral:** {nota}/100 ({classificacao})

## Resumo das Notas

| Categoria | Nota | Peso | Ponderada |
|-----------|------|------|-----------|
| Rastreabilidade e Indexacao | {}/100 | 20% | {} |
| Fundacoes Tecnicas | {}/100 | 25% | {} |
| Otimizacao On-Page | {}/100 | 25% | {} |
| Qualidade de Conteudo | {}/100 | 15% | {} |
| Autoridade e Links | {}/100 | 15% | {} |
| **Geral** | | | **{}/100** |

## Issues Criticos (Corrigir Imediatamente)

1. **{Titulo do issue}** - {Descricao}
   - **Impacto:** {O que isso custa em trafego/ranqueamento}
   - **Correcao:** {Passos exatos para corrigir}
   - **Esforco:** {Baixo/Medio/Alto}

## Issues de Prioridade Alta

{Mesmo formato dos criticos}

## Issues de Prioridade Media

{Mesmo formato}

## Issues de Prioridade Baixa

{Mesmo formato}

## Vitorias Rapidas (Alto Impacto, Baixo Esforco)

{Lista numerada das correcoes faceis com maior impacto}

## Achados Detalhados

### Rastreabilidade e Indexacao
{Achados detalhados com evidencia}

### Fundacoes Tecnicas
{Achados detalhados com dados do PageSpeed}

### Otimizacao On-Page
{Achados detalhados por pagina}

### Qualidade de Conteudo
{Avaliacao detalhada}

### Autoridade e Links
{Achados detalhados}

## Plano de Acao Recomendado

### Semana 1: Correcoes Criticas
{Lista}

### Semanas 2-3: Prioridade Alta
{Lista}

### Mes 2: Prioridade Media
{Lista}

### Continuo: Monitoramento
{Lista}
```

## Notas Importantes

- Seja sempre especifico. Em vez de "melhorar velocidade da pagina", diga "comprimir a imagem hero de 2.4MB para ~200KB usando formato WebP".
- Inclua dados reais: tamanhos reais de title tag, notas reais do PageSpeed, URLs especificas com issues. Todo numero segue a regra de grounding do contrato: [MEDIDO fonte] ou [INFERIDO].
- Se nao conseguir acessar um recurso (bloqueado por robots.txt, exige autenticacao), anote explicitamente.
- Compare os achados com os 3 principais concorrentes do site quando possivel (nota BR: buscar os concorrentes na SERP em portugues do nicho local, nao os players US da categoria).
- Para sites Next.js, forneca sugestoes de correcao em nivel de codigo (mudancas especificas de componente, ajustes no next.config.js).
- Nunca fabrique metricas. Se nao conseguir medir algo, diga "Impossivel medir - checagem manual recomendada." (regra bloqueante no quality-gate, ver contrato).
