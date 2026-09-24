# CONTRACTS.md - contrato dos 10 modulos da Alia Flow 2.0

Tabela curta (TASK-804, revisao e7: virou duplicata do e4). Um dono escreve o Artifact do modulo;
os outros so leem. LEIs fracas e o mapa completo das 78 LEIs ficam so em `v2/LAW-MAP.md` (insumo
do `proof/check.py`, nao repetido aqui).

| Modulo | Responsabilidade | Dono | Prova positiva | Prova negativa |
|---|---|---|---|---|
| kernel | boot, os 5 passos | Lattice | 2 boots, mesmo hash | edicao a mao diverge o hash |
| flow | 5 passos, brief, risco, debate | Nexus | 12 casos certos | campo vazio nao abre |
| squad | persona, gerador, ferramentas | Weaver | gerar 2x, mesmo hash | `gateway: false` com Agent, FAIL |
| ledger | eventos so de acrescimo | Archive | payload gera a linha exata | evento sem campo obrigatorio nega |
| gate | 6 criterios + goal-backward | Canon | criterio rotulado passa | travessao ou rotulo ausente, FAIL |
| memoria | playbook, RSI, validade, linhagem | Archive | patterns real, zero item sem causa | sem sinal, nada muda |
| context | brief por indice, mapa sob demanda | Gauge | brief de 3 Tasks cabe no teto | mapa injetado sem pedido, FAIL |
| guard | despachante unico | Warden | escrita legitima passa + Stop sem Task tocada passa | 4 negacoes barram (kernel, segredo, publicacao, dominio sem delegacao) + Stop com Task tocada sem gate_verdict bloqueia 1x (TASK-812) |
| proof | conferencia rapida, 1 catraca | Warden | bateria roda ate o alvo (30s) | quebrar cada modulo, FAIL |
| release | pacote e migracao com backup | Courier | migracao em copia muda so campo novo | restaurar devolve o hash original |
