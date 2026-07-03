---
name: rsi-friction
description: Captura atrito real do operador com o workflow Alia (a Alia ou um agente) e o transforma em OPP de melhoria da engine alia.flow, com prioridade. E a COLETA do RSI a partir de frustracao humana - a fonte que faltava ao lado de gate/custo/drift. Tambem executa o ciclo de MELHORIA (regua de 3 sinais + teste + rollback). Use em silencio quando perceber frustracao com o workflow, sob demanda com /alia-friction, ou quando o operador pedir para rodar o loop de melhoria do backlog-rsi.
trigger: /alia-friction
provenance: nucleo
---

# RSI Friction - frustracao real vira melhoria da engine

A Alia e o prototipo de estudo de RSI (Recursive Self-Improvement). Esta capacidade fecha o
unico ponto que o RSI ainda nao tinha: o atrito do proprio operador, ao vivo, virando combustivel
para a engine se melhorar. Spec do motor: `engine/rsi/rsi.md`. Politica: `engine/rsi/rsi.yaml`
(`triggers -> operator-friction-pattern`). Guardrails de proposta: `engine/governance/provenance.md`.

Toda escrita: UTF-8 sem BOM. Arquivo de produto (skills/, engine/, scripts/) e SEMPRE ASCII puro,
sem acento e sem emoji (lei do CEO; o smoke-test trava). Os itens do backlog vivem no `studio/`
privado (dado do operador) - ali o texto pode ter acento, pois nao e produto.

## Nao confundir com session-reflection

Mesmo sinal (frustracao), destinos diferentes:

- `session-reflection` -> nota de MEMORIA (quem e o operador / como executar a tarefa). Vai para
  `memory/_proposals/`. Conserta o COMPORTAMENTO do agente.
- `rsi-friction` (esta) -> OPP de MELHORIA DA ENGINE (o que mudar no alia.flow). Vai para o
  `rsi-backlog/`. Conserta o PRODUTO.

Quando a licao for "como a Alia deveria agir comigo", use session-reflection. Quando for "o
workflow/engine tem um buraco que me travou", use esta.

## Como o loop roda (feature /loop do Claude)

Nao ha agendador externo nem script de batimento. O loop e a feature `/loop` do Claude Code:
o operador (ou a Alia) dispara um `/loop` que, a cada rodada, executa o Procedimento B sobre o
rsi-backlog. O proprio `/loop` se auto-regula no intervalo e encerra quando o backlog nao tem
mais item pendente e tudo passou nos testes (ver B6).

Comando de referencia (auto-paced; pode pedir cadencia, ex. 2x ao dia):

  /loop Leia studio/clients/alia-flow/rsi-backlog/inbox, pegue o item de maior prioridade com
  status novo e rode o Procedimento B da skill rsi-friction. Se nao houver item pendente, encerre.

A captura (Procedimento A) acontece em silencio durante as sessoes normais - nao depende do loop.

---

## Procedimento A - CAPTURA (silenciosa, nunca interrompe)

### A1. Quando marcar atrito

Sinais de frustracao com o workflow:

- Frase negativa direta: "isso ta ruim", "nao era isso", "de novo isso", "voce nao entendeu".
- Repeticao/correcao do mesmo pedido mais de uma vez na mesma sessao.

So registre com confianca razoavel. Na duvida, NAO registra (melhor perder um do que encher de
lixo). Nunca pergunte "voce esta frustrado?" - a captura e silenciosa; no maximo, ao fim da
resposta, uma linha discreta de que o atrito foi anotado para melhoria.

### A2. Lista anti-captura (jamais vira OPP)

Descartar - igual ao session-reflection:

- Falha de ambiente (path, permissao, disco, comando ausente).
- "Ferramenta X nao funciona / API fora / timeout" (afirmacao negativa sobre ferramenta).
- Erro transitorio (flaky, retry resolveu, rede caiu e voltou).

Regra mestra: capturar a OPORTUNIDADE de melhoria do workflow, nao o desabafo. Incidente isolado
nao e padrao - mas aqui cada item ja entra com `recorrencia: 1` e a prioridade sobe se repetir.

### A3. Prioridade (regua clara)

`prioridade = severidade x recorrencia`

- severidade: 1 = incomodo (segui sem travar) | 2 = travou a tarefa | 3 = parou tudo / perdi confianca.
- recorrencia: quantas vezes este mesmo atrito ja aparece no backlog (some +1 se ja existe item igual).
- faixa: produto >= 6 = alta | 3 a 5 = media | < 3 = baixa.

Antes de criar item novo, procure no `rsi-backlog/inbox/` um item do mesmo atrito. Se achar,
incremente `recorrencia` e recalcule a prioridade em vez de duplicar.

### A4. Formato do item (um arquivo .md por atrito)

Grava em `studio/clients/alia-flow/rsi-backlog/inbox/AAAA-MM-DD-slug-curto.md`:

```
---
id: AAAA-MM-DD-slug-curto
origem: alia | agente:<nome>
severidade: 1 | 2 | 3
recorrencia: 1
prioridade: alta | media | baixa
status: novo
criado: AAAA-MM-DD
---

## O que aconteceu
(1 frase: o atrito real)

## Prova (trecho da conversa)
(citacao curta do que o operador disse / fez - a evidencia)

## Alvo provavel na engine
prompt | fluxo | gate | domain_pack | cadencia_de_loop  (ver engine/rsi/rsi.yaml -> evolvable)

## Hipotese de melhoria
(o conserto provavel - sera testado, nao aplicado as cegas)
```

Status do item: `novo` -> `em-melhoria` -> `resolvido` | `tentado-nao-compensou`.

---

## Procedimento B - MELHORIA (o trabalho do loop)

Roda quando o operador pede, ou via /loop sobre o backlog. Pega UM item por vez, o de maior
prioridade com status `novo`. Respeita os guardrails do RSI (`engine/rsi/rsi.yaml -> guardrails`):
so toca camada `evolvable`, nunca o nucleo; teste antes de aplicar; versao anterior guardada.

### B1. Mede o ANTES (regua de 3 sinais)

Para a tarefa que gerou o atrito, registre o estado atual:

1. passos: quantos passos para chegar ao resultado.
2. tempo: tempo / esforco ate o resultado.
3. clareza: a linguagem para o operador esta simples? (sim/parcial/nao)

### B2. Faz a melhoria

Aplica a hipotese no alvo `evolvable`. Marca o item como `em-melhoria`.

### B3. Mede o DEPOIS e roda os testes

- Roda `scripts/smoke-test.ps1` (engine) e, se tocou o studio, `scripts/smoke-test-studio.ps1`.
- Mede de novo os 3 sinais.

### B4. Criterio de aceite (so mantem se compensou)

MANTEM a melhoria somente se TODAS forem verdade:

- o atrito original foi resolvido;
- nenhum dos 3 sinais piorou sem ganho claro (mais passos, mais lento, ou linguagem mais dificil
  reprova, a menos que haja ganho evidente que compense);
- os testes passaram (smoke verde).

Caso contrario: reverte (rollback da versao anterior) e marca o item `tentado-nao-compensou`
com 1 linha do porque. A engine prioriza MENOS atrito e SIMPLICIDADE - melhoria que complica
sem ganho e regressao, nao progresso.

### B5. Fecha o ciclo (aprendizado para a engine)

Item aprovado -> marca `resolvido` e escreve uma licao curta em
`rsi-backlog/resolved/AAAA-MM-DD-slug.md`: o atrito real -> a mudanca que funcionou -> qual sinal
melhorou. E o registro que alimenta a proxima versao do alia.flow (CHANGELOG/VERSION quando virar
release, conforme a cadencia "uma OPP = uma versao").

### B6. Condicao de parada do loop

O loop encerra quando: nao ha item `novo` de prioridade alta/media pendente, e toda melhoria
aplicada no ciclo passou no aceite (B4). Itens `tentado-nao-compensou` nao reabrem sozinhos -
ficam como aprendizado. Nada de ficar girando a toa: backlog limpo = loop dorme.

## Invariantes

- Captura em silencio; nunca interrompe para perguntar.
- Captura a OPORTUNIDADE, nao a reclamacao. Na duvida, nao registra.
- So toca camada `evolvable` do RSI; nunca o nucleo / constituicao / engine_core.
- Teste antes de aplicar; rollback se piorar; mantem so se reduz atrito sem complicar.
- Arquivo de produto = ASCII puro, UTF-8 sem BOM. Backlog (studio/) pode ter acento.
- Se a propria skill virar burocracia, ela falhou (menos atrito sempre).
