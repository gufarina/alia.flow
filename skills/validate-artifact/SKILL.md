---
name: validate-artifact
description: Frugal Skill deterministica (script, sem LLM) que valida um Artifact contra o CONTRATO do seu tipo, ja declarado em engine/features/validated-artifacts.yaml. Dado um caminho de artefato e seu tipo (json, copy, story, migration, component), roda os checks de FORMATO daquele contrato e retorna PASS, ou FAIL com o desvio exato apontado (deviation). E a porta de formato do criterio Funciona do Quality Gate: roda ANTES de qualquer revisao de conteudo cara. Use como passo 1 do gate-on-artifact, antes de gastar julgamento de Specialist.
trigger: /validate-artifact
provenance: nucleo
---

# Validate Artifact

Capacidade deterministica que confere um Artifact contra o contrato de FORMATO do seu
tipo, sem chamar modelo. Format-before-content: a estrutura barata reprova antes do
julgamento caro.

Spec do padrao: `engine/features/validated-artifacts.md`.
Contrato (fonte da verdade): `engine/features/validated-artifacts.yaml`.
Mecanismo: `skills/validate-artifact/validate-artifact.ps1`.

Sem acentos, sem emojis em qualquer arquivo gerado (regra do CEO).

## O que e e por que existe

`validated-artifacts.yaml` ja declara, por tipo de Artifact, o checklist de formato que
o entregavel DEVE cumprir (ex.: `copy` exige headline + CTA + Expert Mind citado; `story`
exige Given/When/Then). Ate aqui isso era contrato lido, sem mecanismo que o cumprisse.

Esta skill e o EXECUTOR que faltava: le os contratos do yaml (REUSE total, nao inventa
regra) e roda os checks declarados para o tipo do artefato.

## Onde pluga

No Quality Gate (`engine/governance/quality-gate.md`), criterio 1 (Funciona): e o passo 1
do `gate-on-artifact`. Se o formato nao bate o contrato, o Gate reprova de graca, por
script, antes de acionar o Specialist para revisar conteudo.

## O check (deterministico, sem LLM)

Entrada: caminho do artefato (`-Path`) e tipo (`-Type`; se omitido, e inferido do nome do
arquivo). Opcional: `-ContractsPath` (default: `engine/features/validated-artifacts.yaml`),
`-TaskId` (so no relatorio).

Saida: PASS (exit 0) ou FAIL (exit 1) com cada `deviation` apontando o desvio exato.

O mecanismo:
- Le os contratos de `validated-artifacts.yaml` (mapa `type -> checks`).
- Resolve o tipo do artefato e roda cada check declarado para aquele tipo.
- Junta os desvios; se houver qualquer um, e FAIL com a lista.

## Os dois modos

| Situacao | Resultado | Exit | Significado |
|----------|-----------|------|-------------|
| formato bate o contrato do tipo | PASS | 0 | segue para revisao de conteudo |
| formato viola o contrato | FAIL | 1 | reprova automatica, com o desvio apontado |

## Invariante

So executa o deterministico (o formato bate o contrato?). Nunca julga a QUALIDADE do
conteudo (isso e o Specialist). REUSE dos contratos do yaml; o executor nao define regra
nova. Custo zero de token de modelo.
