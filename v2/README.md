# Alia Flow 2.0 - README de uso

> Para quem vai abrir e operar esta pasta. Indice de doc: `v2/MAP.md`. Contrato dos modulos:
> `v2/CONTRACTS.md`. Kernel (voz, 5 passos, glossario): `v2/AGENTS.md`.

## O que e

A reescrita enxuta do motor: o mesmo protocolo de 5 passos (IDENTIFICA, REGISTRA, DELEGA,
MONITORA, FECHA), com o texto de boot 61% menor, brief por fatia exata de arquivo (nunca leitura
fixa inteira) e registro de custo e veredito gravado pela propria maquina, nao digitado a mao.

## Os 4 contextos de verdade

Todo estado que importa mora em um destes quatro. `proof/` (a conferencia) e `release/` (o
empacotamento e a migracao) NAO sao contexto de verdade - sao ferramenta que le os quatro e nunca
guarda estado proprio.

1. **Task** - a unidade de trabalho (`v2/bin/task.py`, `v2/lib/task_model.py`). Brief de 6 campos,
   risco R1/R2, ledger de eventos, criterio de aceite. Vive em `state.json` (sempre via `--state`
   explicito, nunca resolvido sozinho).
2. **Squad** - quem executa (`v2/squad/squad-bridge.ps1`, `v2/bin/client.py`). Persona vira agente
   invocavel; so o squad do Client ativo fica visivel ao host.
3. **Adaptador do host** - onde e como o motor roda (deteccao de harness, `v2/hooks/dispatch.py`
   como despachante unico de PreToolUse/PostToolUse/SubagentStop). Cada host (Claude Code, Codex,
   OpenCode) tem um modo de delegacao diferente; o adaptador decide qual usar na entrada.
4. **Aprendizado** - o que fica de uma volta para a proxima (`v2/learn/curator.py`,
   `promote.py`, `reflector.py`). Licao so entra com causa-raiz declarada.

## Comandos

- `python v2/bin/task.py open --state <state.json> ...` - abre Task com os 6 campos do checklist;
  campo faltando ou Client invalido lista as opcoes validas, nunca so "invalido".
- `python v2/bin/task.py close --state <state.json> --artifact <prova> --veredito PASS|FAIL|CONCERN`
  - exige evidencia de veredito no ledger; Task de correcao sem `--root-cause` e erro.
- `python v2/bin/task.py context --state <state.json> --id <task_id>` - le a Task, nunca muta.
- `python v2/bin/client.py list` / `python v2/bin/client.py use <client>` - troca o squad visivel
  em `.claude/agents` para so o do Client escolhido (+ `--keep`). So vale a partir da PROXIMA
  sessao - o host le sub-agentes na abertura, `use` no meio nao troca quem ja e acionavel agora.
- `python v2/bin/brief.py open ...` - devolve ao Specialist so os 6 campos do checklist mais
  fatias `caminho#Lx-Ly` (embutidas se menores que 2 KB); fatia sem ancora ou fora do disco e
  recusada.
- `python v2/bin/migrate.py apply --source <v2> --target <instancia>` / `migrate.py undo --target
  <instancia>` - aplica a 2.0 numa pasta com backup datado; undo devolve o hash original.
- `python v2/proof/check.py` - a conferencia rapida unica: todas as baterias mais checagem cruzada
  do ledger. Alvo 30s, medido ~4s.

## A regra de ouro de economia

- Brief por trecho: nunca leitura fixa de abertura - so a fatia `caminho#Lx-Ly` que a Task
  declarou.
- Squad so do Client ativo: nunca os 82+ agentes do studio inteiro carregados de uma vez.
- Especialista com ferramentas minimas: ferramenta a mais custa contexto de boot antes mesmo de
  trabalhar (medido: ~27 mil tokens com ferramentas limitadas contra ~78 mil com tudo liberado).
- Relatorio em arquivo, nunca despejado na conversa - quem le busca o arquivo quando precisar.
- Troca de conversa acima do teto: a conversa longa de coordenacao e o maior desperdicio que
  sobra; ao estourar o orcamento combinado, o proximo trabalho comeca numa conversa nova, com um
  resumo de passagem curto no lugar de reler tudo.

## O que a 2.0 NAO faz ainda

- **Gateway (modo gerente de time) nao foi provado ao vivo.** O mecanismo existe (um agente pode
  abrir outros ate 3 camadas), mas a pesquisa + especialista novo (TASK-577) nao foi medida -
  fica para o teste do Operator na copia.
- **Codex e OpenCode seguem SO CONTRATO.** O fluxo completo so foi validado ao vivo dentro do
  Claude Code; os outros hosts tem o disco pronto, mas sem sessao real ponta a ponta.
- **A Laya so observa.** Em todos os 5 testes com dado real ela perdeu para a regra grata; fica
  como porta opcional, nunca decide nada.

## Onde estao as provas

Historico de medicao por incremento: `v2/proof/RELATORIO-*.md`. Numeros da entrega consolidada:
`clients/alia-flow-lab/artifacts/alia-2.0-2026-09-22/entrega.html`.
