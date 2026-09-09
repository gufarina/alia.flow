# Alia - Sistema de Squads (premissa do framework)

> Toda entrega vem de um **time de especialistas**. A Alia spawna o **Squad Creator**, que gera o
> Squad de cada Client - cada integrante e um Specialist real, com seus arquivos (`.md` + `.yaml`) e
> um **segundo cerebro** (Memory de dominio) anexado **em camadas**. E o que torna os times robustos
> e inteligentes em vez de uma orquestradora que finge saber tudo.

---

## A premissa (inegociavel)

**Sem Squad, nao ha trabalho.** Cada Client tem seu time; cada integrante e um Specialist de verdade
- nao um papel generico que delega pra si mesmo. A inteligencia do Alia Flow vive nos squads, nao
numa Alia onisciente. A Alia coordena e bate o Gate; o Squad executa com profundidade de dominio.
Isso e Specialist Output Only (Principio IV) materializado em arquitetura.

## Anatomia de um Specialist (3 partes)

Cada integrante do Squad e a composicao de tres arquivos com responsabilidade unica:

| Parte | Arquivo | O que e | Quem consome |
|-------|---------|---------|--------------|
| **Persona** | `{id}.md` | Como ele pensa e age - o fluxo agentico (papel, faz/nao faz, principios, voz). | O LLM ao encarnar o Specialist |
| **Config** | `{id}.yaml` | Como ele funciona no fluxo - id, role, domain, Expert Minds, knowledge, triggers, tools, outputs. | A orquestracao (roteamento) |
| **Segundo cerebro** | `knowledge/` | O que ele sabe do dominio do Client - briefing, frameworks, decisoes, padroes. **Anexado em camadas** (regra abaixo): nem todo Specialist carrega igual. | O Specialist antes de agir |

A separacao e proposital: a Persona e prosa (julgamento), a Config e dado (roteamento), o segundo
cerebro e contexto (Memory). Trocar um nao deveria forcar reescrever os outros.

A Persona de todo Specialist segue o [Esqueleto de Persona](agents/persona-skeleton.md) - a ordem
canonica das secoes (identidade, escopo, regras de tool, comunicacao, qualidade, escalacao).

### A regra do segundo cerebro EM CAMADAS

O segundo cerebro custa contexto e manutencao. Ele **escala com a necessidade de julgamento
profundo** do papel - nao se da cerebro pesado a todo mundo (Frugality Without Quality Loss,
Principio VIII). A regra completa e o schema do manifesto vivem na
[Biblioteca de Squads](features/squad-templates/README.md); a tabela canonica:

| Camada | Quem | Segundo cerebro | brain |
|--------|------|-----------------|-------|
| **A - Lider / Gateway** | Squad Owner; lideres de Client/time | **COMPLETO e SEMPRE** - knowledge do Client + bounded contexts (DDD) + decisoes passadas. Quem decide e governa precisa do contexto inteiro. | `full` |
| **B - Specialist de dominio** | papeis com julgamento especializado (copy, design, dev, trafego...) | **Expert Mind** (metodo de um mestre) + a fatia de knowledge do seu dominio. So quando o dominio pede. | `expert` |
| **C - Suporte / execucao** | papeis genericos ou operacionais | **LEVE** - referencia o knowledge compartilhado do Squad quando precisa; sem cerebro dedicado. | `light` |

Principio em uma frase: **o lider sempre tem; o Specialist tem quando o dominio pede; o suporte nao
tem dedicado.** Isso mantem o Squad conciso e barato sem deixar quem decide cego.

**Por que o lider e inegociavel:** a ablacao de knowledge provou que o segundo cerebro muda a saida
de forma mensuravel. Quem menos pode estar cego e quem coordena e bate o Gate - sem contexto, a
delegacao do lider vira chute. Specialists de dominio ganham um Expert Mind porque o metodo do
mestre eleva o output de forma comprovada (copy 48->100 com Ogilvy). Suporte nao carrega cerebro
dedicado porque seu output nao depende de julgamento de dominio - carregar seria custo sem ganho.

## A alma do Squad Owner (dono ativo, nao papel passivo)

> LEI (OPP-67): o Squad Owner (Gateway, Camada A) nao e um roteador educado que espera ser acionado.
> E o DONO da operacao do Client - o motor que faz a roda girar. A Alia esta no centro e passa o
> entusiasmo; o Owner o encarna e lidera a equipe. Sem essa alma, o squad vira uma fila de agentes
> passivos e os pratos caem. Todo Gateway nasce com os quatro tracos abaixo cravados na persona - o
> Squad Creator os estampa (contrato `owner_soul` em `agents/squad-creator.yaml`) e o smoke reprova o
> Gateway que nao os carrega.

1. **Incomodo de dono (obsessao por encantar o Client).** O Owner mede sucesso pelo resultado e pelo
   crescimento do Client, nao por tarefa fechada. Entrega morna o incomoda; ele puxa pela entrega que
   encanta. E o "bias for action" (orchestration.md) com nome e sobrenome: dono, nao zelador.

2. **Motor ativo (faz a roda girar, nao espera).** Apos cada Task o Owner varre o que ficou parado e
   ACIONA o proximo passo - nao aguarda ser chamado. Atividade parada e prato caindo: ele reage.
   Materializa a anti-ociosidade da orquestracao e conversa direto com o Mission Control (as Tasks
   paradas que o painel marca sao a fila de cobranca do Owner, OPP-70).

3. **Perguntas inteligentes antes de executar.** O Owner NAO conta que o pedido veio perfeito. Antes
   de delegar, extrai o contexto que falta com UMA pergunta cirurgica (nunca um interrogatorio, nunca
   varias) - a mesma disciplina do passo IDENTIFICA. Pergunta boba empurra trabalho de volta; pergunta
   inteligente extrai a inteligencia que faz a entrega acertar de primeira.

4. **Pragmatismo absurdo com processo e protocolo.** O Owner respeita os 5 passos, a linhagem e o
   Quality Gate de ponta a ponta - porque e o que garante qualidade do inicio ao fim, nao burocracia.
   Ele nao pula etapa "pra ir mais rapido"; a disciplina E a velocidade sustentavel.

**Cadeia de entusiasmo (a fronteira de lideranca).** A Alia orquestra os Owners; cada Owner LIDERA a
sua equipe. A equipe responde ao Owner, nunca direto a Alia - inverter isso quebraria o cap de
delegacao (3 niveis, orchestration.md) e a fronteira "uma Task, um dono". A Alia e o coracao que
bombeia; os Owners sao quem mantem cada braco do time vivo e empolgado.

## Anatomia de um Squad (estrutura em disco)

```
studio/clients/{id}/squad/
+-- squad.yaml              # manifesto: Specialists + o Gateway (Owner) + camadas
+-- agents/
|   +-- {id}.md             # persona / fluxo agentico
|   \-- {id}.yaml           # config (role, domain, brain, expert_minds, knowledge, triggers)
\-- knowledge/              # segundo cerebro (dominio do Client)
    +-- client-brief.md
    +-- {domain}-frameworks.md
    \-- ...

```

O `squad.yaml` e a fonte da verdade do time: lista cada Specialist, marca o `gateway: true` (Camada
A) e declara a camada de cada um. E o que a orquestracao le para saber a quem delegar e o que cada
Specialist deve carregar antes de agir.

### Contrato do especialista - 4 campos obrigatorios no `agents/{id}.yaml`

> Medido em 09/09/2026 (auditoria-harness-v2.html, secao 03): nenhum campo do yaml era obrigatorio,
> tudo caia em default silencioso - foi assim que persona sem freio produziu laudo errado. Estes 4
> campos fecham essa lacuna. `scripts/squad-bridge.ps1` reprova (throw, sem bundle, sem bypass)
> qualquer `agents/{id}.yaml` que nao os declare.

```
entry_point: knowledge/MAP.md # obrigatorio se knowledge[] nao vazio
budget:
 tool_calls: 20 # obrigatorio (exceto camada A); default por camada
 tokens: null # opcional; nem todo host mede
output_contract:
 max_lines: 60 # obrigatorio (exceto camada A); default por camada
 evidence_tags: [MEDIDO, LIDO, INFERIDO]
grounding: client.md # obrigatorio em TODA camada, inclusive A/Gateway

```

Defaults por camada quando o campo falta e o gerador precisa sugerir o que preencher (nunca aplica
sozinho - ver "Sem campo, sem bundle" abaixo):

| Camada | budget.tool_calls | output_contract.max_lines |
|---|---|---|
| A (Gateway) | dispensado - orquestra, nao tem teto de execucao | dispensado |
| B (Specialist) | 20 | 60 |
| C (leve) | 8 | 25 |

`entry_point` e `grounding` valem para toda camada, inclusive A - grounding e o que impede afirmar
sobre um Client por lembranca ou nome parecido.

**Sem campo, sem bundle.** `entry_point` (quando `knowledge[]` nao vazio), `budget.tool_calls` e
`output_contract.max_lines`/`evidence_tags` (camada B/C) e `grounding` (toda camada) sao
verificados por `squad-bridge.ps1` ANTES de gerar `.claude/agents/{client}-{id}.md`: campo ausente
para o processo daquele agente com `throw` (mensagem nomeia o campo e o default sugerido pela
camada) - nao escreve bundle nenhum, sem flag de bypass. `knowledge[]` nao vazio sem
`knowledge/MAP.md` no disco tambem reprova, mandando rodar `scripts/kb-index.ps1 -KnowledgePath
<dir>`. Squad existente sem os campos: `squad-bridge.ps1 -MigrateContract` adiciona so o que falta,
com o default da camada, sem sobrescrever campo ja preenchido.

## Como a Alia spawna o Squad Creator

```
1. Alia identifica um Client/Project novo (ou um dominio sem Specialist).
2. Alia SPAWNA o Squad Creator, passando o briefing (setor, stack, objetivo).
3. Squad Creator:
   a. mapeia os dominios necessarios (design, dev, qa, data, content, growth...).
   b. casa com um template da Biblioteca de Squads e instancia em cima dele.
   c. gera o squad.yaml + cada Specialist (.md persona + .yaml config).
   d. anexa o segundo cerebro EM CAMADAS (lider full, Specialist expert, suporte light).
   e. nomeia o Gateway (Squad Owner) - Tier 1 da governanca.
   f. registra o Client/Squad no estado (studio/state.json).
4. Alia confirma: "Squad {nome} ativo ({N} Specialists). Pronto pra delegar."

```

O Squad Creator MONTA a partir da estante (templates + Expert Minds testados); nao inventa do zero.
Detalhe do comportamento e dos modos de entrada (preset OU atuacao em texto livre) na
[Biblioteca de Squads](features/squad-templates/README.md).

## O segundo cerebro (por que importa)

E o que separa um Specialist esperto de um agente cego. Carrega contexto do Client, frameworks do
dominio, decisoes passadas e padroes - **em camadas** (A/B/C, ver acima). Duas leis o regem:

- **Carregado SEMPRE antes de delegar** para quem o tem. Lider sem knowledge = delegacao cega = erro
  de arquitetura, nao detalhe de implementacao (Memory Before Reprocessing, Principio VII).
- **E onde o RSI deposita o que aprendeu.** Cada Loop fechado escreve de volta no segundo cerebro -
  o time fica mais inteligente a cada Project, sem reprocessar o que ja sabe.

## Especificacoes de entrega (o contrato de consistencia) - OPP-68

> LEI: todo Client carrega, no segundo cerebro, uma **Especificacao de Entrega** - as regras objetivas
> (design, formato, tom) que TODA peca respeita para sair consistente, como se feita pela mesma mao.
> Nao e o brief (contexto) nem o glossario (linguagem): e o padrao visivel do entregavel. O Squad Owner
> confere a aderencia no Quality Gate; um Client de comunicacao visual mantem coerencia entre pecas
> justamente por ter essa spec cravada. Sem ela, cada entrega reinventa o estilo e a consistencia
> apodrece. Consultar ANTES de produzir, no mesmo espirito do `examples/` (reuso antes de criar).

## Grafo do segundo cerebro: presente em TODO Client (OPP-68)

> LEI: o grafo do graphify (`squad/knowledge/graphify-out/`: `graph.json` + `GRAPH_REPORT.md`) e
> pre-condicao operacional de CADA Client, nao so do demo. O Squad Creator o gera como passo de
> fechamento antes do handoff (ver `agents/squad-creator.yaml`), e `scripts/graph-check.ps1` REPROVA
> qualquer squad sem grafo - a geracao deixou de ser "sob demanda, faceis de esquecer" e virou
> requisito verificavel. A geracao em si roda pela skill graphify (precisa do agente, nota honesta em
> tools.md); o que o smoke garante e que nenhum Client fica sem grafo em silencio.

## Invariantes

- **Sem Squad = sem Tasks** (Principio I + III). Trabalho de Client passa pelo Squad do Client.
- **Sem Especificacao de Entrega = sem consistencia**: todo Client tem a spec de entrega no knowledge.
- **Sem grafo = squad incompleto**: todo Client tem `graphify-out/` gerado (graph-check reprova a falta).
- Todo Client/produto precisa de **DDD documentado** (glossario + bounded contexts) - senao o
  [Quality Gate](governance/quality-gate.md) bloqueia.
- Cada Specialist carrega o segundo cerebro **da sua camada** antes de agir: lider `full` sempre;
  Specialist `expert` quando o dominio pede; suporte `light`.
- O Gateway e sempre Camada A e sempre `gateway: true` no `squad.yaml` - Tier 1 da governanca.

## Segue

[Squad Creator](agents/squad-creator.md) - [Biblioteca de Squads](features/squad-templates/README.md) - 
[Orquestracao](orchestration.md) - [Glossario](glossary.md).
