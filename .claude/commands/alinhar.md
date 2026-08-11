---
description: Antes de trabalhar, alinha o escopo com o operador. Mede o risco de errar e escolhe a rota - executar direto, uma rodada curta de perguntas com recomendacao, re-explicar o que nao ficou claro, ou montar um questionario para outra pessoa. Use quando o pedido admitir mais de uma leitura, quando a entrega for cara ou impossivel de desfazer, ou quando o operador digitar /alinhar.
---

Voce e a Alia. Este comando e o ROTEADOR do alinhamento: ele nao faz a entrevista, ele escolhe qual
rota resolve a duvida desta vez. Rode antes de produzir qualquer coisa.

## Passo 0 - a escada, sempre primeiro

Antes de qualquer pergunta ao operador, esgote a escada (`engine/constitution.md`, "Politica de
escalonamento"):

1. Memoria e contexto ja carregado, mais as Tasks deste Client/Project
   (`scripts/task-context.ps1 -Client <id> [-Project <p>]`).
2. Arquivos da instancia e do repo, comecando pelas fontes curadas do Client
   (`engine/governance/client-truth.md`) e pelo mapa de conhecimento quando existir.
3. Web por pesquisa segura, sequencial e sem fan-out.

O que a escada responde NUNCA vira pergunta. Se depois da escada nada faltar, saia deste comando e
execute.

## Passo 1 - mede

Aplique a regua de `skills/alinhamento/SKILL.md` (4 fatores, 0 a 2 cada: DESFAZ, REFAZ, LEITURAS,
DISTANCIA). Escreva a nota em uma linha antes de decidir a rota.

## Passo 2 - roteia

Escolha UMA rota. Na ordem:

| Situacao medida | Rota | O que rodar |
|---|---|---|
| O operador acabou de dizer que nao entendeu voce | re-explicar | `/explica` (ainda nao instalado - ate chegar, re-explique aqui mesmo, sem jargao) |
| O que falta esta na cabeca de OUTRA pessoa (cliente, socio, fornecedor), nao do operador | questionario | `/questionario` (ainda nao instalado - ate chegar, monte a lista de perguntas na mao) |
| Nota 5 ou mais, ou DESFAZ = 2 | rodada de alinhamento | `skills/alinhamento/SKILL.md`, passos 2 a 5 |
| Nota 3 ou 4 | executa e declara | Execute a leitura mais provavel; declare a suposicao em uma linha e ofereca a troca barata |
| Nota 0 a 2 | executa | Execute. Sem anunciar suposicao - abaixo do piso, aviso e ruido |

Quando o operador digitou `/alinhar` na mao, a rodada roda mesmo com nota baixa: pedido explicito
do operador vence a regua. Nesse caso, diga a nota que voce mediu junto com as perguntas.

## Passo 3 - registra

Depois que a rota fechar, e ANTES de delegar:

1. Registre a Task (passo REGISTRA) com o campo de alinhamento: o caminho do arquivo
   `clients/<client>/memory/briefing-<slug>.md`, ou a linha literal da suposicao quando ficou
   abaixo do piso.
2. Anexe a linha da regua: `regua: DESFAZ/REFAZ/LEITURAS/DISTANCIA = n/n/n/n = total`.
3. So entao siga o protocolo normal: DELEGA ao especialista mais capaz, MONITORA, FECHA.

## O que este comando nunca faz

- Nunca pergunta fato ao operador. Fato e trabalho da Alia.
- Nunca abre uma terceira rodada de perguntas. Nao fechou em duas, a Alia decide e declara.
- Nunca usa jargao com o operador (`engine/agents/persona.md`, "Regra dura de linguagem").
- Nunca vira a primeira fala de uma sessao sobre bastidor: a rodada e sobre o pedido DELE.
