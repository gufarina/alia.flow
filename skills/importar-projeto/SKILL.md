---
name: importar-projeto
description: A Alia importa um projeto existente (ex um cliente do legado ou outra base) para dentro do Alia Flow, traduzindo-o para a arquitetura atual (cliente em studio/clients/{id}, squad em camadas A/B/C, knowledge com DDD, loops). Nao e um monolito novo - ORQUESTRA o que ja existe (scaffold deterministico, Squad Creator, Loop Designer, smoke). A origem e SO LEITURA; nada vira active sem aprovacao do operador. Use quando o operador pede para "importar", "trazer", "migrar" ou "onboardar" um projeto para o studio.
trigger: /importar-projeto <id>
provenance: nucleo
---

# Importar Projeto

Capacidade da Alia de trazer um projeto que ja existe para dentro do Alia Flow, na arquitetura
atual, reusando as ferramentas que o framework ja tem. A skill e a RECEITA que amarra os passos;
cada passo inteligente reusa uma capacidade existente, nao reescreve nada.

Sem acentos, sem emojis em qualquer arquivo gerado (regra do CEO).

## O que ela reusa (nao duplica)

| Passo | Ferramenta existente | Papel |
|-------|----------------------|-------|
| scaffold + registro | `scripts/import-project.ps1` (helper deterministico) | cria a estrutura vazia e registra como `proposed` |
| squad + DDD | [Squad Creator](../../engine/agents/squad-creator.md) | mapeia dominio -> squad em camadas + knowledge com DDD |
| loops | [Loop Designer](../loop-designer/SKILL.md) (modo sugerir) | propoe o `loops.yaml` do cliente novo |
| verificacao | `scripts/smoke-test-studio.ps1` | confirma que o import nao quebrou nada |

A skill nao monta squad nem desenha loops com as proprias maos: ela ACIONA o Squad Creator e o Loop
Designer. O helper so faz a parte bracal (criar pastas, client.md, registrar no state.json).

## A receita (6 passos)

### Passo 1 - Ler a origem (SO LEITURA)
Ler o projeto de origem (ex um cliente no legado, ou outra base apontada por `SourcePath`).
Extrair o briefing: setor, stack, dominio, objetivo, e qualquer DDD ja documentado (glossario,
bounded contexts). NUNCA escrever na origem - leitura pura. A origem e referencia, nao destino.

### Passo 2 - Scaffold do cliente novo (via helper)
Rodar o helper deterministico para criar o cliente na arquitetura atual:

```
scripts/import-project.ps1 -Id {id} -Name "{nome}" -Sector "{setor}" -SourcePath "{origem}" -DryRun
```

Conferir o DryRun primeiro (nada e escrito). Quando estiver certo, rodar sem `-DryRun`. O helper:
- cria `studio/clients/{id}/squad/agents/` e `studio/clients/{id}/squad/knowledge/` VAZIAS
  (para o Squad Creator preencher).
- cria um `client.md` minimo (id, name, sector, source) em UTF-8 sem BOM.
- registra o cliente em `studio/state.json` com `status: proposed` (NAO active), sem apagar nada.

O helper NAO monta squad nem knowledge e NAO marca active - isso e dos passos seguintes e da
aprovacao do operador.

### Passo 3 - Acionar o Squad Creator (squad + DDD)
Spawnar o [Squad Creator](../../engine/agents/squad-creator.md) com o briefing do passo 1. Ele:
- mapeia o dominio -> os Specialists necessarios.
- monta o squad EM CAMADAS (gateway Camada A `brain: full`; Specialists de dominio Camada B com
  `expert_mind`; suporte Camada C `light`), conforme [squad-system.md](../../engine/squad-system.md).
- escreve o DDD no knowledge: glossario / linguagem ubiqua + bounded contexts (obrigatorio - o
  [Quality Gate](../../engine/governance/quality-gate.md) bloqueia cliente sem DDD documentado).
- preenche `squad/agents/` e `squad/knowledge/` que o helper deixou vazias, e escreve o `squad.yaml`.

### Passo 4 - Acionar o Loop Designer (loops)
Rodar o [Loop Designer](../loop-designer/SKILL.md) modo SUGERIR sobre o cliente recem-montado. Ele le
o perfil (client.md / state.json / squad.yaml) e propoe o `loops.yaml` aplicando R0-R6. Como o
cliente nasce `proposed` (status != active), a regra R0 vale: nenhum loop agendado entra ainda - so
o Plano de Loops fica proposto, junto do squad, aguardando a aprovacao.

### Passo 5 - PARAR para aprovacao do operador
Apresentar ao operador o pacote proposto: o squad em camadas, o DDD, e o Plano de Loops. O squad
nasce `status: proposed`. So o OK do CEO o promove a `active` (e so ai o Loop Designer modo CRIAR
grava os loops e liga os mecanismos). Nada vira active por automacao. Este e o gate humano.

### Passo 6 - Registrar e verificar
Apos a aprovacao, atualizar o `status` no `state.json` (proposed -> active) e rodar a verificacao:

```
scripts/smoke-test-studio.ps1
```

Tem que ficar ALL GREEN. O [Quality Gate](../../engine/governance/quality-gate.md) fecha a Task:
funciona, aderente ao DDD, frugal, rastreavel, sem aumentar atrito.

## Guardrails (explicitos)

- **Origem read-only.** A skill NUNCA escreve na origem (legado ou outra base). Le e traduz.
- **So escreve em studio/.** O destino e sempre `studio/clients/{id}/`. Nunca toca `engine/` nem o
  proprio legado.
- **Provenance.** O conteudo gerado em studio/ e `agent-authored`; a automacao propoe via diff e
  NUNCA deleta - quando algo deixa de valer, ARQUIVA (`_retired/` ou `status: retired`), conforme
  [provenance.md](../../engine/governance/provenance.md).
- **Nada vira active sem aprovacao.** O cliente nasce `proposed`; so o operador o promove a `active`.
- **O gate fecha.** Sem squad em camadas, sem DDD documentado, ou com smoke vermelho, a Task nao
  fecha.

## Invariante

Importar e TRADUZIR para a arquitetura atual reusando o que ja existe - nunca um pipeline paralelo.
Origem intacta, destino em studio/, squad em camadas com DDD, governanca proposta, aprovacao humana
antes de active, smoke verde no fim.
