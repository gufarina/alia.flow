# Alia Flow - Versionamento e Fluxo de Update

> Como o motor (engine) evolui sem quebrar quem o usa. O Alia Flow e um produto open source
> distribuivel: cada mudanca precisa ser modular, rastreavel e reversivel. Este documento e a
> lei do update. O CHANGELOG na raiz e o registro; o VERSION na raiz e o numero vigente.
> Sem acentos, sem emojis.

---

## Por que isto existe

Um produto distribuido nao pode mudar no susto. Quem instalou a v0.1 precisa saber o que muda na
v0.1.1, se quebra algo, e como reverter. Sem versionamento, cada update e um risco cego - o oposto
da Frugality Without Quality Loss (Principio VIII) e do Evidence or It Did Not Happen (Principio V).

## Esquema de versao (semantico, adaptado)

`MAJOR.MINOR.PATCH`

| Nivel | Quando sobe | Exemplos | Exige |
|-------|-------------|----------|-------|
| PATCH (0.1.x) | correcao de doc, adicao modular pequena, scaffolding | corrigir glossario, novo script de loop | smoke ALL GREEN |
| MINOR (0.x.0) | nova feature/cluster, retrocompativel | loop de aprendizado, nova capability | smoke + teste no Studio |
| MAJOR (x.0.0) | quebra de contrato | mudar a constituicao, o glossario base, o schema de loops/squads | migracao documentada |

Contrato = o que outros arquivos e o estado dependem: constitution.md/.yaml, glossary.md, os
schemas (loops.catalog.yaml, quality-gate.yaml) e os nomes do protocolo.
Mexer neles e MAJOR por padrao.

## A regra da modularidade (inegociavel)

Cada oportunidade/mudanca vira UM incremento de versao auto-contido. Um update e:

- **Isolavel** - toca o minimo necessario; nao mistura duas OPPs no mesmo bump.
- **Reversivel** - da pra desfazer so aquele incremento (um commit/tag por versao).
- **Testado na instancia viva** - validado na instancia aplicada (smoke verde) antes de fechar.

Update que toca dez coisas ao mesmo tempo nao e update, e refatoracao disfarcada - e o Quality
Gate reprova.

## O fluxo de update (6 passos)

```
1. VERIFICAR   - medir o gap da mudanca vs o engine real (parecer com evidencia path:linha)
2. APROVAR     - o operador le o parecer + o diff proposto e da go/no-go
3. IMPLEMENTAR - aplicar a mudanca modular (sempre via diff; nunca escrever direto no nucleo sem ok)
4. TESTAR      - rodar scripts/smoke-test-studio.ps1 (ALL GREEN obrigatorio) na instancia viva
5. VERSIONAR   - bump do VERSION + entrada no CHANGELOG (Added/Changed/Fixed/Removed) + git tag
6. APRENDER    - o RSI registra o que mudou; a proxima mudanca entra
```

## Fronteira de mutabilidade no update

O versionamento respeita a fronteira da constituicao:

- **Nucleo (estavel)** - constitution, glossario base, schemas de contrato. Mudanca aqui e MAJOR e
  exige aprovacao explicita do operador. Nunca por automacao.
- **Engine mutavel** - features, workflows, agents, governanca. Mudanca aqui e MINOR/PATCH conforme
  o impacto, sempre proposta como diff.
- **Studio (dados do operador)** - nao entra no versionamento do produto. Privado. Em distribuicao
  publica, vira `studio.example/` com placeholders; `studio/.secrets/` nunca e versionado.

## Distribuicao open source

O produto distribuido = o engine + scripts + skills + a constituicao. Os dados do operador
(`studio/`) ficam de fora do pacote publico. O CHANGELOG e a face publica da evolucao: quem adota o
Alia Flow le o CHANGELOG para decidir quando atualizar e o que esperar.

## Liga com

[Constituicao](constitution.md) (a fronteira de mutabilidade) - 
[Quality Gate](governance/quality-gate.md) (o teste do passo 4) - 
[RSI](rsi/rsi.md) (o aprendizado do passo 6) - 
CHANGELOG.md e VERSION na raiz (o registro e o numero vigente).

---

*Alia - Delegue. Nao opere.*
