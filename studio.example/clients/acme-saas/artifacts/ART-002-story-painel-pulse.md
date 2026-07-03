# ART-002 - Story - Painel Pulse - Acme SaaS

> Artifact do Specialist Rex. Ligado a Task TASK-ART-002. Sem acentos, sem emojis.

## Story
Como membro de um Espaco, quero ver o estado dos Cartoes no Painel Pulse
para acompanhar o trabalho sem perguntar ao time.

## Criterios de aceite

### Cenario: Painel mostra os Cartoes do Espaco
- Given que estou em um Espaco com Cartoes
- When abro o Painel Pulse
- Then vejo cada Cartao com seu estado atual

### Cenario: Atualizacao reflete no Painel
- Given que um Cartao mudou de estado
- When o Painel Pulse recarrega
- Then o novo estado do Cartao aparece