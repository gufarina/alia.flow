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

## A janela de validade (o tempo do EVENTO, nao o da faxina) - OPP-76

> LEI: fato de memoria nunca se apaga - se marca. Nota que declara no corpo que um fato morreu
> ("DERRUBADO", "SUPERSEDED", "NAO VALE MAIS") e cujo cabecalho continua de janela ABERTA e um
> fato morto se passando por vigente: isso reprova a prova da instancia.

O `expires:` acima responde "quando NOS decidimos jogar fora". Ele nao responde a pergunta que
custou caro nesta casa: **quando o fato deixou de ser verdade NO MUNDO?** O caso real: em 01/jul o
CEO cravou uma identidade de produto, em 02/jul a reverteu, e em 07/jul a Alia ainda se apresentava
com a identidade morta - porque a nota nao tinha onde dizer que a janela dela tinha fechado. A casa
consertou do jeito mais caro possivel (um veto escrito a mao + um teste novo). **Isso nao escala:
cada fato que morre nao pode exigir uma linha de veto e um guard novo.**

Quatro campos OPCIONAIS no cabecalho da nota resolvem na origem. Todos legiveis por regex de uma
linha; nenhum motor novo, nenhum banco, nenhum servidor:

| Campo | Formato | O que significa |
|---|---|---|
| `valido_de` | `YYYY-MM-DD` | quando o fato passou a valer no mundo. Ausente = desconhecido. |
| `valido_ate` | `YYYY-MM-DD` | quando deixou de valer. **Ausente = janela ABERTA (o fato vive).** |
| `substituido_por` | slug da sucessora | quem tomou o lugar. Sozinho, ja marca a nota como SUPERSEDIDA. |
| `substitui` | slug + janela do fato morto | o inverso: declara que ESTA nota e a sucessora. |
| `fonte` | texto livre | quem decidiu, quando e onde (ex: `CEO 02/07/2026 - CLAIMS.md secao VETOS`). |
| `validade: registro` | literal | escape honesto: a nota REGISTRA a morte de um fato de terceiro, nao esta morta. |

O ESTADO nunca e escrito a mao - e derivado, com esta precedencia:

- **SUPERSEDIDO** - tem `substituido_por` (ou o legado `superseded_by` / `status: superseded`).
- **VENCIDO** - `valido_ate` no passado (ou o legado `expires` no passado em nota nao-critica).
- **VIGENTE** - qualquer outro caso, **inclusive nota sem nenhum desses campos**.

**Migracao suave, regra dura:** nota antiga sem nenhum campo continua VIGENTE de janela aberta -
nenhuma nota precisa ser tocada para o formato entrar em vigor. `valido_ate` nao substitui
`expires:`: ele o GENERALIZA (o `expires` e o caso particular "Estado com prazo"; a janela vale para
qualquer tipo e carrega o tempo do evento). Onde os dois existirem, `valido_ate` manda.

**Regra de leitura:** quem consulta a memoria enxerga por padrao so o VIGENTE. O vencido e o
supersedido ficam no disco, auditaveis - respondem "o que valia em fevereiro" e explicam a mudanca.

Quem confere: `scripts/memory-curator.ps1 -Validade` (somente leitura; a unica escrita possivel e a
migracao cirurgica de UMA nota via `-Fechar <slug> -Aplicar`, com backup datado antes). Ele le os
DOIS cofres de notas do operador, que ate entao se ignoravam. So `[FATO-MORTO-VIVO]` reprova; os
outros achados (`[CITA-VENCIDO]`, `[ASSUNTO-DUPLO]`, `[LINK-QUEBRADO]`) sao SINAL, porque medem
divida acumulada e heuristica de nome de arquivo - reprovar por debito velho nao pega regressao
nova. Doutrina completa e o relatorio de migracao:
`research/graph-engineering/spec-memoria-com-validade.md`.

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
