---
name: last30days
description: Inteligencia de mercado sob demanda. Dado um tema, varre sinais publicos recentes (comunidades, noticias, repositorios, tendencias de busca), ranqueia por relevancia e engajamento e sintetiza um brief curto e acionavel - o que mudou, o que importa, o que fazer. E discovery pontual, disparado pelo operador na hora, nao pesquisa agendada. Use quando alguem pede "o que rolou em X nos ultimos dias", precisa de um pulso rapido de um mercado ou tecnologia antes de uma decisao, ou quer escanear o cenario de um tema novo sem montar um loop.
trigger: /last30days <tema>
provenance: nucleo
---

# Last 30 Days

Capacidade de discovery de mercado sob demanda: o operador da um tema e recebe um brief
curto do que mudou nos sinais publicos recentes, ranqueado por importancia. E uma foto
acionavel do agora, tirada quando o operador pede.

## Diferenca frente ao Deep Research Loop (nao confundir, nao duplicar)

O [Deep Research Loop](../../engine/features/deep-research-loop.md) e outra coisa:

| Eixo | Deep Research Loop | last30days |
|------|--------------------|------------|
| Disparo | AGENDADO (cadencia diaria/semanal) | SOB DEMANDA (operador pede na hora) |
| Escopo | dominios ATIVOS do projeto, fixos | qualquer tema avulso, escolhido na hora |
| Destino | grava DATADO no segundo cerebro do Specialist | brief efemero entregue ao operador |
| Dono | Alia, como loop de governanca | quem perguntou, no momento |
| Proposito | manter o conhecimento existente com pulso | descobrir um cenario novo rapido |

Os dois se complementam: o loop mantem o que ja e dominio do squad atualizado; o
last30days explora um terreno que ainda nao virou dominio. Se um tema do last30days se
provar recorrente e estrategico, a recomendacao e promove-lo a um loop agendado via o
[Loop Designer](../loop-designer/SKILL.md) - mas isso e decisao da Alia, fora desta skill.

## O procedimento

### 1. Enquadrar o tema

- Reformule o tema livre num foco pesquisavel: o objeto + o angulo (ex: "framework X" ->
  "adocao, releases e criticas de X"). Se o tema vier ambiguo, faca UMA pergunta cirurgica
  antes de varrer (Principio: pensar antes de codar).
- Defina a janela. O default e o ultimo mes (o nome da skill); ajuste se o operador pedir
  outro recorte.

### 2. Varrer sinais publicos recentes

Use as FERRAMENTAS DE PESQUISA DISPONIVEIS no ambiente - busca web nativa e Perplexity
(intent rapido por default, sem gastar quota cara a toa). Nenhuma API key obrigatoria,
nenhum codigo externo. Cubra canais complementares para nao enxergar so um angulo:

- Comunidades e discussao (foruns tecnicos, agregadores de noticias da area, threads).
- Noticias e publicacoes do setor (anuncios, lancamentos, posicionamentos).
- Repositorios e releases (atividade de codigo, changelogs, novas versoes, traction).
- Tendencias de busca e interesse (o que subiu ou caiu de procura no periodo).

Regra de frugalidade: comece pela busca nativa; escale para Perplexity so quando precisar
de sintese de varias fontes ou de dado muito recente que a busca simples nao cobre
(alinhado a selecao de ferramentas em `engine/tools.md`). Pare quando os sinais novos
comecam a se repetir - saturacao e sinal de cobertura suficiente.

### 3. Ranquear por relevancia e engajamento

Cada sinal coletado recebe um peso por dois eixos, para o brief mostrar o que importa
primeiro:

- Relevancia: o quanto o sinal toca o foco do tema (direto > tangencial) e o quao recente
  e dentro da janela (mais novo pesa mais).
- Engajamento: tracao publica do sinal (discussao, reacoes, estrelas/forks, repercussao
  em mais de uma fonte). Sinal confirmado por fontes independentes sobe; rumor de fonte
  unica desce e entra marcado como nao confirmado.

Ordene do maior para o menor. Corte a cauda longa: o brief mostra o topo, nao tudo.

### 4. Sintetizar o brief curto e acionavel

Formato fixo, enxuto, em linguagem do operador (sem jargao tecnico cru):

- Titulo: o tema e a janela coberta.
- TL;DR: 2 a 3 linhas com o veredito - o que mudou e por que importa agora.
- Top sinais: lista curta (ate 5 a 7), cada item em uma linha = o que e + por que importa
  + a fonte. Ordenada pelo ranking do passo 3.
- O que fazer: 1 a 3 acoes ou perguntas concretas que esses sinais sugerem.
- Confianca e lacunas: o que ficou confirmado por mais de uma fonte e o que e sinal fraco
  ou nao confirmado. Honestidade sobre o que NAO se sabe.

Cada afirmacao do brief carrega a fonte - sem fonte, nao entra (Principio: evidencia ou
nao aconteceu).

## Invariante

- Discovery sob demanda, nao loop agendado: nao grava no segundo cerebro nem cria
  cadencia. Quem agenda dominio recorrente e o Loop Designer.
- Frugal: busca nativa primeiro, Perplexity so quando agrega; parar na saturacao.
- Todo item do brief tem fonte; sinal de fonte unica vai marcado como nao confirmado.
- Brief enxuto e acionavel: ranqueado, com TL;DR e proximos passos - nunca um despejo bruto.
- Português correto, com acentos. Arquivo salvo em UTF-8 sem BOM; o único erro é caractere corrompido. Emoji continua fora de peça pública.
