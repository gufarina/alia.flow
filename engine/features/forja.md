# Forja - a linha de producao autonoma da Alia

> Feature do motor. A Forja e a versao proprietaria do ADE (Autonomous Development Engine) do
> framework upstream de origem, redesenhada para o mundo Alia: squads-first, gate unico,
> frugalidade e advisor. Transforma pedido vago em Artifact entregue por um caminho PREVISIVEL
> de 5 estacoes, com recuperacao e memoria embutidas. Origem e atribuicao: dossie da dissecacao
> de 2026-07-07 (lab: opportunities/, dossie da origem; creditos em CREDITS.md).
> UTF-8 sem BOM.

---

## O problema que resolve

Hoje cada squad improvisa o caminho do pedido ate o codigo: a spec nasce em profundidade
imprevisivel, a execucao nao tem checkpoint de autocritica, a falha vira loop ad-hoc e o
aprendizado morre no chat. O upstream provou (ADE, "Production Ready") que dar FORMA fixa ao
caminho - spec, execucao, recuperacao, prova, memoria - reduz retrabalho e torna o autonomo
auditavel. A Forja traz essa forma sem trair as leis da casa: coordenador nao executa,
gate unico, profundidade segue irreversibilidade.

## As 5 estacoes

Pedido -> FUNDIR -> MOLDAR -> TEMPERAR (se falhar) -> PROVAR -> GUARDAR -> Artifact no operador.

### 1. FUNDIR (spec)

O pedido bruto vira SPEC com criterios verificaveis, em 5 passos encadeados:
grilling de requisitos -> avaliacao de complexidade -> pesquisa de dependencias -> escrita da
spec -> critica adversarial da spec. Dono: gateway do squad; architect entra como consultor na
avaliacao de complexidade. Saida obrigatoria: SPEC com aceite testavel. Pedido trivial
(reversivel, 1 arquivo) pode pular direto ao MOLDAR com spec de 3 linhas - a aposta calibra.
(ADE upstream: Spec Pipeline gather -> assess -> research -> write -> critique.)

### 2. MOLDAR (execucao)

A spec vira plano de subtasks; cada subtask roda no executor (tier standard) com DOIS
checkpoints de autocritica obrigatorios:

1. Depois de escrever, ANTES de considerar pronto: o executor rele o proprio diff em postura
   hostil (judgment-discipline) e corrige o que nao sustenta.
2. Depois dos testes, ANTES de fechar: confere se a evidencia de execucao existe e cobre o aceite.

Os checkpoints sao tambem os pontos naturais de CONSELHO do advisor-pattern: executor em duvida
de rumo consulta o tier strong (2-3x max) e segue. (ADE upstream: 13 steps do Coder com
self-critique nos steps 5.5 e 6.5 - reduzimos a 2 checkpoints por frugalidade; o resto dos
13 steps ja vive em story-cycle.md.)

### 3. TEMPERAR (recuperacao)

Falhou, esfria e tenta de novo - com registro. Toda tentativa falha vira REGISTRO DE TENTATIVA
(1 linha: abordagem, por que falhou). Ate 3 abordagens DIFERENTES (a lei anti-insistencia de
orchestration.md); na terceira falha, rollback do trabalho sujo (worktree/commit de recuo) e
escalada a Alia com os registros anexos - quem recebe a escalada ve o que JA foi tentado.
Stuck detection: mesma abordagem repetida = tentativa queimada, nao conta como nova.
(ADE upstream: Recovery System track -> retry<3 -> stuck -> rollback -> escalate.)

### 4. PROVAR (gate)

O Quality Gate unico da casa (governance/quality-gate.md, 6 criterios) - NAO as 10 fases fixas
do ADE. A profundidade dos passes de verificacao segue a irreversibilidade da entrega
(judgment-discipline): mudanca reversivel leva passes leves; migracao/publicacao leva a bateria
completa. Verdicts Pass/Concerns/Fail com evidencia; Fail entra no qa-loop (fix-on-fail).

Extensao da Forja para EVOLUCAO DE MOTOR (permitida pela regua - squads adicionam, nunca
removem): alem dos 6 minimos, toda mudanca de engine recebe duas notas na regua de vocabulario
da judgment-discipline (fraco/decente/forte/excelente):

| Nota | Pergunta |
|------|----------|
| **AS - Arquitetura de Solucao** | Fronteiras certas? Modulo fundo (interface estreita)? Reversivel? Nao duplica o que existe? |
| **NB - Negocio** | Qual dor de cliente, receita ou risco esta mudanca move? Em uma frase, com fonte |

Evolucao com NB fraco so passa com justificativa explicita do Operator registrada. Isso poe a
regua de "solidez de arquitetura e negocio" DENTRO do mecanismo, nao no discurso.

### 5. GUARDAR (memoria)

Antes de fechar, o executor captura o que a proxima Task pagaria para saber, em 4 tipos ja
mapeados aos memory-types (com TTL): INSIGHT (entendimento novo), PATTERN (padrao reutilizavel),
GOTCHA (armadilha que custou tempo), DECISION (decisao e por que). Zero captura tambem e
resposta valida - registro vazio declarado, nunca silencio. E o combustivel do RSI.
(ADE upstream: Memory Layer com os mesmos 4 tipos.)

## O bastao (o fio entre as estacoes)

Nenhuma estacao passa a conversa inteira adiante. A troca e um ARTEFATO DE BASTAO de ate 500
tokens: de quem para quem, a Task, max 5 decisoes tomadas, max 10 arquivos tocados, max 3
bloqueios, proximo passo em 2 frases, flag consumed. Quem entra recebe SO o proprio perfil + o
bastao. Cada estacao declara a proxima (cadeia), e o coordenador sugere o comando seguinte ao
agente que entra - o bastao nunca cai no chao entre gateway, especialista e QA.
(upstream: template de handoff <500 tokens + cadeias de workflow + sugestao no greeting.)

## O que a Forja NAO copia do ADE (decisoes de projeto)

| ADE upstream | Forja (por que diferente) |
|---|---|
| 12 agentes genericos com comandos novos | Squads-first: as estacoes sao PAPEIS do squad do cliente, nao agentes novos |
| 13 steps fixos do Coder | 2 checkpoints + advisor: mesmo efeito, fracao do peso (frugalidade) |
| QA Evolution em 10 fases fixas | Gate unico + passes por aposta: profundidade segue irreversibilidade |
| Worktree Manager proprio (Epic 1) | Worktree do harness (EnterWorktree/git) - nao reinventar |
| Formato autoClaude V3 (schema novo) | Contratos da casa: quality-gate.yaml, loops.catalog.yaml, squad manifest |

## Economia (por que o Operator aprova)

- Executor paga preco standard; o strong entra so no conselho e no julgamento.
- Registro de tentativa mata o retrabalho invisivel (a falha repetida e o token mais caro).
- Bastao compacto substitui handoff de transcript inteiro.
- A forma fixa permite medir: onde as Tasks morrem (qual estacao) vira metrica de RSI.

## Segue
[Orquestracao](../orchestration.md) - [Story Cycle](../workflows/story-cycle.md) -
[QA Loop](../workflows/qa-loop.md) - [Quality Gate](../governance/quality-gate.md) -
[Advisor Pattern](advisor-pattern.md) - [Disciplina de Julgamento](judgment-discipline.md) -
[Memory Types](../governance/memory-types.md)
