# Alia Flow - Governanca por Loops

> Como o Alia Flow garante que projetos evoluem, mantem qualidade e aderem ao DDD - sem a Alia
> virar gargalo. Este arquivo e o CATALOGO da governanca: define os 2 tiers, a taxonomia de loops
> (dinamicos e agendados) e o contrato de cada loop. O manifesto estruturado fica ao lado em
> [loops.catalog.yaml](loops.catalog.yaml). Quem RECEITA por projeto e a Alia, via a capacidade
> Loop Designer ([features/loop-designer.md](../features/loop-designer.md)), que materializa a
> selecao em `clients/{id}/loops.yaml`. Sem acentos, sem emojis.

---

## Hierarquia em 2 tiers

A governanca tem profundidade: cada tier ve um nivel de granularidade e nenhum reprocessa o
trabalho do outro. E o que mantem a Alia frugal e escalavel ao mesmo tempo.

- **Tier 1 - O Squad Owner revisa o time.** Cada Squad tem um Owner (o gateway). Ele olha
  diretamente o Artifact de cada Specialist, garante que passou no
  [Quality Gate](quality-gate.md) e que esta aderente ao DDD do Client. O Owner e o unico que
  toca o trabalho cru.
- **Tier 2 - A Alia revisa os Owners.** A Alia NAO micro-gerencia Specialists. Ela cobra dos
  Owners por excecao: os loops rodaram? Os gates passaram? Ha drift de DDD? O projeto evoluiu?
  A Alia age sobre desvios, bottlenecks e estagnacao - nunca sobre o caso comum.

> Por que 2 tiers e nao 1: se a Alia revisasse cada Artifact, ela reprocessaria tudo (caro) e
> viraria gargalo de N squads. Delegar a revisao crua ao Owner e elevar a Alia a auditora de
> excecoes torna a governanca O(squads), nao O(artifacts).

## Loops dinamicos (event-driven)

Disparados por um evento - reacao imediata, sem cadencia. Sao o sistema imunologico do projeto:
respondem no instante em que algo acontece.

| id | Gatilho | O que roda | Owner | Registra na Memory |
|----|---------|-----------|-------|--------------------|
| `gate-on-artifact` | Task concluida / Artifact pronto | [Quality Gate](quality-gate.md) | Squad Owner | verdict do gate |
| `drift-on-commit` | Mudanca de codigo/design (commit) | DDD anti-drift check | Squad Owner | desvio (se houver) |
| `pr-review` | PR aberto | revisao + gate | Squad Owner | verdict da revisao |
| `fix-on-fail` | Gate = Fail | loop de correcao (max N abordagens *diferentes*) | Specialist -> Owner | tentativas |

## Loops agendados (scheduled)

Rodam em cadencia fixa, independentemente de evento. Sao a rotina de saude: pegam o que um
gatilho pontual nao ve - acumulo, afastamento lento, ausencia de progresso.

| id | Cadencia padrao | Owner | Funcao |
|----|-----------------|-------|--------|
| `health-check` | diaria | Squad Owner | o projeto esta vivo e consistente? |
| `ddd-drift-scan` | diaria | Squad Owner | entregaveis/codigo se afastando da linguagem ubiqua? |
| `deep-research` | diaria | Alia | atualiza knowledge do dominio + propoe RSI |
| `evolution-scan` | semanal | Alia | o projeto avancou desde o ultimo ciclo? (estagnacao -> bottleneck) |
| `debt-scan` | semanal | Alia | Concerns marcados que nunca foram resolvidos |
| `squad-report` | semanal | Squad Owner | status que a Alia (Tier 2) revisa |
| `memory-curator` | semanal | Alia | memorias/regras consolidadas; stale arquivado (nunca deletado) |

> Cadencias sao *padrao*; o operador ajusta. Cada loop agendado tem um mecanismo real (`scripts/*.ps1`)
> - um loop sem mecanismo e uma promessa vazia, e o Quality Gate reprova. Por padrao a Alia roda os
> agendados SOB DEMANDA (a skill Loop Designer sugere proativamente quando devido; o operador aceita,
> a Alia roda via `scripts/run-loops.ps1` - 1 passada, 1 resumo). O Task Scheduler
> (`scripts/install-loops.ps1`) e OPCIONAL, para quem quer execucao sem sessao aberta. Governanca nao
> exige infra de SO nem que o operador rode script na mao.

## Contrato de 6 elementos por loop (OPP-57)

> LEI: todo loop instanciado (`clients/{id}/loops.yaml`) declara os 6 campos abaixo. Loop
> `status: active` sem qualquer um dos 6 preenchidos = FAIL no smoke. Fonte: orange-book de
> Loop Engineering (secao 09) - sao as guardas que decidem se o loop se enrasca ou entrega.

| # | Campo | Pergunta que responde |
|---|-------|-----------------------|
| 1 | `discovery_source` | De onde o loop ACHA o proprio trabalho (arquivo/scan/evento que le)? |
| 2 | `state_file` | Onde a volta registra "onde parou" (memoria em disco entre voltas)? |
| 3 | `evaluator` | Quem diz NAO (instancia != executor; deterministico quando possivel)? |
| 4 | `isolation` | O que o loop pode tocar (escopo de escrita; "none" explicito quando so le)? |
| 5 | `token_cap` | Teto de gasto: `per_round` e `daily` (mecanismo: `scripts/budget-check.ps1`, OPP-58; `cost_class` vira insumo, nao substituto)? |
| 6 | `human_review_point` | Qual passo para e espera humano? "none" e PROIBIDO em loop que escreve fora de staging. |

O check do smoke e de PRESENCA/formato; a verdade do valor declarado e cobrada pelo Quality Gate
normal (validador semantico foi cortado por YAGNI - ver OPP-57).

## O que os loops detectam

Os tres sinais que a governanca caca, em ordem de urgencia:

- **Drift de DDD** - entregaveis/codigo se afastando da linguagem e dos bounded contexts do
  Client. Sinal precoce de erosao de qualidade. Pego por `drift-on-commit` (imediato) e
  `ddd-drift-scan` (acumulado).
- **Estagnacao** - projeto sem evolucao no periodo. Sinal de bottleneck que a Alia precisa
  destravar. Pego por `evolution-scan`.
- **Debito** - Concerns liberados com ressalva que nunca viraram correcao. Pego por `debt-scan`.

## Memoria e RSI

Todo resultado de loop (verdict, drift, estagnacao, debito) e registrado na Memory COM evidencia
e alimenta o RSI: padroes de falha recorrentes viram propostas de melhoria do proprio framework -
prompts, gates, Domain Packs. O sistema fica melhor *e mais barato* a cada Loop. Sem registro com
evidencia, nao houve Loop.

## Frugalidade (lei dura dos loops)

Loop caro e loop morto - o operador desliga. Por isso todo loop OBRIGA:

- Consultar Memory/grafo ANTES de reprocessar (Memory Before Reprocessing).
- Revisao incremental - so o que mudou desde o ultimo ciclo.
- O modelo certo para cada verificacao - sem canhao para mosquito.
- `cost_class` declarado (baixo | medio | alto) no manifesto - o que nao tem custo conhecido nao
  entra em producao.

## Ciclo de vida de um loop

Um loop nao e eterno por decreto; ele nasce, e revisado e pode ser aposentado.

1. **Criar** - a Alia (Loop Designer) le o perfil do projeto, escolhe os loops do catalogo e os
   instancia em `clients/{id}/loops.yaml`. Todo loop nasce com `status` e `review_on`.
2. **Gerenciar** - o loop roda na sua cadencia/gatilho; cada execucao grava `last_result` na
   Memory.
3. **Revisar** - na data de `review_on`, a Alia decide: mantem, ajusta a cadencia, ou aposenta
   (`status: retired`). Loop que nao gera sinal util e custo puro.

> `review_on` e obrigatorio em todo loop instanciado (lei do operador): um loop sem data de
> revisao vira fundo de gaveta caro.

## Liga com
[Quality Gate](quality-gate.md) (a regua que `gate-on-artifact` aplica) - 
[Loop Designer](../features/loop-designer.md) (quem receita os loops por projeto) - 
[loops.catalog.yaml](loops.catalog.yaml) (o manifesto estruturado deste catalogo).

---

*Alia - Delegue. Nao opere.*
