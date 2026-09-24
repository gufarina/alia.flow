# Mapa de LEIs 1.84 para a 2.0 (I0, condição 1 do Gate)

Laudo do Canon (papel só-leitura), salvo pela coordenação, TASK-801, 23/09/2026.

**Contagem [MEDIDO]:** grep `^\| L\d+ \|` em `engine/governance/law-ledger.md` = 87 ocorrências. Dessas, 78 leis distintas (L01 a L79, L63 nunca usado; Q01 é quarentena, não lei) e 9 duplicatas históricas na tabela "Poda executada" (L02, L03, L05, L07, L08, L14, L15, L16, L22). Os "83" do Nexus foram subcontagem.

**Resumo:** 78 leis. 70 com destino em módulo. 8 MORREM com motivo. 6 com mecanismo fraco listadas no fim.

| Lei | Resumo | Destino | Como |
|---|---|---|---|
| L01 | Artifact só sai do Gate aprovado | gate | contrato |
| L02 | 10 Princípios inconstitucionais | kernel | doutrina |
| L03 | Pergunta ao operador é último recurso | flow | contrato (risco, ordem do Operator) |
| L04 | RSI nunca toca núcleo | guard | negação 1 |
| L05 | Knowledge-first | context | doutrina |
| L06 | Claims Registry, veto não ressuscita | gate | critério |
| L07 | Escopo público vs interno | gate | critério |
| L08 | Reuse-first de ativos | context | doutrina |
| L09 | Loop declara 6 campos | flow | checklist de brief |
| L10 | Git é vitrine | release | check-public-surface |
| L11 | 6 critérios do Gate | gate | núcleo do módulo |
| L12 | 5 passos | flow | módulo inteiro |
| L13 | Linhagem de Task | memória | lineage-graph |
| L14 | Grounding com rótulo | gate | critério (response-guard morre) |
| L15 | Fonte de verdade duplicada | MORRE | já podada em 09/08 |
| L16 | Escalação em escada | MORRE | já virou orientação |
| L17 | Tasks paradas visíveis | proof | checagem cruzada |
| L18 | Squad Owner dono ativo | squad | doutrina |
| L19 | Especificação de Entrega | context | doutrina |
| L20 | Grafo pré-condição | MORRE | superada por L67 |
| L21 | Pesquisa segura, sem loop | flow | FRACA (ver fim) |
| L22 | Produto só produto | MORRE | já virou orientação |
| L23 | Raiz limpa (arquivo) | proof | prova |
| L24 | studio.example | MORRE | nunca se aplicou aqui |
| L25 | Marca fora do produto | release | check-public-surface |
| L26 | Mapa forjado não vale | memória | graph-check |
| L27 | Adoção do grafo medida | MORRE | graph-usage-sensor morre |
| L28 | Fato de memória nunca se apaga | memória | validade |
| L29 | Fronteira fato vs decisão | flow | função de risco |
| L30 | Formato de plano HTML | MORRE | check documental vai para auditoria |
| L31 | Resposta por decisão | MORRE | check documental vai para auditoria |
| L32 | Raiz limpa (pasta) | proof | prova |
| L33 | Especialista existe, usá-lo | guard | negação 4 |
| L34 | Revisão de release | release | package-release |
| L35 | Frugalidade dos loops | flow | FRACA, cost_class no budget |
| L36 | Escada da simplicidade | squad | FRACA (ver fim) |
| L37 | Reuse examples-driven | context | doutrina |
| L38 | Invariantes do Squad | squad | contrato parcial (gateway, I5) |
| L39 | Relatório de coordenação | flow | doutrina |
| L40 | Turno, Sessão, Task | ledger | vocabulário |
| L41 | Teto de delegação visual | ledger | budget + PostToolUse (I1) |
| L42 | Caçada de credencial | release | prova no pacote |
| L43 | Docs fecham a entrega | release | docs-check |
| L44 | Economia de token | context | doutrina |
| L45 | Guarda no ato | guard | negação 4 |
| L46 | Ritual de presença | kernel | FRACA (ver fim) |
| L47 | Segredos com auditoria | guard | negação 2 |
| L48 | Contrato do especialista, 4 campos | squad | gerador recusa sem os campos |
| L49 | Custo na Task | ledger | absorvida por L54 e L65 |
| L50 | Baseline do harness | proof | catraca |
| L51 | Núcleo em toda janela | kernel | AGENTS.md estático |
| L52 | Contrato do especialista, 6 campos | squad | contrato |
| L53 | Ficha de Project magra | flow | doutrina |
| L54 | Custo obrigatório no FECHA | ledger | contrato |
| L55 | Linhagem órfã | proof | prova |
| L56 | Ciclo de vida da Task | ledger | task-sweep |
| L57 | Capacidade com prova datada | gate | contrato |
| L58 | Memória promove sozinha | memória | Refletor e Curador (I8) |
| L59 | Acentuação da entrega | proof | prova |
| L60 | Leitura inteira negada | context | FRACA (ver fim) |
| L61 | Olho oficial, fonte única | proof | FRACA (ver fim) |
| L62 | Gate antes do push | release | prova |
| L64 | Teto de chamadas por especialista | ledger | MONITORA, corte em 3 vezes o budget |
| L65 | Task fecha com custo medido | ledger | contrato |
| L66 | Especialista só aciona leitor | guard | FRACA (ver fim) |
| L67 | Índice estrutural, grafo sob critério | memória | graph-check |
| L68 | Plano de etapas com diário | ledger | prova |
| L69 | Identidade de commit em allowlist | release | prova |
| L70 | Especialista nunca publica | guard | negação 3 |
| L71 | Wikilink quebrado é regressão | memória | memory-curator |
| L72 | Índice-mãe com teto | context | prova |
| L73 | Régua de alinhamento com gatilho | MORRE | vira função de risco em flow |
| L74 | Brief de delegação, 7 campos | flow | checklist de brief |
| L75 | Painel de desperdício sem LLM | proof | prova |
| L76 | Prova de Task fechada | ledger | contrato |
| L77 | Correção exige causa-raiz | ledger | contrato |
| L78 | Número público reprodutível | release | contrato |
| L79 | Veredito de gate por volta | gate | contrato |

## Leis com mecanismo fraco na 2.0 (risco real, Canon)

| Lei | Risco | Proposta da coordenação (Lattice confirma no fechamento da E5) |
|---|---|---|
| L21 pesquisa segura | nenhuma negação cobre agente de pesquisa se multiplicando | teto nativo do host: `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` e `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` no settings da 2.0 + `research_limits` na persona |
| L66 especialista só aciona leitor | sub-agente pode voltar a abrir sub-agente livre | a ferramenta Agent só no gerado com `gateway: true` (I5); folha sem Agent |
| L60 leitura inteira negada | troca de bloqueio duro por convenção | doutrina no context + a E6 mede leitura de arquivo acima de 350 linhas; se regredir, a negação volta no despachante (Read segue sem gancho enquanto não regredir) |
| L46 ritual de presença | ninguém confere a linha de status | doutrina no kernel; sem prova automática (aceito: é voz, não segurança) |
| L36 escada da simplicidade | sem dono de padrão de código | doutrina na persona do Specialist (squad) |
| L61 olho oficial | ativo de marca sem módulo | doutrina no release (check-public-surface já cobre marca fora do produto) |
