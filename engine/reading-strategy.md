# Alia - Estrategia de Leitura (ler sem ler tudo)

> Como a Alia e os squads leem a base de conhecimento gastando o minimo de token: nunca varrer o
> arquivo inteiro quando um indice, uma assinatura ou uma fatia resolvem. E o Frugality Check (passo 2,
> tools.md) aplicado a TODA leitura de markdown - o mesmo principio do repo-map do Aider, adaptado a
> uma base de conhecimento em markdown. O manifesto maquinavel vive ao lado em
> [reading-strategy.yaml](reading-strategy.yaml). Sem acentos, sem emojis.

---

## Por que existe

Ler um diretorio inteiro para achar uma coisa e o desperdicio classico de token (e de contexto). A
pesquisa de mercado (Aider repo-map, cAST, repomix) converge num padrao simples: **indice barato
primeiro, leitura cara depois**. Para uma base de conhecimento em markdown - clientes, projetos,
tarefas - nao precisamos de banco vetorial nem embeddings (overkill, viola YAGNI): tres convencoes de
arquivo + convencao resolvem com zero dependencia.

## Os tres padroes (a regra da casa)

### 1. Indice mestre com teto (o repo-map de markdown)
Todo nivel navegavel tem um **indice de uma linha por item** que cabe pequeno - o `engine/MAP.md` do
motor e o exemplo canonico; cada Client tem o seu `knowledge/MAP.md`. Regra: o indice inteiro cabe no
teto (`index_budget_lines`); quando um nivel cresce demais, ele e fatiado, nao inchado. Ler o indice
(barato) decide o que abrir - em vez de abrir tudo para descobrir onde esta.

### 2. Assinatura antes do corpo (outline-first)
Cada doc abre com uma **assinatura** legivel sem ler o corpo: a primeira linha de titulo (`# ...`) e a
descricao de uma linha logo abaixo (o blockquote `> ...` que a casa ja usa). Decidir por assinatura -
como ler a declaracao de uma funcao sem o corpo - evita abrir o arquivo so para saber se e o certo.

### 3. Grep-por-secao (ler so a fatia)
Docs usam **headers previsiveis** (`## ...`) para que a leitura pegue so a secao necessaria (buscar o
header e ler N linhas de contexto), nunca o arquivo inteiro. Custo zero de infra, ganho imediato -
e o que o coding agent hospedeiro ja faz de melhor.

> Ordem de leitura: indice (1) -> assinatura (2) -> fatia (3). So se as tres nao bastarem, leia o
> arquivo inteiro. A metrica e a mesma do produto: custo medio por Artifact cai com o tempo (tools.md).

## Descartado de proposito (KISS/YAGNI)
Embeddings, RAG e grafos de PageRank sobre a KB markdown: complexidade e dependencia sem ganho no
nosso tamanho (centenas de arquivos). O grafo do graphify ja cobre a relacao semantica quando precisa
(tools.md, "Grafo obrigatorio"); para achar e ler arquivo, indice + assinatura + grep ganham.

## Liga com DDD e SDD
- **DDD** ja e trava do Gate (criterio 2): a leitura por assinatura respeita a linguagem ubigua -
  o indice e as descricoes usam os termos do glossario do Client.
- **SDD (spec-driven)**: o fluxo canonico e o [story-cycle](workflows/story-cycle.md) - Story + AC
  (criterio de aceite) ANTES do codigo, e o Gate confere a entrega contra a spec (criterio 1, prova
  de execucao). Ler a spec e um caso de leitura seletiva: assinatura + secao de AC, nao o doc todo.

## Mecanismo
`scripts/kb-index.ps1` gera/valida o `knowledge/MAP.md` de um Client: monta o indice de uma linha por
doc (a partir do titulo + assinatura) e REPROVA se o indice estourar o teto ou se um doc nao tiver
assinatura. E o cadeado que impede a base virar um monte de arquivos sem indice.

## Segue
[tools.md](tools.md) (Frugality Check) - [MAP.md](MAP.md) (o indice do motor) -
[reading-strategy.yaml](reading-strategy.yaml) (as regras maquinaveis).
