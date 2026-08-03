# Contribuir com o Alia Flow

Obrigado pelo interesse. O Alia Flow e um arnes de operador que roda dentro do seu coding
agent - a maior parte do motor e linguagem natural (`.md`/`.yaml`), com scripts de apoio em
PowerShell. Contribuir aqui e diferente de um projeto so-codigo: voce edita doutrina e contratos,
e a prova de qualidade e um smoke test deterministico.

## O contrato de qualidade (a regra dura)

Nada entra sem o trilho verde. Antes de abrir um PR:

```sh
powershell -ExecutionPolicy Bypass -File scripts/smoke-test.ps1
#   -> todos [PASS], "ALL GREEN", exit 0
```

Se o smoke fica vermelho, o PR nao avanca - o mesmo trilho roda na sua maquina e no CI.

## Como uma mudanca entra (o ciclo do motor)

O Alia Flow evolui em incrementos pequenos e reversiveis. Cada mudanca segue:

1. **Edite o motor** (`engine/`) ou os scripts. Uma mudanca = um incremento isolavel.
2. **Suba a VERSION** (semver): PATCH (correcao de doc, adicao pequena) / MINOR (feature nova
   retrocompativel) / MAJOR (quebra de contrato - constituicao, glossario, schema).
3. **Escreva no CHANGELOG.md** (topo, com o que mudou e por que).
4. **Rode o smoke** ate ALL GREEN. O trilho exige que a VERSION bata com o topo do CHANGELOG.
5. **Abra o PR** contra `main`.

## Camadas do framework (o que voce pode tocar)

O motor tem uma fronteira de mutabilidade. Respeite-a:

| Camada | Regra | Onde |
|--------|-------|------|
| Nucleo | evite mudar sem discussao | `engine/constitution.*`, `engine/glossary.md`, `engine/orchestration.md` |
| Features / governanca | mutavel via PR + smoke | `engine/features/`, `engine/governance/`, `engine/workflows/` |
| Scripts | mutavel via PR + smoke | `scripts/` |
| Dados do operador | NUNCA no repo publico | `studio/`, `state.json` (o publico ve so `studio.example/`) |

## Estilo

- **Sem acentos, sem emojis** nos arquivos do produto (motor, scripts, docs de produto). O smoke
  checa encoding. A LP de marketing e a excecao (portugues completo).
- **Linguagem ubiqua:** use os termos de `engine/glossary.md`. Inventar sinonimo confunde o
  agente e reprova no gate. Termo novo entra no glossario primeiro.
- **Commits:** descreva a mudanca e o porque, nao so o "o que".

## Reportar bug ou pedir feature

Use os templates em `.github/ISSUE_TEMPLATE/`. Para bug, inclua o sistema operacional, o coding
agent usado e a saida do smoke test. Para feature, descreva a dor do operador antes da solucao.

## Licenca

Ao contribuir, voce concorda que sua contribuicao e licenciada sob a [MIT](LICENSE), a mesma do
projeto.
