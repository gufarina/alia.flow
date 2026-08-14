# Alia Flow - Quality Gate (regua unica)

> A regua de qualidade que TODO squad herda. Garante que nenhum time entregue abaixo do padrao -
> e o "Quality Gate Always" da [constituicao](../constitution.md) virado mecanismo. Squads podem
> ADICIONAR criterios; nunca REMOVER os minimos. O contrato estruturado (criterios + verdicts)
> fica ao lado em [quality-gate.yaml](quality-gate.yaml). Sem acentos, sem emojis.

---

## Quando roda

A cada Artifact, ANTES de chegar ao operador. Disparado pelo loop dinamico `gate-on-artifact`
([governance/loops.md](loops.md)) e reaplicado nas verificacoes agendadas. Nenhum Artifact
alcanca o operador sem passar por aqui - essa e a unica porta de saida.

## Criterios minimos (6)

> LEI: os 6 criterios abaixo sao inegociaveis. Reprovar um reprova o Artifact; nenhum squad rebaixa
> os minimos.

Seis perguntas, todas inegociaveis. Reprovar uma e reprovar o Artifact.

| # | Criterio | Pergunta | Evidencia que prova |
|---|----------|----------|---------------------|
| 1 | **Funciona** | O entregavel faz o que deveria, sem quebrar? | EVIDENCIA DE EXECUCAO anexada: o avaliador RODOU o artefato e cita o resultado observado [MEDIDO comando -> saida]. Leitura de codigo NAO e prova |
| 2 | **Aderente ao DDD** | Usa so termos da linguagem ubiqua do Client? Respeita os bounded contexts? | termos batidos contra o glossario do Client |
| 3 | **Frugal** | Foi produzido sem desperdicio de tokens? Ha caminho mais barato? | reuso de Memory/segundo cerebro citado |
| 4 | **Rastreavel** | Tem Artifact (evidencia) ligado a uma Task? | id da Task + caminho do Artifact |
| 5 | **Simplicidade / Atrito** | A entrega REDUZ o atrito do usuario (menos passos, menos perguntas, menos peso), ou e so capacidade/peso a mais? | menos passos para o resultado vs a baseline; nada de peso sem ganho |
| 6 | **Fundamentada (grounding)** | Toda afirmacao de fato/diagnostico cita a fonte verificavel que foi LIDA, ou esta rotulada como inferencia? | cada afirmacao de peso traz [MEDIDO arquivo:linha] ou [INFERIDO]. Afirmacao de peso sem rotulo = Fail |

> Criterio 5 (Atrito): o que so adiciona capacidade ou peso, sem deixar o usuario mais simples, NAO
> passa. Mais profundidade vai para a biblioteca sob demanda (ver `engine/MAP.md`), nunca para o peso
> sempre-carregado.

> Criterio 5 (Atrito) - evidencia de saida: o Artifact segue a escada de
> [artifact-ladder.md](../features/artifact-ladder.md) - ou o resultado E o minimo que passa no Gate
> (nenhum degrau pulado), ou a simplificacao deliberada carrega `frugal-debito: <teto> - upgrade:
> <caminho>`. Marcador ausente onde a saida claramente simplificou = Concerns, nao Fail automatico
> (o avaliador julga se a simplificacao era mesmo necessaria); marcador sem teto+upgrade = Fail. O
> Gate vence qualquer degrau da escada: economia que reprova um dos 6 criterios minimos nao
> economizou nada.

> Tipos de Artifact (imagem, texto, codigo, site) podem ter criterios extras - por exemplo, um
> contrato de formato deterministico (Validated Artifacts). Mas os 6 minimos acima sao a base que
> nenhum squad pode rebaixar.

> Criterios extras OBRIGATORIOS para Artifact do tipo PECA PUBLICA (landing, site, social, deck,
> README publico) - a [lei da fonte de verdade do cliente](client-truth.md), 07/jul: (a) fontes
> curadas do Client (BRAND/PRD/persona) DECLARADAS e carregadas antes de produzir; (b) todo claim
> quantitativo, feature e tagline rastreado ao registro de claims - numero fabricado por soma de
> fontes distintas = Fail; feature nao-LANCADA anunciada = Fail; identidade/angulo VETADO pelo
> Operator ressuscitado = Fail; (c) gramatica completa da lingua do publico + zero vocabulario de
> bastidor (regra interna de operacao nao vaza pra peca); (d) ativos de marca vindos do inventario
> oficial do Client, nunca recriados por descuido.

> Criterio 6 (Fundamentada) - por que existe e como checa: nasceu do incidente em que a Alia
> entregou um diagnostico do proprio harness INFERIDO (estudo externo + memoria) em vez de LIDO do
> codigo real, num canvas sem rotulo de palpite. E o espelho da LEI "investigar antes de escalar"
> (orchestration.md, escada Memory->local->web) virado para o lado da AFIRMACAO: antes de afirmar,
> leia a fonte ou rotule. O check e barato e deterministico no mesmo molde do `verify-artifact-persisted`:
> nao julga se a fonte SUSTENTA a afirmacao (isso seria LLM-judge caro, fora de escopo) - so confere
> se toda afirmacao de peso CARREGA rotulo [MEDIDO arquivo:linha] ou [INFERIDO]. Afirmacao de peso
> sem rotulo = Fail. Fecha a fresta da inferencia-sem-rotulo; a inferencia caprichada (rotulo falso)
> fica como evolucao futura declarada.

> Criterio 1 (Funciona) - o avaliador AGE, nao le (OPP-59): o verdito PASS exige EVIDENCIA DE
> EXECUCAO anexada - o avaliador rodou o artefato (script/smoke/preview/clique) e cita o resultado
> observado [MEDIDO comando -> saida]. Julgamento por leitura e julgamento por intencao: a divida
> de verificacao acumula em silencio e explode na entrega. Postura do avaliador no
> `gate-on-artifact`: assume QUEBRADO ATE PROVA EM CONTRARIO. Tipologia de prova por tipo de
> artefato: codigo -> roda teste/smoke; pagina/UI -> abre preview e interage (Playwright/preview
> quando disponivel; DOM/funcional quando screenshot indisponivel); documento -> confere fatos
> contra a fonte (ja coberto pelo criterio 6, Grounding); script -> executa em fixture. Sem
> execucao possivel (ambiente indisponivel)? O verdito NAO pode ser Pass - vira Concerns com o
> motivo registrado. Indisponibilidade nao e aprovacao.

> Criterio 1 (Funciona) tambem cobra o motor: mudanca em `engine/**` que declare ou altere LEI so
> passa com entrada correspondente no [law-ledger.md](law-ledger.md) - sem entrada, Fail.

> Checks deterministicos dos criterios 1 (Funciona) e 4 (Rastreavel): alem do contrato de FORMATO
> (Validated Artifacts), a Frugal Skill `verify-artifact-persisted`
> ([skills/verify-artifact-persisted/SKILL.md](../../skills/verify-artifact-persisted/SKILL.md))
> confirma por git que o Artifact ligado a Task foi de fato PERSISTIDO (existe no disco e esta
> versionado), retornando PASS/FAIL/CONCERN sem LLM.

## Resultado (verdict)

Tres saidas possiveis, e nada entre elas. Todo verdict e registrado na Memory COM evidencia -
nunca um "passou" sem prova.

| Verdict | Significado | Acao |
|---------|-------------|------|
| **Pass** | Entrega liberada, sem ressalva. | segue ao operador |
| **Concerns** | Liberada com ressalvas registradas. | vira input de RSI; se nao resolvida, vira debito (pego pelo `debt-scan`) |
| **Fail** | Volta para correcao. | loop `fix-on-fail` (max N abordagens *diferentes*) -> re-gate; persistiu -> escala a Alia |

> Concerns nao e um "Pass preguicoso": e uma divida assumida e rastreada. Concerns que nunca vira
> correcao e detectado pelo loop de debito e cobrado pela Alia no Tier 2.

## DDD anti-drift (o coracao do criterio 2)

O criterio 2 nao e cosmetico - e o freio contra a entropia que um LLM injeta quando solto numa
codebase. O Gate verifica o Artifact CONTRA o DDD do Client:

- **Termo fora do glossario** -> sinal de drift semantico -> Concerns ou Fail, com o termo
  divergente apontado e o termo correto sugerido.
- **Violacao de bounded context** -> o Artifact mistura conceitos de contextos que deviam estar
  separados -> Fail.
- **Contradicao da linguagem estabelecida** -> o Artifact redefine um termo ja firmado -> Fail.

**Pre-condicao dura:** Client/produto sem DDD documentado (glossario + bounded contexts) nao pode
receber entrega - o Gate bloqueia ANTES de avaliar os outros criterios. Sem linguagem ubiqua, nao
ha como medir aderencia, e medir aderencia e metade do que este Gate existe para fazer.

## Postura do avaliador (disciplina de julgamento)

O avaliador verifica em POSTURA DIFERENTE da que gerou - reler no mesmo quadro nao verifica nada.
Os passes, escolhidos pela aposta (profundidade segue irreversibilidade), estao na
[Disciplina de Julgamento](../features/judgment-discipline.md): passe de extracao (afirmacoes
peladas numa lista, fora do brilho da prosa), aritmetica recomputada, siga-a-premissa, leitura
hostil (o implementador de segunda-feira), caca ao contraexemplo (zero, um, maximo, malformado).
"Le bem" e "se sustenta" nao sao correlacionados; o paragrafo bonito e o mais perigoso. A regua
de vocabulario dos verdicts (fraco/decente/forte/excelente) vive no mesmo doc.

## Liga com
[Constituicao](../constitution.md) (principio VI - Quality Gate Always) - 
[Governanca por Loops](loops.md) (quem dispara e reaplica o Gate) - 
[quality-gate.yaml](quality-gate.yaml) (o contrato estruturado dos criterios e verdicts) - 
[Disciplina de Julgamento](../features/judgment-discipline.md) (os passes de verificacao do avaliador).

---

*Alia - Delegue. Nao opere.*
