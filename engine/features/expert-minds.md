# Expert Minds (Domain Packs)

> Cada Specialist carrega no segundo cerebro a metodologia de um mestre real do dominio.
> Versao propria do conceito de "mentes-clone" do legado: a IDEIA (emular o metodo de um mestre) e
> livre; a marca e o codigo do legado, nao. Aqui e nosso, com metodologias publicas e documentadas.
>

---

## O que e

Um Domain Pack que injeta, no segundo cerebro de um Specialist, o metodo de pensar de um mestre do
dominio. Em vez de um designer generico, um designer que raciocina como Brad Frost (atomic design).
Em vez de um copywriter qualquer, um que aplica os principios de Ogilvy. Em vez de um dev, um que
segue Kent Beck (TDD). E o Expert Mind que torna o Squad inteligente de verdade em vez de raso: ele
nao adiciona conhecimento de fato, adiciona um criterio de decisao - como o mestre escolheria,
priorizaria e reprovaria.

A ablacao provou o efeito: o mesmo modelo, com o Expert Mind do Ogilvy carregado, levou uma copy de
48 para 100 no scorer de qualidade. A metodologia muda a saida de forma medivel.

## Anatomia

```
engine/features/expert-minds/{dominio}/{mestre}.md
```

Cada arquivo de mestre e texto puro (prompt), carregavel no `knowledge/` de qualquer Specialist, e
segue sempre a mesma estrutura de quatro blocos:

| Bloco | Funcao no segundo cerebro |
|-------|---------------------------|
| **Principio central** | A tese unica do mestre, em uma frase - a ancora de todas as decisoes. |
| **Heuristicas de decisao** | Como o mestre escolhe entre opcoes; o "se X, entao Y" do metodo. |
| **Checklist de qualidade** | O que o mestre verifica antes de aprovar - vira insumo do Gate. |
| **Anti-patterns** | O que o mestre reprova na hora - o filtro negativo. |

## Catalogo atual

Mentes disponiveis hoje, prontas pra carregar. A estante cresce com o uso: dominio novo que se
repete vira Expert Mind novo, sempre nos quatro blocos acima.

| Dominio | Mestre | Metodo | Arquivo |
|---------|--------|--------|---------|
| copy | David Ogilvy | copy que vende, nao que impressiona | [copy/ogilvy.md](expert-minds/copy/ogilvy.md) |
| ads | Eugene Schwartz | niveis de consciencia e sofisticacao | [ads/eugene-schwartz.md](expert-minds/ads/eugene-schwartz.md) |
| design | Brad Frost | atomic design / design system | [design/brad-frost.md](expert-minds/design/brad-frost.md) |
| dev | Kent Beck | TDD (red, green, refactor) | [dev/kent-beck.md](expert-minds/dev/kent-beck.md) |
| growth | Sean Ellis | North Star e priorizacao por ICE | [growth/sean-ellis.md](expert-minds/growth/sean-ellis.md) |
| analytics | Avinash Kaushik | analytics acionavel, segmentado | [analytics/avinash-kaushik.md](expert-minds/analytics/avinash-kaushik.md) |

> Indice legivel por maquina em [`expert-minds/registry.yaml`](expert-minds/registry.yaml): o Squad
> Creator consulta o registry pra escolher a mente certa por dominio sem reler cada arquivo.

## Como funciona (com o Squad Creator)

1. Ao montar um Specialist, o Squad Creator classifica o dominio dele e consulta o `registry.yaml`.
2. Escolhe o(s) Expert Mind(s) que casam com aquele dominio (um dominio pode pedir mais de uma mente:
   um especialista de lancamento ganha Ogilvy + Eugene Schwartz).
3. O arquivo do mestre e copiado pro `knowledge/` do Specialist (o segundo cerebro dele).
4. O Specialist decide e revisa o proprio trabalho aplicando os principios do mestre.
5. O Loop de deep research mantem cada Expert Mind atualizado ao longo do tempo.

> Camadas: Expert Mind e a marca da Camada B (Specialist de dominio). O lider (Camada A) carrega o
> segundo cerebro COMPLETO do Client, nao um Expert Mind; o suporte (Camada C) nao carrega mente
> dedicada. Regra completa na [Biblioteca de Squads](squad-templates/README.md).

## Diferenca frente ao legado

- Legado: produto proprietario de "mentes-clone" - marca registrada, codigo fechado, pago.
- Alia Flow: Expert Minds - conceito livre, metodologias publicas redocumentadas por nos, codigo
  nosso. Pegamos a inteligencia do metodo, nunca a propriedade de ninguem.

## Invariante

Expert Mind ENRIQUECE a decisao do Specialist; nunca substitui o Quality Gate nem o DDD do Client.
O Gate continua sendo o juiz final, e o conhecimento especifico do Client sempre vence o metodo
generico do mestre quando os dois conflitam.

## Ver tambem

[Biblioteca de Squads](squad-templates/README.md) - quem carrega os Expert Minds e em que camada.
[Sistema de Squads](../squad-system.md) - a anatomia do Squad.
