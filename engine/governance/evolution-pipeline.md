# Alia Flow - Pipeline de Evolucao (findings -> proposals -> decisao)

> Como uma ideia ou um achado sobre o proprio framework vira mudanca real no motor. Formaliza o
> caminho que ja usamos (opportunities/, loops, provenance) sem criar sistema paralelo: FINDING
> registrado -> vira PROPOSAL (um OPP-NN, mesmo formato de sempre) -> o CEO decide. Aprovado, segue
> o pipeline de versao normal e ainda passa pelo Quality Gate. LEVE - achado trivial nao precisa de
> OPP. Sem acentos, sem emojis. UTF-8 sem BOM.

---

## As 3 fases

### 1. FINDING (o achado)

Um FINDING e qualquer sinal de que o framework poderia evoluir: saida de um Loop (`debt-scan`,
`evolution-scan`, `deep-research`), um padrao que o [RSI](../rsi/rsi.md) detectou na Memory, uma
auditoria, uma dor observada em producao, ou uma ideia direta do CEO. Todo FINDING carrega origem
e evidencia - sem isso nao e FINDING, e palpite.

- Origem tipica: `rsi.md` estagio 2 (DETECTA), os loops agendados (`loops.md`), ou observacao
  direta registrada na Memory.
- Nao existe arquivo/fila nova para FINDING. Ele mora onde ja mora hoje: a nota de Memory que o
  gerou, ou o item de `rsi-backlog` que a skill `rsi-friction` grava.

### 2. PROPOSAL (a proposta estruturada)

Um FINDING com risco ou escopo relevante vira um `opportunities/OPP-NN-titulo.md` - o MESMO
formato que ja usamos (veja os OPP-NN existentes em `opportunities/` como exemplo de forma).
Nao ha template novo. Um OPP bom carrega:

- Problema medido (a evidencia do FINDING).
- Opcoes consideradas (quando existirem).
- AS/NB esperado (arquitetura de solucao / negocio) - a mesma regua que o OPP-22 ja usa.
- Risco e esforco (P/M/G).
- Veredito proposto: VIAVEL JA / VIAVEL COM HOOK / VIAVEL FUTURO / JA COBERTO / NAO VALE.

Quem escreve o OPP e a Alia (ou quem detectou o FINDING) - ela PROPOE, nunca decide sozinha.

### 3. DECISAO (o aprovador unico)

O CEO e o UNICO aprovador de mudanca de framework. Le o OPP, decide: aprova, adia ou rejeita.
Sem essa decisao explicita, o OPP fica em backlog - nenhuma mudanca de motor comeca sem ela.

Aprovado, o OPP vira um incremento normal pelo pipeline de versao (`versioning.md`): editar -> bump
-> CHANGELOG -> smoke -> propagar. O incremento, ja como codigo/doc, ainda passa pelo
[Quality Gate](quality-gate.md) como qualquer Artifact - a aprovacao do CEO libera o trabalho, nao
substitui o Gate.

```
FINDING (origem + evidencia)
   |
   v  risco/escopo relevante?
PROPOSAL (OPP-NN: problema, opcoes, AS/NB, risco)
   |
   v
DECISAO (CEO: aprova / adia / rejeita)
   |
   v  aprovado
incremento (versioning.md) -> Quality Gate -> CHANGELOG
```

## Quem pode o que (ancorado em provenance)

A regra espelha [provenance.md](provenance.md) 1:1 - nao inventa fronteira nova:

- A Alia (e qualquer automacao) PROPOE. Nunca auto-aprova mudanca de framework - o mesmo guardrail
  5 do RSI ("Aprovacao humana em mudanca de Gate") vale aqui para qualquer mudanca de `nucleo`.
- `provenance: nucleo` (engine/, constitution, schemas) exige DECISAO explicita do CEO antes de
  qualquer diff. `provenance: agent-authored` pode ser proposto e ajustado com mais liberdade, mas
  mudanca de framework - por definicao - tende a tocar `nucleo`.
- O CEO e o unico que aprova. Isso e o Artigo da Constituicao sobre fronteira Engine/Studio virando
  mecanismo neste pipeline.

## Como um Loop de RSI alimenta FINDINGS automaticamente

O [RSI](../rsi/rsi.md) ja gera FINDINGS sem intervencao manual: quando o estagio DETECTA acha um
padrao (nao incidente isolado) na Memory alimentada pelos [Loops](loops.md) - `debt-scan`,
`evolution-scan`, `ddd-drift-scan`, `deep-research` - ele chama `proposeImprovement`. Esse e
exatamente o ponto onde o FINDING nasce. Se o alvo e `nucleo` ou o escopo e maior que um ajuste de
prompt/cadencia, o RSI nao aplica direto - ele vira um OPP e segue as fases 2 e 3 acima.

## Regra anti-burocracia (achado trivial nao precisa de OPP)

Se o FINDING e trivial e reversivel - ajuste de prompt, cadencia de loop, correcao de typo,
melhoria que o RSI ja tem autoridade pra propor e testar sozinho dentro do escopo evoluivel (rsi.md
linhas 18-24) - ele NAO abre OPP. Vai direto pelo pipeline de versao normal (diff pequeno -> teste
-> Gate -> versiona). O OPP existe para achado com RISCO ou ESCOPO: toca `nucleo`, muda arquitetura,
ou tem esforco M/G. Pedir aprovacao formal para um typo e peso sem ganho - o Criterio 5
(Simplicidade/Atrito) do Quality Gate reprova isso.

## Liga com

[Governanca / Loops](loops.md) (de onde vem o FINDING) -
[Provenance](provenance.md) (quem muda o que; a base da regra de aprovacao) -
[Quality Gate](quality-gate.md) (a regua que o incremento aprovado ainda precisa passar) -
[RSI](../rsi/rsi.md) (o motor que detecta padrao e gera FINDING) -
[Loop Designer](../features/loop-designer.md) (como um loop e receitado; pode ser o proprio FINDING
sobre governanca) -
[Versionamento](../versioning.md) (o pipeline que o incremento aprovado segue).

---

*Alia - Delegue. Nao opere.*
