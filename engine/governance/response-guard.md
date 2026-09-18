# Alia Flow - Response Guard (M1: O FREIO na SAIDA)

> O enforcement da lei "a coordenadora delega dominio, nunca executa" na PORTA DE SAIDA da
> resposta. Contrato estruturado (limiares, modo) em response-guard.yaml.

## Unidade de tempo que este guard audita

O guard roda sobre o **TURNO** (nunca a sessao inteira, nunca a Task) - ver
`engine/orchestration.md`, secao "Turno, Sessao e Task", para a definicao das 3 unidades de tempo
do motor e por que confundi-las e a causa raiz de guard que mede a coisa errada.

## O furo que isto fecha

A lei de delegacao ja tinha 2 guardas de maquina: `delegation-guard.ps1` (hook de UserPromptSubmit,
lembra a lei ANTES do pedido) e `session-reflection.ps1` (captura aprendizado DEPOIS que a sessao
acaba). Entre os dois nao havia nenhuma verificacao no momento em que a RESPOSTA sai para o
operador. Uma auditoria mediu a lacuna: a lei foi violada em menos de 24h com o lembrete de entrada
ja ligado. Lembrete no boot nao e enforcement - o freio precisa estar no pedal, nao so no manual.
`response-guard.ps1` (hook de Stop) e esse pedal: roda a cada turno, sobre o que de fato aconteceu.

## As regras (deterministicas, sem LLM, sem rede)

Nasceu com 2 (DELEGA/GROUNDING); ganhou REGRA 3 BUDGET (TASK-286, law-ledger L41 clausula c, so
documentada no cabecalho do script + law-ledger.md) e REGRA 4 RITUAL (07/09/2026, abaixo).

1. **DELEGA** - se o turno escreveu/editou arquivo de dominio (`clients/`, `engine/`, `docs/`,
   `skills/`, `scripts/`, `AGENTS.md`, `CLAUDE.md`, raiz - fora de
   memoria/proposta/backup/scratchpad/state) sem nenhuma chamada de `Agent`/`Task` no mesmo turno,
   e violacao. A excecao legitima e a ORDEM EXPLICITA do Operator para a Alia executar ela mesma -
   ver "A VALVULA" abaixo: desde 09/08/2026 essa excecao tem maquina propria, nao e mais so
   "aceitar o alerta" em modo aviso. ESTENDIDA (11/08/2026, decisao de governanca da revisao
   adversarial LATTICE/WEAVER/CANON, law-ledger L33): a regra original so confere SE houve
   `Agent`/`Task`, nunca PARA QUEM. Quando a escrita de dominio esta em `clients/<id>/` e existe
   squad GERADO pra aquele `<id>` (`.claude/agents/<id>-*.md`), delegar a um agente generico deixa
   de bastar - precisa ser um Specialist daquele Client (`subagent_type` com prefixo `<id>-`).
   Client sem squad gerado segue no comportamento antigo. A VALVULA desarma esta extensao tambem.
   CONSERTO (07/09/2026, incidente sessao 4f2b4cf2, law-ledger L45/L46): ate aqui a regra so
   conferia SE existiu Agent/Task em QUALQUER ponto do turno - uma delegacao no FIM do turno
   "lavava" toda escrita de dominio que ja tinha acontecido ANTES dela. Agora a ORDEM importa:
   so conta como delegacao valida a que aconteceu ANTES da escrita que ela deveria cobrir. Escrita
   de dominio com indice MENOR que a primeira chamada Agent/Task do turno (ou sem delegacao
   nenhuma) e violacao, mesmo que uma delegacao apareca depois no mesmo turno.
2. **GROUNDING** - se o texto da resposta final tem 3 ou mais afirmacoes de peso (referencia a
   arquivo por extensao, ou padrao `arquivo:linha`) e nenhum rotulo de proveniencia (`[MEDIDO`,
   `[INFERIDO`, `[LIDO`) aparece em algum ponto do texto, e violacao. Espelha o criterio 6
   (Fundamentada) do Quality Gate, na porta de saida em vez de so no Gate de Artifact. Esta regra
   e a maquina real da L14 do law-ledger ("Grounding: afirmar fato exige LEU ou rotulo INFERIDO") -
   ver engine/governance/law-ledger.md. ESTENDIDA (11/08/2026, achado CANON: "o portao para de
   mentir" - a regra so olhava o TEXTO DO TURNO, nunca o CONTEUDO do Artifact publicado): a mesma
   heuristica roda tambem sobre todo `.html` escrito em `clients/*/artifacts/` - claim tecnico sem
   rotulo no proprio html e violacao. Calibrado pra nao acusar pagina de marketing legitima: o
   gatilho e a PRESENCA do claim tecnico, nao a ausencia do rotulo em qualquer pagina.
4. **RITUAL** (07/09/2026, incidente sessao 4f2b4cf2, law-ledger L46) - so dispara quando o turno
   avaliado e o PRIMEIRO turno assistant da SESSAO INTEIRA (conta quantas entradas `type='assistant'`
   existem em todo o transcript lido pelo hook, nao so na janela do turno atual; <=1 = primeiro
   turno). Nesse caso, o texto final precisa casar a linha de status do "Ritual de presenca"
   (AGENTS.md/persona.md): `host:\s*\S+\s*\|\s*delegac[a~]o:\s*\S+` (aceita "delegacao" com ou
   sem til). Ausente -> bloqueio com motivo `[RITUAL] primeira resposta sem a linha de status
   (persona.md, Ritual de presenca)`. Limitacao aceita: so cobre o PRIMEIRO turno da sessao
   dentro da janela de ate 2000 linhas que o hook le - nao re-audita a saudacao de `/alia` no meio
   de uma sessao ja em andamento (isso e prosa/skill, nao maquina).

## Os 2 modos e a rampa

O guard nasceu em **aviso** (nunca bloqueia, so grava uma linha por turno em
`studio/response-guard-log.jsonl`) - o modo certo para o primeiro ciclo, quando ainda nao se sabia
a taxa real de falso-positivo das 2 regras num check so sintatico. Em 09/08/2026, apos calibrar os
limiares contra 94 turnos reais logados (ver o cabecalho de response-guard.yaml), o `mode` virou
**bloqueio**: violacao agora devolve `{"decision":"block","reason":"..."}` no stdout do hook. Pular
a rampa (nascer direto em bloqueio) teria sido o mesmo erro que travou o item no backlog antes
(OPP-22, onda 2: "hook bloqueante trava instancia viva" foi o risco que impediu de implementar) -
por isso a rampa (aviso primeiro, log real, so depois bloqueio) foi respeitada.

## A VALVULA - a excecao vira maquina (09/08/2026)

A REGRA 1 sempre teve uma excecao doutrinaria: o Operator pode mandar a Alia executar dominio ela
mesma (engine/orchestration.md, engine/governance/client-truth.md - "Reforcos de fronteira"). Antes
da valvula, essa excecao so existia em prosa: em modo bloqueio ela nao tinha por onde passar - ou o
guard bloqueava trabalho legitimo, ou alguem desligava o `mode` inteiro (repetindo o padrao que fez
outros 10 mecanismos nascerem em aviso e nunca virarem bloqueio).

A valvula abre SO com as duas pernas provadas no MESMO turno (fail-closed: falta uma, ou e ambigua,
a valvula fica fechada):

1. **Linguagem natural do Operator** - a mensagem que o Operator digitou no turno bate com uma
   ordem explicita de execucao direta (`faca voce mesma`, `resolve direto`, `nao delega`, `sem
   especialista`, `sem agente`, entre outras - lista completa no header de `response-guard.ps1`).
   Nunca configuracao: o Operator e leigo, tem TDAH e nao edita arquivo nenhum pra isso.
2. **Registro auditavel** - no mesmo turno, uma tool de shell chamou
   `scripts/register-task.ps1 ... -OperatorOrder` e o registro deu certo (`[OK] tarefa registrada`
   no resultado da tool). REUSA o mecanismo que ja existia (`register-task.ps1` grava
   `operator_order:true` na Task) - a valvula nao inventa um segundo conceito paralelo de excecao.

Quando as duas pernas batem, a REGRA 1 nao acusa violacao NAQUELE turno - e so naquele: a proxima
resposta do operador comeca um turno novo, com a janela do guard reiniciada do zero (a linguagem
natural do turno anterior nao e lida de novo). O log grava tres campos por turno -
`ordem_detectada`, `ordem_registrada`, `valvula_aberta` - para que "a valvula abriu" fique
DISTINGUIVEL de "nao houve sinal de dominio" ou "houve delegacao normal": excecao registrada e
excecao; excecao silenciosa seria furo. A valvula so desarma a REGRA 1; a REGRA 2 (GROUNDING)
continua intacta - a excecao e sobre QUEM executa, nunca sobre citar fonte sem rotular.

**Conserto necessario para a valvula fazer prova real (09/08/2026):** provando a valvula pelo
negativo descobriu-se que o recorte do "turno atual" (item abaixo) tratava qualquer `tool_result`
como se fosse a ULTIMA mensagem do Operator - no contrato da API todo `tool_result` chega como uma
mensagem de role `"user"` tambem. Sem filtrar isso, a janela do turno quase sempre cortava fora o
proprio `Write`/`Edit` que a REGRA 1 existe para pegar (e a chamada de `register-task.ps1` que a
valvula precisa achar). `response-guard.ps1` agora so aceita como inicio de turno uma mensagem
"user" que carrega TEXTO genuino (string ou bloco `type='text'`) - mensagem que so tem
`tool_result` nao conta mais.

## A limitacao aceita e declarada

Isto e um CHECK SINTATICO, no mesmo molde honesto do criterio 6 do Quality Gate: a REGRA 1 olha se
existiu uma chamada de tool `Agent`/`Task` no turno, nao se a delegacao foi para o especialista
certo nem se ela cobriu o trabalho todo. A REGRA 2 olha se o ROTULO existe no texto, nao se a fonte
citada de fato sustenta a afirmacao (ninguem confere o conteudo do arquivo apontado). Um rotulo
falso, ou uma chamada de Agent que nao tem nada a ver com o dominio escrito, passa o guard. Isto e
aceito de proposito: o guard e barato e deterministico porque ele so mede a FORMA, nunca o
CONTEUDO - julgar conteudo continua sendo trabalho de julgamento (Gate, revisao humana), nao de
regex. NUNCA trave nem derrube a sessao do operador: qualquer erro no guard e exit 0 silencioso -
essa regra dura vale mais que pegar mais um caso.

## Detector de delegacao vazia (07/09/2026, estudo oh-my-openagent)

Modo AVISO SEMPRE, nunca bloqueia: toda chamada `Agent`/`Task` do turno cujo `tool_result` tem
menos de 200 caracteres OU nenhuma referencia a arquivo (mesma heuristica de extensao/`arquivo:linha`
da REGRA 2) grava `delegacao_vazia:true` e a lista em `delegacoes_vazias` no
`response-guard-log.jsonl` - sinal de sub-agente que "respondeu" sem entregar nada concreto, para
quem le o log decidir se cobra de volta. Nao vira nova REGRA numerada porque nunca bloqueia.

## Mapa de pontos de enforcement (LATTICE, 07/09/2026)

Toda LEI do law-ledger.md age em UM destes 4 pontos - nomear o ponto e o que impede confundir
"lembrete" com "bloqueio":

- PROMPT (UserPromptSubmit/SessionStart) - lembra a lei ANTES do pedido, nunca bloqueia.
  Ex: delegation-guard.ps1.
- ATO (PreToolUse, ou gate dentro do proprio script de publicacao) - bloqueia ANTES do ato
  terminar. Ex: graph-usage-sensor.ps1 (PreToolUse real); package-release.ps1 passo 0/3
  (gate de publicar). So 4 leis do motor tem ATO hoje: L27, L34, L42, L45 (delegation-gate.ps1,
  ATO desde 07/09/2026).
- FIM (hook de Stop, response-guard.ps1) - confere DEPOIS que o turno ja aconteceu. Este
  arquivo documenta as REGRAS 1/2/3 (L14, L33, L39, L41).
- SMOKE - so roda quando smoke-test*.ps1/law-ledger-check.ps1 e chamado a mao; nunca ativo
  numa sessao viva. E onde vive a maioria das leis do motor hoje.

Medido em 07/09/2026 (LATTICE): das 40 leis ativas, 37 so eram cobradas DEPOIS do estrago
(FIM/SMOKE/NENHUM) e 3 ANTES (ATO). Furo conhecido: PreToolUse so cobria
Read|Grep|Glob|Bash|PowerShell (.claude/settings.json) - Write/Edit nao tinham guarda no ATO.
FECHADO em 07/09/2026 por `scripts/delegation-gate.ps1` (L45): Write/Edit/NotebookEdit de dominio
agora tem guarda no ATO tambem, com a granularidade de SESSAO declarada (mais fraca que a REGRA 1
do response-guard.ps1, que isola o TURNO - ver L45 no law-ledger.md para a limitacao exata).

Regra pra lei nova: ao registrar uma LEI no law-ledger.md, declare tambem o PONTO (PROMPT/
ATO/FIM/SMOKE/NENHUM) na mesma linha - lei sem ponto e lei sem prova de quando ela age.
