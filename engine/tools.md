# Alia - Selecao de Ferramentas e Frugalidade

> Qual ferramenta usar, e como gastar o minimo de token fazendo o maximo. Frugalidade nao e
> avareza: e fazer o trabalho certo na forca certa, sem desperdicio e sem perda de qualidade.
> O manifesto estruturado vive ao lado em [tools.yaml](tools.yaml) - esta prosa explica, o YAML
> deixa as regras maquinaveis.

---

## Prioridade de ferramentas

**Nativa primeiro.** Ler, escrever, buscar e rodar comando com a ferramenta nativa - rapida,
precisa, barata. MCP **so quando a nativa nao cobre**: navegador, banco de dados, API externa,
busca na web. Cada salto de camada custa mais contexto e mais latencia; nao salte sem motivo.

| Tarefa | Use | Nao use |
|--------|-----|---------|
| Ler / escrever / buscar arquivo | ferramenta nativa | MCP generico |
| Rodar comando | shell nativo | MCP generico |
| Navegador / scraping / banco / web search | MCP especifico | MCP generico, scraping manual |

> Regra de uma linha: a ferramenta mais barata que resolve com qualidade vence. Subir de camada
> exige justificativa, nao o contrario.

## Frugality Check

Antes de qualquer operacao cara (delegar a um Specialist, varrer arquivos, chamar MCP, gerar
resposta longa), passe por estes cinco filtros. E o Principio VIII tornado pratica.

1. **Memory antes de reprocessar** - existe contexto na Memory que eu posso recall em vez de
   recalcular do zero? (Principio VII)
2. **Grafo antes de varredura (PASSO OBRIGATORIO)** - quem tem segundo cerebro CONSULTA o grafo em
   `squad/knowledge/graphify-out/` ANTES de qualquer varredura cega (grep/glob). Nao e lembrete nem
   preferencia: e passo obrigatorio. Pular so com justificativa explicita (ver "Grafo obrigatorio").
3. **Forca certa** - e o modelo/agente certo pra esta Task? Nao usar canhao pra mosquito; nao usar
   estilingue pra muralha.
4. **Mecanico antes de julgamento** - da pra resolver por Frugal Skill (script, custo zero de token)
   em vez de acionar um Specialist? (ver [Frugal Skills](features/frugal-skills.md))
5. **Compactar antes de entregar** - comprimir o handoff antes de delegar; em resposta grande,
   extrair so o essencial e descartar ruido.

> Ordem importa: recall (1) e grafo (2) evitam o gasto; forca (3) e mecanico (4) escolhem a rota
> barata; compactacao (5) corta o que sobra. Pare no primeiro filtro que resolve.

## Grafo obrigatorio (consulta antes de varredura cega)

A consulta ao grafo deixou de ser lembrete/prioridade e virou **passo obrigatorio**: quem tem
segundo cerebro consulta `squad/knowledge/graphify-out/` (o grafo da Memory) ANTES de qualquer
varredura cega - grep, glob, leitura em massa de arquivos. O grafo leva direto ao alvo e ao que ja
se sabe; varrer sem consultar e reprocessar o que a Memory ja indexou (viola Memory Before
Reprocessing, Principio VII).

A regra, em uma frase: **grafo primeiro, varredura depois - e a varredura so amplia o que o grafo
nao cobriu.** Pular o passo so e aceitavel COM justificativa explicita, por exemplo:

- o grafo ainda nao foi gerado para este Client/Squad (pre-condicao abaixo);
- a busca e por algo fora do escopo do grafo (ex: um arquivo recem-criado, ainda nao indexado);
- o alvo exato e conhecido (ler um caminho especifico nao e varredura cega).

Sem justificativa, varrer antes de consultar o grafo e desvio - o mesmo desvio que o Frugality
Check (passo 2) existe para evitar. Isso alinha tools.md com o fluxo do boot loader (AGENTS.md: o
Specialist consulta o grafo em `squad/knowledge/graphify-out/` antes de delegar).

### Pre-condicao operacional (nota honesta)

O passo so faz sentido onde o grafo JA existe. Gerar o `GRAPH_REPORT.md` (e o `graph.json`) via a
capacidade graphify e **pre-condicao operacional**: sem grafo gerado pelo menos uma vez por Squad,
nao ha o que consultar e a regra fica vazia. Onde o grafo ainda nao existe, gera-lo primeiro e a
acao - nao pular a consulta. (Gerar o grafo do proprio engine nao e requisito desta regra; a regra
vale para o segundo cerebro de cada Client.)

#### Como gerar o grafo (o comando real - nao e aspiracional)

A GERACAO nao e uma flag do CLI `graphify` (o CLI so faz `install`/`path`/`explain`/`query`). O grafo
e gerado pela **skill graphify**, que o agente roda: detecta os arquivos -> extrai entidades/relacoes
(estrutural por tree-sitter + semantica pelo proprio modelo do agente, tudo LOCAL) -> build/cluster ->
escreve `graph.json` + `GRAPH_REPORT.md` + `graph.html` na pasta `graphify-out/`. Passos:
1. `python -m graphify install --platform <claude|codex|opencode>` - instala a skill no coding agent hospedeiro.
2. O agente roda a skill apontando para a pasta do Client; a saida vai pra `squad/knowledge/graphify-out/`.
3. PROVADO end-to-end no Studio Farina (cliente farina, 29/jun): 39 nos, 53 arestas, 6 comunidades.
NOTA HONESTA: hoje a geracao depende do agente rodar a skill - nao ha hook que gere sozinho ao criar o
Squad. Enquanto isso, o setup-alia OFERECE e o agente gera sob demanda. (Auto-geracao no onboarding =
evolucao futura declarada.)

### Bonus: commit auditavel de memoria e grafo

Mudancas na Memory (`memory/`, `knowledge/`) e no `graphify-out/` sao commitadas com mensagem real
que descreve a evolucao - assim o segundo cerebro tem historia auditavel (o que mudou, quando, por
que), nao um diff anonimo. O commit respeita a fronteira da [governanca de ferramentas](#governanca-de-mcp):
`git push` continua **exclusivo do DevOps** (engineering.md). Commitar localmente com mensagem real
e do agente; publicar e do DevOps.

## Pipeline em CLI, nao sequencia tagarela (PTC)

Um pipeline deterministico de N passos deve virar UMA invocacao de CLI cujo unico custo de contexto
e o stdout - nao N chamadas tagarelas de ferramenta. Cada chamada de tool separada paga ida, volta e
ruido intermediario; um script que encadeia os N passos paga so o resultado final. E o passo 4 do
Frugality Check (mecanico antes de julgamento) levado ao pipeline inteiro: se a sequencia e fixa e
verificavel, ela e um comando, nao uma conversa.

Regra: quando os passos sao deterministicos e a ordem e fixa, colapse em 1 CLI e leia so o stdout.
Reserve as chamadas passo a passo para quando cada passo exige julgamento ou ramifica conforme o
resultado anterior.

Exemplo real do proprio produto - os scripts em `scripts/` ja sao esse colapso:
`smoke-test.ps1` roda dezenas de checks (engine, studio, squad, gates, ablation, encoding) numa
unica invocacao e devolve `ALL GREEN` ou a lista de falhas; conferir cada item por chamada de tool
custaria N vezes mais contexto. O mesmo vale para `install-loops.ps1` (le o yaml e gera a config num
passo).

## Budget e a metrica viva

Cada operacao tem um **Budget** (limite/meta de token). O Frugality Check protege o Budget antes do
gasto; o Loop de RSI mede o resultado depois. A metrica que prova a alma do Alia Flow:

> **Custo medio por Artifact cai com o tempo.** Se o custo por entrega sobe sem ganho de qualidade,
> e regressao - vira sinal pro RSI.

## Frugalidade nunca corta qualidade

Reduzir custo e obrigatorio; reduzir qualidade e proibido (Principio VIII). Na duvida entre a rota
barata e a rota segura, a qualidade do Artifact final ganha - e o gasto extra vira evidencia pro
Loop ajustar a regra. Economia cega que reprova no Gate nao economizou nada.

## Governanca de MCP

A gerencia de MCP (instalar, configurar, remover) e **exclusiva do DevOps**. Os demais agentes sao
consumidores: usam o que esta provisionado, nao mexem na infra.

A forma curada de declarar quais MCP sao aprovados e o catalogo `optional-mcps/` (raiz): cada servidor
e um diretorio com `manifest.yaml`, e presenca no diretorio = aprovacao. Ver
[optional-mcps/README.md](../optional-mcps/README.md).

## Erro de tool e frugalidade

Tool que falha ou e negada nao se repete identica: re-tentar igual queima token sem ganho (viola o
Budget). Leia o erro, ajuste a chamada ou troque de rota; negacao do operador se respeita, nao se
contorna. A disciplina completa esta na [regra de tool do Specialist](agents/persona-skeleton.md)
(secao 3, regra 4: erro e sinal, nao parede).

## Pesquisa segura (sem runaway)

> LEI: agente de pesquisa nao se multiplica e nao entra em loop. Pesquisa e SEQUENCIAL e LIMITADA.

Agentes com segundo cerebro de pesquisa (MCP de web/fontes, ex: notebooklm, perplexity) seguem um
contrato duro - a regua que impede o desastre de varrer o mundo em paralelo:

1. **Sequencial, nunca em enxame.** Uma consulta por vez, a um cerebro por vez. `max_parallel: 1`.
2. **Proibido auto-spawn.** O agente de pesquisa NUNCA cria sub-agentes nem dispara lote de buscas.
   Quem orquestra fan-out e a Alia - e so com aviso. `self_spawn: forbidden`.
3. **Fan-out so com aviso e aprovacao.** Qualquer busca em lote/paralela exige avisar a escala e o
   custo ANTES e ter o sim do operador. `fanout: human_approval`.
4. **Teto duro de consultas por Task.** Atingiu o teto, para e entrega o que tem. `max_queries_per_task`.
5. **Quota-aware, sem re-tentar em loop.** Checa a quota ANTES (ex: `pplx_usage`); erro ou quota
   estourada = PARA e reporta, nunca repete identico (e a regra de erro de tool aplicada a pesquisa:
   erro e sinal, nao parede). `on_quota_or_error: stop_and_report`.

**Rota de pesquisa (padrao).** Perplexity em busca normal (Pro) e a primeira parada - amplitude da
web. Modelo padrao: **Claude Sonnet 4.6 com thinking** (`pplx_claude_sonnet_think`); **JAMAIS Sonar**
(regra dura do operador). **Deep research NAO** (quota escassa; so a pedido explicito do operador).
NotebookLM e a escalada quando a Perplexity nao der conta: cerebro ancorado em fontes, com citacao,
mais forte para profundidade. Ordem: Perplexity normal -> (se nao bastar) NotebookLM. Uma de cada vez.

Esses campos vivem no `.yaml` do agente de pesquisa (bloco `research_limits`); o smoke reprova um
agente de pesquisa sem a trava declarada. O contrato estruturado esta em [tools.yaml](tools.yaml)
(`research_safety`).

## Segue

[Constituicao](constitution.md) - os Principios. [Persona](agents/persona.md) - a voz.
[Frugal Skills](features/frugal-skills.md) - o mecanico sem LLM.
[Manifesto: tools.yaml](tools.yaml) - as regras maquinaveis.
