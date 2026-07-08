# Changelog - Alia Flow

Mudancas visiveis de cada versao publica do Alia Flow.
Formato baseado em Keep a Changelog. Versionamento semantico.

## [0.6.0] - 2026-07-07

MINOR - Forja: a linha de producao autonoma do Alia Flow (lab 1.22.0-1.23.3). Um pedido vago
percorre 5 estacoes previsiveis - FUNDIR (spec com aceite testavel e critica adversarial),
MOLDAR (execucao com dois checkpoints de autocritica), TEMPERAR (recuperacao com registro de
tentativa, ate 3 abordagens diferentes antes de escalar), PROVAR (o Quality Gate unico) e
GUARDAR (memoria em 4 tipos). Entre estacoes viaja um bastao de ate 500 tokens - quem entra
recebe so o proprio perfil e o bastao, nunca a conversa inteira. Evolucao de motor ganha duas
notas obrigatorias no gate: arquitetura de solucao e negocio. Redesenho proprio inspirado em
engines autonomos de mercado, adaptado ao modelo de squads e gate unico do Alia Flow.
- Novo: engine/features/forja.md
- Alterado: engine/MAP.md (Forja no indice de entrega)
- Correcao: scripts/git-sync.ps1 valida o repo antes de tocar em pasta (input malformado
  rejeitado antes de qualquer efeito de ambiente)

## [0.5.0] - 2026-07-07

MINOR - Guard de vetos + purge do "COO" (lab 1.21.0). O termo "COO" (identidade derrubada pelo
CEO) estava vivo em persona.md e orchestration.md - virou "braco direito"/coordenadora. O smoke
ganhou um GUARD que le os vetos de docs/CLAIMS.md e reprova se algum aparecer no motor: veto
ressuscitado = smoke vermelho. Molde do zero-aiox.
- Alterado: engine/agents/persona.md, engine/orchestration.md (sem "COO")
- Alterado: scripts/smoke-test.ps1 (guard de vetos), docs/CLAIMS.md (secao GUARD:)

## [0.4.0] - 2026-07-07

MINOR - Fonte de Verdade do Cliente (client-truth, lab 1.20.0): 4 leis que protegem a
documentacao do cliente e matam invencao na raiz. (1) Knowledge-first: hierarquia fixa de fonte
(decisao do Operator > BRAND/PRD/persona > docs internos > README/codigo), vetos respeitados,
decisao nova registrada na fonte na mesma Task. (2) Claims Registry: peca publica so afirma
numero/feature/tagline do registro curado do cliente; numero nunca se fabrica somando fontes;
feature so LANCADA. (3) Escopo publico vs interno: regra de operacao nao vaza pra peca publica.
(4) Reuse-first de ativos: inventario da marca antes de criar; efeito proprietario se replica.
Reforcos: coordenador nao produz dominio (gatilho explicito) e briefing de delegacao com travas.
- Novo: engine/governance/client-truth.md
- Alterado: engine/orchestration.md (LEI no DELEGA)
- Alterado: engine/governance/quality-gate.md (criterios extras obrigatorios pra PECA PUBLICA)

## [0.3.0] - 2026-07-06

MINOR - Disciplina de Julgamento: as tecnicas do manual de julgamento dos modelos de fronteira
(Fable/Claude 5) destiladas em doutrina do motor e mapeadas ao fluxo agentico. O agente e um
motor de julgamento, nao um gerador de texto: todo pedido e um proxy da decisao por tras dele.
- Novo: engine/features/judgment-discipline.md - as 3 leituras do pedido (literal/intencional/
  adversarial), as 5 caixas + pedra-chave na decomposicao, um rival serio por conclusao,
  proveniencia de afirmacao (dada/derivada/lembrada), os 5 passes de verificacao (extracao,
  aritmetica, siga-a-premissa, leitura hostil, contraexemplo), destino-primeiro na comunicacao,
  auto-revisao modo rapido/profundo, 12 heuristicas de bolso e a regua fraco/decente/forte/excelente
- Alterado: engine/orchestration.md (bloco apos os 5 passos: como cada passo pensa)
- Alterado: engine/agents/persona-skeleton.md (secao Qualidade: modo rapido obrigatorio antes de
  todo Artifact, rival por conclusao, lacuna nomeada)
- Alterado: engine/governance/quality-gate.md (secao Postura do avaliador: verificar em postura
  diferente da que gerou)

## [0.2.0] - 2026-07-06

MINOR - Advisor Pattern: cerebro forte aconselha, cerebro rapido executa. Baseado na advisor tool
da Anthropic (beta advisor-tool-2026-03-01). Um especialista rodando em modelo barato/rapido
(Sonnet/Haiku) agora pode consultar o tier forte (Opus) no meio da tarefa - ate 3 vezes, em
checkpoints medidos (apos orientacao; apos escrita/testes) - e receber um plano ou correcao de
rumo curto, sem parar a tarefa e sem escalar. Resultado do padrao original medido pela Anthropic:
qualidade proxima do modelo forte, pagando preco do modelo barato na maior parte dos tokens.
- Novo: engine/features/advisor-pattern.md (doutrina completa, Forma A nativa no harness + Forma B via API)
- Alterado: engine/agents/model-matrix.yaml (secao advisor: pareamentos, teto de consultas, checkpoints)
- Alterado: engine/orchestration.md (item 5 da doutrina de delegacao: conselho nao e escalacao, nao substitui o Gate)

## [0.1.0] - 2026-07-03

Primeiro beta publico. O Alia Flow e um arnes de operador que voce roda dentro do seu
proprio coding agent (Claude Code, Codex ou OpenCode): a Alia recebe o trabalho em
linguagem comum, escolhe o especialista certo, roda um loop de qualidade e so entrega o
que passou pela conferencia.

O que ja funciona neste beta:
- **Instalacao de uma linha.** Sem git, sem Python - so o PowerShell do Windows. Abre a
  pagina de boas-vindas sozinha e voce diz "pronto".
- **Cliente > Projeto > Tarefa com rastreabilidade.** Todo pedido vira uma tarefa
  registrada, com de onde partiu e o que produziu. Nada se perde entre sessoes; a Alia le
  o historico antes de agir e continua de onde parou.
- **Times por cliente (squads).** Cada cliente ganha um time de especialistas com um dono
  ativo (Squad Owner) que faz a roda girar, e um segundo cerebro (memoria + grafo do
  conhecimento) que mantem a consistencia das entregas.
- **Quality Gate.** Nenhuma entrega sai crua: passa por uma conferencia (funciona, usa a
  linguagem do cliente, e frugal, e rastreavel) antes de chegar a voce.
- **Especificacao de entrega por cliente.** Regras objetivas de design/formato/tom para
  que todas as pecas saiam coerentes.
- **Mission Control.** Um painel que mostra o que foi feito e destaca o que empacou -
  tarefas paradas ganham atencao.
- **Provado por teste.** Um conjunto de verificacoes deterministicas (o smoke test) roda
  sem IA e sai ALL GREEN; inclui a prova de ablacao (a memoria muda o resultado, 0/5 para
  5/5), que voce roda na sua maquina.

Pre-requisito: um coding agent. A Alia mora dentro de um deles.
- Claude Code: https://claude.com/claude-code
- Codex: https://github.com/openai/codex
- OpenCode: https://opencode.ai

Licenca MIT.
