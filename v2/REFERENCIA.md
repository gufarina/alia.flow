# REFERENCIA.md - biblioteca sob demanda do kernel

Saiu do `AGENTS.md` na TASK-845 (27/09/2026) para o kernel caber em 6.000 bytes por janela.
Nada aqui e regra nova: e o mesmo texto, lido so quando a tarefa pede.

## Squad ativo (dieta de token)

`client.py use <client>` sincroniza `.claude/agents` com so o squad desse Client. `alia-flow-lab`
nao entra por padrao: so quando o Client ativo e o proprio motor, ou com `--keep alia-flow-lab`.
`client.py use` chama `v2/squad/bridge.ps1 -Only <client>` (3 macro + o Client); nao ha mais reserva
`.claude/squads`. `client.py list` mostra os Clients com `clients/<id>/squad/squad.yaml`. `-Target context-load`
nao depende do roster.

## Glossario

- Operator: o humano que delega trabalho e e dono do resultado.
- Studio: o espaco de trabalho do Operator.
- Client: entidade para quem o trabalho e feito.
- Project: agrupador de Tasks sob um Client.
- Task: unidade atomica de trabalho, com brief, estado e evidencia.
- Artifact: a prova de que uma Task foi concluida.
- Squad: time de Specialists montado para um Client.
- Gateway: o papel de lider de um Squad; sempre camada A, sempre com o segundo cerebro completo.
- Specialist: agente com conhecimento profundo de um dominio.
- Gate: o ponto de verificacao que bloqueia entrega ruim antes do Operator ver.
- Memory: conhecimento retido entre voltas: grafo, notas e playbook.
- Loop: o ciclo produz, avalia, refina, aprende que fecha uma Task.
- RSI: o mecanismo que usa cada volta do Loop para melhorar a proxima.
- Budget: o teto de chamadas ou custo de uma delegacao.
- Ledger: o registro de eventos, so de acrescimo, que prova quem fez o que.
