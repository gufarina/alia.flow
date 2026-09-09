# Persistence Catalog - todo lugar onde o motor grava estado em disco

> TASK-213 (item 5a, benchmark DeepSeek Harness): o motor grava estado em varios pontos
> (ledgers append-only, baselines datadas, staging de memoria, snapshots de estado) sem UM lugar
> que liste todos eles com classe, escritor e leitor. Divida do mesmo padrao que motivou a
> auditoria de 04/08/2026: "projetado com rigor, ligado por lembrete" - quem cria um ledger novo
> nao tinha onde conferir se ja existe um parecido (reuse-first) nem onde declarar o ciclo de
> vida (quando isso e apagado? promovido? nunca?). Levantado varrendo `scripts/*.ps1` por alvo de
> escrita `.jsonl`/`*baseline*.txt`/`state.json`/`_proposals/`/`release-reviews/` (18/08/2026).
> UTF-8 sem BOM.

## As 4 classes

- **durable**: nunca se apaga, so cresce (ou se apaga so por decisao humana explicita, nunca por
  script). Historico de verdade - apagar destroi prova.
- **live**: estado vivo, sobrescrito/atualizado no lugar a cada operacao (nao e historico, e o
  ESTADO ATUAL). Perder um live e perder "onde estamos agora", nao perder historico.
- **staging**: area de espera entre "aconteceu" e "foi aprovado/promovido". Sempre tem um script
  que MOVE (nunca deleta) dali para o destino final quando aprovado.
- **ratchet**: baseline datada que so pode ENCOLHER (o numero so melhora) - divida aceita e
  visivel, nao escondida; crescer alem do baseline reprova o smoke.

## Catalogo

| arquivo/pasta | classe | escritor | leitor | ciclo de vida |
|---|---|---|---|---|
| `{studio}/state.json` | live | `scripts/register-task.ps1` (cria/atualiza Task), `scripts/client-state.ps1` (helper generico de leitura/escrita), `scripts/task-context.ps1` | `scripts/mission-control.ps1`, `scripts/stale-tasks.ps1`, `scripts/lineage-graph.ps1`, `scripts/smoke-test-studio.ps1` | nunca se apaga sozinho; Task fecha (`status: done`) mas o registro fica - e o ledger de linhagem completo (project+base_artifact+session por Task) |
| `studio/response-guard-log.jsonl` | durable (append-only) | `scripts/response-guard.ps1` (hook de Stop, 1 linha por turno em modo aviso; agora tambem 1 linha `{"erro":...}` quando o catch geral dispara, TASK-213 item 2) | `scripts/smoke-test.ps1`/`scripts/smoke-test-studio.ps1` (ratchet de linhas com erro) | nunca se apaga; cresce a cada turno medido |
| `studio/graph-usage-log.jsonl` | durable (append-only) | `scripts/graph-usage-sensor.ps1` (hook de PreToolUse, kind=map\|scan por evento; linha `{"erro":...}` no catch geral e no catch interno do gate, TASK-213 item 2) | `scripts/graph-usage.ps1` (o contador - 3 vereditos independentes, TASK-213 item 3), `scripts/smoke-test.ps1`/`scripts/smoke-test-studio.ps1` | nunca se apaga; e o unico jeito de medir a adocao da lei do grafo, apagar destroi a serie historica |
| `studio/harness-baseline.txt` | ratchet (catraca) | `scripts/harness-baseline.ps1` (gera; regravar so por decisao explicita) | `scripts/harness-baseline.ps1 -Check` via `scripts/smoke-test-studio.ps1` | congelado na onda zero da auditoria de harness (09/09/2026, L50); metrica atual pior que o gravado em >10% = FAIL |
| `studio/baton/<session_id>.md` | staging (efemero) | `scripts/session-baton.ps1` (hook PreCompact/SessionEnd via `session-baton-guard.ps1`) | `scripts/session-start.ps1` (injeta o mais recente na janela nova) | 1 arquivo por sessao, teto 1.800 bytes; pode ser apagado a qualquer momento sem perda de lei (bastao.md, secao Bastao de sessao) |
| `studio/smoke-log.jsonl` | durable (append-only) | `scripts/smoke-test-studio.ps1` (uma linha por rodada, placar PASS/FAIL) | `scripts/mission-control.ps1` (le so a ULTIMA linha, exibicao) | nunca se apaga; historico de saude do motor ao longo do tempo |
| `studio/error-log-baseline.txt` | ratchet | humano (edicao manual, decisao consciente de aceitar mais erro) | `scripts/smoke-test.ps1` (ratchet de linhas `"erro"` nos 2 ledgers do freio, TASK-213 item 2) | so encolhe; sobe so quando um humano decide aceitar mais volume de erro registrado |
| `studio/graph-map-baseline.txt` | ratchet | humano (edicao manual, quando fecha a divida de um Client `[FAKE]`/`[FALTA]`) | `scripts/smoke-test-studio.ps1` (ratchet: mapa FAKE/FALTA novo fora da baseline reprova) | so encolhe; linha sai quando o Client ganha mapa de verdade |
| `studio/graph-map-stale-baseline.txt` | ratchet | humano (edicao manual, quando fecha a divida de um Client `[STALE]`) | `scripts/smoke-test-studio.ps1` (ratchet: grafo PODRE novo fora da baseline reprova) | so encolhe; linha sai quando o grafo do Client e regenerado |
| `studio/graph-adoption-baseline.txt` | ratchet | humano (edicao manual, quando a taxa de adocao medida melhora de verdade) | `scripts/smoke-test-studio.ps1` (regressao vs baseline reprova; abaixo da meta mas sem regressao e so Warn) | so pode subir quando a taxa real sobe; nunca abaixado por decreto de codigo |
| `studio/artifacts-baseline.txt` | ratchet | humano (edicao manual) | `scripts/smoke-test-studio.ps1` (ratchet de Artifact sem prova/gate) | so encolhe; divida de Artifact sem Gate registrada aqui ate ser fechada |
| `memory/_proposals/prop-*.md` | staging | `scripts/session-reflection.ps1` (digest de sessao) | `scripts/promote-memory.ps1` (move pra `memory/{client}/` quando aprovado) | fica em staging ate aprovacao humana; `promote-memory.ps1` MOVE (nunca deleta) pra `_proposals/_archive/` |
| `memory/_proposals/reflection-inbox-*.md` | staging | `scripts/session-reflection.ps1` (inbox de reflexao pos-sessao) | `scripts/reflect-check.ps1` (lembra o pendente no boot da proxima sessao) | mesma regra: fica ate ser processado, move pra `_archive/`, nunca deleta |
| `memory/_proposals/patterns-*.md` | staging | `scripts/rsi-patterns.ps1` (varre `_proposals/` + `_archive/` atras de padrao recorrente) | humano/Alia no ciclo RSI | fica em staging ate virar nota de memoria promovida ou ser descartado por decisao humana |
| `memory/_proposals/_archive/` | durable | `scripts/promote-memory.ps1`, `scripts/session-reflection.ps1` (destino do MOVE, nunca do DELETE) | `scripts/rsi-patterns.ps1` (historico para detectar padrao recorrente) | nunca se apaga; e o arquivo morto do staging, prova de que o item foi processado |
| `release-reviews/<VERSION>.md` | durable | humano (revisor independente escreve o veredito) | `scripts/package-release.ps1` (passo 0/3 - sem `veredito: PASS` batendo o VERSION atual, aborta o empacotamento, law-ledger L34) | nunca se apaga; um por VERSION, historico de toda decisao de release |
| `studio/instance-overlay.md` | live (sobrescrito a cada update) | `scripts/update-engine.ps1` (TASK-213 item 5b - persiste o Get-MirrorDiff que ja calculava, so em console antes) | humano (auditoria de drift entre a instancia e o lab) | sobrescrito por inteiro a cada `update-engine.ps1` aplicado (nao em `-Check`); nao e historico, e o retrato do ULTIMO update |
| `.core-baseline.sha256` | live (sentinela) | `scripts/guard-core.ps1` (grava so com `-AllowCore`, mudanca deliberada de nucleo) | `scripts/guard-core.ps1` (compara hash a cada rodada), `scripts/smoke-test.ps1` | sobrescrito so quando o nucleo muda DE PROPOSITO (RSI nunca toca o nucleo sem isso, law-ledger L04) |
| `studio/cost-log.jsonl` | durable (append-only) | `scripts/cost-sensor.ps1` (1 linha por rodada real, nunca em `-WhatIf`: `{ts,date,slug,sessionCount,dayTotalMB,dayTotalSubagents,sessionEstouros,dailyEstouro}`) | humano (tendencia de custo), `scripts/smoke-test-studio.ps1` (quando pendurado numa instancia real, mesmo padrao de `memory-curator.ps1 -Validade`) | nunca se apaga; cresce a cada rodada medida - serie historica do custo-proxy (MB de transcript + subagentes) por sessao/dia, TASK-283 |
| `studio/delegation-seen.jsonl` | durable (append-only) | `scripts/delegation-gate.ps1` (hook de PreToolUse, matcher `Edit\|Write\|NotebookEdit\|Task`; grava 1 linha `{ts,session_id}` a cada chamada Task/Agent - o fallback honesto pra saber "houve delegacao nesta sessao" quando o payload de PreToolUse nao distingue loop principal de sub-agente, WARDEN 07/09/2026, law-ledger L45) | `scripts/delegation-gate.ps1` (le antes de decidir bloquear escrita de dominio seguinte) | nunca se apaga; cresce a cada delegacao vista - serie da qual o gate consulta so as linhas da sessao atual |
| `studio/secrets-ledger.jsonl` | durable (append-only) | `scripts/secret.ps1` (toda acao - set/use/revoke/get/leak/fail - grava 1 linha com nome, escopo, quem, pra que e IMPRESSAO DIGITAL, NUNCA o valor) + `scripts/secret-write-guard.ps1` (hook de PreToolUse, grava linha `fail` quando bloqueia valor de segredo aparecendo em conteudo prestes a ser gravado) | qualquer agente (e a prova de auditoria - unico dos dois arquivos de segredo que pode ser lido livremente), `scripts/check-public-surface.ps1` secao (1.7) le o cofre irmao (nao este) | nunca se apaga; e o historico de auditoria do mecanismo de segredos (mandato do CEO, 08/09/2026, law-ledger L47) |
| `studio/.secrets/vault.json` | live (sobrescrito a cada `-Set`/`-Revoke`) | `scripts/secret.ps1` (unico escritor legitimo) | `scripts/secret.ps1` (unico leitor legitimo), `scripts/secret-write-guard.ps1` e `scripts/check-public-surface.ps1` secao (1.7) leem SO pra comparar valor, nunca imprimem | guarda o VALOR vivo de cada segredo; fora do git por LEI (studio/ e .secrets/ ja cobertos por .gitignore, defesa em profundidade); `-Revoke` remove a entrada, `-Set` sobrescreve |

## Onde registrar um ledger/baseline NOVO

Antes de criar um arquivo de estado novo em `scripts/*.ps1`: (1) confira esta tabela - reuse-first,
um ledger parecido pode ja existir; (2) se for mesmo novo, adicione uma linha aqui NA MESMA Task
que o cria, com classe/escritor/leitor/ciclo de vida; (3) `scripts/smoke-test.ps1` varre
`scripts/*.ps1` atras de alvo de escrita `.jsonl`/`*baseline*.txt` e reprova alvo sem entrada
aqui (molde `scripts/law-ledger-check.ps1` secao A - mesmo principio, "nada nasce sem registro").

## Segue
[MAP](../MAP.md) - [law-ledger](law-ledger.md) - [response-guard](response-guard.md).
