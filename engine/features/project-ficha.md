# Ficha de Project - a camada do meio, magra por desenho

> Desenho do LATTICE, TASK-509 (09/09/2026), auditoria de harness v3. Motivo medido: `Project` era
> so uma string livre dentro da Task. Em 10 Clients, um unico tinha pasta `projects/` - e a unica
> ficha que existia REDECLARAVA `codePath` e squad, que ja moram na ficha do Client. Resultado: 95
> pares Client/Project com nome livre e nenhuma heranca de verdade.

## A lei da camada

Camada de baixo NUNCA redefine o que a de cima ja resolveu, e NUNCA copia a de cima inteira.

- **Client** (`clients/<id>/client.md`) - identidade, restricoes, squad, `codePath`, invariantes.
  Vale para TODO projeto daquele Client. Nunca se repete numa ficha de projeto.
- **Project** (`clients/<id>/projects/<slug>.md`) - o recorte: arquitetura e decisoes DAQUELE
  projeto, e o estado atual. Herda o Client por REFERENCIA, com um link de volta.
- **Task** (o registro em `state.json`) - a intencao pontual. Descartavel ao fim. O que virar
  permanente SOBE de camada: decisao de arquitetura vai para a ficha do Project, restricao
  duradoura vai para a ficha do Client.

## O modelo (6 campos, nada alem)

```markdown
# Projeto: <nome>

**client_id:** <id>  |  **project_id:** <slug>

## O que e
Uma ou duas frases: o recorte deste projeto dentro do Client.

## Arquitetura e decisoes deste projeto
So o que NAO esta na ficha do Client. Decisao com data e motivo.

## Estado atual
Onde parou. Uma linha por frente viva.

## Client
clients/<id>/client.md - identidade, restricoes, squad e codePath moram la. Nao repita aqui.
```

## Quando criar (e quando NAO criar)

- **Project novo** nasce com ficha, no passo IDENTIFICA, antes da primeira Task dele.
- **Project que ja existe** e so citado na Task. Nao se reescreve ficha a cada Task.
- **Client com um projeto so**: a ficha PODE ser uma secao dentro do proprio `client.md`. Nao crie
  arquivo separado para inventar hierarquia onde nao ha duas frentes. Burocracia sem heranca real
  e custo sem ganho.
- **Migracao do acervo**: fichas para os 95 pares historicos NAO se criam em massa. Cada par ganha
  ficha quando aquele projeto voltar a receber Task. Decisao do operador, nunca varredura.

## Prova de que a ficha esta certa

Abra a ficha do Project e a do Client lado a lado: nenhuma linha aparece nas duas. Se aparecer,
a linha pertence ao Client e sai da ficha do Project.
