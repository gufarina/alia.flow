# Loop Designer (a Alia receita os loops de cada projeto)

> A governanca por loops so vira pratica quando alguem decide QUAIS loops cada projeto merece. O
> Loop Designer e essa capacidade da Alia: olhar um projeto, propor o conjunto certo de loops,
> grava-los como registros reais e revisa-los na data marcada (criar, gerenciar, revisar - lei do
> operador). O catalogo de arquetipos vive na governanca; aqui mora a DECISAO de quais aplicar e
> por que. As regras desta decisao tem um manifesto estruturado ao lado em
> [loop-designer.rules.yaml](loop-designer.rules.yaml). Sem acentos, sem emojis.

---

## O que e

Cada projeto tem necessidades diferentes de governanca. Um SaaS com codigo precisa de checagem de
drift a cada commit; um projeto de marca precisa de pesquisa diaria sobre tendencia de design; um
projeto pausado nao deve carregar nenhum loop agendado - seria queima de token sem retorno. Aplicar
o mesmo pacote de loops a todos e caro e cego. O Loop Designer e a habilidade da Alia de **receitar
os loops sob medida** para o perfil de cada projeto.

Divisao de responsabilidade, sem sobreposicao:
- A [governanca/loops.md](../governance/loops.md) (+ [loops.catalog.yaml](../governance/loops.catalog.yaml))
  e o **formulario**: define quais loops existem, seu contrato e seu custo.
- O Loop Designer e o **medico**: examina o projeto, prescreve do formulario o que cabe, na dose
  (cadencia) certa, e marca o retorno (`review_on`).

## As 3 capacidades (sugerir, criar, revisar)

1. **Sugerir** - a partir do perfil do projeto, a Alia monta um Plano de Loops (quais loops, com
   que cadencia, dono e custo) e justifica cada escolha por uma regra explicita. O operador aprova
   ou ajusta antes de virar registro.
2. **Criar** - os loops aprovados sao gravados como registros reais em `clients/{id}/loops.yaml` e
   ligados ao mecanismo: o engine cobre os de evento; o unico agendado sobrevivente
   (`memory-curator`) roda quando a prova roda (ver "Execucao sob demanda"). Sem agendador de SO -
   e estado escondido, invisivel, nao viaja com o produto (mandato do CEO, 10/08/2026).
3. **Revisar** - na data de `review_on`, a Alia audita o loop pelo `last_result`: se agregou valor,
   mantem (com novo `review_on`); se nao, reduz a cadencia ou aposenta. Loop sem retorno e
   aposentado com motivo - nenhum loop sobrevive por inercia.

## Execucao sem agendador (CORTE 10/08/2026, mandato do CEO)

O loop NAO precisa de agendador de SO para existir - Task Scheduler e estado escondido na maquina:
invisivel, nao viaja com o produto, dependencia de sistema operacional. `run-loops.ps1` (runner sob
demanda) e `install-loops.ps1` (instalador no Task Scheduler) foram removidos.

O unico loop agendado que sobrevive (`memory-curator`) roda pelo mecanismo mais simples possivel:
`scripts/smoke-test-studio.ps1` ja chama `memory-curator.ps1 -Validade` toda vez que a prova roda,
e a prova roda em todo trabalho relevante. Rotina que precisa rodar "de vez em quando" roda quando
a prova roda - zero agendamento, zero estado fora do repositorio. Os demais scans mecanicos
(health-check, ddd-drift-scan, evolution-scan, debt-scan, squad-report) sao comando manual: o
operador (ou a Alia, se pedido) roda `scripts/{id}.ps1 -Client {id}` quando quiser, sem cadencia
fixa. `deep-research` segue agente-driven, sob demanda via skill, nunca agendado.

Configuravel por projeto: o `loops.yaml` do cliente declara quais loops existem e em que cadencia
nominal (`memory-curator`: semanal), mesmo sem mecanismo de agendamento algum por tras do numero.

## Catalogo de loops (de onde a Alia escolhe)

A Alia nunca inventa um loop: seleciona do catalogo da governanca e ajusta apenas a cadencia. O
quadro abaixo e o resumo operacional; o contrato completo e o manifesto estao em
[loops.catalog.yaml](../governance/loops.catalog.yaml).

| id | trigger | cadencia padrao | dono | custo | produz |
|----|---------|-----------------|------|-------|--------|
| gate-on-artifact | evento (Artifact pronto) | none | Squad Owner (T1) | baixo | verdict do Quality Gate |
| drift-on-commit | evento (commit) | none | Squad Owner (T1) | baixo | desvio de DDD |
| pr-review | evento (PR aberto) | none | Squad Owner (T1) | medio | verdict de revisao |
| fix-on-fail | evento (gate Fail) | none | Specialist -> Owner | medio | tentativas de correcao |
| memory-curator | agendado | semanal | Alia (T2) | baixo | memorias/regras consolidadas; stale arquivado |

> Os quatro de evento (gate-on-artifact, drift-on-commit, pr-review, fix-on-fail) custam zero ate o
> evento acontecer - por isso ficam ligados por padrao em todo projeto ativo. `memory-curator` e o
> UNICO agendado que a Alia recomenda por padrao hoje (10/08/2026): e o unico com consumidor real
> medido (`scripts/smoke-test-studio.ps1`) e roda de graca. `health-check`, `ddd-drift-scan`,
> `evolution-scan`, `debt-scan`, `squad-report` foram cortados do catalogo agendavel (nenhum tinha
> leitor do proprio relatorio) - continuam existindo como **comando manual**
> (`loops.catalog.yaml` -> `manual_commands`); a Alia pode sugerir rodar um deles pontualmente, mas
> nao os instancia mais como loop agendado por padrao. `deep-research` tambem saiu do agendamento
> (agente-driven, custa modelo, sem freio de orcamento real) - vira capacidade sob demanda: a Alia
> aciona quando o operador pede pesquisa de dominio, nunca via Task Scheduler.

## O raciocinio (perfil do projeto -> loops recomendados)

A Alia le o perfil do projeto e aplica as regras abaixo. O perfil sai do registro do cliente
(client.md / state.json / squad.yaml) sem reprocessar nada novo: status, se tem codigo, dominios do
squad, velocidade do conhecimento de cada dominio, se tem DDD documentado. As mesmas regras estao
codificadas em [loop-designer.rules.yaml](loop-designer.rules.yaml) para aplicacao deterministica.

| Regra | Condicao | Loops |
|-------|----------|-------|
| R0 Frugal | status != active (pausado/arquivado) | NENHUM loop agendado. So eventos, se o projeto for tocado. |
| R1 Baseline | status = active | memory-curator (semanal) - unico agendado por padrao (corte 10/08/2026) |
| R2 Eventos | status = active | gate-on-artifact + fix-on-fail (sempre) |
| R3 Codigo | has_code = true | drift-on-commit + pr-review |
| R4 DDD | has_ddd = true | comando manual `ddd-drift-scan` sob demanda (nao agendado - ver corte) |
| R5/R6 Conhecimento | qualquer velocidade | `deep-research` fica sob demanda (skill aciona quando o operador pede pesquisa de dominio); nunca agendado |

> Velocidade do conhecimento = o quanto o estado-da-arte de um dominio muda; hoje so afeta a
> PRIORIDADE que a Alia da ao pedido sob demanda de `deep-research`, nao mais uma cadencia
> agendada (corte 10/08/2026: agente-driven custa modelo e nao tinha freio de orcamento real).
> R0 e a regra que prevalece: projeto fora de `active` zera os agendados antes de qualquer outra.

## O registro de um loop (o dado real)

Cada loop aprovado vira um registro em `studio/clients/{id}/loops.yaml`. O schema obrigatorio e
validado pelo smoke test (`id`, `trigger`, `cadence`, `owner`, `status`, `review_on` em todo loop) e
formalizado no `instance_schema` de [loops.catalog.yaml](../governance/loops.catalog.yaml). Formato:

```yaml
- id: deep-research
  trigger: scheduled          # scheduled | event
  cadence: daily              # daily | weekly | none (none = evento, sem cadencia)
  owner: alia                 # alia (T2) | squad-owner (T1) | specialist
  cost_class: medio           # baixo | medio | alto
  domains: [design, copy, produto]   # so os dominios ativos (frugal)
  produces: "knowledge atualizado + proposta de RSI"
  mechanism: "agente-driven via MCP perplexity (Sonnet 4.6 thinking), sob demanda"
  proactive: on               # on | off - Alia sugere rodar quando devido (default on em projeto ativo)
  status: active              # proposed | active | retired
  created: "2026-06-14"
  review_on: "2026-07-14"     # todo loop nasce com data de revisao (lei do operador)
  last_result: null           # resumo do ultimo retorno (preenchido nas revisoes)
```

## Ciclo de vida (criar, gerenciar, revisar)

```
proposed --(operador aprova)--> active --(chega o review_on)--> em revisao
em revisao --(agregou valor)--> active (novo review_on)
em revisao --(nao agregou)----> retired (com motivo registrado)
```

Nenhum loop e eterno por inercia. Todo loop carrega `review_on`. Na revisao, a Alia le o
`last_result` e decide manter, ajustar a cadencia ou aposentar. Loop sem retorno e aposentado - nao
fica queimando token escondido.

## Quando a Alia roda o Loop Designer

- **Proativo, ao nascer um squad** - logo apos o Squad Creator montar o time, a Alia propoe o Plano
  de Loops do cliente novo. Nenhum projeto comeca sem governanca.
- **Proativo, na revisao agendada** - quando chega o `review_on` de um loop, a Alia o revisa.
- **Sob demanda** - o operador pede "revise os loops do cliente X" via a skill / comando `*loops`.

## Frugalidade (inegociavel)

- Projeto fora de `active` = zero loop agendado (R0).
- deep-research roda SO nos dominios ativos e de velocidade alta - nunca no squad inteiro.
- Cadencia e o minimo que pega o problema, nao o maximo que a infra permite.
- Cada loop declara seu `cost_class`; a Alia soma o custo do plano antes de aprovar e o expoe ao
  operador. Custo desconhecido nao entra em producao.

## Liga com

[Governanca / Loops](../governance/loops.md) (o catalogo de arquetipos e os 2 tiers) - 
[loops.catalog.yaml](../governance/loops.catalog.yaml) (o contrato estruturado dos arquetipos) - 
[loop-designer.rules.yaml](loop-designer.rules.yaml) (as regras R0-R6 em manifesto) - 
[Deep Research Loop](deep-research-loop.md) (o loop de conhecimento vivo do catalogo) - 
[Squad Creator](../agents/squad-creator.md) (quem dispara o Loop Designer ao nascer um squad) - 
[RSI](../rsi/rsi.md) (para onde vai o aprendizado dos loops).

---

*Alia - Delegue. Nao opere.*
