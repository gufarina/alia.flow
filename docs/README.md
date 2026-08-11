# Documentacao - Alia Flow (indice mestre)

> Porta de entrada do produto. Este e o Alia Flow: o motor (clean) + uma instancia de exemplo
> para testar. Comece por aqui antes de navegar a estrutura.

## O que e o Alia Flow

Um estudio operado por IA. A Alia orquestra: identifica o Client, registra a Task, delega ao
Specialist certo do Squad do Client, monitora e fecha com o Quality Gate. A Alia delega, nao opera.

## Estrutura (por tema, sem arquivo solto)

```
alia-flow/
|- alia.config.json   # nome do Studio + caminhos (studio_dir aponta a pasta de dados)
|- AGENTS.md          # boot loader (a Alia operando o Alia Flow)
|- README.md          # visao geral da raiz
|- engine/            # o motor Alia Flow (a lei; nunca tem dado de Client)
|- skills/            # skills do produto (file-organization, loop-designer...)
|- scripts/           # provas deterministicas (smoke-test, loops)
|- studio.example/    # instancia de exemplo (Client acme-saas) - a unica que e publicada
\- docs/              # esta documentacao
```

A pasta de **dados do operador** (Clients, Squads, estado) e definida em `alia.config.json` pelo
campo `studio_dir`. Numa instalacao ela e privada e nunca vai pro repo publico - so o
`studio.example/` e publicado, como demonstracao.

## Engine (a base Alia Flow)

`engine/` e o produto Alia Flow limpo - a lei do Studio. Nunca contem dado de Client.
Carregue, nesta ordem, antes de operar:

| Arquivo | Papel |
|---------|-------|
| `engine/agents/persona.md` | A voz e o jeito da Alia |
| `engine/constitution.md` | A lei (principios). O Quality Gate bloqueia o que viola |
| `engine/glossary.md` | A linguagem ubiqua (os unicos termos aceitos) |
| `engine/orchestration.md` | O protocolo de 5 passos (IDENTIFICA, REGISTRA, DELEGA, MONITORA, FECHA) |
| `engine/squad-system.md` | Como os Squads e o segundo cerebro funcionam |
| `engine/governance/` | Quality Gate e governanca por Loops |
| `engine/features/` | Recursos do motor (loop-designer, expert-minds...) |

Detalhe completo da biblioteca do motor (o que existe e quando consultar): `engine/MAP.md`.

## A instancia de exemplo

`studio.example/` tem o Client **acme-saas (Acme Pulse)**: squad em camadas, segundo cerebro
(`squad/knowledge/`), grafo do graphify, artefatos com gates, memoria e loops. Use para testar o
fluxo de ponta a ponta sem montar um cliente do zero. O Gateway e o Squad Owner (Tier 1 da
governanca); os Specialists carregam o segundo cerebro antes de executar.

## Skills

| Skill | Para que serve |
|-------|----------------|
| [file-organization](../skills/file-organization/SKILL.md) | Senso de design organizacional - casa arrumada = escalabilidade |
| [loop-designer](../skills/loop-designer/) | Desenhar os Loops de governanca de cada Project |

## Scripts (provas deterministicas, rodam sem agente)

| Script | O que faz |
|--------|-----------|
| `scripts/smoke-test.ps1` | Valida o motor (via studio.example) |
| `scripts/smoke-test-studio.ps1` | Valida uma instancia real (clientes do state.json); tambem chama `memory-curator.ps1 -Validade` a cada execucao (o unico loop agendado, sem Task Scheduler) |

## Estado e fonte de verdade

- o `state.json` do studio em uso - **fonte canonica**: Clients, Squads, Tasks. Toda decisao de
  status le daqui.
- o `studio.yaml` do studio em uso - manifesto do Studio (nome, operador, proposito).
