---
name: apply-safe-output
description: Frugal Skill deterministica (script, sem LLM) que executa o block_when da provenance antes de qualquer escrita. Le o campo provenance do alvo (campo proprio, ou o mapa de engine/governance/provenance.yaml) e BLOQUEIA quando provenance==nucleo e a origem e automation; para alvo agent-authored exige diff+evidence. E a porta de escrita aprovada por resultado - a mudanca irreversivel/nucleo so passa por gente. Use como guarda ANTES de aplicar qualquer auto-edicao proposta pelo RSI ou por um agente.
trigger: /apply-safe-output
provenance: nucleo
---

# Apply Safe Output

Executor deterministico do `block_when` da provenance. Confere, sem chamar modelo, se
uma escrita proposta pode efetivar - aplicando a regra que ja vive no manifesto, nao a
adesao do modelo.

Spec da fronteira: `engine/governance/provenance.md`.
Contrato (fonte da verdade): `engine/governance/provenance.yaml` (enforcement, linhas 64-66).
Mecanismo: `skills/apply-safe-output/apply-safe-output.ps1`.

Sem acentos, sem emojis em qualquer arquivo gerado (regra do CEO).

## O que e e por que existe

`provenance.yaml:64-66` ja declara o enforcement:

```
block_when: provenance == nucleo AND change_source == automation
require_for_agent_authored: [diff, evidence]
human_only: nucleo
```

Ate aqui isso era contrato lido: `provenance.md` promete "automacao SEMPRE via diff,
nunca aplica sozinha", mas nenhum script cumpria - dependia 100% de o modelo obedecer a
prosa. `orchestration.md:104-107` admite que o hook ainda nao existe.

Esta skill e o EXECUTOR que faltava: le o `provenance` do alvo (REUSE total do manifesto,
nao inventa politica) e aplica o `block_when`. E o primeiro mecanismo do "hook futuro".

## Como resolve a provenance do alvo

A excecao explicita vence o padrao (mesma ordem do manifesto):

1. Campo top-level `provenance:` no proprio alvo (`.yaml` de agente, frontmatter de SKILL.md).
2. Mapa de `provenance.yaml`: listas `nucleo[]` / `agent_authored[]` (por basename ou glob).
3. Defaults por arvore: `engine/` = nucleo; `studio/` = agent-authored.

## O check (deterministico, sem LLM)

Entrada: `-Path` (alvo), `-Source` (`automation` default | `operator`), `-Diff`,
`-Evidence` (switches). Opcional: `-ManifestPath` (default: `engine/governance/provenance.yaml`).

| Situacao | Resultado | Exit |
|----------|-----------|------|
| nucleo + automation | BLOQUEIA | 1 |
| agent-authored + automation sem diff+evidence | REPROVA | 1 |
| agent-authored + automation com `-Diff -Evidence` | PERMITE | 0 |
| qualquer alvo + `-Source operator` | PERMITE | 0 |
| provenance indeterminada | REPROVA (fail-closed) | 1 |

Saida: PASS (exit 0) ou FAIL (exit 1) com cada `deviation` apontando o desvio exato.

## Onde pluga

Antes de o RSI (ou um agente) aplicar qualquer auto-edicao proposta. `nucleo` + `automation`
= bloqueio duro (guardrail 1 do RSI virando check). Para `agent-authored`, a automacao so
passa propondo diff com evidencia - nunca aplica direto.

## Invariante

So executa o deterministico (a regra do manifesto). Nao julga o MERITO da mudanca (isso e o
Gate/Specialist). REUSE do `block_when` do yaml; o executor nao define politica nova. Custo
zero de token de modelo. Fail-closed: na duvida, bloqueia.
