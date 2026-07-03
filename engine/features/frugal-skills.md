# Frugal Skills

> Capacidades que rodam por SCRIPT (sem LLM) quando a tarefa e deterministica. Economia direta de
> token, sem perda de qualidade. Versao propria do executor por script do legado, reescrita em torno
> da nossa alma: fazer o maximo gastando o minimo. Contrato maquinavel ao lado em
> [frugal-skills.yaml](frugal-skills.yaml).

---

## O que e

Tarefa mecanica nao precisa de um modelo caro pra ser feita. Validar um JSON contra um contrato,
gerar um digest a partir do state, renomear arquivos por regra, checar paths, contar e somar - tudo
isso tem resposta unica e verificavel: roda por script, custo zero de token de modelo. A Alia separa
o que e MECANICO (Frugal Skill) do que exige JULGAMENTO (Specialist via LLM). Essa separacao e a
aplicacao operacional do principio VIII (Frugality Without Quality Loss): o caminho mais barato que
resolve com qualidade vence.

## Onde entra no roteamento

E o passo 4 do Frugality Check em [tools.yaml](../tools.yaml) (`mechanical_before_judgment`): antes
de delegar a um Specialist, a Alia pergunta se a tarefa cabe num script. Se cabe, a Frugal Skill
resolve e o token de modelo nunca e gasto.

1. Frugality Check classifica a tarefa: mecanica ou de julgamento?
2. Mecanica -> roda a Frugal Skill (deterministica, sem LLM); o resultado ja vem verificavel.
3. De julgamento (criar, decidir, avaliar) -> roteia pro Specialist MAIS CAPAZ.

## Catalogo de Frugal Skills

| Skill | O que faz | Onde e usada |
|-------|-----------|--------------|
| **validate-artifact** | Confere um Artifact contra o contrato do seu tipo | [Validated Artifacts](validated-artifacts.md) no Quality Gate |
| **state-digest** | Resume o `state.json` num digest legivel | Loop de status / governanca |
| **path-healthcheck** | Verifica existencia e integridade de paths | Pre-flight de Tasks |
| **file-organize** | Renomeia/move arquivos por regra declarada | Higiene de Studio |
| **data-compute** | Contagens, somas, formatacoes deterministicas | Preparo de dados pra Specialist |

## Invariante

Frugal Skill so executa o deterministico - nunca toma decisao que exige julgamento. Na duvida entre
script e Specialist, vence o Specialist: qualidade acima de economia. Mas onde o script resolve com
seguranca, usar o LLM e desperdicio - e o desperdicio tambem reprova no Gate (criterio Frugal).

## Diferenca frente ao legado

| Eixo | Legado | Alia Flow |
|------|--------|-----------|
| Conceito | Execucao por script embutida na infra de service | Frugal Skill como capacidade de primeira classe |
| Objetivo | Performance da plataforma | Economia de token DECLARADA e MEDIDA (`cost_per_artifact` cai com o tempo) |
| Governanca | Implicita no codigo | Passo explicito do Frugality Check; o RSI observa a metrica |

O legado executava scripts; nos transformamos isso num filtro de custo governado, com a frugalidade
como meta auditavel - nao um efeito colateral.

## Liga com

[Frugalidade / Tools](../tools.md) e o [contrato de selecao](../tools.yaml) - o Frugality Check.
[Quality Gate](../governance/quality-gate.md) - onde a validacao roda. [Validated
Artifacts](validated-artifacts.md) - a Frugal Skill canonica.
