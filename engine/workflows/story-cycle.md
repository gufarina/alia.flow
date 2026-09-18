# Workflow - Story Development Cycle (SDC)

> O [protocolo de 5 passos](../orchestration.md) APLICADO a dev - nao um fluxo separado. Da intencao
> ao Artifact entregavel, com qualidade garantida em cada fase. A Alia orquestra; o Squad executa; o
> Gate decide. As 4 fases abaixo sao os 5 passos vestidos para dev: Create = IDENTIFICA+REGISTRA (a
> Story e o contrato), Validate+Implement = DELEGA, Gate = FECHA.

---

## As 4 fases

| Fase | Quem | Entrada | Saida | Gate de fase |
|------|------|---------|-------|--------------|
| 1. **Create** | Squad Owner | Intencao + contexto do Client | Story com AC testavel (Given/When/Then), escopo IN/OUT, Definition of Done | Tem AC testavel? |
| 2. **Validate** | Squad Owner | Story em `Draft` | Veredito GO / NO-GO via checklist | GO promove a `Ready` |
| 3. **Implement** | Dev (Specialist) | Story em `Ready` | Codigo + testes, ciclo TDD (teste falha -> codigo minimo -> refactor) | Testes verdes |
| 4. **Gate** | QA (Specialist) | Story em `InReview` | Veredito do Quality Gate: Pass / Concerns / Fail | Pass libera ao Operator |

Cada fase so abre quando o gate da fase anterior fecha. Nenhuma fase pula etapa: e a disciplina que
limita a entropia que o LLM injeta numa codebase sem trilhos.

## Estados da Story

```
Draft -> Ready -> InProgress -> InReview -> Done
```

| Estado | Significado | Transita por |
|--------|-------------|--------------|
| `Draft` | Story criada, ainda nao validada | Create |
| `Ready` | Validada com GO; pronta para implementar | Validate (GO) |
| `InProgress` | Dev implementando sob TDD | Implement |
| `InReview` | Artifact pronto, aguardando o Gate | Implement -> Gate |
| `Done` | Gate Pass + publicacao com release note | Gate (Pass) + DevOps |

## Regras inegociaveis

- Story sem **AC testavel** nao passa da fase Validate (Constitution: Evidence or It Did Not Happen).
- `Done` so existe apos **Gate Pass** mais **DevOps publicar** com release note.
- Gate **Fail** abre o [QA Loop](qa-loop.md); nao retrocede direto a `Draft`.
- Toda transicao registra evidencia no historico e na Memory (Artifact, decisao ou checklist).
- A linguagem ubiqua do Client e obrigatoria desde a AC: termo fora do glossario e drift de DDD.

## Quando usar

| Situacao | Rota |
|----------|------|
| Story nova de um epico, feature simples, bug fix | SDC direto (este workflow) |
| Feature complexa, requisitos ambiguos | Rodar o **Spec Pipeline** antes, depois SDC |
| Entrar em projeto existente sem mapa | **Brownfield Discovery** primeiro, depois SDC |

## Segue

[Orquestracao](../orchestration.md) - [Quality Gate](../governance/quality-gate.md) -
[QA Loop](qa-loop.md) - [Command Chaining](command-chaining.md) - [Engenharia](../engineering.md).
