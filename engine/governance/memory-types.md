# Alia Flow - Tipos de Memoria e TTL (a convencao de memoria do produto)

> A convencao canonica que diz, para cada nota de Memory, QUE tipo ela e e SE/QUANDO expira.
> A Memory ja e definida no glossario (grafo + notas navegaveis, [glossary.md](../glossary.md)) e o
> segundo cerebro ja e estruturado em camadas ([squad-system.md](../squad-system.md)). O que faltava
> era uma tipagem explicita com TTL: distinguir o que e duravel do que e volatil, para o curador
> arquivar so o que envelheceu de fato. Sem motor novo - o campo e lido pelo curador semanal
> ([loops.md](loops.md): memory-curator) e respeita a provenance ([provenance.md](provenance.md):
> arquiva, nunca deleta). Sem acentos, sem emojis.

---

## A tese

Nem toda memoria tem o mesmo prazo de validade. Uma decisao de arquitetura vale ate ser revogada;
um estado de sprint vale uma semana. Tratar as duas igual gera dois erros: ou o curador arquiva uma
decisao ainda viva (perda), ou deixa estado volatil acumular como ruido (debito). A tipagem resolve
isso na origem: cada nota declara seu tipo, e o tipo decide o comportamento de expiracao.

A regra de ouro: **memoria critica nao expira por inercia; memoria volatil tem prazo.** Decisoes e
Preferencias so saem por decisao do operador (revogacao explicita). Estado pode carregar um
`expires:` e o curador propoe arquivar quando a data passa.

## Os tres tipos

| Tipo | Natureza | Expira? | O que e |
|------|----------|---------|---------|
| **Preferencias** | duravel | NAO por padrao | Como o Client/operador quer as coisas: tom, formato, padroes a reusar, restricoes fixas. |
| **Decisoes** | duravel | NAO por padrao | O que foi decidido e por que: escolhas de arquitetura, vereditos de Gate, acordos. Liga Artifact a razao. |
| **Estado** | volatil | SIM (via `expires:`) | Contexto de momento: status de sprint, foco da semana, notas de sessao, hipoteses em teste. |

Preferencias e Decisoes sao **memoria critica**: sao o que o segundo cerebro deposita do RSI e o que
evita reprocessar (Memory Before Reprocessing, Principio VII). Estado e **memoria de trabalho**: util
agora, ruido depois.

## Mapa para os tipos ja usados

O segundo cerebro ja carrega tipos de conteudo (user / feedback / project / reference). A tipagem
nova nao os substitui - os agrupa por durabilidade:

| Tipo de conteudo ja usado | Tipo de memoria | Expira? |
|---------------------------|-----------------|---------|
| `reference` (frameworks, padroes, exemplos padrao-ouro) | Preferencias | NAO |
| `user` (como o operador/Client quer; restricoes) | Preferencias | NAO |
| `feedback` (vereditos de Gate, licoes, decisoes) | Decisoes | NAO |
| `project` (status, foco, contexto de sprint/sessao) | Estado | SIM (se marcado) |

Regra de fronteira: na duvida entre duravel e volatil, **duravel vence** - melhor manter uma nota a
mais do que perder uma decisao viva. Estado e a excecao que se declara, nao o padrao silencioso.

## O campo `expires:`

Campo **opcional**, valido **somente em memoria do tipo Estado**. Sem motor: o curador le, compara
com a data de hoje e PROPOE arquivamento - nunca um runtime que apaga.

- Formato: data ISO `expires: YYYY-MM-DD`. Mesmo padrao datado ja provado em `review_on` dos loops.
- Onde vive: no cabecalho/metadado da nota de Memory (uma linha `expires: 2026-01-31`), legivel por
  regex simples - sem exigir frontmatter rigido.
- Semantica: `expires` no passado = a nota venceu; o curador propoe arquivar (em `_retired/`, com
  motivo+data). `expires` no futuro ou ausente = a nota fica.

Memoria critica (Decisoes / Preferencias) **nao deve** carregar `expires:`. Se carregar, e erro de
tipagem - o curador ignora o `expires` em nota critica e so age sobre Estado. Decisoes e Preferencias
saem do recall ativo apenas por revogacao explicita do operador (rebaixar para `status: retired` ou
mover para `_retired/`, como manda a provenance), nunca por prazo.

## Como o curador consome (TTL)

O curador semanal (`scripts/memory-curator.ps1`, loop `memory-curator` em
[loops.catalog.yaml](loops.catalog.yaml)) ja arquiva por data de inatividade (stale). A tipagem
adiciona um segundo sinal, mais preciso: **expirou por declaracao** (`expires:` no passado), que vale
para Estado mesmo que o arquivo tenha sido tocado recentemente.

- O curador so age sobre **agent-authored** (nunca nucleo, nunca `engine/`) - regra da provenance.
- Em `-DryRun`: so LISTA o que expirou; nada e movido.
- Sem `-DryRun`: ARQUIVA em `_retired/` com `retired_reason`+`retired_on`; NUNCA deleta.
- `expires` so dispara arquivamento se a data ja passou; nota critica e ignorada para TTL.

Stale-por-data e expirou-por-declaracao sao complementares: stale pega o que ninguem mais toca;
`expires` pega o Estado que tem prazo conhecido. Os dois levam ao mesmo destino seguro (`_retired/`).

## Exemplo (Estado com TTL)

```
# MEM-014 - Foco da sprint 2026-Q1

type: Estado
expires: 2026-01-31

> Memory de trabalho do Client. Volatil: vence no fim da sprint. Sem acentos, sem emojis.

- Foco: estabilizar o fluxo de checkout antes do lancamento.
- Hipotese em teste: cache de sessao reduz reprocessamento.
```

Uma Decisao, ao contrario, nao leva `expires:` - vence so quando o operador a revoga:

```
# MEM-001 - Decisoes do Squad

type: Decisoes

- ART-001: a landing usa Headline forte e uma unica Chamada de acao. Verdict do Gate: PASS.
```

## Liga com

[Glossario](../glossary.md) (define Memory) -
[Sistema de Squads](../squad-system.md) (o segundo cerebro em camadas) -
[Governanca / Loops](loops.md) (o memory-curator que le o `expires:`) -
[Provenance](provenance.md) (so toca agent-authored; arquiva em `_retired/`, nunca deleta).

---

*Alia - Delegue. Nao opere.*
