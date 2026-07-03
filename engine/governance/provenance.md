# Alia Flow - Provenance (origem e mutabilidade dos artefatos)

> A convencao canonica que diz, para cada artefato do framework, QUEM pode muda-lo e COMO.
> E o freio de governanca que destrava o loop de aprendizado (reflexao pos-sessao, curador de
> memoria): a automacao so age onde tem permissao, sempre via diff, e nunca deleta.
> Politica estruturada ao lado: [provenance.yaml](provenance.yaml). Termos em
> [glossary.md](../glossary.md).

---

## A tese

O RSI separa o que pode evoluir do que e intocavel ([rsi.md](../rsi/rsi.md), tabela linhas 18-27;
guardrails 81-90). Mas essa fronteira vivia so na prosa do RSI. A provenance materializa a fronteira
NO METADADO de cada artefato: um campo que a automacao le antes de propor qualquer mudanca. Sem o
campo, o gate nao tem como saber se um arquivo e nucleo (e deve bloquear a auto-edicao) ou
agent-authored (e a automacao pode propor um diff).

## O campo `provenance`

Dois valores, e so dois:

| Valor | Quem muda | A automacao pode? |
|-------|-----------|-------------------|
| `nucleo` | so o operador humano | NAO. Auto-edicao em `nucleo` e bloqueada pelo gate. |
| `agent-authored` | a automacao PROPOE; o operador aprova | SIM, mas SEMPRE via diff. Nunca aplica sozinha. |

`nucleo` espelha exatamente a coluna "Nunca" da tabela do RSI (rsi.md:25-26) e a fronteira da
constituicao (constitution.yaml:74-80). `agent-authored` espelha a camada "evoluivel" (rsi.md:20-24).

Onde o campo vive:
- Nos `.yaml` dos agentes (campo top-level `provenance:`). Os `.md` dos agentes NAO tem frontmatter -
  NUNCA adicione frontmatter a eles.
- No frontmatter ja existente dos `SKILL.md`.
- Em `provenance.yaml` (este diretorio), o manifesto legivel por maquina com o mapa completo.

## Regra: auto-edicao SEMPRE propoe diff

Amarrada aos guardrails do RSI (rsi.md:81-87):

1. A automacao nunca escreve direto no nucleo (guardrail 1 do RSI: "Escopo fechado").
2. Toda mudanca em `agent-authored` sai como diff proposto, testado antes de aplicar
   (guardrail 3 do RSI: "Teste antes de aplicar"), versionado para rollback (guardrail 4).
3. Quem aplica o diff e gente. O sistema propoe; o operador aprova (guardrail 5 do RSI:
   "Aprovacao humana em mudanca de Gate").

## Regra: nunca deletar, so arquivar

A automacao JAMAIS deleta um artefato. Quando algo deixa de valer, ela ARQUIVA. Duas formas,
espelhando o ciclo de vida que os loops ja usam (loops.catalog.yaml:20, status
`proposed|active|retired`):

- Rebaixar para `status: retired` no proprio artefato, com `retired_reason:` e `retired_on:` (data
  ISO). E o caminho preferido para artefatos que ja carregam `status` (loops instanciados, etc.).
- Mover o arquivo para uma pasta `_retired/` irma, preservando o nome. E o caminho para artefatos
  sem campo `status` (notas de memoria, skills geradas, relatorios de loop).

Convencao da pasta `_retired/`:
- Fica ao lado do artefato original (ex: `memory/_retired/`, `skills/_retired/`).
- O arquivo arquivado ganha um cabecalho ou metadado com `retired_reason` e `retired_on`.
- `_retired/` e historico: nunca e re-executado, nunca alimenta recall ativo, nunca e deletado pela
  automacao. So o operador limpa, se quiser.

Deletar e prerrogativa exclusiva do operador. A automacao que precisaria deletar, arquiva e segue.

## O mapa: o que e nucleo vs o que e agent-authored

Fonte: a fronteira de constitution.yaml:74-80 e a tabela do RSI (rsi.md:18-27).

### Nucleo (provenance: nucleo - intocavel pela automacao)

- `engine/constitution.md` e `engine/constitution.yaml` - a lei do framework.
- `engine/glossary.md` - os termos base do contrato.
- Os schemas de contrato: `engine/governance/loops.catalog.yaml`,
  `engine/governance/quality-gate.yaml` e o schema de squad/agentes.
- `engine/agents/persona.md` e os agentes do produto: `engine/agents/*.yaml` (alia, architect,
  dev, devops, qa, data-engineer, squad-creator) e seus `.md` pares.
- As skills do produto: `skills/loop-designer/`, `skills/file-organization/`.
- O motor: orquestracao, governanca, RSI, versionamento (os specs `.md` do engine).

### Agent-authored (provenance: agent-authored - automacao propoe diff)

- O knowledge do studio (segundo cerebro): `studio/clients/{id}/squad/knowledge/...`.
- As memorias: `studio/clients/{id}/memory/...`.
- Skills GERADAS por agente (nao as do produto).
- Artefatos de loop: instancias em `studio/clients/{id}/loops.yaml`, relatorios de scan,
  graphify-out, propostas de RSI.
- Artefatos de entrega: `studio/clients/{id}/artifacts/...`.

Regra de fronteira: tudo em `engine/` (o motor publico) e nucleo por padrao. Tudo em `studio/`
(dados do operador) e agent-authored por padrao. A excecao explicita vence o padrao; o manifesto
[provenance.yaml](provenance.yaml) lista as areas.

## Como o Quality Gate e o RSI consomem o campo

- Antes de propor qualquer auto-edicao, o RSI le o `provenance` do alvo. `provenance: nucleo` +
  tentativa de auto-edicao = BLOQUEIO duro (e o guardrail 1 do RSI virando check verificavel).
- O Quality Gate, ao avaliar uma proposta de mudanca da automacao, reprova qualquer diff que toque
  um artefato `nucleo`. So o operador muda nucleo, e fora do ciclo automatico (versioning.md:56-57:
  "Mudanca aqui e MAJOR e exige aprovacao explicita do operador. Nunca por automacao").
- Para `agent-authored`, o gate exige que a mudanca venha como diff (nunca aplicada direto) e que
  carregue a evidencia que a justifica (guardrail 2 do RSI).

## Liga com

[Constituicao](../constitution.md) (a fronteira de mutabilidade) -
[RSI](../rsi/rsi.md) (os guardrails que a provenance torna verificaveis) -
[Versionamento](../versioning.md) (nucleo = MAJOR + aprovacao humana; agent-authored = diff) -
[Governanca / Loops](loops.catalog.yaml) (o ciclo proposed|active|retired do "nunca deletar").

---

*Alia - Delegue. Nao opere.*
