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
- NAO promove sem aprovacao independente: a promocao para `memory/` (canonico) so ocorre com
  `approved_by` carimbado por uma instancia != quem propos, executada por
  `scripts/promote-memory.ps1`. O CONFERE (AUTONOMIA COM FREIO) auto-aprova o que passa nos 4 crivos
  (SEGURA_AUTO) e ESCALA para o cartao S/N do operador o que falha ou gera duvida. Autonomia SO na
  promocao de memoria; nucleo/engine/Gate continuam exigindo humano.

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

### 4. SEMPRE so PROPOE

Toda saida vai para `memory/_proposals/` como proposta. Nada e escrito na memoria real do
operador. O operador le as propostas e aprova (ou nao). O sistema propoe; quem aplica e gente
(provenance.md: agent-authored sai como diff; quem aprova e o operador).

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
4. CONFERE independente (AUTONOMIA COM FREIO, abaixo): uma instancia != quem propos triagem
   cada proposta pelos 4 crivos -> SEGURA_AUTO carimba `approved_by` e auto-promove; ESCALA_HUMANO
   mostra o cartao S/N ao operador so no que ficou arriscado ou duvidoso.
5. `promote-memory.ps1 -ArchiveInbox`: move as aprovadas (as carimbadas com `approved_by`) para
   `memory/` e arquiva os inboxes julgados.

## Protocolo de dialogo (teste da mae - decisao do CEO, 02/jul)

Todo este ciclo e BASTIDOR. A regra dura de linguagem da persona (persona.md: jargao PROIBIDO
para o usuario; o loop fica nos bastidores) manda aqui tambem - e o gatilho nao a atropela:

- QUANDO: o julgamento roda DEPOIS de atender o pedido do operador (ou num momento morto do
  trabalho), nunca como abertura da sessao. A primeira fala da Alia e sobre o pedido DELE.
  Adiar dentro da sessao pode; pular nao - o processamento continua obrigatorio na sessao,
  e a prova da instancia FALHA se aprendizado ficar parado > 3 dias (a trava de maquina).
- COMO SE FALA: nao se anuncia ("vou fechar o loop de RSI" e violacao), nao se narra, nao se
  usa RSI/digest/inbox/promocao/cartao na conversa. Se TUDO passou no CONFERE (SEGURA_AUTO),
  o operador nem fica sabendo - a evidencia e a memoria melhor.
- ESCALA_HUMANO vira UMA pergunta simples em linguagem de negocio, encaixada no fim de uma
  resposta: "Da ultima vez anotei que [licao em palavras do dia a dia]. Guardo isso pra valer
  daqui pra frente?" Nunca um bloco tecnico de aprovacao.
- Teste da mae: se a mae do operador nao entenderia a frase, a frase nao sai.

## AUTONOMIA COM FREIO (o CONFERE que fecha o loop sem pedir OK item-a-item)

Decisao do CEO (30/jun): no fechamento do loop, a Alia NAO deve pedir cartao S/N item-a-item ao
operador. Pedir aprovacao em bloco vira ruido, o operador ignora, e o loop apodrece (era o furo do
OPP-53). O freio nao e o operador clicar em tudo - o freio e um CONFERE INDEPENDENTE que separa o
que promove sozinho do que sobe pro humano.

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

Desfecho:

- Passou nos 4 -> **SEGURA_AUTO**: o CONFERE carimba `approved_by:` no frontmatter com a SUA
  identidade (a instancia que conferiu, != autor) e a proposta e auto-promovida por
  `promote-memory.ps1`. O operador nao e interrompido pelo seguro.
- Falhou QUALQUER crivo, OU o CONFERE ficou em duvida -> **ESCALA_HUMANO**: a proposta NAO recebe
  `approved_by` (o script a mantem BLOQUEADA em staging) e entra no cartao S/N que a Alia mostra ao
  operador. So o arriscado/duvidoso rouba a atencao dele.

### Fronteira dura (nao afrouxar)

Esta autonomia vale SO para promocao de MEMORIA (`prop-*.md` -> `memory/`, notas
`user|feedback|project|reference`). Qualquer mudanca em engine/nucleo/constituicao/Gate continua
exigindo humano: e `provenance: nucleo` (bloqueio duro, provenance.yaml `block_when`) e, para o
Gate, `human_approval_for: [gate]` no `rsi.yaml`. O crivo 3 (Aditiva/SEGURA) ja reprova para
ESCALA_HUMANO qualquer proposta que tente tocar essa fronteira - o CONFERE nunca a atravessa
sozinho. A politica machine-checkable esta em `engine/rsi/rsi.yaml` -> `memory_promotion_policy`.

## Procedimento do agente (passo a passo)

1. Rodar `scripts/session-reflection.ps1` (sem DryRun) para gerar o digest no inbox.
2. Ler `memory/_proposals/reflection-inbox-{data}.md`.
3. Para cada item do digest, decidir: descartar (lista anti-captura) ou capturar.
4. Para cada item capturado: classificar (heuristica 1), tratar frustracao como conserto
   (heuristica 2), escrever a proposta no formato acima como novo `.md` em `memory/_proposals/`.
5. Atualizar o resumo do inbox com o que foi proposto e por que.
6. Atualizar o resumo do inbox. NUNCA tocar nucleo ou engine/.
7. CONFERE (AUTONOMIA COM FREIO, instancia != autor): para cada `prop-*.md`, aplicar os 4 crivos
   (Fundamentada, Nao-duplicata, Aditiva/SEGURA, Duravel). Passou nos 4 -> SEGURA_AUTO: carimbar
   `approved_by: <identidade do CONFERE>` no frontmatter. Falhou algum crivo OU duvida ->
   ESCALA_HUMANO: NAO carimbar; juntar no cartao S/N e mostrar ao operador so essas.
8. Rodar `scripts/promote-memory.ps1 -ArchiveInbox` - promove as que tem `approved_by` (SEGURA_AUTO
   + as que o operador aprovou no cartao), move os `prop-*.md` para `memory/` (status: active) e
   arquiva os `reflection-inbox-*.md` ja julgados em `_archive/`. As sem `approved_by` ficam
   BLOQUEADAS em staging (o script sinaliza). Nunca deleta: promover preserva, arquivar move.

## Invariante

- O passo de REFLEXAO so propoe (status: proposed); nunca aplica; nunca deleta; nunca toca nucleo.
  A promocao e outro passo (CONFERE independente + promote-memory.ps1), nunca o mesmo agente.
- Autonomia SO na promocao de memoria (SEGURA_AUTO nos 4 crivos). Nucleo/engine/Gate = humano.
- Captura o conserto, nao a reclamacao. Padrao duravel, nao incidente transitorio.
- Toda escrita: UTF-8 sem BOM,
- Disparo plugado (desde 1.1.0): digest no SessionEnd; julgamento lembrado no SessionStart
  (reflect-check.ps1); promocao apos CONFERE (promote-memory.ps1, approved_by). O loop fecha.
