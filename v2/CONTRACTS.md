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
| gate | 6 criterios + goal-backward | Canon | criterio rotulado passa | travessao, rotulo ausente, ou `funciona`/`goal-backward` em PASS so com frase (sem ponteiro verificavel), FAIL |
| memoria | playbook, RSI, validade, linhagem | Archive | patterns real, zero item sem causa | sem sinal, nada muda |
| context | brief por indice, mapa sob demanda | Gauge | brief de 3 Tasks cabe no teto | mapa injetado sem pedido, FAIL |
| guard | despachante unico | Warden | escrita legitima passa + Stop sem Task tocada passa + SessionStart/compact devolve ponteiro de recuperacao | 5 negacoes barram (kernel, segredo, identidade real do operador em arquivo publicavel - TASK-841/842, publicacao, dominio sem delegacao) + Stop com Task tocada sem gate_verdict bloqueia 1x (TASK-812) + SessionStart de outro source/sem transcript_path devolve {}. RESSALVA (R2, revisor LATTICE): a negacao de identidade em Write/Edit cobre SEMPRE; em Bash/PowerShell cobre SO quando ha alvo publicavel entre os alvos de escrita E o comando carrega texto inline (heredoc/echo/Set-Content) - download/copia binaria/redirecionamento de arquivo existente ficam fora do guard em tempo real, cobertos depois por `proof` (ver `v2/lib/identity_guard.py`, docstring). |
| proof | conferencia rapida, 1 catraca | Warden | bateria roda ate o alvo (30s), inclui varredura de identidade real (TASK-841/842) - modo AUTOMATICO por ONDE roda: dentro da oficina varre a allowlist de package-release.ps1, dentro de um repo do PRODUTO ja publicado varre o repo inteiro (R2, achado do revisor LATTICE) | quebrar cada modulo, FAIL |
| release | pacote e migracao com backup | Courier | migracao em copia muda so campo novo | restaurar devolve o hash original |
