# Workflow - QA Loop

> Ciclo iterativo de revisao e correcao ate a qualidade - nenhum Artifact quebrado escapa ao
> Operator. E o que roda quando o [Quality Gate](../governance/quality-gate.md) da Fail no
> [Story Cycle](story-cycle.md).

---

## O loop

```
QA revisa o Artifact contra o Quality Gate -> veredito
   |- Pass     -> Story -> Done
   |- Concerns -> libera com ressalva registrada (vira debito / input de RSI)
   |- Fail     -> Dev corrige -> re-review (nova ABORDAGEM, nao a mesma tentativa)
   |- Blocked  -> escala a Alia
Maximo N iteracoes (padrao 5). Cada Fail consome 1 iteracao.
```

A correcao de um Fail nao repete o mesmo caminho: cada re-review exige uma **abordagem diferente**.
Insistir na mesma tentativa nao conta como progresso e dispara escalonamento mais cedo.

## Vereditos

| Veredito | Significado | Acao | Registra na Memory |
|----------|-------------|------|--------------------|
| **Pass** | Atende os 6 criterios minimos do Gate | Story -> Done | verdict + evidencia |
| **Concerns** | Liberavel com ressalva | Libera; ressalva vira debito rastreado e input de RSI | verdict + ressalva |
| **Fail** | Issues HIGH/CRITICAL abertas | Volta ao Dev com feedback acionavel | tentativa + motivo |
| **Blocked** | Falta decisao ou recurso externo | Escala a Alia | bloqueio + causa |

> Os 6 criterios minimos (Funciona, Aderente ao DDD, Frugal, Rastreavel, Simplicidade/Atrito,
> Fundamentada) sao herdados do
> [Quality Gate](../governance/quality-gate.md). O QA Loop e o motor; o Gate e a regua.

## Escalacao a Alia

Disparada por qualquer um:
- `max_iterations` atingido (padrao 5);
- veredito **Blocked**;
- mesma falha reincidindo apos abordagem trocada.

A Alia aplica **5 Whys** sobre a causa raiz e decide: corrigir a abordagem, trocar o recurso
(outro Specialist/Expert Mind), reduzir o escopo, ou levar ao Operator. A Alia nao reabre a
implementacao - ela governa a fronteira e a rota.

## Conexao com a governanca

Cada veredito e registrado na Memory com evidencia (nunca um "passou" sem prova). Padroes de **Fail
recorrente (3+ no mesmo ponto)** alimentam o **RSI**: viram melhoria de prompt, de Gate ou de
Domain Pack. O sistema fica melhor e mais barato a cada Loop. Ver [loops](../governance/loops.md).

## Frugalidade

- Revisao incremental: o QA olha so o que mudou desde o ultimo veredito.
- Consultar Memory/grafo antes de reprocessar contexto ja conhecido.
- O modelo certo para a verificacao - nao usar canhao para matar mosquito.

## Segue

[Quality Gate](../governance/quality-gate.md) - [Story Cycle](story-cycle.md) -
[Loops](../governance/loops.md) - [Orquestracao](../orchestration.md).
