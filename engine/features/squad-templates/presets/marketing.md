# Squad Preset - Marketing

> Molde para um cliente/time de marketing (trafego, conteudo, growth). O Squad Creator parte
> daqui e ajusta pela atuacao descrita. Segundo cerebro EM CAMADAS: lider sempre full;
> especialista de dominio expert (com Expert Mind); suporte light.

---

## Schema

```
preset: marketing
dominio: marketing (trafego pago, conteudo, growth, dados)
gateway: Marketing Lead (Camada A - segundo cerebro COMPLETO)
papeis:
  - papel: Marketing Lead (gateway)
    camada: A
    expert_mind:
    brain: full
  - papel: Especialista de Trafego / Paid
    camada: B
    expert_mind: ads/eugene-schwartz
    brain: expert
  - papel: Copywriter / Conteudo
    camada: B
    expert_mind: copy/ogilvy
    brain: expert
  - papel: Designer
    camada: B
    expert_mind: design/brad-frost
    brain: expert
  - papel: Analista de Dados
    camada: C
    expert_mind:
    brain: light
knowledge_skeleton:
  - client-brief
  - brand-voice
  - marketing-frameworks
  - audience-personas
  - campaign-history
ajustes_tipicos: >
  Foco em aquisicao -> reforcar o Especialista de Trafego/Paid (growth/sean-ellis para
  priorizar experimentos) e subir o Analista de Dados para Camada B com analytics/avinash-kaushik
  (julgamento de atribuicao/funil). Foco em conteudo organico/SEO -> reforcar o Copywriter.
  Operacao enxuta -> manter so gateway + Trafego + Copywriter.
```

## Expert Minds usados

- Especialista de Trafego / Paid -> [Eugene Schwartz](../../expert-minds/ads/eugene-schwartz.md)
- Copywriter / Conteudo -> [Ogilvy](../../expert-minds/copy/ogilvy.md)
- Designer -> [Brad Frost](../../expert-minds/design/brad-frost.md)
- Analista de Dados (quando sobe a Camada B) -> [Avinash Kaushik](../../expert-minds/analytics/avinash-kaushik.md)
- Especialista de Trafego em modo growth -> [Sean Ellis](../../expert-minds/growth/sean-ellis.md)

## Liga com

[Squad Creator](../../../agents/squad-creator.md) - [Biblioteca de Squads](../README.md)
