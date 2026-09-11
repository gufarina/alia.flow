---
name: thread-writer
description: Escreve threads para Twitter/X e posts para Reddit usando estruturas comprovadas (narrativa, listicle, contrarian, tutorial, case study), hooks testados e regras de cadencia. A Alia dispara quando o Job pede conteudo social em formato thread ou post longo para divulgar o Cliente.
trigger: thread, escrever thread, thread viral, post reddit, post no reddit, conteudo twitter, conteudo x, fio no twitter
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/thread-writer
wave: 2
---

# Thread Writer

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa esta skill diretamente.
2. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Se nao existe Task registrada para a demanda, registrar primeiro e so entao executar.
3. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada. Publicar (postar no X ou no Reddit) e acao do operador, nunca da skill.
4. Grounding bloqueante: todo numero e toda afirmacao de peso citam fonte LIDA como [MEDIDO fonte] ou saem marcados [INFERIDO]. Nunca fabricar metrica, resultado ou historia falsa de "case" para dar credibilidade a thread.
5. Contexto BR: hooks, referencias e exemplos US viram equivalentes locais quando fizer sentido para o publico do Cliente (moeda, plataformas, girias, cases conhecidos no Brasil).

Nota de idioma: Português correto, com acentos. Arquivo salvo em UTF-8 sem BOM; o único erro é caractere corrompido. Emoji continua fora de peça pública. O conteudo final produzido - as threads e posts entregues como Artifact - usa acentuacao correta do portugues, no idioma do publico do Cliente.

## O que coletar antes de escrever

Antes de escrever qualquer thread, coletar (da Task, do contexto do Cliente ou do operador):

1. Topico - sobre o que e a thread?
2. Objetivo - engajamento, seguidores, trafego, autoridade ou awareness de produto?
3. Material-fonte - blog post, experiencia real, dados, pesquisa ou ideia original. E a base do grounding: o que nao vier daqui sai [INFERIDO].
4. Publico - quem segue esta conta? Interesses e nivel de sofisticacao.
5. Tom - educacional, storytelling, provocativo, casual, autoritario.
6. Comprimento - curto (5-7), medio (8-12), longo (13-15 tweets).
7. CTA - o que o leitor deve fazer? Seguir, retweetar, visitar link, responder.

## Templates de thread

### 1. Story Thread (narrativa pessoal)

1. Hook - momento dramatico ou resultado
2. Contexto - situacao inicial do autor
3. Problema ou desafio
4. Ponto de virada - o que mudou
5. Acao tomada
6. Obstaculo ou luta inesperada
7. Breakthrough ou resultado alcancado
8. Licao aprendida
9. Como o leitor pode aplicar
10. CTA

### 2. Listicle Thread (lista numerada)

1. Hook - "N [coisas] que [resultado]"
2 a N-2. Cada item numerado com explicacao
N-1. Resumo / TL;DR
N. CTA

### 3. Contrarian Take (posicao contraria)

1. Hook - afirmacao controversa
2. Sabedoria comum que as pessoas seguem
3. Por que essa sabedoria esta errada
4. Evidencia (dados, historia ou exemplo)
5. Mais evidencia ou segundo angulo
6. O que fazer em vez disso
7. Resultados esperados da nova abordagem
8. Responder a objecao principal
9. Conclusao - reafirmar a posicao contraria
10. CTA

### 4. Tutorial Thread (passo a passo)

1. Hook - "Como [resultado] em [prazo]"
2. Pre-requisitos ou contexto
3. Passo 1 com detalhe
4. Passo 2 com detalhe
5. Passo 3 com detalhe (continuar com os passos necessarios)
N-2. Erros comuns a evitar
N-1. Resultados esperados com prova
N. CTA com link para recurso mais detalhado

### 5. Case Study Thread (estudo de caso)

1. Hook - resultado impressionante com numeros especificos
2. Background (quem / o que / quando)
3. Situacao antes
4. Estrategia ou abordagem
5. Detalhes de implementacao
6. Desafios inesperados
7. Resultados com numeros especificos
8. Aprendizado-chave 1
9. Aprendizado-chave 2
10. Como replicar
11. CTA

Regra de grounding especial para case study: so escrever um case se o material-fonte contem o case de verdade. Numeros de resultado sao sempre [MEDIDO fonte]; sem fonte lida, nao existe case - trocar de template.

## Formulas de hook

| Formula | Exemplo (adaptar ao Cliente e ao contexto BR) |
|---|---|
| Resultado + prazo | "Cresci de 0 para 50 mil seguidores em 6 meses. Aqui esta exatamente como:" |
| Afirmacao corajosa | "90% das startups falham em marketing. Nao por orcamento. Por isto:" |
| Contraria | "A melhor estrategia de conteudo e postar menos. Deixa eu explicar:" |
| Abertura de historia | "Em 2019 eu estava quebrado, esgotado, pronto pra desistir. Ai tentei uma coisa:" |
| Listicle | "10 licoes de copywriting que levei 8 anos para aprender:" |
| Bastidores | "Fomos de R$0 a R$1M de receita anual. Aqui esta cada erro que cometemos:" |
| Curiosidade | "Existe um truque de precificacao que SaaS de 7 digitos usam e ninguem comenta:" |
| Desafio | "A maioria dos fundadores nao consegue explicar o que faz em uma frase. Voce consegue?" |

Os numeros dos exemplos acima sao ilustrativos do formato; no hook real do Cliente, valem as regras de grounding do contrato.

## Anatomia da thread

### Tweets de contexto (tweets 2-3)

- Estabelecer credibilidade: por que o leitor deve confiar em voce neste topico?
- Definir o problema: que dor ou pergunta esta thread resolve?
- Definir expectativas: o que o leitor vai ganhar?

### Tweets de valor (tweets 4 ate N-2)

A carne da thread. Cada tweet entrega um ponto, licao ou passo.

Regras:
- Uma ideia por tweet, nunca espremer duas
- Comecar cada tweet com afirmacao ousada ou numero
- Exemplos concretos, nunca conselho abstrato
- Variar o formato: dicas, historias, dados
- Cada tweet deve valer a leitura mesmo isolado

Padroes de formatacao:

| Padrao | Exemplo |
|---|---|
| Dica numerada | "3. Escreva a headline primeiro. Se a headline nao tem gancho, nada mais importa." |
| Licao + historia | "Maior licao: especificidade vende. A primeira landing dizia 'Economize tempo'. Conversao: 1,2%. Troquei para 'Economize 4 horas por semana'. Conversao: 4,7%." |
| Faca isto, nao aquilo | "Nao diga: 'Ajudamos negocios a crescer.' Diga: 'Ajudamos 200 SaaS a reduzir churn em 30%.'" |
| Dado + insight | "73% dos visitantes nunca passam da primeira dobra. Traducao: seu hero E a sua landing page." |

### Resumo (tweet N-1)

Recapitular os aprendizados em formato escaneavel:

```
TL;DR:

1. [Primeiro ponto]
2. [Segundo ponto]
3. [Terceiro ponto]
4. [Quarto ponto]
5. [Quinto ponto]

Salva essa thread. Voce vai precisar.
```

### CTA (tweet N)

| Tipo | Exemplo |
|---|---|
| Follow | "Se achou util, me segue @handle para threads diarias de marketing" |
| Retweet | "Retweeta o primeiro tweet para compartilhar com seu publico" |
| Reply | "Qual seu maior aprendizado? Responde que eu respondo todos" |
| Link | "Escrevi um guia mais profundo sobre isto. Baixa gratis: [link]" |
| Engajamento | "Qual dica te surpreendeu mais? Vou aprofundar a mais votada" |

Regras criticas de CTA:
- Sempre incluir CTA - thread sem CTA desperdica distribuicao
- Parear follow com retweet para crescimento maximo
- CTA com link: ultimo tweet ou primeira resposta, nunca no hook
- Posicao: tweet final ou primeira resposta

## Cadencia, formatacao e comprimento

### Estrutura dos tweets

- Sentencas curtas: maximo 15 palavras por sentenca
- Quebra de linha entre cada sentenca para legibilidade no mobile
- Sem muro de texto: se parece denso, dividir ou cortar palavras
- Fragmentos sao permitidos e adicionam impacto
- Variar o ritmo: alternar golpes curtos com explicacoes um pouco mais longas

### Emojis (no conteudo final, nunca neste arquivo)

- Maximo 0-2 por tweet
- Melhores usos: marcadores, enfase, quebras visuais
- Evitar: emojis em sequencia, texto carregado de emoji
- Nunca comecar o hook com emoji
- Usos comuns: seta (fluxo), check (listas), fogo (enfase), dedo para baixo (continue lendo)

### Numeros

- Digitos, nao palavras ("7 dicas", nao "sete dicas")
- Numeros especificos batem arredondados ("247%" bate "cerca de 250%")
- Comecar tweets de valor com "1.", "2." etc. para escaneabilidade
- Valores monetarios e percentuais prendem atencao: "R$50 mil", "300%", "4,7x"

### Comprimento da thread

| Comprimento | Tweets | Melhor para |
|---|---|---|
| Curto | 5-7 | Insight unico, dica rapida, historia simples |
| Medio | 8-12 | Listicle, tutorial, case study (ponto otimo) |
| Longo | 13-15 | Guia abrangente, historia detalhada |
| Muito longo | 16+ | Evitar - abandono alto. Dividir em duas threads |

Comprimento otimo: 8-12 tweets - longo o bastante para entregar valor, curto o bastante para reter.

## Processo de escrita (6 passos)

1. Outline - listar os pontos-chave em bullets e verificar o fluxo logico
2. Escrever o hook - gastar 50% do tempo aqui; rascunhar 5-10 variacoes e escolher a mais forte
3. Rascunhar os tweets de valor - um ponto por tweet, com exemplo; cada um deve funcionar sozinho
4. Escrever o CTA - alinhado ao objetivo (seguidores, retweets, cliques, respostas)
5. Editar - cortar palavras desnecessarias, trocar vagueza por especificidade, checar 280 caracteres, ler em voz alta para o ritmo, confirmar que a thread entrega o que o hook prometeu
6. Formatar - numerar cada tweet e sugerir horario otimo de postagem para o fuso do publico (BR: em geral fuso de Brasilia)

## Checklist pre-entrega (viral thread checklist)

- [ ] Hook tem menos de 280 caracteres e para o scroll
- [ ] Hook faz promessa clara que a thread entrega
- [ ] Cada tweet contem uma ideia, nao duas
- [ ] Numeros, exemplos ou historias especificas incluidos
- [ ] Nenhum tweet e muro de texto; quebras de linha separam pensamentos
- [ ] Comprimento entre 7 e 15 tweets
- [ ] CTA claro no tweet final
- [ ] A thread ensina, inspira ou entretem (idealmente dois dos tres)
- [ ] Sem link no hook (link no ultimo tweet ou primeira resposta)
- [ ] Cada tweet e compreensivel sem o contexto do anterior
- [ ] Grounding: todo numero e afirmacao de peso esta [MEDIDO fonte] ou [INFERIDO]

## Reddit

### Diferencas Twitter/X vs Reddit

| Aspecto | Twitter/X | Reddit |
|---|---|---|
| Titulo | Sem titulo - o hook e o primeiro tweet | O titulo e tudo - precisa puxar o clique |
| Comprimento | 280 caracteres por tweet | Ate 40.000 caracteres - ir fundo |
| Tom | Direto, confiante, pessoal | Util, humilde, comunidade em primeiro lugar |
| Autopromocao | Aceitavel com valor | Deve ser sutil ou leva ban |
| Formatacao | So quebras de linha | Markdown completo (negrito, listas, headers, links) |
| Engajamento | Retweets, likes | Upvotes e comentarios (comentarios importam mais) |
| Hashtags | 1-3 relevantes | Nunca usar hashtag no Reddit |

### Formato de post long-form

```
Titulo: [titulo atraente e especifico]

Corpo:
[Paragrafo de abertura - declarar a proposta de valor imediatamente]

[Conteudo principal - markdown: negrito, listas com bullets, passos numerados]

[Conclusao com pergunta para puxar comentarios]

---

[Opcional: CTA sutil ou link para recurso]
```

### Converter thread em post Reddit

1. Titulo: transformar o hook em titulo que puxa clique
2. Corpo: fundir os tweets em paragrafos fluidos com markdown
3. Expandir: leitor de Reddit espera profundidade - adicionar exemplos, dados, contexto
4. Terminar com pergunta: "O que funcionou pra voce?" puxa comentarios
5. Remover autopromocao: sem CTA de "me segue" - so agregar valor

Contexto BR: alem do Reddit, avaliar se o publico do Cliente vive em comunidades locais equivalentes (por exemplo, grupos e forums BR do nicho); a mesma logica de tom util-e-humilde se aplica.

### Postagem via API (referencia)

Se `REDDIT_CLIENT_ID` e `REDDIT_CLIENT_SECRET` estiverem disponiveis, e possivel montar a submissao via OAuth:

```bash
curl -X POST "https://oauth.reddit.com/api/submit" \
  -H "Authorization: Bearer ${REDDIT_ACCESS_TOKEN}" \
  -A "${REDDIT_USER_AGENT}" \
  -d "sr={subreddit}&kind=self&title={title}&text={body}&api_type=json"
```

No Alia Flow, este trecho e apenas referencia: pelo contrato, publicar e SEMPRE acao do operador. A skill entrega o Artifact pronto e a previa; nunca submete sozinha.

## Formato de saida (o Artifact)

Para toda requisicao de thread, o Artifact entrega:

1. Thread outline - plano em bullets mostrando o arco da thread
2. Thread completa - cada tweet numerado com contagem de caracteres, formatado exatamente como seria postado
3. Variacoes de hook - 3 a 5 hooks alternativos para o operador escolher
4. Instrucoes de postagem - horario sugerido, postar tudo de uma vez ou com intervalos, primeira resposta recomendada (frequentemente link ou dica bonus) e plano de engajamento para a primeira hora
