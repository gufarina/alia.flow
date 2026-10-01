# MAP - indice da Alia Flow 2.0

> Indice mestre da pasta v2/. Uma linha por doc: leia AQUI para decidir o que abrir, nao varra a
> pasta. Regeneravel - nunca editar por cima sem atualizar esta linha. Relatorios de prova moram
> em `proof/` mas NAO tem ponteiro aqui (TASK-804, revisao e7) - abra `proof/` direto quando
> precisar de historico; o MAP so indexa modulo, nao entrega.

- [AGENTS.md](AGENTS.md) - o kernel (I3). Quem e a Alia, os 5 passos, o checklist de brief, R1/R2,
  um escritor por Artifact, squad ativo, o glossario. Estatico, ate 6.000 bytes.
- [CONTRACTS.md](CONTRACTS.md) - tabela curta dos 10 modulos: responsabilidade, dono, prova
  positiva, prova negativa. LEIs fracas e o mapa completo ficam so em LAW-MAP.md.
- [LAW-MAP.md](LAW-MAP.md) - o mapa das 78 LEIs da 1.84 (Canon): destino por modulo, o que morre e
  as 6 com mecanismo fraco. Insumo de `proof/check.py`.
- [squad/squad-bridge.ps1](squad/squad-bridge.ps1) - o gerador de agentes (I5). Agent/Task so em
  `gateway: true`, Skill em todo Specialist, descricao encurtada a "acionar quando". (o
  gerador agora e `squad/bridge.ps1`; `squad-bridge.ps1` e ponteiro; sem reserva `.claude/squads`.)
  TASK-804 e7: o ritual fixo de leitura (MAP/grounding/GRAPH_REPORT) so entra no corpo do Gateway
  (Camada A) - o Specialist recebe contexto pelo brief da Task, nao pelo corpo do agente.
- [bin/client.py](bin/client.py) - CLI `list`/`use` do squad ativo. Sincroniza `.claude/agents`
  com so o squad do Client escolhido (+ `--keep` explicito; `alia-flow-lab` NAO entra por padrao,
  Ajuste 0). Chama a bridge; idempotente, so apaga com `--prune`.
- [bin/brief.py](bin/brief.py) - CLI `open` do brief de Task (TASK-804 e7, mudanca 3). Devolve so
  os 6 campos do checklist + fatias `caminho#Lx-Ly` (embute a fatia se menor que 2 KB); recusa
  fatia que nao resolve no disco; nunca inclui texto de coordenacao (risco, justificativa, nota de
  protocolo) - isso fica com quem delega, nao com quem executa.
- [hooks/dispatch.py](hooks/dispatch.py) + [lib/ledger.py](lib/ledger.py) - o despachante unico
  (I1/I4, Warden). PreToolUse/PostToolUse/SubagentStop de Agent/Task viram evento no ledger; as 5
  negacoes do guard rodam so no PreToolUse (a 5a, TASK-841/842: identidade real do operador -
  Client id, nome do estudio, caminho da maquina - em arquivo publicavel do motor, ver
  [lib/identity_guard.py](lib/identity_guard.py)). Stop (TASK-812, a trava de fim): bloqueia 1 vez
  quando ESTA sessao tocou (evidencia no ledger) uma Task que segue sem gate_verdict;
  stop_hook_active nunca bloqueia de novo (anti-laco) e grava "encerrou_sem_gate"; desliga com
  ALIA_END_LOCK_OFF=1 ou .claude/end-lock.off. SessionStart matcher "compact" (TASK-839): devolve
  additionalContext apontando o transcript_path da sessao (recuperacao pos-compactacao) e grava
  "compact_recovery"; qualquer outro source, ou sem transcript_path, devolve {}.
- [lib/identity_guard.py](lib/identity_guard.py) - fonte UNICA da regra de identidade real do
  operador (TASK-841/842, Warden). Espelha `scripts/check-public-surface.ps1`
  (Find-OperatorClientIds + secao "(1.5)"): mesma fonte de dado (alia.config.json -> studio_dir
  -> state.json), mesma fronteira de casamento. Usado por hooks/dispatch.py (trava na escrita) e
  proof/check.py (prova a cada rodada).
- [lib/paths.py](lib/paths.py) - resolvedor unico de ledger/state/Task corrente (Warden).
  `read_current_task(session_id)`: com session_id conhecido, SO a entrada daquela sessao (sem
  entrada propria, None - TASK-838, nunca mais cai no "_last" de outra sessao); sem session_id
  (CLI fora do hook), cai no "_last" como sempre.
- [bin/task.py](bin/task.py) - CLI `task open/close/context` (I2, Warden). Sempre sobre `--state`
  explicito (copia), nunca resolve o state.json real por conta propria. `close` exige evidencia de
  veredito no ledger (`review_verdict` ou o `gate_check` que nasce de `bin/gate.py`, TASK-825) e
  recusa se o `--veredito` digitado divergir do `gate_check` mais recente da Task. Entrega PASS
  com Client exige recibo de conhecimento (`lib/frescor.recibo_de_fechamento`, L80); raiz em
  `--studio-root`, senao pasta do `--state` com `clients/`, senao estudio da sessao; sem pasta do
  Client grava `SEM_PASTA`.
- [lib/pulso.py](lib/pulso.py) - PULSO (Operacao Deep, TASK-847, Warden): estado dinamico
  Alia-operador (`pressao`, `calor`, `confianca_acumulada`, `historia`) e, por extensao, de todo
  Specialist/Gateway (`{client}-{specialist}`), calculado so de `ledger.read_events_from()`
  (fatia por offset, nunca o ledger inteiro) e decaido por meia-vida (pressao 4h, calor 1h,
  confianca nunca decai sozinha). `render(agent_id, state)` monta o bloco de template fixo (teto
  600 caracteres para "alia", 400 para sub-agente) que `hooks/dispatch.py` injeta no
  SessionStart (`startup`/`resume`) e no PreToolUse de Agent/Task (via `updatedInput`, provado
  funcionando no host real). Arquivo em disco `pulso.json` ao lado do ledger; so o hook (Stop)
  escreve, Write/Edit/Bash direto nele e negado pelo guard.
- [lib/frescor.py](lib/frescor.py) + [bin/frescor.py](bin/frescor.py) - conferencia de FRESCOR do
  conhecimento por Client (TASK-856, Warden, L67): mapa semantico, indice estrutural, entregas e
  ficha de produto atrasada, cada um com veredito OK/VELHO/AUSENTE (divida em
  `studio/conhecimento-dividas.txt` pode calar por prazo). `hooks/dispatch.py` avisa no
  SessionStart (`startup`/`resume`) e `bin/brief.py` embute a linha no brief quando o Client nao
  esta OK. `recibo_de_fechamento` e a regra do recibo que `bin/task.py close` exige (L80).
- [proof/check.py](proof/check.py) - a conferencia rapida UNICA (I9, Warden): roda as baterias de
  cada modulo, mais kernel (hash/bytes), LAW-MAP (lei sem destino), decide (I7), checagem cruzada
  do ledger, identidade real do operador (TASK-841/842: varre todo texto de v2/ com
  lib/identity_guard.py - sem Client/estudio/caminho real fora de pasta privada) e 1 catraca
  generica (travessao). Alvo 30s, medido ~19s.

Ainda faltam nesta pasta (fora do escopo desta entrega, donos declarados em CONTRACTS.md):
o restante dos incrementos I6/I8/I10 (parcialmente entregues em sessoes anteriores, ver `proof/`
para o historico).
- `v2/REFERENCIA.md`: glossario e squad ativo, sob demanda (saiu do AGENTS.md na TASK-845).
