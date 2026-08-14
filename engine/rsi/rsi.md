# Alia - RSI (Recursive Self Improvement)

> O coracao do aprendizado do Alia Flow. Este documento descreve o motor REAL, tal como existe em
> disco em 10/08/2026 (v1.48.0) - 5 pecas, cada uma com script, prova pelo negativo e limite
> honesto. Politica estruturada ao lado: [rsi.yaml](rsi.yaml). Termos em [glossary.md](../glossary.md).

---

## A tese

O legado tratava memoria e melhoria como subprodutos: anotava o que deu errado, mas a correcao
dependia de alguem ler a anotacao e agir. O Alia Flow inverte: o aprendizado e um Loop fechado.
A Memory nao e um diario passivo - e o combustivel que dispara propostas de melhoria no proprio
framework. RSI e o Principio X da Constituicao virando mecanismo - **estrutura, nunca so
instrucao em markdown**: cada estagio abaixo tem um script que roda, nao so um paragrafo pedindo
comportamento.

## O que o RSI melhora (e o que NUNCA toca)

| Alvo | Camada | RSI pode? |
|------|--------|-----------|
| Prompts de agente, instrucoes de Specialist | evoluivel | Sim - propoe versao melhor |
| Definicao de Gate (criterios, thresholds) | evoluivel | Sim - aperta ou afrouxa com evidencia |
| Domain Pack / Expert Mind (conhecimento de dominio) | evoluivel | Sim - enriquece a cada projeto |
| Rota/fluxo de uma Task recorrente | evoluivel | Sim - troca caro por barato |
| Cadencia de um Loop | evoluivel | Sim - acelera o util, aposenta o inutil |
| Constituicao, principios, fronteira Engine/Studio | **nucleo** | **Nunca** |
| Codigo do motor (orquestracao, governanca) | **nucleo** | **Nunca** |

Tres frentes concretas de ganho: **Qualidade** (o que falhou no Gate vira versao que passa),
**Custo** (caminho caro vira caminho barato - casa com a Frugalidade), **Expertise** (o Domain Pack
fica mais rico a cada entrega do dominio).

## O Loop RSI, as 5 pecas que existem de verdade

```
1. COLETA    session-reflection.ps1 (hook SessionEnd) grava o digest deterministico da sessao
             em memory/_proposals/ - E, desde a PECA 2, tambem varre a mesma sessao por atrito
             real do operador (regex, sem LLM) e grava memory/_proposals/friction-<data>-<id8>.md
             quando encontra.

2. DETECTA   scripts/rsi-patterns.ps1 (PECA 3) varre memory/_proposals/ (staging vivo) e
             memory/_proposals/_archive/ (ja julgado) procurando o MESMO TIPO de item em 3+
             SESSOES DISTINTAS - padrao, nunca incidente isolado. So relata: nunca aplica nada.

3. PROPOE    Uma proposta nasce em engine/rsi/_candidates/<slug>/ (manifest + arquivo proposto +
             caso de teste especifico). NUNCA edita o arquivo vivo nessa etapa - so registra a
             intencao, a evidencia e o teste que hoje falha e deveria passar.

4. APLICA    scripts/rsi-apply.ps1 -Candidate <slug> (PECA 1) - o portao. Roda o teste especifico
             contra o vivo (tem que falhar), aplica numa COPIA TEMPORARIA isolada, roda o teste de
             novo (tem que passar), roda os dois smokes (nada regride), roda o held-out (PECA 4,
             nenhuma decisao do dono e violada) - SO ENTAO promove: o vivo antigo vai para
             engine/rsi/_archive/<data>-<slug>/original (nunca se apaga), o candidato assume o
             lugar, LINEAGE.md registra a cadeia. -Rollback <slug> desfaz, byte a byte.
```

`engine/rsi/_candidates/` e `engine/rsi/_archive/` sao ESTADO LOCAL DA INSTANCIA (lineage de
candidatos propostos/aplicados aqui), nao codigo-fonte do motor - cada instalacao tem o seu;
por isso nao sao espelhados entre oficina e raiz, e `scripts/update-engine.ps1` preserva as
pastas ja existentes no destino em vez de as apagar (secao de exclusoes do script).

A regra do estagio 2 e o que separa RSI de ruido: **padrao, nunca incidente**. Uma falha isolada
e um fato; tres falhas iguais sao um sinal. So sinal vira proposta.

## As 5 pecas, uma a uma (caminho, contrato, prova)

### PECA 1 - O portao do estagio APLICA (`scripts/rsi-apply.ps1`)

O mecanismo mais importante: nenhuma proposta de melhoria a um arquivo do motor (persona, regra,
skill, prompt) toca o arquivo vivo sem passar por teste, sem copia isolada e sem prova de
nao-regressao. Se o alvo e NUCLEO (`constitution.md`, `glossary.md`, `agents/persona.md`,
`orchestration.md`), o portao PARA antes de promover e exige `-ApproveCore` explicito - nucleo
nunca se auto-modifica sem humano, e isso e comportamento (o script recusa e imprime o resumo),
nao um aviso que pode ser ignorado. Biblioteca compartilhada: `scripts/_rsi-lib.ps1` (constroi a
copia de trabalho isolada, barata: pastas pequenas sao copiadas de verdade, o resto vira junction
NTFS - nunca copia os 3.5GB de dados de Client que nao mudam).

Provado pelo negativo em 10/08/2026 (candidatos de demonstracao aplicados e depois limpos):
candidato BOM promoveu com LINEAGE.md e rollback restaurou byte a byte (hash identico
confirmado); candidato que injetava o termo legado banido foi REJEITADO por regressao no smoke
(o check do termo legado no smoke subiu de 1 para 2 arquivos afetados); candidato cujo teste especifico ja passava no
vivo foi REJEITADO como desnecessario, sem sequer criar copia; candidato de nucleo (persona.md)
PAROU no passo de promocao (exit code 2, distinto de sucesso e de rejeicao) sem tocar o arquivo
vivo, esperando `-ApproveCore`.

### PECA 2 - O canal do dono (`scripts/session-reflection.ps1`, atrito)

O mesmo hook de SessionEnd que ja gerava o digest agora tambem varre a transcricao por sinais de
frustracao do operador - regex/heuristica DETERMINISTICA (sem chamada de modelo: o hook roda no
fim de toda sessao, com timeout, e nao pode depender de LLM). A lista de gatilhos foi calibrada
lendo `memory/_proposals/_archive/` de verdade (o historico REAL de frustracao nesta casa -
"ja falei isso e nao corrigiu", "vergonhoso... que merda eh essa", "pqp alia", "inaceitavel", "ta
mto ruim", "amador", jun-ago/2026), nao inventada. Cada atrito vira um item estruturado
`{texto, severidade, tipo}` em `memory/_proposals/friction-<data>-<id8>.md`, separado do digest.
O `reflect-check.ps1` (hook de SessionStart) conta os itens de atrito pendentes junto com os
digests. Escaneia a mensagem CRUA do usuario, antes da lista anti-captura do digest (a lista
anti-captura existe para manter o digest legivel, e descartaria justamente frases como "nao
funciona" que sao, ao mesmo tempo, o sinal de atrito mais comum).

Provado pelo negativo em 10/08/2026: transcricao sintetica com frustracao plantada
("ja falei isso e nao corrigiu, continua ruim, que merda eh essa, ta inaceitavel, vc perdeu tempo
de novo") gerou `friction-*.md` com severidade 3 e 4 tipos batidos; transcricao sintetica sem
frustracao (elogio + pedido normal) nao gerou arquivo nenhum.

### PECA 3 - O detector de recorrencia (`scripts/rsi-patterns.ps1`)

Varre os digests e os itens de atrito acumulados (staging + `_archive`) e detecta o mesmo tipo de
item aparecendo em 3+ sessoes DISTINTAS - o "padrao, nunca incidente" da tese, agora com maquina
em vez de so o julgamento de quem le. Dois classificadores: um le o campo `tipo:` ja estruturado
dos itens de atrito (PECA 2); outro aplica um pequeno classificador por palavra-chave sobre o
texto livre dos digests, calibrado nos DOIS padroes que a casa ja sabia que eram recorrentes
(ver `memory/delegar-exige-classificar-o-dominio.md` e o numero fossil citado em
`memory/_proposals/_archive/reflection-inbox-2026-07-03-c5e36aa2.md`). O detector NUNCA aplica
nada sozinho - so escreve um relatorio de candidatos (`-Write`, opcional) para virar proposta da
PECA 1 por decisao humana.

Validado RETROATIVAMENTE em 10/08/2026 contra o historico real (77 digests + 0 atritos, a PECA 2
sendo nova): achou "delegacao-furada" em 8 sessoes distintas (2026-08-02 a 2026-08-06) - o padrao
real que a casa ja registrava em memoria solta. "numero-publico-fossil" apareceu em 2 sessoes -
visivel no relatorio como "abaixo do minimo", nao escondido, honesto sobre nao ter batido o teto
de 3 ainda com o volume de digests disponivel.

**Cobertura completa dos 3 tipos de staging (TASK-159, 13/08/2026 - NAO e peca nova, e o
fechamento de lacuna nas pecas ja existentes):** `memory/_proposals/` guarda 3 classes vivas
(`reflection-inbox-*.md` da PECA 1/COLETA, `friction-*.md` da PECA 2, `patterns-*.md` da PECA 3)
e, ate esta correcao, so a primeira classe tinha ciclo de vida completo (visivel no boot, com
staleness travada no smoke, arquivavel). Auditoria mediu o furo: `scripts/promote-memory.ps1`
tratava `friction-*.md`/`patterns-*.md` como `[ORFAO]` (nome desconhecido, nunca promovido, aviso
que morre so impresso); o cadeado de vivacidade do smoke so olhava `reflection-inbox-*.md`.
Consertado sem inventar peca nova - as 4 pontas que ja existiam passaram a cobrir as 3 classes:
`scripts/reflect-check.ps1` (boot) conta as 3 e sinaliza `.md` de formato desconhecido a parte;
`scripts/promote-memory.ps1` reclassifica friction/patterns como `[STAGING]` (nunca promovidas -
insumo de OUTRO fluxo, nao proposta de memoria) e so arquiva `friction-*.md` quando ele ja foi
CONSUMIDO por esta PECA 3 (citado como `Fonte` num `patterns-*.md` escrito) - `patterns-*.md`
nunca arquiva sozinho, e relatorio de decisao humana pendente, nao processo automatico;
`scripts/smoke-test-studio.ps1` secao (i) trava staleness > 3 dias nas 3 classes, nao so na
primeira; `scripts/mission-control.ps1` mostra contagem+idade das 3 no painel ("Pendencias do
motor"). Prova pelo negativo de cada ponta na Task que fechou este cluster.

### PECA 4 - O held-out (`scripts/rsi-heldout.ps1`)

Conjunto FIXO de 6 assercoes deterministicas que representam decisoes JA TOMADAS pelo dono, lidas
de `docs/CLAIMS.md` (vetos e claims vigentes) e das LEIS ja registradas em prosa (nenhuma
inventada aqui): o cargo corporativo vetado (derrubado 02/jul, ver CLAIMS.md, secao VETOS) nao
reaparece como auto-descricao na persona; a headline vigente nao some de
`BRAND.md`; nenhum arquivo de motor (engine/scripts/skills proprios, instancia e oficina) tem
emoji; nenhum tem caractere fora de ASCII; a LEI da superficie publica e o script que a mede
continuam presentes; a oficina continua sem ser repositorio git. `rsi-apply.ps1` chama este script
no passo (e) do portao - nenhuma proposta promove se violar qualquer uma. `-SelfTest` planta uma
violacao de cada assercao, uma de cada vez, numa copia isolada, e confirma que SO aquela assercao
falha (as outras continuam limpas) - rodado e verde em 10/08/2026, as 6 pegam a propria violacao
plantada sem ruido cruzado (exceto a sobreposicao ESPERADA entre emoji e nao-ASCII, documentada).

### PECA 5 - Reflexao por tipo de tarefa (`scripts/task-context.ps1 -TaskType`)

Extensao minima viavel do padrao Reflexion: notas de memoria promovidas ganham um campo opcional
`aplica_a: <tipo>` (landing, auditoria, release, delegacao...). `task-context.ps1`, que ja mostrava
a continuidade de Tasks por Cliente/Projeto, ganhou `-TaskType <tipo>` - devolve as notas cujo
`aplica_a` casa com o tipo pedido. Match simples por campo (string igual ou item de lista),
NUNCA banco nem embedding. Duas notas reais ja migradas em 10/08/2026:
`memory/delegar-exige-classificar-o-dominio.md` (`aplica_a: delegacao`) e
`memory/lp-vitrine-de-designer-aclamado.md` (`aplica_a: landing`), ambas devolvidas corretamente
pelo comando quando o tipo casa, e um tipo inexistente devolve mensagem honesta de "nada marcado
ainda" (nao erro).

## De onde vem o combustivel (ligacao com os Loops)

O RSI nao gera dados - ele consome o que os Loops ja produzem. Cada Loop agendado ou dinamico
escreve seu resultado na Memory; o RSI le esse rastro.

| Loop | O que entrega ao RSI |
|------|----------------------|
| Quality Gate (no Artifact) | verdict + razao da reprova - materia-prima da melhoria de Qualidade |
| fix-on-fail | quantas abordagens foram precisas - sinal de prompt/fluxo fraco |
| ddd-drift-scan | desvio da linguagem ubiqua - sinal de Domain Pack desatualizado |
| debt-scan | Concerns que nunca fecham - candidatos a mudanca de Gate ou de rota |
| deep-research | pratica externa nova - enriquece Domain Pack / Expert Mind |
| rsi-friction | atrito real do operador (frustracao ao vivo) - aponta onde o workflow trava de verdade |

A fonte `rsi-friction` (skill `skills/rsi-friction/SKILL.md`, quando existir) e a unica que vem de
gente, nao de metrica; hoje o mecanismo QUE a alimenta e a PECA 2 (`session-reflection.ps1`), que
capta a frustracao do operador em silencio e grava em `memory/_proposals/friction-*.md`, contada
pelo `reflect-check.ps1` no boot da proxima sessao. A promocao de um item de atrito recorrente em
melhoria de verdade passa pela PECA 3 (deteccao) e pela PECA 1 (portao) - nunca automatico.

Catalogo dos Loops: [governance/loops.md](../governance/loops.md). Quem receita por projeto: a Alia
via Loop Designer ([features/loop-designer.md](../features/loop-designer.md)). O loop que mais
alimenta a frente de Expertise e o
[deep-research-loop](../features/deep-research-loop.md).

## Guardrails (inegociavel)

A parte que se auto-modifica **nunca** toca o nucleo do Engine. Um sistema que se reescreve sem
freio pode "se melhorar" para um buraco - a pesquisa do estado da arte (Darwin Godel Machine da
Sakana) MEDIU reward hacking crescendo de 26.4% para 57.8% com mais passos de otimizacao, e um
agente removendo os proprios marcadores de deteccao apesar de instrucao explicita contra. Por
isso o RSI vive dentro de cercas MECANICAS, nao so de instrucao:

1. **Escopo fechado** - so a camada evoluivel da tabela acima. O nucleo e imutavel pelo RSI
   (checado por `Test-IsCoreTarget` em `rsi-apply.ps1`, mesma lista que `guard-core.ps1` protege).
2. **Evidencia obrigatoria** - sem o padrao na Memory que a justifica, a proposta e rejeitada
   (PECA 1, passo (a): teste especifico tem que falhar no vivo, senao a proposta e "desnecessaria").
3. **Teste antes de aplicar** - toda proposta roda contra um caso de teste especifico + os dois
   smokes + o held-out, numa copia isolada, ANTES de tocar o vivo (PECA 1, passos (a)-(e)).
4. **Arquivo, nunca substituicao** - a versao anterior vai para `engine/rsi/_archive/`, nunca se
   apaga; rollback e trivial porque o antigo nunca some (mesmo padrao que DGM/Voyager/ADAS usam
   na literatura: acumular variantes com proveniencia, nunca sobrescrever).
5. **Aprovacao humana em mudanca de nucleo** - mexer no que define o motor exige o sinal do
   Operator, via `-ApproveCore` explicito. O sistema propoe; quem aprova nucleo e gente.
6. **Verificacao independente (CONFERE)** - o teste do passo APLICA roda numa instancia separada
   (o proprio `rsi-apply.ps1`, chamado pelo operador ou por um sub-agente dedicado, nunca pelo
   mesmo agente que escreveu o candidato) - auto-aprovacao e o furo que deixa um erro virar
   verdade no ciclo seguinte.
7. **Held-out contra decisoes ja tomadas (PECA 4)** - a suite fixa de assercoes representa vetos e
   leis que o dono ja decidiu; nenhuma proposta promove se violar qualquer uma, mesmo que passe no
   teste especifico e nos smokes.

Os limites numericos (N de falhas, janela de observacao, teto de propostas por ciclo) ficam em
[rsi.yaml](rsi.yaml) -> `guardrails`, para serem auditaveis e ajustaveis sem reescrever esta spec.

## O que e automatico e o que exige humano (limite honesto)

| Estagio | Roda sozinho? | Quem decide |
|---|---|---|
| COLETA (digest + atrito) | Sim - hook SessionEnd, sem LLM | ninguem decide, so registra |
| DETECTA (padrao recorrente) | Sim, sob demanda (`rsi-patterns.ps1`) | ninguem decide, so relata |
| PROPOE (candidato nasce) | **Nao** - um agente ou o operador escreve manifest+proposed+test.ps1 | humano/agente que propos |
| APLICA - alvo evoluivel | Roda sozinho ate a promocao (`rsi-apply.ps1 -Candidate`) | o portao (testes+smokes+held-out), sem cartao S/N extra |
| APLICA - alvo NUCLEO | Para antes de promover, mesmo com tudo verde | `-ApproveCore` explicito do Operator |
| ROLLBACK | Sim, sob comando (`-Rollback <slug>`) | quem decide reverter |

O que continua **EXISTE MAS NAO PROVADO** (honestidade acima de placar): o estagio PROPOE
(escrever o manifest/teste do candidato) hoje e manual - nenhum agente ainda gera candidato
sozinho a partir de um padrao detectado pela PECA 3. O elo PECA 3 -> PECA 1 e decisao humana por
desenho (o proprio detector "NUNCA aplica nada sozinho"), nao um furo a fechar depois.

## Metrica viva

A prova de que o RSI funciona e uma so: **o custo medio de tokens por Artifact entregue deve cair
ao longo do tempo**, sem queda de qualidade (taxa de PASS no Gate estavel ou subindo). Essa queda
e a evidencia de que RSI e Frugalidade trabalham juntos - o sistema fica melhor *e* mais barato.

A fonte do numero e o `state.json` do Studio (custo por Task) cruzado com os verdicts de Gate na
Memory. A definicao formal da metrica e da janela esta em [rsi.yaml](rsi.yaml) -> `metric`.

## Anti-patterns (o que NAO e RSI)

- Reagir a uma unica falha como se fosse padrao (estagio 2/PECA 3 existe pra impedir isso).
- Aplicar melhoria sem teste nem rollback (vira aposta, nao engenharia - PECA 1 barra isso).
- "Melhorar" tocando o nucleo do Engine ou a Constituicao sem `-ApproveCore` (PECA 1, passo f).
- Otimizar custo derrubando qualidade (a Frugalidade do Alia Flow proibe trade de qualidade).
- Aprovar a propria proposta - quem produz nao confere (viola a separacao de instancias e o CONFERE).
- Confundir "projetado" com "provado" - cada peca acima so entra aqui com prova pelo negativo
  executada nesta mesma sessao, nao so leitura de codigo.

## Liga com

[Constituicao](../constitution.md) (Principio X - RSI Discipline) -
[Governanca / Loops](../governance/loops.md) (de onde vem o feedback) -
[Quality Gate](../governance/quality-gate.md) (o crivo que o RSI usa e respeita) -
[Deep Research Loop](../features/deep-research-loop.md) (RSI alimentado por pesquisa externa) -
`docs/CAPACIDADE-REAL.md` (itens 16, 21, 22 - os selos que este trabalho mudou).

---

*Alia - Delegue. Nao opere.*
