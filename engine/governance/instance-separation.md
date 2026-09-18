# Alia Flow - Instance Separation (a LEI dos dois contextos)

> A convencao canonica que separa o PRODUTO (Alia, open source, CLEAN) da INSTANCIA APLICADA
> (privada, do operador). E a fronteira de bounded context que impede os dois mundos de voltarem a
> se misturar. Termos em [glossary.md](../glossary.md).

---

## A tese

O Alia e um produto open source. A instancia aplicada e a instalacao privada do operador. Sao dois
bounded contexts distintos, com regras de mutabilidade e visibilidade diferentes. Quando o codigo do
produto carrega dado do operador, ou quando a operacao do operador vaza para o que viaja open source,
a fronteira quebra e o smoke falha. Esta LEI materializa a fronteira em regras duras e
machine-checkable.

A fronteira espelha a mesma logica de [provenance.md](provenance.md) (nucleo vs agent-authored) e da
[constitution.md](../constitution.md): o que viaja para todo mundo nao pode conter o que e so do
operador.

## Os dois contextos

### 1. Alia (produto) - Contexto Produto (CLEAN)

O produto open source. Tudo que viaja para qualquer operador. Vive na raiz e nas pastas
convencionais:

- `engine/` - o motor (orquestracao, governanca, memoria, RSI).
- `scripts/` - automacao deterministica (frugal skills, smokes, loops).
- `skills/` - capacidades por script.
- `onboarding/` - a porta de entrada do novo operador.
- `optional-mcps/` - integracoes opcionais.
- `studio.example/` - a Studio-modelo LIMPA de referencia (so o demo `acme-saas`).
- Arquivos convencionais de raiz: `README.md`, `AGENTS.md`, `CHANGELOG.md`, `VERSION`,
  `alia.config.json`, mais `docs/` para documentacao do produto.

Regra dura: o Contexto Produto NUNCA contem dado do operador, cliente real, nem material de marca/
go-to-market de ninguem. `studio.example` e a Studio-modelo que viaja: so o demo, jamais um cliente
real.

### 2. Instancia aplicada - Contexto Operador

A instalacao privada do produto, na pasta de dados do operador (definida em `alia.config.json` pelo
campo `studio_dir`). E a operacao real do operador. Dentro dela vivem os clientes reais do operador,
seus squads, seu estado e sua memoria - tudo com nomes e dados que so dizem respeito a ele.

Um operador pode, opcionalmente, manter um cliente dedicado so a manutencao do proprio produto
(dogfooding de engenharia) e outro dedicado a marca/go-to-market do estudio dele. Esses sao arranjos
da casa do operador - nunca fazem parte do produto que viaja.

Regra dura: o Contexto Operador e privado. Nunca sobe para o open source. Marca e go-to-market do
operador moram na instancia aplicada dele, jamais no produto.

## As regras duras (a LEI)

Orientacao geral (poda 09/08/2026, law-ledger L22: rebaixada de item numerado da LEI pra aqui - o
guarda-chuva "produto so produto" nao tem check proprio, mas os 3 vetores concretos abaixo, que sao
onde a violacao de fato acontece, continuam com machine-checkable de verdade): o Contexto Produto
cobre o motor e nada de operador - nenhuma pasta de marketing/comercial e nenhum cliente real dentro
do que viaja. As 3 leis abaixo sao os vetores testados dessa orientacao.

1. **Raiz so convencional.** A raiz do repositorio contem apenas arquivos convencionais. Nenhum
   `.md` solto fora de `{README.md, AGENTS.md, CHANGELOG.md}`. Documentacao do produto vive em
   `docs/`. Pastas sao livres.
2. **studio.example limpa.** `studio.example/clients/` contem SO o demo `acme-saas`. Qualquer outro
   id de cliente ali e violacao (e dado de operador vazando para o produto).
3. **Marca/go-to-market fora do produto.** Material de marca, design e go-to-market e do operador
   (ou do dono do produto, em sua instancia privada). Nunca na raiz do produto, nunca em `docs/` que
   viaja, nunca em `studio.example`.

## Os guardrails que fazem a LEI cumprir (machine-checkable)

A LEI nao vive so na prosa - cada regra vira um check no smoke (`scripts/smoke-test.ps1` para o gate
do produto, `scripts/smoke-test-studio.ps1` para o gate da instancia aplicada):

| Guardrail | Onde | O que barra |
|-----------|------|-------------|
| Raiz limpa | smoke-test.ps1 | `.md` solto na raiz fora de `{README.md, AGENTS.md, CHANGELOG.md}`. |
| studio.example limpa | smoke-test.ps1 | qualquer cliente fora do demo `acme-saas` dentro de `studio.example`. |
| produto CLEAN | smoke-test-studio.ps1 | pasta `marketing`/`comercial` dentro do cliente de manutencao do produto. |

Os checks somam-se aos existentes - nenhum afrouxa qualidade. Um guardrail vermelho significa que a
fronteira foi violada e a entrega esta bloqueada.

## Liga com

[Constituicao](../constitution.md) (a lei base e a fronteira motor/dados) -
[Glossary](../glossary.md) (os termos dos dois contextos) -
[Versionamento](../versioning.md) (o produto versiona; a instancia aplicada nao entra no semver
publico) -
[Provenance](provenance.md) (nucleo vs agent-authored, a mesma logica de fronteira no metadado).

---

*Alia - Delegue. Nao opere.*
