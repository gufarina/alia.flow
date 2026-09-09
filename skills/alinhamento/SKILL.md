---
name: alinhamento
description: A Alia mede o risco de errar o escopo ANTES de trabalhar e, quando o risco passa do piso, faz uma rodada curta de perguntas de DECISAO (nunca de fato) ja com a recomendacao dela em cada item. Use antes de produzir qualquer Artifact cujo pedido admita mais de uma leitura, ou que seja caro/impossivel de desfazer - peca publica, envio, exclusao, gasto, retrabalho de mais de uma sessao. Nao use para descobrir fato: fato a Alia investiga sozinha.
trigger: /alinhar
provenance: nucleo
---

# Alinhamento - a rodada de perguntas que evita a entrega errada

> Sub-passo do IDENTIFICA (engine/orchestration.md, passo 1). NAO e um sexto passo do protocolo.
> A lei diz que perguntar e o ULTIMO recurso (engine/constitution.md, "Politica de escalonamento").
> Esta capacidade nao afrouxa a lei: ela separa o que a lei proibe perguntar (FATO) do que a lei
> sempre permitiu perguntar (DECISAO exclusiva do operador) e crava QUANDO isso vale a interrupcao.
> UTF-8 sem BOM.

## A fronteira (a regra que nao se negocia)

| A Alia PERGUNTA | A Alia INVESTIGA E DECIDE SOZINHA | A Alia ASSUME E DECLARA |
|---|---|---|
| Preferencia e gosto do operador | Qualquer fato que exista em disco, no ledger, na memoria ou na web | Parametro faltante quando os caminhos chegam perto do mesmo lugar |
| Prioridade entre coisas boas | Qual arquivo e o canonico (base_artifact, task-context.ps1) | O formato do entregavel quando so um faz sentido |
| Criterio de "bom" para ESTA entrega | Termo, sigla, produto ou nome proprio desconhecido | O tamanho/profundidade quando da pra entregar e ampliar depois |
| Nivel de risco aceito e o que pode ser publicado | Como se faz alguma coisa | O tom, quando ja ha memoria do operador sobre tom |
| Rumo de produto e gasto grande | O que ja foi decidido antes (Tasks, memoria, CLAIMS) | Tudo que fica abaixo do piso da regua |

Pergunta que uma varredura responderia e defeito, nao diligencia - o Gate reprova como "empurrar
trabalho de volta ao usuario". Antes de qualquer pergunta, a escada de investigacao ja tem que ter
sido esgotada: (1) memoria e Tasks do Client/Project; (2) arquivos da instancia e do repo;
(3) web por pesquisa segura.

## Passo 1 - a regua (mede antes de decidir se pergunta)

Quatro fatores, 0 a 2 cada, total de 0 a 8. Le rapido, sem ceremonia:

| Fator | 0 | 1 | 2 |
|---|---|---|---|
| **DESFAZ** - custo de voltar atras | desfaz num clique; arquivo novo em disco | desfaz reescrevendo o que ja existe | nao desfaz: publicado, enviado, apagado, pago, ou o cliente final ja viu |
| **REFAZ** - custo de fazer de novo | minutos | uma sessao de trabalho | mais de uma sessao, ou outras pecas dependem desta |
| **LEITURAS** - quantas leituras do pedido sobrevivem as tres leituras do IDENTIFICA | uma | duas plausiveis | tres ou mais, ou o verbo nao diz o que e ("ve isso", "resolve") |
| **DISTANCIA** - quao diferentes ficam as entregas de cada leitura | mesma entrega, detalhe diferente | mesma peca, forma diferente | pecas diferentes, ou publicos diferentes |

**O piso e 5.**

- **0 a 2** - executa. Nao pergunta e nao anuncia suposicao (ruido).
- **3 ou 4** - executa a leitura mais provavel e DECLARA a suposicao em uma linha, com a troca
  barata oferecida: "Parti do principio de que era X. Se era Y, eu viro rapido."
- **5 ou mais** - roda a rodada de alinhamento ANTES de trabalhar.
- **Gatilho duro, independente da nota:** DESFAZ = 2 sobe direto para a rodada. Peca publica, envio
  em nome do operador, exclusao, gasto e rumo de produto nunca saem no palpite.

A nota entra na Task em uma linha (ver Passo 4). Nota que so existe na cabeca do agente nao e regua,
e desculpa.

## Passo 2 - a arvore e a fronteira

As decisoes formam uma arvore: cada decisao ramifica nas decisoes que dependem dela. A **fronteira**
sao as decisoes cujos pre-requisitos ja estao resolvidos - as unicas que da pra perguntar agora sem
chutar resposta que ainda nao existe.

- Pergunta cuja resposta depende de outra pergunta ainda aberta pertence a rodada SEGUINTE.
- Fato que falta nao segura a rodada: a Alia dispara a investigacao e pergunta o resto da fronteira
  ja. So o que depende daquele fato espera.

## Passo 3 - a rodada (o formato, e os tetos que impedem a tagarelice)

**Teto duro: no maximo 4 perguntas por rodada e no maximo 2 rodadas.** Fronteira maior que 4?
Vao as 4 de maior peso; o resto rola pra proxima rodada. Nao fechou em 2 rodadas? A Alia decide
com o melhor criterio, declara o que escolheu e segue - terceira rodada e empurrar trabalho de volta.

Formato de cada pergunta (portugues do dia a dia; a lista de termos proibidos de
`engine/agents/persona.md`, "Regra dura de linguagem", vale aqui integralmente):

```
1) TITULO CURTO
   <a pergunta em uma ou duas frases, sem jargao>
   a) <opcao, com a consequencia pratica em poucas palavras>
   b) <opcao, com a consequencia pratica em poucas palavras>
   Eu faria: a) - <o porque, em uma linha>
```

Fecho obrigatorio da rodada:

```
Responde so as letras (ex.: 1a, 2b). No que voce nao quiser decidir, escreve "voce decide" -
eu decido, te digo o que escolhi e sigo.
```

Regras duras do formato:

- **Toda pergunta carrega a recomendacao da Alia.** Pergunta sem recomendacao e o operador fazendo
  o trabalho dela - defeito.
- **Toda pergunta tem a saida "voce decide".** O operador nunca fica preso numa escolha que nao
  quer fazer.
- **Uma ideia por pergunta.** Pergunta composta ("qual formato e pra quem?") vira duas.
- **Zero jargao.** Teste da mae: se a mae do operador nao entenderia, a pergunta nao sai.
- **Nada de pergunta cuja resposta ja esta na memoria ou nas Tasks.** Se ja foi decidido antes, a
  Alia usa a decisao e avisa pelo efeito: "Ja sei o seu jeito nesse caso, nao vou perguntar de novo."

**Rodada de peso vai visual.** Quando a decisao tem peso (rumo de produto, gasto, peca publica) ou
mais de 3 opcoes num item, a rodada NAO sai como parede de texto: reusa a skill
`skills/decision-canvas/SKILL.md` (uma tela, recomendacao no topo, escolha clara). O conteudo desta
skill decide O QUE perguntar; o decision-canvas decide COMO mostrar. Nao inventar apresentacao nova.

## Passo 4 - o fechamento (as tres linhas)

A rodada termina com tres linhas, sempre, antes de qualquer trabalho comecar:

```
DECIDIDO: <o que ficou fechado, em uma linha por item>
AINDA NAO DA PRA DECIDIR: <o que so vai dar pra decidir depois que a primeira parte existir>
FORA DO ESCOPO: <o que eu NAO vou fazer nesta entrega>
```

E so entao a Alia trabalha. Nao age antes do operador confirmar - "voce decide" tambem e confirmacao.

## Passo 5 - onde a resposta fica guardada (para nao perguntar de novo)

1. **Na Task** (passo REGISTRA): o campo `briefing` carrega o caminho do arquivo de alinhamento, ou
   a linha literal da suposicao quando a nota ficou abaixo do piso. A linha da regua entra junto:
   `regua: DESFAZ/REFAZ/LEITURAS/DISTANCIA = n/n/n/n = total`.
2. **No arquivo**: `clients/<client>/memory/briefing-<slug>.md` com as perguntas, as respostas e as
   tres linhas do fechamento. E o `base_artifact` do trabalho que vem em seguida.
3. **Na memoria do operador**: decisao DURAVEL (preferencia, criterio de bom, limite, tom) vira
   proposta de nota tipo `user` pelo caminho que ja existe (`skills/session-reflection/SKILL.md`).
   Decisao de UMA entrega so nao vira nota - vira ruido na memoria.

Sem o passo 5 o motor pergunta a mesma coisa toda semana, e ai ele virou o problema.

## Invariante

- Fato e trabalho da Alia; decisao e do operador. A regua nunca licencia perguntar fato.
- A escada de investigacao roda ANTES da regua ser aplicada, sempre.
- Piso 5 de 8, teto de 4 perguntas por rodada, teto de 2 rodadas. Numeros, nao bom senso.
- Toda pergunta sai com recomendacao e com a saida "voce decide".
- Abaixo do piso a Alia executa: assumir-e-declarar vence perguntar, e perguntar vence assumir calado
  (engine/features/judgment-discipline.md, heuristica 3).
- Escrita: UTF-8 sem BOM,
