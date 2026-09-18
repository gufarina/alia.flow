---
name: verify-artifact-persisted
description: Frugal Skill deterministica (script, sem LLM) que confirma que um Artifact foi PERSISTIDO de verdade no git, nao so produzido. Dado um caminho de artefato e/ou id de Task, checa que o arquivo existe no disco E esta versionado no git, retornando PASS/FAIL/CONCERN. Cobre o delta do Verification Gate de fim de tarefa que Validated Artifacts nao cobre: Validated Artifacts valida o FORMATO/contrato; esta skill valida a PERSISTENCIA. Use no fechamento de Task, no criterio Funciona/Rastreavel do Quality Gate, antes de marcar uma Task como done.
trigger: /verify-artifact-persisted
provenance: nucleo
---

# Verify Artifact Persisted

Capacidade deterministica que prova que um Artifact foi PERSISTIDO no git, nao apenas
gerado no disco. E o check maquinal de fim de tarefa: "Evidence or It Did Not Happen"
virado verificacao de git real.

Spec do padrao: `engine/features/frugal-skills.md` (a skill canonica e validate-artifact).
Mecanismo: `skills/verify-artifact-persisted/verify-artifact-persisted.ps1`.

## O que e e por que existe

Validated Artifacts (`engine/features/validated-artifacts.md`) ja roda como Frugal Skill
e valida o CONTRATO/FORMATO de um Artifact. Mas formato correto nao prova que o artefato
foi salvo e versionado: um arquivo pode estar bem formado e nunca ter sido commitado.

Esta skill cobre SO esse delta: confirma que o artefato existe no disco E esta sob
controle de versao do git. Nao duplica a checagem de formato; complementa.

## Onde pluga

No Quality Gate (`engine/governance/quality-gate.md`), criterios 1 (Funciona) e
4 (Rastreavel): alem do contrato de formato (Validated Artifacts), o Gate ganha um check
deterministico de que o caminho do Artifact ligado a Task esta de fato persistido no git.

## O check (deterministico, sem LLM)

Entrada: um caminho de artefato (-Path) e/ou um id de Task (-TaskId, usado so no relatorio).
Saida: PASS / FAIL / CONCERN, estruturada, com o hash do ultimo commit quando aplicavel.

O mecanismo roda:
- `git ls-files --error-unmatch <path>` para saber se o arquivo esta rastreado pelo git.
- `git log -1 --format=%h -- <path>` para o hash do ultimo commit que tocou o arquivo.

## Os tres modos

| Situacao | Resultado | Exit | Significado |
|----------|-----------|------|-------------|
| arquivo nao existe no disco | FAIL | 1 | artefato ausente: nao foi produzido |
| existe no disco, NAO esta no git | CONCERN (ou FAIL com -RequireCommitted) | 0 (ou 1) | persistido em disco, ainda nao commitado: divida rastreada |
| existe no disco E esta no git | PASS | 0 | persistido e versionado; reporta o hash do commit |

O modo CONCERN espelha o verdict Concerns do Gate: nao e Pass nem Fail, e divida assumida
e rastreada. Com `-RequireCommitted`, o fechamento exige commit real e o uncommitted vira FAIL.

## Invariante

So executa o deterministico (existe no disco? esta no git?). Nunca julga conteudo nem
formato (isso e Validated Artifacts e o Specialist). Custo zero de token de modelo.
