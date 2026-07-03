# Alia - Linguagem Ubiqua (Glossario)

> Os termos abaixo sao os **unicos** aceitos em documentacao, codigo e testes do Alia.
> Inventar sinonimos causa drift semantico no LLM - e anti-pattern. Sem acentos, sem emojis.

| Termo | Definicao | Contexto |
|-------|-----------|----------|
| **Alia Flow** | O produto/framework: o sistema de orquestracao por IA como um todo. | Orchestration |
| **Alia** | A orquestradora central; a interface unica com o operador. Coordena, nunca executa. | Orchestration |
| **Operator** | O humano que delega trabalho e e dono do resultado. | Orchestration |
| **Studio** | O espaco de trabalho do operador (sua agencia). Tem nome parametrizavel. | Orchestration |
| **Client** | Entidade para quem o trabalho e feito (pode ser o proprio operador). | Orchestration |
| **Project** | Agrupador de Tasks sob um Client. | Delivery |
| **Task** | Unidade atomica de trabalho, com estado e evidencia. | Delivery |
| **Artifact** | A prova de que uma Task foi concluida (arquivo, URL, commit). | Delivery |
| **Squad** | Time dinamico de especialistas montado para um Client. | Squads & Expertise |
| **Squad Owner** | O coordenador do squad (Gateway). Roteia e revisa o time diretamente (Tier 1). Coordena, nunca executa. | Governance |
| **Gateway** | O papel de lider de um Squad; sinonimo operacional de Squad Owner. Sempre tem segundo cerebro completo (Camada A). | Governance |
| **Specialist** | Agente com conhecimento profundo (DDD) de um dominio. | Squads & Expertise |
| **Capability Routing** | Escolher o agente MAIS CAPAZ de uma tarefa - por Domain Pack, Expert Mind e Memory -, nao um especialista qualquer. O nucleo da Delegation First. | Orchestration |
| **Domain Pack** | Conhecimento DDD que torna um Specialist expert num dominio. | Squads & Expertise |
| **Expert Mind** | Metodo de um mestre (publico e documentado) carregado no segundo cerebro de um Specialist (Camada B). | Squads & Expertise |
| **Gate** | Ponto de verificacao de qualidade que bloqueia entregas ruins. | Quality |
| **Memory** | Conhecimento retido: grafo + notas navegaveis. | Knowledge & Memory |
| **Loop** | Ciclo de feedback que alimenta o RSI. | Self-Improvement |
| **RSI** | Recursive Self Improvement - o sistema melhora a si mesmo a cada Loop. | Self-Improvement |
| **Budget** | Limite/meta de tokens de uma operacao. | (transversal) |
| **Frugality Check** | Auto-questionamento de custo antes de agir. | (transversal) |
| **Alia (produto)** | O produto open source CLEAN: engine, scripts, skills, onboarding, optional-mcps e a Studio-modelo. Nunca contem dado do operador. | Contexto Produto (CLEAN) |
| **Contexto Produto (CLEAN)** | O bounded context do produto Alia: tudo que viaja open source, sem dado de operador nem marketing/comercial de ninguem. | Contexto Produto (CLEAN) |
| **Instancia aplicada** | A instalacao privada do produto (a pasta de dados do operador, definida em alia.config.json): a operacao real, os clientes reais e o material de marca/marketing do operador. | Contexto Operador |
| **Contexto Operador** | O bounded context da instancia aplicada: dados, clientes, squads e go-to-market do operador. Privado, fora do open source. | Contexto Operador |
| **studio.example** | A Studio-modelo limpa de referencia que viaja com o produto (so o demo acme-saas). Nunca contem dado real de operador. | Contexto Produto (CLEAN) |

---

*Alia - Delegue. Nao opere.*
