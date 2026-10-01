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
| pulso | estado dinamico Alia-operador e Specialist/Gateway (pressao, calor, confianca), decaimento por meia-vida, injecao no SessionStart/PreToolUse-Agent | Warden | estado calculado de eventos sinteticos bate o valor esperado (pressao/calor/decaimento) + bloco do sub-agente anexado a `updatedInput` (provado no host real, `claude -p`) | Write/Edit/Bash direto em pulso.json e sempre negado + render() acima do teto (600/400 caracteres) LEVANTA em vez de truncar |
| release | pacote e migracao com backup | Courier | migracao em copia muda so campo novo | restaurar devolve o hash original |

## Contrato da espinha Cliente > Projeto > Tarefa

A espinha tem UM nucleo, independente de host: `v2/lib/espinha.py` + `v2/lib/task_model.py`, exposto pela CLI `alia` (`v2/bin/alia.py`). Todo write de estado passa por ela; recusa com exit 1 e JSON. `scripts/register-task.ps1` e so wrapper dela. Adaptadores finos por host (`v2/adapters/`: Claude Code, OpenCode, Codex, Pi) traduzem evento do host em chamada `alia`, sem regra propria, e declaram em `matriz.json` o que bloqueiam e o que so avisam.

| Regra | Onde e imposta | Depende de host? |
|---|---|---|
| Projeto obrigatorio | `client.projects[]` no dado; `alia task open` recusa id nao cadastrado | nao |
| Veredito para fechar | `done` exige veredito no ledger e artifact que exista em disco; sem isso `alia task close` sai 1 | nao |
| Gateway antes do Specialist | `alia task dispatch --specialist X` recusa sem `gateway_ack` na Task | so onde o host intercepta a chamada |
| Veredito ao parar | `alia task pending --session` lista Task sem veredito | sim (hook de parada) |
| Ler estado ao abrir | `alia open` devolve o estado; host sem hook segue o AGENTS.md e roda `alia open` | injecao so onde ha hook |
| Delegar, nao escrever | specialist e enum do squad; `alia` so com `coordenacao: true` | sim |

Fora do nucleo: identidade, kernel e segredo sao politica do host, nao da espinha.
