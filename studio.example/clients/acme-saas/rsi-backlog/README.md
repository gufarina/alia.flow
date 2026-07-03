# RSI Backlog - molde (Studio-modelo que viaja)

Molde limpo do backlog de RSI por cliente. Sem dado de operador - so a estrutura. No Studio real do
operador, este e o lugar onde a frustracao captada vira oportunidade de melhoria da engine.

A captura e feita pela skill `rsi-friction` (skills/rsi-friction/SKILL.md): quando o operador se
frustra com o workflow (frase negativa, ou repetir/corrigir o mesmo pedido), um item nasce aqui -
so com confianca razoavel; na duvida, nada e registrado.

## Pastas

- `inbox/` - itens captados, aguardando melhoria. Cada .md = um atrito.
- `resolved/` - itens resolvidos, com a licao (atrito -> conserto que funcionou).

## Ciclo de vida

novo -> em-melhoria -> resolvido | tentado-nao-compensou

## Prioridade

prioridade = severidade x recorrencia

- severidade: 1 incomodo | 2 travou a tarefa | 3 parou tudo / perda de confianca
- recorrencia: quantas vezes o mesmo atrito ja apareceu
- faixa: >= 6 alta | 3 a 5 media | < 3 baixa

## Formato do item (inbox/AAAA-MM-DD-slug.md)

```
---
id: AAAA-MM-DD-slug
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
(citacao curta - a evidencia)

## Alvo provavel na engine
prompt | fluxo | gate | domain_pack | cadencia_de_loop

## Hipotese de melhoria
(o conserto provavel - sera testado, nao aplicado as cegas)
```

## O loop (feature /loop do Claude)

Sem agendador nem script. O loop e a feature /loop do Claude:

```
/loop Leia o rsi-backlog/inbox, pegue o item de maior prioridade com status novo e rode o
Procedimento B da skill rsi-friction. Se nao houver item pendente, encerre.
```

A cada rodada a Alia pega um item, mede antes, melhora, roda os testes, mede depois pela regua de 3
sinais (passos, tempo, clareza) e so mantem se reduziu o atrito sem deixar a Alia mais complexa,
mais lenta ou mais dificil. Senao, reverte. Encerra quando o backlog zera e os testes passam.
