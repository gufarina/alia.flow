# Squad Templates

> Moldes de squad por tipo de cliente, de onde o Squad Creator parte. Onboarding rapido, sem montar
> do zero. Versao proprietaria do "Premium Squads" do legado (conceito livre, moldes nossos).

---

## O que e

Um molde pronto que descreve os especialistas tipicos de um tipo de cliente (SaaS, branding, casino,
edtech...), cada um ja com o Expert Mind sugerido e o gateway definido. O Squad Creator parte do
molde e ajusta ao cliente, em vez de inventar a estrutura toda na hora.

## Anatomia

```
engine/features/squad-templates/{tipo}.md
```

Cada template define: lista de especialistas, dominio de cada um, Expert Mind sugerido, e quem e o
gateway (Squad Owner / Tier 1).

## Como funciona (com o Squad Creator)

1. Cliente novo de um tipo conhecido -> Squad Creator escolhe o template.
2. Instancia os especialistas do molde, ja com Expert Minds carregados.
3. Ajusta ao cliente: nome, knowledge especifico, particularidades.
4. Cliente sem tipo conhecido -> monta do zero (sem template). O template e atalho, nao prisao.

## Diferenca frente ao legado

- Legado: "Premium Squads" - produto fechado, pago.
- Alia Flow: moldes abertos, nossos, versionados no engine. Acelera sem travar.

## Ver tambem

[Squad Creator](../agents/squad-creator.md) - quem usa os templates.
[Expert Minds](expert-minds.md) - as mentes que cada especialista do template carrega.
