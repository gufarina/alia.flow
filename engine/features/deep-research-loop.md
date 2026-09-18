# Deep Research Loop (segundo cerebro vivo)

> O loop que mantem o segundo cerebro dos Specialists atualizado por pesquisa do estado-da-arte.
> "Deep research" aqui = pesquisa PROFUNDA de dominio, NAO a ferramenta deep_research do Perplexity
> (essa e proibida - ver [Pesquisa Segura](../tools.md)). E o RSI alimentado de fora: para os
> dominios ativos de velocidade alta, o Specialist fica mais inteligente sem virar enxame nem loop.
> Receitado por projeto pela Alia via o [Loop Designer](loop-designer.md).

---

## O que e

Para cada dominio ativo de velocidade alta, o loop pesquisa o que mudou no estado-da-arte (frameworks
novos, tendencias, melhores praticas) e grava o resultado, datado e COM FONTE, no knowledge do
Specialist daquele dominio. O segundo cerebro deixa de ser foto fixa e passa a ter pulso. Quem roda e
o Specialist de pesquisa (ex: o RSI Researcher), sob a [LEI de Pesquisa Segura](../tools.md):
sequencial, sem auto-spawn, sem fan-out cego.

## Como funciona

1. Le os dominios ATIVOS do projeto. Dominio inativo ou de velocidade baixa nao entra - frugalidade.
2. Para cada dominio, UMA consulta por vez: Perplexity em busca normal (modelo padrao Sonnet 4.6 com
   thinking; JAMAIS Sonar, JAMAIS deep research). NotebookLM quando a Perplexity nao der conta.
3. Grava o resultado, datado e com citacao, no segundo cerebro do Specialist.
4. Sinaliza as mudancas relevantes para revisao. Nunca aplica cego: o RSI propoe, o Quality Gate
   aprova. A pesquisa entra como insumo, nao como verdade automatica.

## Governanca (criar, gerenciar, revisar - lei do operador)

- Dono: Alia (Tier 2); executa o Specialist de pesquisa.
- Cadencia: SOB DEMANDA (corte 10/08/2026 - mandato do CEO: agente-driven custa modelo e nunca
  teve freio de orcamento real em producao, entao nao entra mais na selecao automatica R5/R6 do
  Loop Designer). A Alia aciona quando o operador pede pesquisa de dominio; dominio rapido pesa
  mais na PRIORIDADE do pedido, nao vira mais cadencia diaria automatica no loops.yaml.
- Custo: usa a sessao Pro do Perplexity (busca normal, sem credito de API). `cost_class: medio`.
  Frugal por construcao - so dominios ativos e rapidos, uma consulta por vez, nunca o squad inteiro.
- Revisao: no `review_on`, a Alia audita se as pesquisas agregaram (via `last_result`). Se nao,
  reduz a cadencia ou aposenta o loop.

## Mecanismo

- Mecanismo: AGENTE-DRIVEN. A Alia sugere proativamente rodar quando devido (opt-in) e o Specialist
  de pesquisa busca via o MCP do Perplexity (Sonnet 4.6 com thinking; jamais Sonar nem deep research).
  O operador nunca roda script na mao.
- O script legado `scripts/deep-research.ps1` foi APOSENTADO (`scripts/_retired/`): usava `pwm research`
  (deep research), que a Pesquisa Segura proibe. A pesquisa agora e do agente, via MCP.
- Instanciacao: registrado em `clients/{id}/loops.yaml` pelo Loop Designer (mechanism = agente-driven,
  fora do Task Scheduler).

## Liga com

[Loop Designer](loop-designer.md) (quem receita este loop) - [Pesquisa Segura](../tools.md) (a LEI
anti-runaway + modelo padrao) - [Expert Minds](expert-minds.md) (o que o loop mantem atualizado) -
[Governanca / Loops](../governance/loops.md) (catalogo e ciclo de vida) - [RSI](../rsi/rsi.md).
