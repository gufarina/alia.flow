---
name: state-resume
description: Frugal Skill deterministica (script, sem LLM) que le o journal append-only de eventos (events[]) do studio/state.json e, por Task, aponta o ultimo passo bom e o ponto de retomada. Se um run multi-passo morre no meio (limite, crash, operador fechou), ela diz de onde continuar em vez de re-disparar tudo. Tambem valida o schema do journal (-Validate): cada evento tem ts, task_id, step (5 passos do protocolo), type e ref, e a cadeia e append-only/monotonica (ts nunca retrocede). PASS exit 0, FAIL exit 1 com o desvio apontado. Custo zero de token.
trigger: /state-resume
provenance: nucleo
---

# State Resume

Capacidade deterministica que le o diario de eventos da Task e responde "de onde retomar?"
sem chamar modelo. Durabilidade do fluxo: o trabalho de varios passos nao recomeca do zero
quando morre no meio.

Spec do padrao (5 passos): `engine/orchestration.md`.
Estado (fonte da verdade): `studio/state.json` (campo `events[]`, aditivo ao `tasks[]`).
Mecanismo: `skills/state-resume/state-resume.ps1`.

## O que e e por que existe

O `state.json` gravava so `tasks[]` (snapshots do que ja fechou) - zero registro do que
acontece DENTRO de uma Task. Run multi-passo que morre no meio nao tinha de onde retomar:
re-disparava tudo, re-aprovava, re-gastava token.

Esta skill ADAPTA o PADRAO journal (nao importa runtime JS/.NET): o estado ganha um
`events[]` append-only e este script o le para apontar o ultimo passo bom por Task.

## O journal (`events[]`, append-only)

Cada evento e uma linha aditiva - nunca se reescreve nem se reordena o passado:

| Campo | Significado |
|-------|-------------|
| `ts` | carimbo de tempo ISO-8601 (monotonico: nunca retrocede) |
| `task_id` | a Task a que o evento pertence |
| `step` | passo do protocolo: IDENTIFICA, REGISTRA, DELEGA, MONITORA, FECHA |
| `type` | started, delegated, artifact, gate, escalated, done |
| `ref` | ponteiro do evento (client, specialist, caminho do artifact/gate/memoria) |

`tasks[]` segue valido e inalterado: `events[]` e aditivo. Estado antigo (so `tasks[]`)
nao quebra - journal vazio nao e erro.

## Os dois modos

| Modo | O que faz | Saida |
|------|-----------|-------|
| `resume` (default) | por Task, ultimo passo bom + de onde retomar | lista por Task; done = nada a retomar |
| `-Validate` | confere schema do journal: campos obrigatorios + append-only/monotonico | PASS exit 0 / FAIL exit 1 + deviation |

Entrada: `-StatePath` (default: `studio.example/state.json`), `-Validate` (liga o modo schema).

## Como aponta a retomada

- Agrupa `events[]` por `task_id`; o evento de maior `ts` e o ultimo passo bom.
- Se o ultimo evento for `type: done` -> Task COMPLETA, nada a retomar.
- Senao -> Task INTERROMPIDA: retoma DO ultimo passo bom (continua o passo corrente,
  sem re-rodar os anteriores). Ex.: ultimo evento `MONITORA/artifact` -> retomar de
  MONITORA (cobra gate + memoria), sem refazer IDENTIFICA/REGISTRA/DELEGA.

## Invariante

So executa o deterministico (ler o journal e apontar o passo). Nao decide dominio, nao
julga conteudo. O journal e append-only: `-Validate` reprova qualquer `ts` que retroceda
(global ou por Task) e qualquer evento sem campo obrigatorio. Custo zero de token de modelo.
