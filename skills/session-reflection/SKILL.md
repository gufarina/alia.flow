---
name: session-reflection
description: Reflexao pos-sessao do Alia Flow - le o transcript da sessao recem-encerrada, separa o que e perfil/preferencia do usuario do que e correcao/regra de tarefa, e PROPOE notas de memoria (nunca aplica). Materializa a OPP-02 (gatilho + leitura do transcript) respeitando os guardrails do RSI. Use ao fim de uma sessao, ou quando o operador pede para refletir sobre a ultima sessao e propor aprendizados.
trigger: /alia-reflect
provenance: nucleo
---

# Session Reflection

Capacidade que fecha o loop de aprendizado do RSI no ponto que faltava: ler o transcript
cru de uma sessao e transformar o que aconteceu em PROPOSTAS de memoria. Spec do motor:
`engine/rsi/rsi.md` (estagios COLETA -> DETECTA -> PROPOE). Governanca:
`engine/governance/provenance.md` (so propoe diff, nunca aplica, nunca deleta, nunca toca nucleo). Escrita UTF-8 sem BOM.

## O que esta capacidade NAO faz

- NAO aplica nada na memoria real. So escreve em uma area de PROPOSTAS (`memory/_proposals/`).
- NAO deleta nem arquiva nada existente.
- NAO toca nucleo (qualquer artefato com `provenance: nucleo`, engine/, constituicao).
- NAO roda o julgamento dentro de um hook. O digest (passo frugal, sem LLM) roda no SessionEnd
  via `scripts/session-reflection.ps1`; o JULGAMENTO (passo do agente) e disparado no SessionStart
  pelo hook `scripts/reflect-check.ps1`, que detecta inboxes pendentes e lembra a Alia de fechar o
  loop. (Antes este disparo era PLACEHOLDER; desde 1.1.0 esta plugado e testado.)
- NAO promove sem classificacao independente: a promocao para `memory/` (canonico) so ocorre com
  `approved_by` carimbado por uma instancia != quem propos, executada por
  `scripts/promote-memory.ps1`. O CONFERE (AUTONOMIA COM FREIO, decisao do CEO 10/09/2026) classifica
  cada proposta pelos 4 crivos e resolve sozinho, sem cartao S/N: passou nos 4 -> `safe_auto`; duvida
  -> `auto_promote_probation` (30 dias); reprova -> `auto_discard` (arquiva); crivo 3 reprovado ->
  `route_to_rsi`. Autonomia SO na promocao de memoria; nucleo/engine/Gate continuam exigindo humano.

## Divisao de trabalho: script (frugal) + agente (julgamento)

1. `scripts/session-reflection.ps1` (Frugal Skill, sem LLM): acha o transcript mais recente,
   extrai um digest enxuto (mensagens do usuario + pontos de decisao), aplica a lista
   anti-captura por palavra-chave, e grava `reflection-inbox-{data}.md` em `memory/_proposals/`.
   E o passo mecanico - custo zero de token de modelo.
2. O AGENTE (este procedimento): le o digest do inbox e aplica as heuristicas Hermes abaixo
   para escrever as PROPOSTAS de nota de memoria tipadas. E o passo de julgamento.

## Heuristicas Hermes (o nucleo do julgamento)

### 1. SEPARAR: quem e o usuario vs como fazer a tarefa

Cada aprendizado cai em exatamente um balde:

- "quem e o usuario / preferencia" -> nota tipo `user`. Exemplos: o CEO e leigo em termos
  tecnicos; prefere respostas curtas; gosta de analogias; trabalha em janelas curtas.
  Pergunta-guia: isso vale para QUALQUER tarefa futura com este operador? Entao e `user`.
- "como fazer a tarefa / correcao" -> nota tipo `feedback` (regra). Exemplos: ao gravar
  arquivo no Windows use .NET UTF-8 sem BOM; nao usar Set-Content cru; checar provenance
  antes de propor edicao. Pergunta-guia: isso conserta um jeito errado de EXECUTAR? Entao e
  `feedback`.

Na duvida entre `user` e `feedback`: se a licao muda COMO se executa, e `feedback`; se descreve
QUEM e o operador, e `user`.

### 2. FRUSTRACAO do CEO -> capturar como feedback (a licao, nao a reclamacao)

Quando o operador demonstra frustracao ("isso esta errado", "ja falei", "voce nao entendeu"),
NAO registre a reclamacao. Registre o CONSERTO: qual regra/comportamento evita a frustracao da
proxima vez. A nota e tipo `feedback` e descreve a acao corretiva, nunca o desabafo.

Exemplo: o CEO reclamou "sua linguagem esta tecnica, sou leigo". A nota NAO e "CEO reclamou da
linguagem". A nota e "explicar sempre em linguagem de negocio/analogia; traduzir jargao na hora".

### 3. LISTA ANTI-CAPTURA (nunca registrar)

Descartar - jamais vira nota:

- Falha de ambiente (path nao encontrado, permissao negada, disco cheio, comando ausente).
- Afirmacao negativa sobre uma ferramenta ("X nao funciona", "a API esta fora", "deu timeout").
- Erro transitorio (flaky, retry resolveu, rede caiu e voltou).

Regra mestra: capturar o CONSERTO, nao a reclamacao. Se um erro de ambiente levou a uma regra
duravel (ex: "sempre checar se o path existe antes de escrever"), o que se registra e a REGRA
(feedback), nunca o incidente. Incidente isolado nao e padrao (RSI estagio 2: padrao, nao
incidente).

### 4. A REFLEXAO so PROPOE; a PROMOCAO fecha sozinha

Toda saida vai para `memory/_proposals/` como proposta. Nada e escrito direto na memoria real
do operador por este passo. Mas o ciclo nao para esperando gente: o CONFERE independente
(AUTONOMIA COM FREIO, abaixo) classifica cada proposta e a promocao fecha no mesmo ciclo, sem
cartao S/N ao operador (provenance.md: agent-authored sai como diff; quem aprova e o CONFERE,
uma instancia != quem propos - nunca o operador item-a-item).

## Formato da proposta

Cada aprendizado proposto e um arquivo `.md` em `memory/_proposals/` cujo nome DEVE comecar
com `prop-` (ex: `prop-minha-nota.md`). O `promote-memory.ps1` so enxerga `prop-*.md`: proposta
com outro nome fica invisivel e apodrece em staging (o script avisa como [ORFAO], mas nao
promove). Padrao de memoria:

```
---
name: kebab-case-curto
description: uma linha do que e a nota
metadata:
  node_type: memory
  type: user | feedback | project | reference
  originSessionId: <id da sessao, se conhecido>
  status: proposed
---

<corpo da nota: a licao em ASCII puro>

**Why:** por que isso importa (a evidencia/o efeito).

**How to apply:** como aplicar na pratica.
```

Tipos:
- `user` - quem e o operador / preferencia duravel.
- `feedback` - correcao / regra de como executar.
- `project` - fato do projeto em curso.
- `reference` - material de apoio / link.

Alem dos arquivos individuais, o script ja grava um `reflection-inbox-{data}.md` com o digest
e um resumo do que foi proposto e por que - o ponto de entrada que o operador revisa primeiro.

## Destino canonico da memoria (a fonte da verdade do recall)

- STAGING: `memory/_proposals/` - propostas tipadas (`prop-*.md`) e digests brutos (`reflection-inbox-*.md`).
- CANONICO: `memory/` - as notas PROMOVIDAS (`<name>.md`, status: active). E o que o recall le.
- ARQUIVO: `memory/_proposals/_archive/` - digests ja julgados (historico; nao re-disparam o gatilho).
  `memory/_retired/` - notas revogadas pelo operador (provenance.md: nunca deletar, so arquivar).

## O ciclo completo (o cano do RSI, fechado)

1. SessionEnd -> `session-reflection.ps1` gera o `reflection-inbox-{data}-{id8}.md` (digest frugal).
2. SessionStart -> `reflect-check.ps1` detecta inboxes pendentes e lembra a Alia (o gatilho).
3. A Alia julga (heuristicas Hermes abaixo) e escreve `prop-*.md` em `_proposals/`.
4. CONFERE independente (AUTONOMIA SEM ESPERA HUMANA, abaixo): uma instancia != quem propos
   triagem cada proposta pelos 4 crivos e resolve para um dos quatro destinos, todos automaticos:
   `safe_auto` carimba `approved_by` e promove; `auto_promote_probation` promove com
   `confidence: low` e `valid_until` de 30 dias (o tempo retira, via `memory-curator.ps1
   -Validade`); `auto_discard` arquiva a proposta em `_archive/` com `discard_reason` (nunca
   deleta); `route_to_rsi` manda o candidato para `engine/rsi/_candidates/` quando o crivo 3
   (Aditiva/SEGURA) reprova - vira pauta de motor, nao memoria.
5. `promote-memory.ps1 -ArchiveInbox`: move as aprovadas (`safe_auto` e `auto_promote_probation`,
   ambas com `approved_by`) para `memory/` e arquiva os inboxes julgados.

## Protocolo de dialogo (teste da mae - decisao do CEO, 02/jul)

Todo este ciclo e BASTIDOR. A regra dura de linguagem da persona (persona.md: jargao PROIBIDO
para o usuario; o loop fica nos bastidores) manda aqui tambem - e o gatilho nao a atropela:

- QUANDO: o julgamento roda DEPOIS de atender o pedido do operador (ou num momento morto do
  trabalho), nunca como abertura da sessao. A primeira fala da Alia e sobre o pedido DELE.
  Adiar dentro da sessao pode; pular nao - o processamento continua obrigatorio na sessao,
  e a prova da instancia FALHA se aprendizado ficar parado > 3 dias (a trava de maquina).
- COMO SE FALA: nao se anuncia ("vou fechar o loop de RSI" e violacao), nao se narra, nao se
  usa RSI/digest/inbox/promocao/probation/candidato na conversa. O CONFERE resolve tudo sozinho
  (safe_auto, probation, descarte ou roteamento para RSI) - o operador nunca fica sabendo do
  mecanismo, e nunca e interrompido por memoria (decisao do CEO, 10/09/2026: sem cartao S/N).
- Teste da mae: se a mae do operador nao entenderia a frase, a frase nao sai.

## AUTONOMIA SEM ESPERA HUMANA (o classificador e o tempo sao o freio)

Decisao do CEO (10/09/2026): a Alia aprende sozinha, sem eu ter que aprovar nada. O desfecho
ESCALA_HUMANO (cartao S/N ao operador) morreu - pedir aprovacao em bloco virava ruido, o
operador ignorava, e o loop apodrecia (era o furo do OPP-53). O freio nao e mais o operador
clicar em algo - o freio e um CONFERE INDEPENDENTE que classifica automaticamente CADA proposta
em um dos quatro desfechos (`safe_auto`, `auto_promote_probation`, `auto_discard`,
`route_to_rsi`), e o TEMPO, que retira sozinho o que entrou em probation (30 dias, sem confirmar
com ninguem).

Quem confere: uma instancia SEPARADA de quem propos (a Alia num passo dedicado ou um sub-agente
CONFERE), nunca o mesmo agente que escreveu a proposta - e o guardrail `independent_verification`
do RSI (rsi.md:95-99) e o "quem propoe nao aprova" da provenance (provenance.md:26). Auto-aprovar a
propria proposta e o furo que deixa um erro virar verdade no ciclo seguinte.

O CONFERE classifica CADA `prop-*.md` pelos 4 crivos (todos tem que passar):

1. **Fundamentada** no digest: a nota sai do que o digest registrou (grounding), nao de palpite.
2. **Nao-duplicata**: nao repete uma nota ja ativa em `memory/`.
3. **Aditiva / SEGURA**: nao toca nucleo/engine/constituicao/Gate, nao contradiz nem apaga nota
   ativa, sem gasto/credencial/acao destrutiva. So ADICIONA conhecimento.
4. **Duravel**: e regra/fato que vale pra frente, nao desabafo nem incidente transitorio (mesma
   regra da lista anti-captura e do estagio 2 do RSI: padrao, nao incidente).

Desfecho (os quatro, todos automaticos - nenhum espera humano):

- Passou nos 4 -> **safe_auto**: o CONFERE carimba `approved_by:` no frontmatter com a SUA
  identidade (a instancia que conferiu, != autor) e a proposta e auto-promovida por
  `promote-memory.ps1`.
- Duvida nos crivos 1, 2 ou 4 -> **auto_promote_probation**: promove com `confidence: low` e
  `valid_until` de 30 dias. Quem retira e o TEMPO (`memory-curator.ps1 -Validade`), nunca um
  humano.
- Reprova clara nos crivos 1, 2 ou 4 -> **auto_discard**: NAO promove; arquiva o `prop-*.md` em
  `memory/_proposals/_archive/` com `status: discarded` e `discard_reason:`. Nunca deleta.
- Crivo 3 (Aditiva/SEGURA) reprovado -> **route_to_rsi**: NAO vira memoria; vira candidato em
  `engine/rsi/_candidates/`, o cano proprio de mudanca de MOTOR.

### Fronteira dura (nao afrouxar) - agora e roteamento, nao pergunta

Esta autonomia vale SO para promocao de MEMORIA (`prop-*.md` -> `memory/`, notas
`user|feedback|project|reference`). Qualquer mudanca em engine/nucleo/constituicao/Gate continua
exigindo humano: e `provenance: nucleo` (bloqueio duro, provenance.yaml `block_when`) e, para o
Gate, `human_approval_for: [gate]` no `rsi.yaml`. O crivo 3 (Aditiva/SEGURA) e essa fronteira: uma
proposta que tenta tocar nucleo/engine/constituicao/Gate, ou envolve gasto/credencial/acao
destrutiva, nunca vira memoria - o CONFERE a desvia (`route_to_rsi`) para
`engine/rsi/_candidates/`, mantendo L04 / `-AllowCore` como o unico cano de mudanca de motor.
Nao e mais uma pergunta ao operador, e roteamento automatico para o lugar certo. A politica
machine-checkable esta em `engine/rsi/rsi.yaml` -> `memory_promotion_policy`.

## Procedimento do agente (passo a passo)

1. Rodar `scripts/session-reflection.ps1` (sem DryRun) para gerar o digest no inbox.
2. Ler `memory/_proposals/reflection-inbox-{data}.md`.
3. Para cada item do digest, decidir: descartar (lista anti-captura) ou capturar.
4. Para cada item capturado: classificar (heuristica 1), tratar frustracao como conserto
   (heuristica 2), escrever a proposta no formato acima como novo `.md` em `memory/_proposals/`.
5. Atualizar o resumo do inbox com o que foi proposto e por que.
6. Atualizar o resumo do inbox. NUNCA tocar nucleo ou engine/.
7. CONFERE (AUTONOMIA SEM ESPERA HUMANA, instancia != autor): para cada `prop-*.md`, aplicar os
   4 crivos (Fundamentada, Nao-duplicata, Aditiva/SEGURA, Duravel) e resolver para um dos quatro
   outcomes: passou nos 4 -> `safe_auto` (carimbar `approved_by: <identidade do CONFERE>`);
   duvida nos crivos 1/2/4 -> `auto_promote_probation` (carimbar `approved_by`, `confidence: low`,
   `valid_until` +30 dias); reprova clara nos crivos 1/2/4 -> `auto_discard` (arquivar com
   `discard_reason`, nunca deletar); reprova no crivo 3 -> `route_to_rsi` (mover o candidato para
   `engine/rsi/_candidates/`). Nenhum desfecho espera confirmacao do operador.
8. Rodar `scripts/promote-memory.ps1 -ArchiveInbox` - promove as que tem `approved_by`
   (`safe_auto` e `auto_promote_probation`), move os `prop-*.md` para `memory/` (status: active,
   ou `confidence: low` + `valid_until` na probation) e arquiva os `reflection-inbox-*.md` ja
   julgados em `_archive/`. As `auto_discard` ja foram arquivadas no passo 7. Nunca deleta:
   promover preserva, arquivar move.

## Invariante

- O passo de REFLEXAO so propoe (status: proposed); nunca aplica; nunca deleta; nunca toca nucleo.
  A promocao e outro passo (CONFERE independente + promote-memory.ps1), nunca o mesmo agente.
- Autonomia total na promocao de memoria, sem espera humana: os 4 crivos resolvem sempre para
  `safe_auto`, `auto_promote_probation`, `auto_discard` ou `route_to_rsi`. Nucleo/engine/Gate
  continuam exigindo humano (`human_approval_for: [gate]`, `provenance: nucleo`) - e e por isso
  que o crivo 3 reprovado vira `route_to_rsi`, nunca memoria.
- Invariante novo (10/09/2026): nenhuma proposta termina a sessao parada esperando humano. O
  `human_card` deixou de existir para memoria.
- Captura o conserto, nao a reclamacao. Padrao duravel, nao incidente transitorio.
- Toda escrita: UTF-8 sem BOM,
- Disparo plugado (desde 1.1.0): digest no SessionEnd; julgamento lembrado no SessionStart
  (reflect-check.ps1); promocao apos CONFERE (promote-memory.ps1, approved_by). O loop fecha
  sozinho, nos quatro destinos.
