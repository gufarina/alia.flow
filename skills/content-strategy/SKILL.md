---
name: content-strategy
description: Constroi estrategia de conteudo completa para um cliente: topic clusters, calendario editorial, mapeamento de conteudo por etapa da jornada de compra e plano de distribuicao. A Alia dispara quando o Job pede plano de conteudo, blog, cluster de topicos, calendario editorial ou funil de conteudo.
trigger: estrategia de conteudo, plano de conteudo, calendario editorial, topic cluster, cluster de topicos, pillar page, pagina pilar, funil de conteudo, jornada de compra, roadmap de conteudo, mapeamento de conteudo
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/content-strategy
wave: 2
---

# Skill de Estrategia de Conteudo

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa esta skill diretamente.
2. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Se nao existe Task registrada, registrar primeiro e so entao executar.
3. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada.
4. Grounding bloqueante: todo numero e toda afirmacao de peso citam fonte LIDA como [MEDIDO fonte] ou saem marcados [INFERIDO]. Nunca fabricar metrica.
5. Contexto BR: taticas nascidas no mercado US sao referencia, nao receita; antes de recomendar, avaliar o equivalente local (canais, volumes de busca, comunidades e habitos do publico brasileiro).

## Papel

Voce e um estrategista de conteudo senior. Seu trabalho e construir planos de conteudo completos que geram trafego organico, nutrem leads e sustentam os objetivos do negocio por meio de criacao e distribuicao estrategica de conteudo.

## Levantamento de Requisitos

Antes de construir qualquer estrategia, colete estes insumos:

1. **Tipo de negocio** - SaaS, ecommerce, agencia, midia, B2B, B2C etc.
2. **Publico-alvo** - ICPs, personas, demografia, dores.
3. **Objetivos do negocio** - Trafego, leads, brand awareness, lideranca de pensamento, SEO, conversoes.
4. **Estado atual** - Ativos de conteudo existentes, niveis de trafego, conteudos de melhor desempenho.
5. **Concorrentes** - 3-5 concorrentes cujo conteudo voce admira ou contra quem compete.
6. **Recursos** - Tamanho do time, orcamento, capacidade de publicacao (posts por semana/mes).
7. **Canais** - Blog, newsletter, redes sociais, YouTube, podcast etc.
8. **Horizonte** - Plano de 30/60/90 dias ou trimestral/anual.

## Arquitetura de Topic Clusters

### O que e um Topic Cluster?

Um topic cluster e uma pagina pilar (guia abrangente de 2000-5000 palavras) sustentada por 8-20 paginas de cluster (artigos focados de 800-1500 palavras) que se interligam com a pilar e entre si. Essa estrutura sinaliza autoridade topica para os buscadores.

### Como Construir um Topic Cluster

**Passo 1: Identificar os Topicos Centrais**

Liste 3-5 topicos centrais alinhados ao produto e as necessidades do publico.

Exemplo para um SaaS de gestao de projetos:
- Metodologias de gestao de projetos
- Produtividade de times
- Colaboracao em trabalho remoto
- Planejamento de recursos
- Desenvolvimento agil

**Passo 2: Criar as Paginas Pilar**

Para cada topico central, defina uma pagina pilar:

```
Pilar:   "O Guia Completo de Gestao Agil de Projetos"
URL:     /gestao-agil-de-projetos
Alvo:    "gestao agil de projetos" (alto volume, alta dificuldade)
Tamanho: 3000-5000 palavras
Formato: Guia abrangente com sumario e links de ancora
```

Nota Contexto BR: valide volume e dificuldade da keyword em portugues, no Brasil (Google BR); o volume da versao em ingles nao serve de proxy.

**Passo 3: Mapear o Conteudo de Cluster**

Para cada pilar, levante 10-20 artigos de cluster mirando keywords de cauda longa:

```
Pilar: Gestao Agil de Projetos
Clusters:
  - "O que e um Sprint? Guia para Iniciantes" -> /agil/o-que-e-sprint
  - "Scrum vs Kanban: Qual e o Certo para o Seu Time?" -> /agil/scrum-vs-kanban
  - "Como Conduzir uma Retrospectiva de Sprint Eficaz" -> /agil/retrospectiva-de-sprint
  - "Tecnicas de Estimativa Agil: Story Points Explicados" -> /agil/story-points
  - "Boas Praticas de Daily para Times Remotos" -> /agil/daily-standup
  - "Como Criar um Product Backlog que Funciona de Verdade" -> /agil/product-backlog
  - "Agil vs Cascata: Comparacao Lado a Lado" -> /agil/agil-vs-cascata
  - "Template de Sprint Planning (Download Gratis)" -> /agil/template-sprint-planning
  - "Erros Comuns no Agil e Como Evita-los" -> /agil/erros-comuns
  - "Como Medir a Velocity do Time Agil" -> /agil/velocity-do-time
```

**Passo 4: Definir Regras de Links Internos**

- Toda pagina de cluster linka para a sua pagina pilar (obrigatorio).
- A pagina pilar linka para todas as paginas de cluster (obrigatorio).
- Paginas de cluster linkam para 2-3 clusters irmaos quando relevante (recomendado).
- Use texto de ancora descritivo, nunca "clique aqui".

### Template de Topic Cluster

```markdown
## Cluster: [Nome do Topico]

### Pagina Pilar
- Titulo: [Titulo]
- Keyword alvo: [keyword] (volume: [X], dificuldade: [Y])
- URL: [/caminho]
- Palavras: [3000-5000]
- Formato: [Guia abrangente / Guia definitivo]

### Paginas de Cluster
| # | Titulo | Keyword Alvo | Volume | Dificuldade | Palavras | Prioridade |
|---|--------|--------------|--------|-------------|----------|------------|
| 1 | [Titulo] | [keyword] | [X] | [Y] | [800-1500] | [Alta/Media/Baixa] |
| 2 | ... | ... | ... | ... | ... | ... |

### Mapa de Links Internos
- Pilar -> Todos os clusters
- Cluster 1 -> Cluster 3, Cluster 5
- Cluster 2 -> Cluster 1, Cluster 7
- (etc.)
```

## Mapeamento de Conteudo por Jornada de Compra

Mapeie cada peca de conteudo a uma etapa da jornada de compra.

### Etapa 1: Descoberta (Topo de Funil)

**Mentalidade do leitor:** "Tenho um problema mas ainda nao conheco a solucao."

**Tipos de conteudo:**
- Posts de blog respondendo perguntas de "o que e" e "por que"
- Guias educativos e artigos de como fazer
- Relatorios de industria e pecas de tendencia
- Infograficos e videos explicativos
- Conteudo educativo em redes sociais

**Intencao de keyword:** Informacional (o que, por que, como, guia, dicas)

**KPIs:** Trafego, tempo na pagina, compartilhamentos, inscricoes na newsletter.

**Objetivo:** Construir awareness e capturar e-mails.

### Etapa 2: Consideracao (Meio de Funil)

**Mentalidade do leitor:** "Ja conheco a categoria de solucao. Qual opcao e a melhor para mim?"

**Tipos de conteudo:**
- Artigos de comparacao (X vs Y)
- Listas de "melhores [categoria] para [caso de uso]"
- Estudos de caso
- Webinars e demonstracoes
- Guias detalhados de funcionalidades
- Templates e kits de ferramentas

**Intencao de keyword:** Investigacao comercial (melhor, comparar, review, alternativa, vs)

**KPIs:** Cadastros de e-mail, downloads de conteudo, inscricoes em webinar, pedidos de demo.

**Objetivo:** Posicionar o produto como a melhor opcao.

### Etapa 3: Decisao (Fundo de Funil)

**Mentalidade do leitor:** "Estou pronto para comprar. Me convenca de que essa e a escolha certa."

**Tipos de conteudo:**
- Landing pages de produto
- Paginas de preco
- Depoimentos de clientes e historias de sucesso
- Paginas de teste gratis / demo
- Calculadoras de ROI
- Guias de implementacao

**Intencao de keyword:** Transacional (comprar, preco, teste gratis, demo, cadastro)

**KPIs:** Cadastros de trial, agendamentos de demo, compras, receita.

**Objetivo:** Converter leads em clientes.

### Etapa 4: Retencao (Pos-Compra)

**Mentalidade do leitor:** "Como extraio o maximo deste produto?"

**Tipos de conteudo:**
- Guias de onboarding e tutoriais
- Boas praticas e dicas
- Anuncios de atualizacao de produto
- Conteudo de comunidade
- Guias de casos de uso avancados
- Destaques de clientes

**KPIs:** Taxa de ativacao, adocao de funcionalidades, NPS, churn, receita de expansao.

**Objetivo:** Reduzir churn e impulsionar expansao.

## Mix e Proporcao de Conteudo

Siga esta proporcao para uma estrategia equilibrada:

| Tipo de Conteudo | % da Producao | Proposito |
|------------------|---------------|-----------|
| Descoberta / Educativo | 40% | Gerar trafego organico, construir autoridade |
| Consideracao / Comparacao | 25% | Capturar leads de meio de funil |
| Decisao / Conversao | 15% | Gerar cadastros e vendas |
| Retencao / Habilitacao | 10% | Reduzir churn, aumentar LTV |
| Lideranca de Pensamento / Marca | 10% | Construir marca, atrair imprensa e links |

## Cadencia de Publicacao

### Cadencia Recomendada por Estagio da Empresa

| Estagio | Posts de Blog | Newsletter | Social | Video |
|---------|---------------|------------|--------|-------|
| Inicial (0-50K trafego) | 2-4/semana | 1/semana | 5/semana | 1/mes |
| Crescimento (50-200K trafego) | 3-5/semana | 1-2/semana | 7/semana | 2/mes |
| Escala (200K+ trafego) | 5-10/semana | 2-3/semana | 10+/semana | 4/mes |

Nota Contexto BR: estas faixas assumem times e mercados de conteudo no padrao US. Para operacoes brasileiras menores, mantenha a logica dos estagios mas calibre o piso pela capacidade real do time; consistencia vale mais que volume.

### Fluxo de Producao em Lote

1. **Semana 1 do mes:** Pesquisar e estruturar (outline) todo o conteudo do mes.
2. **Semana 2:** Escrever os primeiros rascunhos de todas as pecas.
3. **Semana 3:** Editar, produzir os assets de design e preparar para publicacao.
4. **Semana 4:** Publicar, promover e reaproveitar.

## Estrategia de Distribuicao

Para cada peca de conteudo, planeje a distribuicao nestes canais:

### Canais Proprios
- **Blog** - Publicar a peca completa.
- **Newsletter** - Resumir com link para o artigo completo.
- **Redes sociais** - Criar 3-5 posts sociais por artigo (ver abaixo).
- **Podcast/video** - Reaproveitar o conteudo escrito em audio/video.

### Canais Conquistados
- **SEO** - Otimizar para as keywords alvo, construir links internos.
- **Backlinks** - Oferecer a peca para guest posts, roundups de links e paginas de recursos.
- **Assessoria/PR** - Se for noticia, oferecer a jornalistas e publicacoes do setor.
- **Comunidades** - Compartilhar em grupos de Slack, servidores de Discord, Reddit e foruns relevantes.

Nota Contexto BR: no Brasil o peso das comunidades muda; grupos de WhatsApp e Telegram, comunidades no LinkedIn e nichos locais costumam render mais que Reddit ou Slack publicos. Mapear onde o ICP brasileiro realmente conversa antes de escolher o canal.

### Canais Pagos
- **Anuncios sociais** - Impulsionar os posts organicos de melhor desempenho.
- **Retargeting** - Exibir conteudo para visitantes do site que nao converteram.
- **Newsletters patrocinadas** - Inserir em newsletters de nicho do setor.

Nota Contexto BR: o mercado de newsletters patrocinadas de nicho e bem menor no Brasil; avaliar tambem influenciadores de nicho e midia especializada local como equivalente.

### Plano de Reaproveitamento de Conteudo

Transforme um post de blog em 8+ pecas de conteudo:

```
1 Post de Blog (2000 palavras)
  -> 1 Resumo para newsletter (300 palavras)
  -> 1 Thread no Twitter/X (10 tweets)
  -> 1 Post longo no LinkedIn
  -> 1 Carrossel no Instagram (10 slides)
  -> 1 Roteiro de video curto (60 segundos)
  -> 1 Infografico
  -> 1 Outline de episodio de podcast
  -> 3-5 Graficos de citacao
```

Nota Contexto BR: priorize os formatos onde o publico brasileiro do cliente esta de fato; Instagram, WhatsApp e YouTube costumam pesar mais que Twitter/X para muitos ICPs locais.

## Formato de Saida

Ao construir uma estrategia de conteudo, entregue:

### 1. Resumo da Auditoria de Conteudo
Avaliacao do conteudo atual, lacunas e oportunidades.

### 2. Mapa de Topic Clusters
Representacao visual ou tabular de todo o conteudo pilar e de cluster.

### 3. Mapa de Conteudo por Jornada de Compra
Tabela mapeando cada peca planejada a uma etapa do funil.

### 4. Calendario de Conteudo de 90 Dias
Plano de publicacao mes a mes com titulos, keywords alvo, etapa do funil, tipo de conteudo, responsavel e prazo.

### 5. Playbook de Distribuicao
Plano canal a canal para promover cada tipo de conteudo.

### 6. Painel de KPIs
Metricas a acompanhar por etapa do funil, com metas.

### 7. Briefings de Conteudo
Para o conteudo do primeiro mes, forneca briefings detalhados incluindo:
- Titulo e keyword alvo
- Intencao de busca
- Outline (H2s e H3s)
- Conteudo concorrente a superar
- Alvos de links internos
- CTA e objetivo de conversao
