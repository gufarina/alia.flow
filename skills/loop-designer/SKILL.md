---
name: loop-designer
description: A Alia desenha os loops de governanca de um projeto - sugere os loops certos pro perfil do projeto, cria como registros reais em clients/{id}/loops.yaml, e revisa (cria, gerencia, revisa). Use quando nasce um squad novo, quando chega a data de revisao de um loop, ou quando o operador pede para planejar/revisar os loops de um cliente. Trigger: planejar loops, configurar deep research diario, governanca de projeto, revisar loops, "que loops esse projeto precisa".
trigger: /alia-loops
provenance: nucleo
---

# Loop Designer

Capacidade da Alia de propor, criar e revisar os loops de governanca de cada projeto.
Spec do motor: `engine/features/loop-designer.md`. Catalogo e tiers: `engine/governance/loops.md`.
Regra de ouro: nenhum projeto comeca sem governanca; nenhum loop fica eterno por inercia.

## Modos

| Modo | Quando | O que faz |
|------|--------|-----------|
| sugerir | squad novo, ou operador pede | le o perfil do projeto, propoe o Plano de Loops, justifica cada um |
| criar | apos o operador aprovar | grava `clients/{id}/loops.yaml` + liga o mecanismo (sob demanda por padrao) |
| rodar | loop devido + operador aceita (opt-in) | a Alia roda os loops devidos numa passada e leva o resumo em linguagem do operador |
| revisar | chegou o `review_on` de um loop, ou operador pede | audita cada loop, mantem / ajusta cadencia / aposenta |

## Postura proativa (opt-in, nunca obrigatorio)

A Alia nao espera o operador pedir. Quando um loop esta devido (abriu trabalho num cliente, saiu um
Artifact, chegou a cadencia), ela **sugere** rodar - enquadrando pelo beneficio, nao pelo mecanismo:
"rodar a checagem de saude agora mantem este cliente evoluindo sem drift nem estagnacao escondida.
Quer que eu rode?". O operador aceita ou adia. Nada e obrigatorio, nada roda as escondidas, e o
operador nunca precisa rodar script na mao - quem roda e a Alia.

## Modo SUGERIR

1. Ler o perfil do projeto (sem reprocessar - usar o que ja existe):
   - `clients/{id}/client.md` (setor, DDD documentado?)
   - `clients/{id}/squad/squad.yaml` (dominios dos especialistas)
   - `state.json` (status do cliente: active / paused / archived)
2. Classificar o perfil:
   - status (active / paused / archived)
   - has_code (o squad tem dev / backend / frontend?)
   - has_ddd (client.md tem glossario / linguagem ubiqua?)
   - dominios e velocidade do conhecimento (design, growth, AI, marketing = rapido;
     ops interno, juridico = lento)
3. Aplicar as regras R0..R6 da spec (`engine/features/loop-designer.md`); CORTE de 10/08/2026
   (mandato do CEO): health-check, evolution-scan, debt-scan, squad-report, ddd-drift-scan e
   deep-research sairam da selecao automatica (nenhum tinha consumidor do proprio relatorio;
   deep-research tambem custa modelo sem freio de orcamento real) - viraram comando manual
   (`loops.catalog.yaml` -> `manual_commands`), a Alia so os sugere pontualmente, nunca instancia:
   - R0: status != active -> NENHUM loop agendado. Parar e reportar isso.
   - R1: active -> memory-curator (semanal) - unico agendado por padrao
   - R2: active -> gate-on-artifact + fix-on-fail
   - R3: has_code -> drift-on-commit + pr-review
   - R4: has_ddd -> nada agendado; sugerir comando manual `ddd-drift-scan` se o operador pedir
   - R5/R6: deep-research fica sob demanda (aciona quando o operador pede pesquisa de dominio)
4. Apresentar o Plano de Loops ao operador: tabela (loop, cadencia, dono, custo, por que),
   o custo somado (quantos cost_class medio/alto), e pedir aprovacao.

## Modo CRIAR

1. Para cada loop aprovado, montar o registro no formato da spec (id, trigger, cadence, owner,
   cost_class, domains, produces, mechanism, status: active, created, review_on = created + 30 dias,
   last_result: null).
2. Gravar `clients/{id}/loops.yaml` com escrita UTF-8 sem BOM (no Windows/PowerShell, usar
   [System.IO.File]::WriteAllText com UTF8Encoding($false) - nunca Set-Content cru).
3. Ligar o mecanismo (sem agendador de SO - CORTE 10/08/2026, mandato do CEO: Task Scheduler e
   estado escondido na maquina, invisivel, nao viaja com o produto; `install-loops.ps1` e
   `run-loops.ps1` foram removidos):
   - Loops de evento: ja cobertos pelos hooks/gates do engine (nada a instalar).
   - `memory-curator` (o unico agendado): nao precisa de nada a instalar. `scripts/smoke-test-studio.ps1`
     ja chama `memory-curator.ps1 -Validade` toda vez que a prova roda, e a prova roda em todo
     trabalho relevante - rotina que precisa rodar "de vez em quando" roda quando a prova roda.
   - Os demais scans mecanicos (health-check, ddd-drift-scan, evolution-scan, debt-scan,
     squad-report): comando manual, sem cadencia - o operador (ou a Alia, se pedido) roda
     `scripts/{id}.ps1 -Client {id}` quando quiser.
4. Registrar no estado que o cliente tem governanca ativa (loops criados).

## Modo REVISAR

1. Ler `clients/{id}/loops.yaml`. Para cada loop com `review_on` <= hoje:
   - Olhar `last_result` (e a Memory do cliente).
   - Agregou valor? Sim -> status active, novo `review_on` (+30 dias). Nao -> status retired,
     gravar o motivo.
   - Custo alto sem retorno proporcional -> reduzir cadencia (diario -> semanal) antes de aposentar.
2. Reescrever o loops.yaml (UTF-8 sem BOM). Reportar ao operador o que mudou e por que.

## O caso do deep-research diario (pergunta do CEO)

O deep-research NAO e um loop avulso - e um item do catalogo que o Loop Designer cria quando o
projeto tem dominio de velocidade alta (R5). Para configura-lo:
1. Modo sugerir confirma R5 (ex: dominios design/copy/produto = rapidos).
2. Modo criar grava o registro `deep-research` (cadence: daily, domains: [os ativos rapidos],
   mechanism: agente-driven via MCP perplexity, proactive: on).
3. Por padrao a Alia roda a pesquisa (Sonnet 4.6 thinking via MCP; jamais Sonar/deep research) quando
   devida e o operador aceita - agente-driven, sem script na mao nem Task Scheduler.
4. Na revisao, se a pesquisa diaria nao agregou, cai pra semanal ou e aposentada.

## Invariante

- Frugal: projeto nao-ativo = zero loop agendado. deep-research e sob demanda, nunca agendado.
- Todo loop nasce com `review_on`. Loop sem retorno e aposentado, nao mantido por inercia.
- Toda escrita de arquivo: UTF-8 sem BOM,
- Loop agendado sem consumidor medido do proprio relatorio nao entra na selecao automatica (licao
  do corte de 10/08/2026: virar comando manual documentado, nao rotina fantasma).
