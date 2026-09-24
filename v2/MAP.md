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
  `gateway: true`, Skill em todo Specialist, descricao encurtada a "acionar quando". `-Reserve`
  (so com `-Client -Mode spawn`) grava em `.claude/squads/{client}/` em vez de `.claude/agents`.
  TASK-804 e7: o ritual fixo de leitura (MAP/grounding/GRAPH_REPORT) so entra no corpo do Gateway
  (Camada A) - o Specialist recebe contexto pelo brief da Task, nao pelo corpo do agente.
- [bin/client.py](bin/client.py) - CLI `list`/`use` do squad ativo. Sincroniza `.claude/agents`
  com so o squad do Client escolhido (+ `--keep` explicito; `alia-flow-lab` NAO entra por padrao,
  Ajuste 0). Idempotente e reversivel, nunca toca arquivo de Client sem reserva.
- [bin/brief.py](bin/brief.py) - CLI `open` do brief de Task (TASK-804 e7, mudanca 3). Devolve so
  os 6 campos do checklist + fatias `caminho#Lx-Ly` (embute a fatia se menor que 2 KB); recusa
  fatia que nao resolve no disco; nunca inclui texto de coordenacao (risco, justificativa, nota de
  protocolo) - isso fica com quem delega, nao com quem executa.
- [hooks/dispatch.py](hooks/dispatch.py) + [lib/ledger.py](lib/ledger.py) - o despachante unico
  (I1/I4, Warden). PreToolUse/PostToolUse/SubagentStop de Agent/Task viram evento no ledger; as 4
  negacoes do guard rodam so no PreToolUse.
- [bin/task.py](bin/task.py) - CLI `task open/close/context` (I2, Warden). Sempre sobre `--state`
  explicito (copia), nunca resolve o state.json real por conta propria.
- [proof/check.py](proof/check.py) - a conferencia rapida UNICA (I9, Warden): roda as baterias de
  cada modulo, mais kernel (hash/bytes), LAW-MAP (lei sem destino), decide (I7), checagem cruzada
  do ledger e 1 catraca generica (travessao). Alvo 30s, medido ~4s.

Ainda faltam nesta pasta (fora do escopo desta entrega, donos declarados em CONTRACTS.md):
o restante dos incrementos I6/I8/I10 (parcialmente entregues em sessoes anteriores, ver `proof/`
para o historico).
