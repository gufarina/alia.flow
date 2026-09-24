# SKILL: debate (modulo flow, I6)

Usa isto quando o passo DELEGA da Task classificou risco R2 (destino publico, irreversivel,
toca kernel ou contrato de modulo ou 3+ modulos, seguranca, ou ordem direta do Operator). R1
nunca entra aqui - vai direto ao Specialist.

## Passo a passo (1 rodada; 2a rodada so se o Gate der FAIL na 1a)

1. **Dono escreve a v1.** O dono da Task (o Specialist ou Gateway responsavel pelo Artifact)
   produz a v1 completa, ate 1 pagina. A v1 e o material que os revisores vao objetar - nao um
   resumo do plano.
2. **2 revisores so-leitura, lentes diferentes, em paralelo.** Cada revisor le SO a v1 (nunca
   escreve por cima) e devolve ate 40 linhas com objecoes concretas, na lente dele - nunca a
   mesma lente dos dois (ex: um revisor de risco/seguranca, outro de custo/simplicidade; ou um de
   fidelidade ao dominio, outro de aderencia ao contrato do modulo). A lente de cada revisor
   nasce do dominio da Task, escolhida pelo dono ao abrir o debate.
3. **Dono consolida a v2.** O dono le as duas devolutivas e escreve a v2 com uma tabela de
   objecoes: cada objecao vira uma linha com "aceita" ou "recusa" e o motivo. Objecao aceita muda
   a v2; objecao recusada fica registrada com o motivo, nunca some em silencio.
4. **So o dono escreve o Artifact.** Revisor nunca produz Artifact, so devolutiva.
5. **Custo no ledger.** O debate inteiro (v1, as 2 devolutivas, a v2) e uma delegacao a mais no
   ledger da Task - registra chamadas e tempo de cada participante, nao so do dono. E o custo que
   a E6 usa para decidir se o debate compensa (TASK-568: debate so continua como regra se ganhar
   em primeiro tiro custando ate 1,5 vez o caminho sem debate).
6. **2a rodada e excecao, nao regra.** So acontece se o Gate reprovar a v2 (FAIL). Reprovou de
   novo na 2a: escala para o Operator, nao insiste numa 3a.

## Contrato de saida

- v1: ate 1 pagina, do dono, nunca do revisor.
- Cada devolutiva de revisor: ate 40 linhas, objecoes concretas (nao elogio, nao resumo).
- v2: a mesma v1 mais a tabela de objecoes (objecao, aceita ou recusa, motivo) e o texto
  corrigido onde a objecao foi aceita.
- Toda linha da tabela de objecoes leva rotulo [MEDIDO], [LIDO] ou [INFERIDO] quando cita fato.

## O que isto nao e

Nao e uma segunda opiniao decorativa: objecao recusada sem motivo escrito reprova no Gate (L14,
grounding com rotulo). Nao e brainstorm livre: os revisores leem a v1 dada, nao propoem outro
projeto. Nao roda em R1 - gastar debate onde nao ha risco e o oposto de frugalidade.
