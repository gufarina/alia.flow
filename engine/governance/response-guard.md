# Alia Flow - Response Guard (M1: O FREIO na SAIDA)

> O enforcement da lei "a coordenadora delega dominio, nunca executa" na PORTA DE SAIDA da
> resposta. Contrato estruturado (limiares, modo) em response-guard.yaml. Sem acentos, sem emojis.

## O furo que isto fecha

A lei de delegacao ja tinha 2 guardas de maquina: `delegation-guard.ps1` (hook de UserPromptSubmit,
lembra a lei ANTES do pedido) e `session-reflection.ps1` (captura aprendizado DEPOIS que a sessao
acaba). Entre os dois nao havia nenhuma verificacao no momento em que a RESPOSTA sai para o
operador. Uma auditoria mediu a lacuna: a lei foi violada em menos de 24h com o lembrete de entrada
ja ligado. Lembrete no boot nao e enforcement - o freio precisa estar no pedal, nao so no manual.
`response-guard.ps1` (hook de Stop) e esse pedal: roda a cada turno, sobre o que de fato aconteceu.

## As 2 regras (deterministicas, sem LLM, sem rede)

1. **DELEGA** - se o turno escreveu/editou arquivo de algum cliente (`clients/...`, fora de
   memoria/proposta/backup/scratchpad/state/scripts) sem nenhuma chamada de `Agent`/`Task` no
   mesmo turno, e violacao. A excecao legitima e a ORDEM EXPLICITA do Operator para a Alia
   executar ela mesma - essa excecao fica registrada na Task (engine/orchestration.md), nao no
   guard: o guard nao le a Task, entao ele mede o padrao geral e a excecao vira "aceitar o alerta"
   em modo aviso, nunca um bypass tecnico escondido no script.
2. **GROUNDING** - se o texto da resposta final tem 3 ou mais afirmacoes de peso (referencia a
   arquivo por extensao, ou padrao `arquivo:linha`) e nenhum rotulo de proveniencia (`[MEDIDO`,
   `[INFERIDO`, `[LIDO`) aparece em algum ponto do texto, e violacao. Espelha o criterio 6
   (Fundamentada) do Quality Gate, na porta de saida em vez de so no Gate de Artifact.

## Os 2 modos e a rampa

O guard nasce em **aviso**: nunca bloqueia, so grava uma linha por turno em
`studio/response-guard-log.jsonl`. E o modo certo para o primeiro ciclo porque ainda nao sabemos
a taxa real de falso-positivo das 2 regras num check so sintatico. Depois de olhar o log por um
tempo (a meta e uma semana de operacao real) e confirmar que a taxa de falso-positivo e baixa, o
`mode` em response-guard.yaml vira **bloqueio** - so entao o guard passa a devolver
`{"decision":"block","reason":"..."}` quando acha violacao. Pular a rampa (nascer direto em
bloqueio) e o mesmo erro que travou o item no backlog antes (OPP-22, onda 2: "hook bloqueante trava
instancia viva" foi o risco que impediu de implementar).

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
