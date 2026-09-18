# Squad Preset - Cliente SaaS

> Molde para um Client de produto SaaS (web app). O Squad Creator parte daqui e ajusta pela atuacao
> descrita. Segundo cerebro EM CAMADAS: lider sempre full; Specialist de dominio expert (com Expert
> Mind); suporte light.

---

## Schema

```
preset: saas
dominio: produto SaaS (web app, plataforma)
gateway: Product Lead (Camada A - segundo cerebro COMPLETO)
papeis:
  - papel: Product Lead (gateway)
    camada: A
    expert_mind:
    brain: full
  - papel: Design Lead
    camada: B
    expert_mind: design/brad-frost
    brain: expert
  - papel: Frontend Dev
    camada: B
    expert_mind: dev/kent-beck
    brain: expert
  - papel: Backend Dev
    camada: B
    expert_mind: dev/kent-beck
    brain: expert
  - papel: Copywriter
    camada: B
    expert_mind: copy/ogilvy
    brain: expert
  - papel: QA
    camada: C
    expert_mind:
    brain: light
  - papel: DevOps
    camada: C
    expert_mind:
    brain: light
knowledge_skeleton:
  - client-brief
  - product-vision
  - design-system-guide
  - data-architecture
ajustes_tipicos: >
  Foco em aquisicao -> trocar o Copywriter por um Specialist de growth (growth/sean-ellis) e
  subir um Analista de Dados para Camada B (analytics/avinash-kaushik). Produto data-intensive ->
  adicionar Data Engineer dedicado em Camada B. Operacao enxuta -> manter so Product Lead +
  Frontend + Backend, com QA e DevOps em Camada C.
```

## Expert Minds usados

- Design Lead -> [Brad Frost](../expert-minds/design/brad-frost.md)
- Frontend Dev e Backend Dev -> [Kent Beck](../expert-minds/dev/kent-beck.md)
- Copywriter -> [Ogilvy](../expert-minds/copy/ogilvy.md)

## Liga com

[Squad Creator](../../agents/squad-creator.md) - [Biblioteca de Squads](README.md)
