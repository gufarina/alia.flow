# Alia Flow - Auditoria de Memoria (checklist de higiene)

> O checklist que audita a SAUDE da Memory contra as regras ja definidas em
> [memory-types.md](memory-types.md) (TTL por tipo) e [glossary.md](../glossary.md) (linguagem
> ubiqua) - sem motor novo. Memoria hoje existe, mas ninguem verificava se ela continua confiavel:
> nota vencida, nota que contradiz outra, nota duplicada, termo fora do glossario custam token e
> enganam o agente (Memory Before Reprocessing falha se a Memory mente). Consumido pelo loop
> agendado `memory-curator` ([loops.md](loops.md), [loops.catalog.yaml](loops.catalog.yaml)) e por
> qualquer handoff grande que precise confiar no segundo cerebro antes de reprocessar. Português correto, com acentos. Arquivo salvo em UTF-8 sem BOM; o único erro é caractere corrompido. Emoji continua fora de peça pública.

---

## O que e e por que existe

Higiene de memoria: uma nota stale, duas notas que se contradizem, a mesma informacao duplicada em
dois lugares, ou uma nota que usa termo fora da linguagem ubiqua - tudo isso e ruido que o agente
paga para ler e que pode ate leva-lo a decisao errada. O `memory-curator` ja arquiva por TTL
(memory-types.md); este checklist e o roteiro completo de auditoria que ele - ou a Alia, sob
demanda - roda para cobrir os outros sinais de degradacao que o TTL sozinho nao pega.

A auditoria NAO cria um sistema de memoria novo. Ela le o que ja existe (Preferencias, Decisoes,
Estado - memory-types.md) e aplica a mesma lei de sempre: **propor, nunca deletar**
([provenance.md](provenance.md)).

## Quando roda

- **Loop agendado `memory-curator`** (semanal, owner Alia - [loops.catalog.yaml](loops.catalog.yaml)):
  este checklist E o roteiro que a execucao segue. Sem checklist, o loop e uma promessa vazia
  (loops.md: "loop sem mecanismo e uma promessa vazia").
- **Antes de um handoff grande**: quando um Specialist ou a Alia vai delegar/reprocessar a partir
  do segundo cerebro de um Client e o volume de Memory cresceu desde a ultima auditoria, rodar o
  checklist evita propagar contradicao ou nota morta para a proxima Task.
- Execucao sem agendador (CORTE 10/08/2026): `scripts/smoke-test-studio.ps1` ja chama
  `memory-curator.ps1 -Validade` toda vez que a prova roda - nenhum runner, nenhum Task Scheduler.

## O checklist

Cada item e verificavel e tem uma acao definida se falhar. Nenhuma acao aqui e destrutiva - todas
terminam em proposta.

| # | Item | O que checar | Se falhar |
|---|------|---------------|-----------|
| 1 | **Expiracao** | A nota e do tipo Estado e carrega `expires:`? A data ja passou (memory-types.md)? | Propor arquivar em `_retired/` com `retired_reason` + `retired_on`. |
| 2 | **Contradicao** | Duas notas afirmam coisas opostas sobre o mesmo fato/decisao? | Sinalizar as duas para decisao humana - a auditoria NUNCA resolve sozinha qual vale. |
| 3 | **Duplicata** | A mesma informacao aparece em duas ou mais notas, sem uma citar a outra? | Propor consolidar numa nota so, com referencia cruzada nas demais. |
| 4 | **Drift de linguagem** | A nota usa um termo que nao existe em [glossary.md](../glossary.md)? | Apontar o termo usado e o termo correto do glossario; propor a correcao. |
| 5 | **Orfa / sem ligacao** | A nota nao e referenciada por nenhuma outra nota nem foi lida/usada em nenhum Loop ou Task recente? | Marcar como candidata a arquivar; decisao final e do operador. |
| 6 | **Procedencia** | Toda proposta dos itens 1-5 respeita [provenance.md](provenance.md): so toca `agent-authored`, sai como diff, nunca deleta? | Se a proposta tocaria `nucleo` ou aplicaria direto sem diff, a auditoria BLOQUEIA a propria proposta. |

### O que deixou de ser so checklist (OPP-76)

Este checklist era prosa sem script: nada o rodava. `scripts/memory-curator.ps1 -Validade` passou a
cobrir mecanicamente uma parte dele, sobre os DOIS cofres de notas do operador (que ate entao se
ignoravam), e o smoke da instancia o executa a cada prova:

| item | o que o `-Validade` cobre de verdade | veredito |
|---|---|---|
| 1 Expiracao | le `valido_ate` (novo) e `expires` (legado) e imprime o estado VENCIDO | sinal |
| 2 Contradicao | `[FATO-MORTO-VIVO]`: o cabecalho diz VIGENTE mas a tarja da nota declara supersessao - a contradicao entre o que a nota AFIRMA e o que ela DECLARA | **REPROVA** |
| 3 Duplicata | `[ASSUNTO-DUPLO]`: duas notas VIGENTES com assunto sobreposto e sem ligacao, marcando `[CRUZA COFRE]` | sinal |
| 5 Orfa / sem ligacao | `[LINK-QUEBRADO]` + `[CITA-VENCIDO]`: os `[[wikilinks]]` finalmente sao lidos e resolvidos | sinal |

Continua valendo a regra dura do item 2: **a auditoria NUNCA resolve sozinha qual nota vale.** O
`[ASSUNTO-DUPLO]` compara NOME DE ARQUIVO, nao significado - ele acha o par, quem decide e gente.
Detectar contradicao semantica de verdade exigiria uma chamada de LLM por par de notas (105 notas =
5.460 pares), o que contraria a frugalidade da casa e nao foi feito. Os itens 4 (drift de linguagem)
e 6 (procedencia) seguem sem script proprio.

## Saida da auditoria

Um relatorio de propostas - nunca uma acao automatica: `arquivar` (item 1 e 5), `consolidar`
(item 3), `sinalizar` (item 2 e 4). O relatorio segue o mesmo formato de diff proposto que o
`memory-curator` ja usa (memory-types.md: "ARQUIVA em `_retired/`... NUNCA deleta"). A decisao
final - aceitar, ajustar ou rejeitar cada proposta - e sempre do coordenador (Squad Owner) ou do
CEO, nunca da automacao.

## Liga com

[Tipos de Memoria e TTL](memory-types.md) (o que a auditoria checa no item 1) -
[Provenance](provenance.md) (a lei que toda proposta obedece, item 6) -
[Glossario](../glossary.md) (a linguagem ubiqua do item 4) -
[Governanca / Loops](loops.md) e [loops.catalog.yaml](loops.catalog.yaml) (o `memory-curator` que
consome este checklist).

---

*Alia - Delegue. Nao opere.*
