# Changelog - Alia Flow

Mudancas visiveis de cada versao publica do Alia Flow.
Formato baseado em Keep a Changelog. Versionamento semantico.

## [0.1.0] - 2026-07-03

Primeiro beta publico. O Alia Flow e um arnes de operador que voce roda dentro do seu
proprio coding agent (Claude Code, Codex ou OpenCode): a Alia recebe o trabalho em
linguagem comum, escolhe o especialista certo, roda um loop de qualidade e so entrega o
que passou pela conferencia.

O que ja funciona neste beta:
- **Instalacao de uma linha.** Sem git, sem Python - so o PowerShell do Windows. Abre a
  pagina de boas-vindas sozinha e voce diz "pronto".
- **Cliente > Projeto > Tarefa com rastreabilidade.** Todo pedido vira uma tarefa
  registrada, com de onde partiu e o que produziu. Nada se perde entre sessoes; a Alia le
  o historico antes de agir e continua de onde parou.
- **Times por cliente (squads).** Cada cliente ganha um time de especialistas com um dono
  ativo (Squad Owner) que faz a roda girar, e um segundo cerebro (memoria + grafo do
  conhecimento) que mantem a consistencia das entregas.
- **Quality Gate.** Nenhuma entrega sai crua: passa por uma conferencia (funciona, usa a
  linguagem do cliente, e frugal, e rastreavel) antes de chegar a voce.
- **Especificacao de entrega por cliente.** Regras objetivas de design/formato/tom para
  que todas as pecas saiam coerentes.
- **Mission Control.** Um painel que mostra o que foi feito e destaca o que empacou -
  tarefas paradas ganham atencao.
- **Provado por teste.** Um conjunto de verificacoes deterministicas (o smoke test) roda
  sem IA e sai ALL GREEN; inclui a prova de ablacao (a memoria muda o resultado, 0/5 para
  5/5), que voce roda na sua maquina.

Pre-requisito: um coding agent. A Alia mora dentro de um deles.
- Claude Code: https://claude.com/claude-code
- Codex: https://github.com/openai/codex
- OpenCode: https://opencode.ai

Licenca MIT.
