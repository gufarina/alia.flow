# Alia Flow - MAP (indice do motor / porta da biblioteca)

> O mapa de uma tela do motor. O nucleo (persona, constitution, glossary, orchestration) ja vem
> carregado no boot. Tudo abaixo e BIBLIOTECA: a Alia le esta lista e so ABRE o doc fundo quando
> a tarefa exige. Manter o peso sempre-carregado minimo sem perder capacidade.

## Manifestos estruturados (yaml = contrato de maquina, nao espelho de toda prosa)

A prosa (`.md`) e a fonte. Yaml existe SO onde uma maquina consome (`loops.catalog.yaml`,
`quality-gate.yaml`, `agents/*.yaml`, `tools.yaml`) ou onde a prosa DELEGA o numero exato: `rsi.yaml`
carrega os thresholds e janelas do RSI. NAO ha espelho yaml de toda spec - isso seria duplicacao com
risco de drift. Precisa do threshold/cerca exata: abra `rsi.yaml`. Para o resto, a prosa basta.

## Nucleo (injetado em toda janela pelo hook de SessionStart)

- engine/agents/nucleo.md - o nucleo operacional de UMA pagina (teto 4.000 tokens): quem e a Alia,
 os 10 principios, o protocolo de 5 passos, DELEGA e a valvula, grounding, leitura por indice.
 E o UNICO doc carregado mecanicamente (scripts/session-start.ps1, matchers startup/resume/compact).
 Ate a v1.69 este MAP afirmava que os 4 docs abaixo "ja vinham carregados no boot" - era falso:
 nada os injetava, e os 4 somam ~61KB (~17k tokens), peso demais para toda janela.

Biblioteca de referencia do nucleo (abrir a fatia quando o nucleo.md remeter):

- engine/agents/persona.md - voz e jeito da Alia.
- engine/constitution.md - a lei (10 principios) + roteamento por capacidade.
- engine/glossary.md - linguagem ubiqua (os unicos termos aceitos).
- engine/orchestration.md - protocolo de 5 passos (IDENTIFICA, REGISTRA, DELEGA, MONITORA, FECHA).

## Squads e especialistas (abrir ao montar/inspecionar um squad)

- engine/squad-system.md - anatomia do Specialist, segundo cerebro em camadas (A/B/C), invariantes.
- scripts/squad-bridge.ps1 - a ponte persona -> agente invocavel: gera `.claude/agents/{client}-{id}.md`
  (modo spawn) ou `.context-load.md` (modo context-load, host sem sub-agente nativo) a partir da
  MESMA fonte (squad.yaml + agents/{id}.yaml + agents/{id}.md). Doutrina no cabecalho do script.
- engine/agents/squad-creator.md - como a Alia spawna o Squad Creator e gera o time.
- engine/agents/persona-skeleton.md - ordem canonica das secoes de toda persona de Specialist.
- engine/agents/alia.md - definicao publica/generica do agente central.
- engine/agents/{architect,data-engineer,dev,devops,qa,agent-engineer,growth}.md - biblioteca de
  referencia dos 7 arquetipos do motor. SAO: doutrina de leitura para quem ESCREVE a persona de um
  Specialist novo (o autor copia e adapta a mao o que serve). NAO SAO: invocaveis diretamente, nem
  herdados por mecanismo algum - `base_archetype` em `agents/{id}.yaml` e so uma anotacao de qual
  arquivo foi lido, o gerador (squad-bridge.ps1) nao le esse campo (decisao pos-revisao adversarial,
  ver ubiquitous-language.md).
- engine/features/squad-templates.md - moldes de squad por tipo de cliente (ponto de partida).
- engine/features/squad-templates/README.md - regra do segundo cerebro em camadas + schema do manifesto.
- engine/features/expert-minds.md - metodologia de um mestre por dominio (Domain Pack).
- engine/features/expert-minds/<dominio>/*.md - os Expert Minds concretos (Ogilvy, Kent Beck, Brad Frost...).

## Governanca e qualidade (abrir ao fechar Task ou desenhar loops)

- engine/governance/quality-gate.md - a regua unica (6 criterios + verdicts). Roda a cada Artifact.
- engine/governance/loops.md - catalogo da governanca: 2 tiers + taxonomia de loops.
- engine/governance/memory-types.md - tipos de Memory e TTL (quando uma nota expira).
- engine/governance/memory-audit.md - checklist de higiene da Memory (nota vencida/duplicada/contraditoria).
- engine/governance/provenance.md - quem pode mudar cada artefato e como (diff, nunca deleta).
- (evolution-pipeline.md virou a secao "Pipeline de evolucao" dentro de provenance.md em 09/09/2026; original em engine/_retired/.)
- engine/governance/instance-separation.md - a LEI dos 2 contextos (produto CLEAN vs instancia aplicada) e os guardrails que a fazem cumprir.
- engine/governance/client-truth.md - as 4 leis que protegem a documentacao do cliente (knowledge-first, claims registry, publico-vs-interno, reuse-first).
- engine/governance/public-surface.md - a LEI do que pode existir no git (produto publico, nunca material de dev do cliente).
- engine/governance/response-guard.md - o freio na PORTA DE SAIDA da resposta (hook de Stop, `response-guard.ps1`): as 2 regras (DELEGA/GROUNDING), os 2 modos (aviso/bloqueio) e a valvula de excecao por ordem do Operator.
- engine/governance/law-ledger.md - registro de toda LEI declarada no motor: onde vive, que teste cobre, COBERTA ou SEM TESTE.
- scripts/session-start.ps1 - hook de SessionStart (startup/resume/compact): injeta nucleo.md + pendencias + o bastao mais recente de studio/baton/ quando existir (teto 1.800 bytes).
- scripts/pre-tool-use.ps1 - UM spawn por Edit/Write/Task: chama delegation-gate + secret-write-guard em-processo.
- scripts/harness-baseline.ps1 - mede e congela o custo do harness (studio/harness-baseline.txt); -Check e a catraca (L50).
- scripts/session-baton.ps1 - grava o bastao de sessao (PreCompact/SessionEnd), contrato de bastao.md, teto 500 tokens.
- engine/governance/persistence-catalog.md - todo lugar onde o motor grava estado em disco (ledger, baseline, staging), com classe (durable/live/staging/ratchet), escritor, leitor e ciclo de vida. Consultar ANTES de criar um ledger/baseline novo (reuse-first).

## Entrega e workflows (abrir ao executar um ciclo de entrega)

- engine/features/forja.md - linha de producao autonoma em 5 estacoes (FUNDIR, MOLDAR, TEMPERAR, PROVAR, GUARDAR) + bastao entre estacoes + notas AS/NB para evolucao de motor.
- engine/features/bastao.md - doutrina do handoff <=500 tokens entre estacoes/agentes (contrato de campos, cadeia, sugestao de proximo comando) + engine/features/bastao-template.yaml (molde).
- engine/features/project-ficha.md - o modelo da ficha de Project (camada do meio): 6 campos, heranca do Client por referencia, quando NAO criar ficha.
- engine/workflows/story-cycle.md - o protocolo de 5 passos aplicado a dev (da intencao ao Artifact).
- engine/workflows/qa-loop.md - ciclo de correcao quando o Gate da Fail.
- engine/workflows/command-chaining.md - um comando orquestra N skills em sequencia.
- skills/alinhamento/SKILL.md - a regua de risco do escopo + a rodada de perguntas de decisao
  (sub-passo do IDENTIFICA). Abrir quando o pedido admitir mais de uma leitura ou a entrega for
  cara de desfazer.
- engine/features/validated-artifacts.md - validacao do contrato/formato do entregavel.
- engine/features/examples-driven.md - olhar o padrao-ouro antes de criar (REUSE first).

## Frugalidade e auto-melhoria (abrir ao otimizar custo ou alimentar o RSI)

- engine/tools.md - selecao de ferramenta e como gastar o minimo de token.
- engine/features/artifact-ladder.md - escada de frugalidade de SAIDA (7 degraus, marcador
  `frugal-debito:`) - espelho do grafo obrigatorio (tools.md), do lado da producao.
- engine/reading-strategy.md - ler sem ler tudo: indice mestre + assinatura + grep-por-secao (kb-index.ps1).
- engine/features/frugal-skills.md - capacidades por script (sem LLM) para tarefas deterministicas.
- engine/rsi/rsi.md - como o sistema aprende e melhora a si mesmo a cada Loop.
- engine/features/loop-designer.md - a Alia receita os loops de cada projeto (comando *loops).
- engine/features/deep-research-loop.md - loop sob demanda (agente-driven, sem agendamento) que mantem o segundo cerebro vivo.

## Engenharia e evolucao do motor (abrir ao mexer em codigo ou versionar o engine)

- engine/engineering.md - padroes de engenharia (incrementos testaveis, anti-entropia).
- engine/versioning.md - a lei do update do motor (modular, rastreavel, reversivel).

---

*Alia - Delegue. Nao opere.*
