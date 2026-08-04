# Changelog - Alia Flow

Todas as mudancas relevantes do motor (engine) sao registradas aqui.
Formato baseado em Keep a Changelog. Versionamento semantico adaptado ao produto.
Sem acentos, sem emojis (regra do CEO).

## Esquema de versao (o contrato de update)

`MAJOR.MINOR.PATCH`

- PATCH (0.1.x): correcao de doc, adicao modular pequena, scaffolding. NAO muda contrato de
  orquestracao nem a constituicao. Smoke verde obrigatorio.
- MINOR (0.x.0): nova feature/cluster de OPP, retrocompativel. Smoke verde + teste na instancia aplicada.
- MAJOR (x.0.0): mudanca que quebra contrato (constitution, glossario, schema de loops/squads).

Regra de ouro (modularidade): cada OPP do backlog vira UM incremento de versao auto-contido,
testado na instancia viva (a instancia aplicada) antes de fechar. Um update = uma mudanca isolavel e
reversivel. Fluxo: alterar engine -> bump VERSION -> entrada no CHANGELOG -> smoke-test-studio
ALL GREEN -> tag.

---

## [1.42.4] - 2026-08-03

PATCH - Ultima ponta do conserto de ativacao da v1.42.3: os GUIAS ainda ensinavam o caminho
antigo. `README.md` (a frase "abriu a pasta no seu agente, virou a Alia" nao dizia COMO isso
acontece no Claude Code hoje) e `docs/COMPATIBILIDADE.md` (intro + linha da tabela do Claude Code
ainda diziam "boot via AGENTS.md" sem citar o `CLAUDE.md`) foram corrigidos para nomear o
mecanismo real: no Claude Code a porta e `CLAUDE.md` (que importa `@AGENTS.md`) + o comando
`/alia` como rede de seguranca; nos demais agentes (Codex, OpenCode, Aider) o boot continua sendo
o proprio `AGENTS.md`, lido direto. `PRIMEIROS-PASSOS.md` foi conferido e ja tinha a rede de
seguranca do `/alia` no passo 3 desde a v1.42.3 - nenhuma mudanca necessaria la. Nenhum claim
anunciavel novo entrou (mesma feature, descrita com precisao); `docs/CLAIMS.md` nao ganhou linha
nova de feature. Divida do GUARD-NUM fechada: o check comparava o numero do CLAIMS.md contra uma
CONTAGEM DE LINHAS `Check` no codigo-fonte (178), que divergia do total real de execucoes (179)
porque 3 blocos de guard de veto chamam `Check` dentro de um `foreach`. Corrigido para medir o
que o smoke REALMENTE executa: o bloco GUARD-NUM em `scripts/smoke-test.ps1` foi movido pra ser,
de proposito, o ULTIMO `Check` do arquivo (trocou de lugar com o bloco de drift de versao, que so
usa `Warn`), entao `$script:pass + $script:fail + 1` no momento em que ele roda e exatamente o
total que a linha final "Checks: X PASS, Y FAIL" vai reportar - medicao, nao aproximacao.
`docs/CLAIMS.md` atualizado para GUARD-NUM=179 com a fonte remedida. Smoke ALL GREEN (179 PASS,
0 FAIL).

## [1.42.3] - 2026-08-03

PATCH - Bloqueador de release consertado: o produto nao ligava. Medido nesta sessao rodando
Claude Code na raiz do studio-farina (que TEM AGENTS.md): o AGENTS.md nao apareceu no contexto.
Confirmado contra a doc oficial (code.claude.com/docs/en/memory, secao "AGENTS.md", checado
03/ago): Claude Code le CLAUDE.md, NAO AGENTS.md - quem instalasse o produto e abrisse a pasta
no Claude Code recebia um agente generico, nunca a Alia. AGENTS.md continua sendo a fonte da
identidade e o boot neutro de fornecedor (Codex, OpenCode, Aider leem ele direto); nasceu
`CLAUDE.md` na raiz da oficina cuja unica funcao e ser a porta que o Claude Code de fato abre -
ele so importa `@AGENTS.md` (a doc recomenda import por @ em vez de symlink no Windows, porque
symlink exige Administrador ou Developer Mode). Nasceu tambem o comando `/alia`
(`.claude/commands/alia.md`), rede de seguranca que recarrega AGENTS.md e o nucleo e se
apresenta pelo Ritual de presenca ja definido em engine/agents/persona.md (reusado, nao
inventado), para o caso do boot automatico nao pegar. `scripts/package-release.ps1` agora leva
`CLAUDE.md` no ship list (a pasta `.claude/` ja ia inteira desde a v1.42.2, entao o comando
`/alia` viaja junto sem mudanca extra). `PRIMEIROS-PASSOS.md` ganhou a mesma rede de seguranca em
linguagem de nao-tecnico no passo 3. O guard que impede a reincidencia: `scripts/smoke-test.ps1`
ganhou a secao "Ativacao" (6 checks nao acopla so no ship-list-como-string; como o `$root` do
proprio smoke e dinamico, os mesmos checks rodam de novo DENTRO do pacote quando
`package-release.ps1` chama o smoke do output, provando que os arquivos de ativacao chegaram no
pacote de verdade). GUARD-NUM subiu de 172 para 178 (docs/CLAIMS.md atualizado, cadeado intacto).

## [1.42.2] - 2026-08-03

PATCH - Engenharia de release: 3 defeitos medidos antes de publicar (auditoria pre-release do
CEO). (1) `scripts/package-release.ps1` copiava `docs/` inteira para o pacote publico (so com
excecao de `_retired/_dev/_drafts/product` via robocopy /XD); isso vazava doc do arquivo de
edicao (CLAIMS.md, RELEASE-STATUS.md, brand/*) direto pro que o usuario final baixa - exatamente
o que a LEI da superficie publica proibe. Trocado por ALLOWLIST explicita de docs/ (README.md,
COMPATIBILIDADE.md, INTEGRIDADE.md - o criterio: "isto serve a quem instala o produto?"); docs/
saiu de $shipDirs, BRAND.md/DESIGN.md nao precisam mais de remocao pos-copia (nunca sao copiados),
e a validacao 3/3 ganhou defesa em profundidade pra docs/product, docs/brand, docs/CLAIMS.md,
docs/BRAND.md, docs/DESIGN.md, docs/RELEASE-STATUS.md. (2) `scripts/smoke-test.ps1` (o smoke que
VAI NO PACOTE) tinha dois pontos que dependiam de `docs/CLAIMS.md` existir - um Check com `else`
que reprovava (FAIL) quando o arquivo faltava, e um segundo bloco (GUARD-NUM) que lia o arquivo
sem checar existencia, o que lancava excecao nao tratada e DERRUBAVA o script inteiro. Como
CLAIMS.md e doc interno (nunca viaja no pacote/repo publico, esta no .gitignore de la por LEI),
quem clonasse o repo publico via git rodava o smoke e via FAIL ou crash - falso alarme, nao
defeito real. Os dois pontos agora degradam com honestidade: `Warn` (aviso, nunca reprova o
smoke) em vez de FAIL silencioso ou PASS falso, com Test-Path antes de qualquer leitura. (3)
`CREDITS.md`: a atribuicao do framework-base citava soh "aiox" sem nomear a empresa (SynkraAI
Inc.) nem linkar o repo (github.com/SynkraAI/aiox-core), enquanto BMAD-METHOD ja tinha atribuicao
completa (org + link). Corrigido para citar a linhagem completa (BMad Method -> aiox-core -> Alia
Flow), a entidade legal de cada base (BMad Code LLC e SynkraAI Inc., confirmado contra a LICENSE
real do aiox-core em Projetos/aios/_aiox-core-origin/LICENSE) e a nota de marca registrada (nao
usamos "BMad"/"BMad Method"/"BMad Core" como marca nossa). LICENSE em si nao mudou (mecanica
reescrita, nao copia literal - nao exige a clausula de dupla atribuicao do MIT do aiox-core).

## [1.42.1] - 2026-08-03

PATCH - Exclusao pontual no guard de termo legado (secao g do smoke da instancia), motivada por
um artefato real caindo no scan: `clients/farina/artifacts/auditoria-delegacao-2026-08-03.html`,
um painel executivo interno produzido para o CEO que narra a absorcao do aiox (assunto que o
proprio CREDITS.md ja credita abertamente). scripts/smoke-test-studio.ps1 (secao g) ganhou a
exclusao `clients/*/artifacts/` na mesma classe das ja isentas opportunities/, research/ e
_proposals/: por LEI (raiz CLAUDE.md, "git e vitrine, nao gaveta") material de cliente
(paineis, decks, relatorios em clients/*/artifacts/) nunca e versionado, entao nao faz sentido
policiar termo legado nele. O guard continua protegendo o que de fato faz ship: engine/, skills/,
docs de produto (com a mesma isencao ja existente de atribuicao em CREDITS.md/README.md/
CHANGELOG.md/PRD.md/ARQUITETURA.md) e todo o resto do espelho. A secao (f) de encoding (0xFFFD)
NAO foi alterada e continua cobrindo os artefatos normalmente - so o scan de "aiox" filtra.

## [1.42.0] - 2026-08-03

MINOR - Cluster de enforcement na PORTA DE SAIDA da resposta (incidente 03/ago). A coordenadora
produziu artefato de dominio sem delegar dentro da propria sessao que estava fechando o OPP-74 (o
cluster anterior, que ja tinha posto o guard na ENTRADA do pedido). Causa-raiz: o enforcement da
lei DELEGA morava so na entrada (delegation-guard.ps1, so lembra, nunca verifica) e no fim da
sessao (session-reflection.ps1, captura aprendizado depois que ja aconteceu); nao havia guarda
nenhuma no momento em que a RESPOSTA de fato sai para o operador. O incentivo por tras e invertido:
tratar "delegar pro especialista" como operacao cara (mais um turno, mais latencia) faz a
coordenadora executar direto quando ninguem esta olhando - exatamente o padrao que derrubou o veto
COO ate virar guard de maquina. Cinco entregas:
(1) M1 O FREIO: scripts/response-guard.ps1 (hook de Stop) roda a CADA turno sobre o transcript
real, com 2 regras deterministicas - REGRA 1 (DELEGA): Write/Edit/NotebookEdit em clients/... sem
nenhuma chamada de Agent/Task no turno; REGRA 2 (GROUNDING): 3+ afirmacoes de peso (arquivo por
extensao ou padrao arquivo:linha) na resposta final sem rotulo [MEDIDO]/[INFERIDO]/[LIDO]. Modo
aviso (nunca bloqueia, so grava studio/response-guard-log.jsonl) ate uma semana de log provar
aderencia - migrar pra bloqueio e decisao do CEO. engine/governance/response-guard.yaml (mode:
aviso) + engine/governance/response-guard.md (doutrina completa); .claude/settings.json ganhou o
hook Stop.
(2) M2 TAXONOMIA: engine/agents/alia.yaml (routing.lenses) virou a fonte unica das lentes do
motor - constitution.md, orchestration.md, constitution.yaml e alia.md pararam de duplicar a
lista e passaram a apontar pra ca. Lente nova "engenharia-de-agente" (engenharia de prompt, de
contexto, design de persona e desenho de fluxo agentico do proprio motor) resolve pro arquetipo
novo engine/agents/agent-engineer.md + .yaml.
(3) M3 LEDGER: scripts/register-task.ps1 perdeu o default "alia" de -Specialist - quem executou
tem que estar declarado sempre (a lei DELEGA nao tolera mais valor silencioso). Valida NO ATO do
registro contra o squad.yaml do Client; sem squad.yaml vira AVISO, nao trava. Novo switch
-OperatorOrder e a UNICA forma legitima de registrar "alia" como executora (ordem explicita do
Operator), gravando operator_order:true - a excecao vira auditavel em vez de silenciosa.
(4) M4 LEI: engine/governance/law-ledger.md registra as 25 leis do motor (16 COBERTA por teste, 9
SEM TESTE - divida visivel, nao mais prosa sem guarda). Regra de formacao: lei nova so entra com
teste citado na mesma Task que a declara, ou nasce marcada SEM TESTE. Uma frase no criterio 1 de
engine/governance/quality-gate.md + o campo law_change_requires_ledger_entry no .yaml amarram o
Gate a essa regra.
(5) M5 RELEASE: docs/CLAIMS.md corrigido (numero de verificacoes com marca GUARD-NUM, claim de
ablacao rebaixado pra ILUSTRATIVA), docs/product/PRD.md corrigido, novo docs/RELEASE-STATUS.md e
o README da pasta knowledge-ablation.
Smoke ganhou 12 checks novos cobrindo os 5 movimentos (161 -> 173 verificacoes; GUARD-NUM
atualizado em docs/CLAIMS.md), incluindo a regra de ouro do proprio M1: o check do hook Stop prova
que esta LIGADO em .claude/settings.json, nao so que o arquivo existe no disco -
"projetado-mas-desligado" reprova. Baseline do nucleo (engine/.core-baseline.sha256) reassinado
com -AllowCore: constitution.md e orchestration.md mudaram de hash de forma legitima (M2 trocou a
lista duplicada de lentes por ponteiro pra alia.yaml).
ABERTO (decisao do CEO): migrar response-guard de aviso pra bloqueio depois de uma semana de log;
podar ou testar as 9 leis SEM TESTE do law-ledger; publicar este release (package-release.ps1 /
update-engine.ps1 / git-sync.ps1 seguem manuais, fora do escopo deste cluster).
- Novo: scripts/response-guard.ps1, engine/governance/response-guard.yaml,
  engine/governance/response-guard.md, engine/agents/agent-engineer.md,
  engine/agents/agent-engineer.yaml, engine/governance/law-ledger.md, docs/RELEASE-STATUS.md.
- Mudou: .claude/settings.json (hook Stop), engine/agents/alia.yaml (lente
  engenharia-de-agente), engine/constitution.md, engine/constitution.yaml,
  engine/orchestration.md, engine/agents/alia.md (pointers pra alia.yaml), scripts/register-task.ps1
  (-Specialist obrigatorio + -OperatorOrder), engine/governance/quality-gate.md +
  quality-gate.yaml (law_change_requires_ledger_entry), docs/CLAIMS.md, docs/product/PRD.md,
  scripts/smoke-test.ps1 (12 checks novos + conserto do teste rtPesq), engine/.core-baseline.sha256
  (reassinado com -AllowCore).

## [1.41.0] - 2026-08-02

MINOR - Enforcement de delegacao no ponto de decisao (OPP-74). Incidente recorrente flagrado
pelo CEO em 02/ago (mOS): a Alia ia mapear codigo do cliente na mao com grafo pronto, e ia
executar auditoria de dominio em vez de delegar. Causa-raiz: a lei DELEGA morava so em prosa
de boot (persona/orchestration) e dilui em sessao longa - mesmo padrao do veto COO, que so
parou de reincidir quando virou guard de maquina. Tres entregas:
(1) scripts/delegation-guard.ps1 - hook de UserPromptSubmit que re-injeta a lei a cada pedido
do operador, no loop principal (nunca nos especialistas delegados): DELEGA ao especialista +
fonte curada/grafo antes de varredura. Curto, nunca bloqueia (exit 0 sempre).
(2) Hook LIGADO em .claude/settings.json - e nao so projetado; o furo "projetado != ligado" ja
tinha derrubado o lembrete de grafo (a rule do studio afirmava um hook de PreToolUse que nunca
existiu no settings).
(3) Guard no smoke: reprova se o script sumir ou se o hook estiver desligado do settings.json.
Enforcement fail-closed por tool segue pendente do tool-registry (OPP-39, fora de escopo).

## [1.40.0] - 2026-08-02

MINOR - Cluster da narrativa definitiva + blindagem da superficie publica (TASK-011 a 017). A
marca tinha voz, mas nao tinha FONTE: cada peca recunhava heroi, dor e claim do zero, e veto
derrubado sobrevivia em arquivo publico porque nenhum teste olhava para fora do motor. Sete
entregas:
(1) Narrativa definitiva em docs/brand/: BRANDSCRIPT.md (StoryBrand 7 completo, com o heroi
corrigido para "quem nao e tecnico e quer entrar no mundo da IA", mais o vocabulario da marca e as
cenas padrao-ouro), ASSETS-VERBAIS.md (copy pronta por superficie: taglines, headlines por nivel de
consciencia, CTAs, objecoes, micro-copy), PRFAQ.md (press release de lancamento + 12 perguntas do
cliente + 9 internas, com os limites reais) e README.md (indice, ordem de leitura e a hierarquia
dura CLAIMS.md manda em FATO > BRANDSCRIPT.md manda em NARRATIVA > o resto e execucao). Quem
escreve peca agora le daqui e nao inventa. GATE-NARRATIVA.md registra o veredito do Gate de peca
publica sobre os quatro documentos, com a postura "quebrado ate prova em contrario".
(2) Purga de veto vivo na superficie publica: o README.md da raiz ainda ensinava o lema
APOSENTADO, docs/BRAND.md ainda usava o cargo corporativo em ingles DERRUBADO em 02/jul, e
brand/marketing-pack-2026-07-06.md carregava o cargo, a headline vetada, a metafora vetada e o
numero PROIBIDO da soma fabricada (4 ocorrencias). Tudo removido do uso vivo; o que era decisao
virou registro de veto.
(3) Guard de superficie publica (scripts/smoke-test.ps1): o guard de vetos so varria engine/ -
peca publica passava livre. Novo bloco varre README/PRIMEIROS-PASSOS/CONTRIBUTING/CREDITS +
onboarding/ + docs/ + brand/marketing-pack-*.md contra a MESMA lista GUARD: do docs/CLAIMS.md
(fonte unica, sem duplicar a lista), distinguindo uso VIVO de linha que apenas REGISTRA o veto.
Fixture suja prova as duas metades: que o guard PEGA o uso vivo e que NAO acusa o registro - guard
que grita a toa e guard que o time aprende a ignorar. brand/landing/ fica fora do escopo com a
divida DECLARADA no proprio codigo; entra quando a LP for reescrita.
(4) Guard de script gerador (scripts/smoke-test.ps1 + scripts/migrate-to-studio.ps1): o furo que
manteve o cargo derrubado vivo ate hoje - um .ps1 que ESCREVE marca dentro do arquivo que ele gera
injeta o termo em dado FRESCO a cada execucao, e nenhum guard de doc enxerga, porque eles varrem
texto de doc e nao saida de script. migrate-to-studio.ps1 gravava a chave `coo` com o papel em
ingles no state.json; virou `alia` / "Braco direito / orquestradora (coordena, nunca executa)".
Check novo varre scripts/*.ps1 contra os mesmos GUARD:, tambem com fixture.
(5) benchmarks/ no pacote publico (scripts/package-release.ps1): "rode a prova na sua maquina" era
meia-verdade - o smoke ia junto, os benchmarks nao. Agora vao, e rodam de DENTRO do pacote (5/5 ALL
PASS). benchmarks/README.md corrigido com os numeros medidos, porque ao entrar no pacote deixou de
ser nota interna e virou peca publica.
(6) REGRA DO PISO (docs/brand/README.md + opportunities/PERFORMANCE-CLAIMS.md): o numero de
verificacoes mudou tres vezes em duas semanas (99 -> 135 -> 143 -> 152) e deixou copy morta em
quatro lugares. LEI nova: numero que so cresce sai em peca publica como PISO em multiplo de 50
("mais de 150 verificacoes"), sempre colado a linha honesta "o numero exato aparece no fim da
prova, na sua maquina"; o valor cravado so vive em documento interno, com [MEDIDO]. O piso continua
verdadeiro sozinho, sem manutencao - o antigo "na versao atual" so explicava o numero velho depois
de descoberto. Meio-termo vago ("centenas de checagens") reprova igual a numero errado.
(7) Drift de criterios corrigido: PERFORMANCE-CLAIMS.md dizia que o Quality Gate tem 5 criterios;
sao 6.
ABERTO: a LP canonica segue com 2 vetos vivos (headline e metafora) e o publico superado - e
reescrita de narrativa, nao find-replace, e aguarda decisao do CEO (TASK-016); e as 16 propostas do
painel de docs/brand/README.md, incluindo a troca do numero no CLAIMS, seguem esperando o SIM/NAO
do CEO - nada foi aplicado em docs/CLAIMS.md nem no BrandScript de docs/BRAND.md.
- Novo: docs/brand/BRANDSCRIPT.md, docs/brand/ASSETS-VERBAIS.md, docs/brand/PRFAQ.md,
  docs/brand/README.md, docs/brand/GATE-NARRATIVA.md,
  scripts/fixtures/superficie-publica-suja.md, scripts/fixtures/script-gera-dado-sujo.ps1
- Alterado: scripts/smoke-test.ps1 (guard de superficie publica + guard de scripts geradores),
  scripts/migrate-to-studio.ps1 (papel da Alia sem cargo em ingles),
  scripts/package-release.ps1 (benchmarks/ no ship list), benchmarks/README.md (numeros medidos),
  README.md (lema aposentado fora), docs/BRAND.md (cargo derrubado fora),
  brand/marketing-pack-2026-07-06.md (cargo, headline, metafora e numero proibido fora),
  opportunities/PERFORMANCE-CLAIMS.md (REGRA DO PISO + Gate com 6 criterios)

## [1.39.0] - 2026-08-02

MINOR - Cluster da auditoria de fluxo (itens 2-4 do corte do DISCOVERY-1.39 + consertos da
AUDITORIA-FLUXO-1.39; o mint 0.7.0 segue aguardando OK do CEO). Quatro entregas:
(1) Updater diff-only: update-engine.ps1 deixou o espelho cego (robocopy /MIR) e passou a comparar
lab -> instancia por SHA256; -Check imprime o relatorio NOVO/ALTERADO/REMOVIDO sem tocar nada
(-DryRun virou sinonimo); a aplicacao copia SO o que mudou, remove SO o que sumiu do lab, e guarda
o arquivo antigo no MESMO backup datado antes de sobrescrever/remover. Provado por fixture
(1 novo/2 alterados/1 removido aplicados exatos) e por -Check contra a instancia real.
(2) Contrato de task tipado (aditivo, minimo): register-task.ps1 ganhou -Type
(pesquisa|construcao|revisao, default construcao) com UMA regra dura por tipo no ATO do registro -
pesquisa dispensa base_artifact (mata o aviso falso), revisao done exige -GateVerdict; -Project
virou obrigatorio (ERRO, nao aviso) e Status default virou "open" (registrar ANTES de executar e
a LEI). Schemas ricos por tipo descartados por YAGNI.
(3) Graphify em maquina limpa VALIDADO (pendencia OPP-68): simulacao com o pacote real sem o CLI
no PATH -> DEGRADA-BEM (memoria de notas segue, graph-check reprova com mensagem honesta, nenhum
script do pacote invoca o CLI). Conserto do furo menor: setup-alia agora prescreve
`python -m graphify` (PATH-safe no Windows). Evidencia: opportunities/GRAPHIFY-MAQUINA-LIMPA.md.
(4) Drift de boot corrigido: AGENTS.md dizia "4 criterios" e engine/MAP.md dizia "5"; o Gate tem 6
(quality-gate.md). Ambos alinhados.
Smoke: +8 checks (3 do updater diff-only, 5 do contrato tipado, executados de verdade via -DryRun).
Gargalos que exigem decisao ou tocam o nucleo ficaram como proposta em
opportunities/AUDITORIA-FLUXO-1.39.md (contador de tentativas do fix-on-fail no journal,
enforcement de allow-list, paralelismo declarado de sub-Tasks).
- Alterado: scripts/update-engine.ps1, scripts/register-task.ps1, scripts/smoke-test.ps1,
  skills/setup-alia/SKILL.md, AGENTS.md, engine/MAP.md
- Novo: opportunities/GRAPHIFY-MAQUINA-LIMPA.md, opportunities/AUDITORIA-FLUXO-1.39.md,
  opportunities/DISCOVERY-1.39.md (base do corte)

## [1.38.0] - 2026-08-01

MINOR - Fala com acentos, disco ASCII (mandato do CEO, 01/08/2026). A regra "sem acentos" na
persona fazia a Alia CONVERSAR sem acentos - nunca foi essa a intencao do CEO. Agora a persona
separa os dois planos: na conversa com o operador, portugues correto e natural, COM acentos; nos
arquivos que ela escreve (motor, docs, scripts), segue ASCII puro - protecao de encoding, nao
estilo de fala. Mudanca de nucleo intencional (guard-core -AllowCore, baseline atualizado).
Higiene de release na mesma passada: acento removido de docs/BRAND.md (unico infrator do smoke)
e termo legado trocado por generico nos rotulos do grafo gerado (graphify-out), no espirito do
precedente da 1.37.1.
- Alterado: engine/agents/persona.md (regra de linguagem em dois planos), engine/.core-baseline.sha256
- Alterado: docs/BRAND.md (heroi sem acento), graphify-out/* (rotulo generico)

## [1.37.1] - 2026-07-08

PATCH - Zero-upstream no evolution-pipeline. O novo doc citava o nome de um OPP que contem o termo
do framework de origem como exemplo de forma; o check zero-upstream da instancia (motor que faz ship
e limpo do termo) reprovou. Referencia trocada por generica ("os OPP-NN em opportunities/").
- Alterado: engine/governance/evolution-pipeline.md (exemplo generico, sem nome de upstream)

## [1.37.0] - 2026-07-08

MINOR - Pipeline de evolucao formal (Onda 3 do OPP-22). Formaliza LEVE o caminho de uma evolucao do
framework: FINDING (achado de RSI/loop/auditoria/CEO, registrado com origem e evidencia, mora onde ja
mora) -> PROPOSAL (se tem risco/escopo, vira OPP-NN no mesmo formato que ja usamos) -> DECISAO (o CEO
e o aprovador unico; aprovado segue o pipeline de versao e passa pelo Quality Gate). A Alia PROPOE,
nunca auto-aprova mudanca de framework (ancorado em provenance); nucleo exige decisao explicita
(guard-core). Regra anti-burocracia: achado trivial/reversivel vai direto pelo pipeline de versao -
OPP e so pra risco/escopo real. Reusa opportunities/, loops e provenance; nao cria fila paralela.
- Novo: engine/governance/evolution-pipeline.md
- Alterado: engine/MAP.md (indice), scripts/smoke-test.ps1 (evolution-pipeline obrigatorio)

## [1.36.0] - 2026-07-08

MINOR - Primeiro valor em 10 minutos (Onda 3 do OPP-22). O onboarding ganhou uma definicao BINARIA
de sucesso, no espirito do getting-started que projeto serio tem: o usuario sabe que deu certo
quando, em ate 10 min, (1) instalou e abriu no coding agent, (2) escreveu "pronto" e a Alia se
apresentou e puxou a memoria, (3) pediu um trabalho real e recebeu algo util que passou pela
conferencia. Com o ponto de falha mais comum ja apontado (nao ter coding agent). Da ao novo usuario
uma regua clara de "funcionou", nao uma promessa vaga.
- Alterado: PRIMEIROS-PASSOS.md (secao "A primeira conversa": box de primeiro valor em 10 min)

## [1.35.0] - 2026-07-08

MINOR - Manifesto de integridade do pacote (Onda 3 do OPP-22, supply-chain leve). O pacote publico
agora sai com um MANIFEST.sha256 - a impressao digital SHA256 de cada arquivo - e o usuario pode
provar que o que baixou nao foi adulterado. scripts/make-manifest.ps1 gera (formato sha256sum,
ordenado, exclui o proprio manifesto e .git); scripts/verify-manifest.ps1 confere e aponta arquivos
ALTERADOS/FALTANDO/EXTRA (-Json disponivel). Integrado no package-release: o manifesto e gerado no
fim do fluxo, depois da validacao de zero-vazamento e do smoke do pacote. docs/INTEGRIDADE.md
documenta como verificar, com a nota HONESTA de que isto prova integridade (conteudo intacto), nao
autenticidade de origem por PKI - assinatura criptografica fica como evolucao futura. Provado
end-to-end: pacote real com 225 arquivos manifestados, verify confirma exit 0.
- Novo: scripts/make-manifest.ps1, scripts/verify-manifest.ps1, docs/INTEGRIDADE.md
- Alterado: scripts/package-release.ps1 (gera manifesto no fim), scripts/smoke-test.ps1 (4 checks)

## [1.34.0] - 2026-07-08

MINOR - Doc de compatibilidade honesta por IDE (Onda 3 do OPP-22). O tipo de honestidade que
projeto serio documenta e fork esquece: nao so o happy path, mas o que DEGRADA em cada coding agent
e como compensar. Novo docs/COMPATIBILIDADE.md: tabela por agente (Claude Code pleno e validado
E2E; Codex/OpenCode leem o AGENTS.md e assumem a persona, mas delegacao portavel segue no roadmap
OPP-42, nao garantida; outros = basico) + 5 perdas com mitigacao pratica (sem execucao de script,
sem hooks de lifecycle, sem isolamento de contexto, sem allow-list em runtime, sem memoria nativa)
+ a distincao contrato-lido vs codigo-executado. Nao afirma suporte que o README nega. README aponta
pro doc no pre-requisito. Smoke: 2 checks (doc presente + README linka).
- Novo: docs/COMPATIBILIDADE.md
- Alterado: README.md (link no pre-requisito), scripts/smoke-test.ps1 (2 checks de release)

## [1.33.0] - 2026-07-08

MINOR - Sentinela de fronteira do nucleo (Onda 2 do OPP-22, adaptada ao nosso modelo). No aiox a
guarda bloqueia commits a paths protegidos; para nos ela protege o NUCLEO (constitution, glossary,
persona, orchestration - os L1 do MAP) de mudanca acidental, que vira risco real quando o
open-source abrir a contribuidores. Novo scripts/guard-core.ps1: compara o SHA256 dos 4 arquivos de
nucleo contra um baseline versionado (engine/.core-baseline.sha256). Mudanca nao registrada ->
[BLOQUEIO] apontando o arquivo, exit 1; mudanca intencional -> rodar com -AllowCore regrava o
baseline. -Json disponivel. Agora com DENTES: o smoke roda a sentinela e reprova se o nucleo divergir
do baseline - alterar o nucleo passa a exigir -AllowCore, tornando toda mudanca de constituicao/
glossario/persona/orquestracao um ato consciente e registrado. Autotestado (baseline criado, bloqueio
detectado, nucleo restaurado byte-a-byte).
- Novo: scripts/guard-core.ps1, engine/.core-baseline.sha256
- Alterado: scripts/smoke-test.ps1 (sentinela presente + nucleo integro vs baseline)

## [1.32.0] - 2026-07-08

MINOR - Auditoria de memoria (Onda 2 do OPP-22). Os agentes tem memoria mas ninguem auditava a
higiene dela - nota stale, contraditoria, duplicada ou com termo fora do glossario custa token e
engana o agente. Novo engine/governance/memory-audit.md: um checklist de 6 itens (expiracao vs TTL,
contradicao, duplicata, drift de linguagem, orfa/sem uso, procedencia) que roda como parte do loop
memory-curator ja catalogado. A auditoria PROPOE (arquivar/consolidar/sinalizar) e nunca deleta cru -
respeita a lei de provenance; contradicao vai pra decisao humana, nunca se resolve sozinha. Ancorado
em memory-types, provenance e glossary; nao inventa sistema de memoria novo. Smoke passa a exigir o
arquivo na lista do motor.
- Novo: engine/governance/memory-audit.md
- Alterado: scripts/smoke-test.ps1 (memory-audit obrigatorio no motor)

## [1.31.0] - 2026-07-08

MINOR - Bastao: doutrina do handoff entre estacoes/agentes (Onda 2 do OPP-22). A Forja ja citava
"o bastao"; agora ele tem doutrina propria e molde. engine/features/bastao.md define o artefato de
passagem <=500 tokens com 8 campos de teto duro (de, para, task_id, ate 5 decisoes, ate 10 arquivos,
ate 3 bloqueios, proximo passo em 2 frases, flag consumed); quem entra recebe SO o proprio perfil +
o bastao, nunca a conversa inteira. Cada estacao declara a proxima (a cadeia FUNDIR->...->GUARDAR da
Forja) e o coordenador sugere o proximo comando ao entregar, ancorado nos passos MONITORA/FECHA do
protocolo de 5 passos. bastao-template.yaml e o molde pronto pra preencher. E a continuidade sem
despejar contexto - frugalidade e a bola que nao cai entre gateway, especialista e QA. O smoke passa
a exigir forja.md, bastao.md e o template na lista de arquivos obrigatorios do motor.
- Novo: engine/features/bastao.md, engine/features/bastao-template.yaml
- Alterado: engine/MAP.md (indice), scripts/smoke-test.ps1 (bastao/forja obrigatorios)

## [1.30.0] - 2026-07-08

MINOR - Semantic-lint da linguagem ubiqua (Onda 2 do OPP-22). Novo scripts/semantic-lint.ps1: um
linter que bloqueia vocabulario proibido/deprecated no motor (engine/**/*.md, engine/**/*.yaml,
scripts/*.ps1), reportando arquivo:linha de cada violacao. Reusa a MESMA fonte de verdade do smoke -
le a secao GUARD: de docs/CLAIMS.md, nao duplica lista - entao veto novo no CLAIMS e pego automatico.
Exclui os scripts internos do dono (migrate-to-studio, extract-secrets), o mesmo par que o
package-release ja tira do pacote. Saida humana ou -Json; exit 0 limpo / 1 se acha termo vetado.
E a versao developer-facing (com file:line) do Guard de vetos que ja roda no smoke - agora da pra
achar ONDE o termo entrou, nao so saber que entrou. Autotestado: motor real LINGUAGEM LIMPA + fixture
com "COO" detectado corretamente.
- Novo: scripts/semantic-lint.ps1 (le CLAIMS.md GUARD, escaneia motor, -Json, exit 0/1)
- Alterado: scripts/smoke-test.ps1 (2 checks: lint presente + reusa fonte de verdade)

## [1.29.1] - 2026-07-08

PATCH - PRIMEIROS-PASSOS.md alinhado ao updater online. A secao "Atualizar" ainda mandava o
usuario descompactar o pacote na mao ("atualizacao automatica nao disponivel") - defasada desde a
1.29.0. Agora explica o um-clique real: atualizar-alia.bat baixa a versao nova sozinho, faz backup,
troca so o motor, nunca toca nos dados e reverte se falhar; menciona o -Check para prever.
- Alterado: PRIMEIROS-PASSOS.md (secao Atualizar)

## [1.29.0] - 2026-07-08

MINOR - Updater online do usuario final (fecha a Onda 1 do OPP-22, item "updater"). Ate agora quem
instalava o pacote publico nao tinha atualizacao automatica - o update-engine.ps1 so funciona com
laboratorio local (dev) e mandava o usuario baixar e descompactar o zip na mao. Novo
scripts/update-online.ps1: baixa a versao nova do GitHub (gufarina/alia.flow), compara versoes (no-op
se ja atual), faz backup timestampado, troca SO o motor (engine/scripts/skills/onboarding/
optional-mcps + arquivos de topo) e roda o smoke; se vermelho, ROLLBACK completo. LEI DE OURO
provada por fixture: NUNCA toca studio/, clients/, state.json, studio.yaml, alia.config.json, memory/
- um Assert-SafeCopySet aborta se o conjunto for contaminado. Modos -Check (preve sem aplicar) e
-Json. Hardening: Remove-Item resolve .FullName antes de remover (short-path 8.3 tipo "LITEOS~1"
quebra Remove-Item -LiteralPath em PS 5.1 - o rollback nao pode falhar por isso). atualizar-alia.bat
agora ESCOLHE o updater: lab local -> update-engine; senao -> update-online. A mensagem sem-lab do
update-engine aponta pro caminho automatico. Autotestado 15/15 (Sonnet) + reteste do miolo (Alia).
- Novo: scripts/update-online.ps1 (transacional, protege dados do operador, -Check/-Json)
- Alterado: atualizar-alia.bat (branch lab vs online), scripts/update-engine.ps1 (mensagem sem-lab),
  scripts/smoke-test.ps1 (3 checks: updater online presente + transacional/seguro + .bat escolhe certo)

## [1.28.0] - 2026-07-07

MINOR - Instalador transacional (Onda 1 do OPP-22, o item carro-chefe: "instalar sem medo"). O
install.ps1 antes baixava, extraia e copiava por cima SEM backup nem rollback - falha no meio
deixava a pasta do usuario num estado parcial irreversivel. Agora: (1) detecta colisoes com o
destino e faz backup do que existe em .alia-backup-<timestamp>/ (pasta vazia = sem backup); (2)
download, extracao e copia em try/catch separados com erros CLASSIFICADOS por fase (rede/URL, zip
corrompido, copia); (3) se a copia falha no meio, ROLLBACK restaura o estado anterior e remove o
parcial; (4) temporarios limpos sempre num finally. Autotestado por fixture local (rollback
restaura o conteudo antigo e nao vaza o novo; caso pasta-vazia instala sem backup) - a copia real
do GitHub nao da pra testar sem o repo publicado. URL gufarina/alia.flow preservada; guard do
placeholder intacto. Smoke ganhou 1 check provando as funcoes transacionais; README atualizado.
- Alterado: scripts/install.ps1 (Backup-Dest, Restore-Dest, Get-CollidingItems, erros por fase, rollback)
- Alterado: scripts/smoke-test.ps1 (check: instalador transacional), README.md (nota honesta atualizada)

## [1.27.0] - 2026-07-07

MINOR - CI: o trilho vira porta automatica no GitHub (Onda 1 do OPP-22, item "smoke matrix"). Novo
.github/workflows/smoke.yml roda scripts/smoke-test.ps1 e scripts/doctor.ps1 em todo push e PR
contra main (windows-latest, shell pwsh); vermelho bloqueia o merge - a mesma prova da maquina do
contribuidor roda no CI. Multi-OS (pwsh no ubuntu/macos) fica como evolucao futura declarada no
proprio arquivo, pra nao vermelhar o CI antes de provar que o trilho roda identico fora do Windows.
Como .github/ ja entra no pacote (1.25.0), o workflow chega ao repo publico automaticamente. Smoke
ganhou 2 checks provando o workflow presente e que ele cita ambos os scripts.
- Novo: .github/workflows/smoke.yml
- Alterado: scripts/smoke-test.ps1 (2 checks de release: CI presente + roda trilho e doctor)

## [1.26.0] - 2026-07-07

MINOR - Doctor: diagnostico read-only da instalacao (Onda 1 do OPP-22, item "doctor"). Novo
scripts/doctor.ps1 confere em 7 pontos - nucleo do engine, pastas do engine, VERSION nao-vazio,
VERSION coerente com o topo do CHANGELOG, alia.config.json JSON valido, scripts essenciais, e roda
o proprio trilho - com saida humana ("=== Alia Flow Doctor ===" + [OK]/[FALHA] + veredito SAUDAVEL)
ou -Json para automacao. Read-only por design (a autocura --fix fica pra depois). Exit 0 so se tudo
ok E smoke verde. O smoke ganhou 2 checks de presenca (nao roda o doctor - seria recursao, o doctor
ja roda o smoke) e o README documenta o comando.
- Novo: scripts/doctor.ps1 (7 checks, humano + -Json, exit 0/1)
- Alterado: scripts/smoke-test.ps1 (2 checks de release: doctor presente + suporta -Json)
- Alterado: README.md (secao de prova documenta o doctor)

## [1.25.0] - 2026-07-07

MINOR - Polish de lancamento OSS + correcao de credibilidade (loop noturno, Onda de polish do
LAUNCH-READINESS). (1) BUG DE CREDIBILIDADE corrigido: o README apontava a prova de ablacao para
`tests/knowledge-ablation/score.py`, caminho que so existe dentro do cliente-exemplo - a promessa
central ("rode e veja o numero") quebrava na primeira tentativa. Agora cita o caminho real
(studio.example/clients/acme-saas/...) e o smoke prova que o arquivo existe. (2) CONTRIBUTING.md
(contrato de qualidade, ciclo do motor, camadas, estilo). (3) .github/ com templates de issue
(bug/feature) e PR (checklist do contrato de qualidade). (4) package-release passa a incluir
CONTRIBUTING.md e .github/ no pacote publico; o smoke ganha 5 checks de release que provam tudo isso.
- Corrigido: README.md (caminho da prova de ablacao)
- Novo: CONTRIBUTING.md, .github/ISSUE_TEMPLATE/{bug_report,feature_request}.md, .github/PULL_REQUEST_TEMPLATE.md
- Alterado: scripts/package-release.ps1 (ship list), scripts/smoke-test.ps1 (5 checks de release)

## [1.24.1] - 2026-07-07

PATCH - ARQUITETURA.md isento do check zero-upstream (mesma regra do PRD). O novo
docs/product/ARQUITETURA.md descreve a absorcao do upstream e por isso cita o nome da origem -
atribuicao legitima, identica ao PRD. Como docs/product/ e interno (o package-release nunca o
inclui no pacote publico), entra na mesma isencao nominal do check g (zero-upstream guarda o
CODIGO que faz ship, nao a atribuicao em doc interno).
- Alterado: scripts/smoke-test-studio.ps1 (ARQUITETURA.md na isencao do check g)

## [1.24.0] - 2026-07-07

MINOR - PRD e arquitetura alinhados com a Forja (correcao de feature orfa). A Forja estava no
CHANGELOG publico 0.6.0 mas nao no PRD - violacao da propria lei client-truth (decisao nova
registrada na fonte na mesma Task). Fix: (1) PRD ancora a Forja na tabela do motor (secao 5), no
fluxo principal que agora se chama Forja (secao 10) e no roadmap (fase 7.5, com status HONESTO -
doutrina feita, 20 mecanicas do OPP-22 = backlog); (2) novo docs/product/ARQUITETURA.md - desenho
oficial que consolida o que estava espalhado em OPP-17/26/71: os 3 corpos (lab/instancia/produto),
as 2 camadas, os 6 bounded contexts, a Forja atravessando, os guardrails de runtime e um quadro
de maturidade honesto. E o mapa que o Gate usa pra medir a nota AS.
- Alterado: docs/product/PRD.md (Forja na solucao + fluxo principal + roadmap 7.5)
- Novo: docs/product/ARQUITETURA.md (desenho de solucao validavel)

## [1.23.3] - 2026-07-07

PATCH - git-sync valida o argumento antes do ambiente (bug pego no mint 0.6.0). O git-sync.ps1
checava a existencia da pasta a versionar ANTES de validar o formato de -Repo; na instancia a
pasta studio/ existe e o erro certo aparecia, mas no pacote publico (so studio.example/) o script
morria antes com mensagem trocada - e o proprio smoke do pacote reprovava (Git-sync: repo
invalido -> owner/repo). Fix: validar -Repo primeiro (input malformado se rejeita antes de tocar
pasta). Disciplina: validar argumento antes de efeito de ambiente.
- Alterado: scripts/git-sync.ps1 (ordem de validacao: -Repo antes da pasta)

## [1.23.2] - 2026-07-07

PATCH - Prova da instancia ALL GREEN: duas pendencias pre-existentes reveladas pelo update
1.23.x. (1) CLAUDE.md legalizado na allowlist da raiz (smoke-test-studio + skill
file-organization): e o boot do harness Claude Code da instancia, par do AGENTS.md - nao e
vazamento. (2) Nota de memoria da instancia com o termo legado no nome renomeada
(segundo-cerebro-modelo-origem) - o check zero-upstream guarda o espelho inteiro.
- Alterado: scripts/smoke-test-studio.ps1 (allowlist + CLAUDE.md)
- Alterado: skills/file-organization/SKILL.md (allowlist documentada)
- Externo (instancia): memory/segundo-cerebro-modelo-*.md renomeada + _index.md

## [1.23.1] - 2026-07-07

PATCH - Zero-upstream no motor: a prova da instancia (smoke-test-studio, check g) acusou o nome
do framework de origem dentro de engine/features/forja.md. O motor que faz ship fica limpo do
termo; a atribuicao vive em CREDITS.md e no dossie do lab (opportunities/), como manda o proprio
check. Referencias reescritas como "upstream de origem".
- Alterado: engine/features/forja.md (purge do nome; atribuicao apontada a CREDITS.md/dossie)

## [1.23.0] - 2026-07-07

MINOR - Verdade de design + regra de sync anti-drift (correcao C do Operator, 07/jul). A LP
canonica (brand/landing/lp-alia-flow.html) evoluiu - body Public Sans, motor de dither de FORMAS
via Bayer 8x8 (eye-engine.js), ASCII abandonado - mas a lei visual (DESIGN.md + skill
animated-infographics) ficou fotografada em 22/06: artefatos novos nasciam com Inter Tight e
engine ASCII legado. Causa-raiz: nao existia loop de propagacao LP -> lei. Fix sistemico:
(1) DESIGN.md atualizado (Public Sans, paths reais das Spock .otf, motor canonico, fonte viva);
(2) nova secao REGRA DE SYNC: mudou a LP -> atualiza DESIGN.md + skill + espelho no MESMO ciclo;
lei defasada em peca nova = Fail no criterio de peca publica (client-truth); (3) skill
animated-infographics do harness atualizada (SKILL.md + aesthetic.md + assets ganham
eye-engine.js e SpockPro-*.otf; contradicao serif-display removida; squircle 22/14 legalizado).
- Alterado: docs/DESIGN.md (tokens body, tipografia, fonte viva + regra de sync)
- Externo (harness): ~/.claude/skills/animated-infographics (SKILL.md, references/aesthetic.md, assets/)

## [1.22.0] - 2026-07-07

MINOR - Forja (ADE proprietario) + dossie de absorcao do aiox-core. Dissecacao completa do
upstream SynkraAI/aiox-core@5.2.9 (4 agentes, clone em Projetos/aios/_aiox-core-origin) virou:
(1) a Forja - linha de producao autonoma em 5 estacoes (FUNDIR, MOLDAR, TEMPERAR, PROVAR,
GUARDAR) com bastao <=500 tokens entre estacoes e notas AS/NB (arquitetura de solucao + negocio)
obrigatorias para evolucao de motor - versao nossa do ADE, redesenhada para squads-first e gate
unico; (2) OPP-22 - backlog de absorcao de 20 mecanicas em 3 ondas (confianca, enforcement,
ecossistema), cada uma com path-fonte no upstream; (3) dossie completo com nota juridica
(MIT, cadeia BMad -> SynkraAI -> Studio Farina).
- Novo: engine/features/forja.md
- Novo: opportunities/OPP-22-absorcao-aiox-core.md
- Novo: opportunities/aiox-origin-dossie/ (MAGNUM-OPUS.md + ultima-revisao.html)
- Alterado: engine/MAP.md (entrada da Forja em Entrega e workflows)

## [1.21.0] - 2026-07-07

MINOR - Guard de vetos + purge do "COO" (auditoria do dia, correcoes C1/C2 do report). O termo
"COO" (derrubado pelo CEO em 02/jul) estava vivo na alma da Alia (persona.md 26/32/162 +
orchestration.md 129) - virou "braco direito"/coordenadora. E o smoke ganhou um GUARD que le os
vetos declarados em docs/CLAIMS.md e REPROVA se qualquer um aparecer no motor: veto ressuscitado =
smoke vermelho. Molde do zero-aiox: transforma "confie que a Alia lembra do veto" em "o teste
prova". CLAIMS.md ganhou a secao "GUARD:" com os regexes proibidos no motor.
- Alterado: engine/agents/persona.md (COO -> braco direito)
- Alterado: engine/orchestration.md (COO -> Coordenadora)
- Alterado: docs/CLAIMS.md (secao Guard do smoke)
- Alterado: scripts/smoke-test.ps1 (bloco Guard de vetos - 4 novos checks)

## [1.20.0] - 2026-07-07

MINOR - Fonte de Verdade do Cliente (client-truth): as causas-raiz do dia de falhas de 07/jul
viradas LEI. Novo engine/governance/client-truth.md com 4 leis: (1) Knowledge-first - hierarquia
fixa de fonte (decisao do Operator > BRAND/PRD/persona > docs internos > README/codigo), vetos
respeitados, decisao nova REGISTRADA na fonte na mesma Task; (2) Claims Registry - peca publica
so afirma numero/feature/tagline do registro curado, numero nunca se fabrica somando fontes,
feature so LANCADA; (3) Escopo publico vs interno - regra de operacao nao vaza pra peca (quem le
isto: operacao ou publico?); (4) Reuse-first de ativos - inventario da marca antes de criar,
efeito proprietario se replica, nao se imita. Reforcos: coordenador nao produz dominio (gatilho
antes do artefato) e briefing de delegacao com travas obrigatorias (nao re-delegar, criterio de
encerramento, fontes a ler, proibicoes de invencao).
- Novo: engine/governance/client-truth.md
- Alterado: engine/orchestration.md (LEI no DELEGA)
- Alterado: engine/governance/quality-gate.md (criterios extras obrigatorios pra PECA PUBLICA)
- Instancia: docs/CLAIMS.md do cliente alia-flow criado (primeiro registro de claims, alimentado
  pela auditoria growth TASK-064)

## [1.19.0] - 2026-07-06

MINOR - Disciplina de Julgamento: manual de julgamento dos modelos de fronteira (Fable/Claude 5)
destilado em engine/features/judgment-discipline.md (3 leituras do pedido, 5 caixas + pedra-chave,
rival por conclusao, proveniencia de afirmacao, 5 passes de verificacao, destino-primeiro,
auto-revisao rapida/profunda, 12 heuristicas, regua fraco/decente/forte/excelente) + ancoras em
orchestration.md, agents/persona-skeleton.md e governance/quality-gate.md.
NOTA DE PROCESSO: as features 1.18.0 e 1.19.0 nasceram fora do fluxo (autoradas direto no repo do
produto e espelhadas na mao no engine do studio, sessao 0b0eaf0e de 06/07) - backporteadas ao lab
nesta entrada para restaurar a ordem lab -> produto -> studio. Nao repetir o desvio.

## [1.18.0] - 2026-07-06

MINOR - Advisor Pattern: executor em tier barato (standard/fast) pode consultar o tier strong ate
3x por Task (checkpoints pos-orientacao e pos-escrita/testes); conselho e rumo curto, nunca
execucao; nao e escalacao e nao substitui o Gate. Baseado na advisor tool da Anthropic (beta
advisor-tool-2026-03-01). Novo engine/features/advisor-pattern.md + secao advisor no
agents/model-matrix.yaml + item 5 da doutrina de delegacao em orchestration.md.

## [1.17.0] - 2026-07-05

MINOR - Especialista growth + 16 skills de marketing (OPP-73). Origem: CEO (05/jul) - estudo do repo
OpenClaudia (67 skills de marketing p/ Claude Code, MIT) aprovado com todas as ondas: "quero todas as
ondas, garantindo a qualidade da alia, e que esses agentes ou skills vao respeitar nossa arquitetura
de clientes, projeto e task e de gerenciamento das equipes". Estudo: research/openclaudia-skills (studio).

- engine/agents/growth.md + growth.yaml: especialista novo de marketing/conteudo/crescimento (tier
  core, model standard, gate quality-gate, grounding required). A Alia delega; o growth nunca publica
  (devops) nem implementa (dev) - recomenda com evidencia.
- 16 skills adaptadas do OpenClaudia em skills/ (provenance: openclaudia + upstream no frontmatter),
  traduzidas ao contrato da casa: delegacao via lente marketing, Task registrada antes de executar
  (Cliente > Projeto > Tarefa), Artifact pelo quality-gate, grounding [MEDIDO]/[INFERIDO] bloqueante,
  notas de Contexto BR (LGPD, Pix/BRL, Reclame Aqui, calendario BR) onde o original assume mercado US.
  Onda 1 (zero API): launch-strategy, icp-builder, competitor-analysis, pricing-strategy, page-cro,
  seo-audit. Onda 2 (conteudo): content-strategy, content-calendar, write-blog, social-content,
  thread-writer, email-sequence, newsletter. Onda 3 (requer chaves Google; degrada p/ modo manual,
  nunca finge dado): google-analytics, search-console, brand-monitor.
- alia.yaml: lente marketing -> growth; alia.md cita a lente nova. Curadoria: 51 das 67 skills do
  upstream ficaram FORA (ads pagos, bots, hubspot, podcast...) - catalogo no estudo, resgate e decisao nova.
- smoke-test.ps1: bloco OPP-73 (par growth presente, 16 skills presentes, provenance + contrato em
  toda skill, roteamento da lente marketing).

## [1.16.1] - 2026-07-03

PATCH - Blindagem de dados no atualizador (a pedido do CEO: "garante que nao estragamos as infos base
dos usuarios?"). update-engine.ps1 ganhou duas travas: (1) GUARDA que ABORTA o update se a camada de
dados (clients/, state.json, studio.yaml, alia.config.json, AGENTS.md, .gitignore) algum dia entrar no
conjunto de copia por engano - nada e tocado antes de abortar; (2) BACKUP automatico datado do
registro + config (state.json, studio.yaml, alia.config.json) em _backups/ ANTES de tocar no motor.
clients/ (grande) segue estruturalmente fora do alcance (nunca e alvo de copia). Provado empiricamente:
clients/ e state.json byte-identicos antes e depois do update.

## [1.16.0] - 2026-07-03

MINOR - Publicacao e "instalar sem atrito" (OPP-72). Origem: CEO (03/jul) - preparar o repo OSS,
garantir instalador apontando pro git certo, e que a Alia consiga salvar/versionar o trabalho SEM o
usuario ter git; "sinto que nao ta claro que precisa ser facil de funcionar".
- OPP-72 git-sync (commit+push SEM git): novo scripts/git-sync.ps1 versiona uma pasta (default: o
  studio do operador) num repo do GitHub usando SO a API HTTPS (Invoke-RestMethod) - nenhum git.exe,
  nenhuma dependencia. Commit atomico de varios arquivos (blobs -> tree -> commit -> move o branch).
  Token uma vez (fine-grained, Contents:RW) por -Token / ALIA_GH_TOKEN / %LOCALAPPDATA%\Alia. -DryRun
  valida e lista sem tocar a rede. Reusavel pela Alia E pelo launcher (comando sync_studio). Smoke
  reprova repo invalido e confirma o dry-run.
- Instalador aponta pro repo publico real: scripts/install.ps1 saiu do placeholder ORG/alia-flow para
  gufarina/alia.flow (branch main); README ganhou pre-requisito (coding agent) + a linha de instalar;
  numero fossil corrigido (79 -> 99 checks). Links de download (Claude Code / Codex / OpenCode) no
  instalador, no README e no changelog publico.
- Atualizador nao apaga docs locais: update-engine.ps1 passou a SOMAR a pasta docs/ (antes espelhava
  com /MIR e apagaria planos/documentos locais do operador). Motor segue espelhado; docs preservados.
- Launcher (.exe, Tauri): novo comando sync_studio (dispara o git-sync no terminal). Empacotar +
  assinar o exe segue como frente propria.

## [1.15.0] - 2026-07-03

MINOR - Cluster "consolidacao para publicar" (OPP-66 a OPP-70). Origem: CEO (03/jul) pediu para
revisar o fluxo inteiro antes de publicar - garantir que tudo vira Task rastreada com continuidade,
dar protagonismo de dono ao Squad Owner, consolidar conhecimento/consistencia por Client, validar
metodo (DDD/SDD/leitura otimizada) e por os olhos da Alia no que empaca. Cada OPP e um incremento
auto-contido, pareado (prosa + yaml/mecanismo) e travado no smoke (79 -> 99 checks, ALL GREEN).
- OPP-66 Rastreabilidade dura + continuidade: o furo de rastreio (Task com artifact sem
  project/base_artifact/session) deixou de ser so aviso amarelo no painel e virou FALHA do smoke;
  o demo foi zerado de furos. Novo scripts/task-context.ps1: dado um Client (e Projeto), devolve o
  historico e crava a ULTIMA REVISAO - o mecanismo da continuidade ("vi aqui a ultima revisao, parto
  dela"), em vez de grep manual. LEI atualizada em engine/orchestration.md.
- OPP-67 Alma de dono do Squad Owner: o Gateway nasce com quatro tracos (incomodo de dono, motor
  ativo, perguntas inteligentes, pragmatismo de processo) e a cadeia de entusiasmo (a equipe responde
  ao Owner, nunca direto a Alia). Doutrina em engine/squad-system.md; contrato owner_soul em
  agents/squad-creator.yaml (estampado no passo e); a persona do Gateway do demo (maya) encarna a alma.
- OPP-68 Conhecimento por Client (consistencia + grafo garantido): todo Client carrega uma
  Especificacao de Entrega (contrato de consistencia: design + formato + tom + checklist) no segundo
  cerebro; novo scripts/graph-check.ps1 REPROVA qualquer squad sem grafo do graphify (a geracao
  deixou de ser "sob demanda, facil de esquecer"). squad-creator fecha com spec + indice + grafo (passo g).
- OPP-69 Estrategia de leitura (ler sem ler tudo): engine/reading-strategy.md + .yaml formalizam os
  3 padroes (indice mestre com teto + assinatura antes do corpo + grep-por-secao), fruto da pesquisa
  de mercado (Aider repo-map, cAST, repomix) - embeddings/RAG descartados por YAGNI. Novo
  scripts/kb-index.ps1 gera/valida o indice mestre knowledge/MAP.md de cada Client (reprova indice
  acima do teto ou doc sem assinatura). Liga DDD (ja no Gate) e SDD (story-cycle) a leitura seletiva.
- OPP-70 Mission Control vivo (olhos da Alia): novo scripts/stale-tasks.ps1 lista as Tasks paradas
  (nao-done, paradas ha mais de N dias, com data de referencia parametrizavel para determinismo);
  mission-control.ps1 ganhou KPI e secao "paradas / em risco" no topo. LEI em orchestration.md
  (anti-ociosidade): a Alia confere o painel no inicio da sessao e aciona os Owners - no bastidor,
  nunca como primeira fala.
- Marca (fora do motor, registrado por linhagem): correcoes de mobile na LP canonica (hero - o olho
  vai para depois do texto, headline volta pra dobra; fx2__rail colapsa para 1 coluna, sem estouro
  lateral), verificadas por CSS computado em viewport mobile (console 0 erros). Standalone
  reconstruida pelo build. Itens de design que exigem verificacao visual do CEO seguem pendentes no
  lp-review (purge do codigo morto, explorador Cliente>Projeto>Tarefa, toggle PT/EN, ritmo P/B,
  icones de host, URL de download real - este depende do repo publico, B7).

## [1.14.0] - 2026-07-02

MINOR - LEI da rastreabilidade + Mission Control. Origem: incidente da LP (02/jul) - a Alia
reconstruiu o site sobre um arquivo-base obsoleto porque a Task registrada nao guardava DE ONDE
se partiu, e o CEO cobrou: "tudo que e demandado pra Alia deve virar task, de um projeto, de um
cliente, e ter rastreabilidade - o Alia Flow e sobre isso".
- LEI da rastreabilidade e continuidade (engine/orchestration.md, junto dos 5 passos): toda
  demanda vira Task de um Projeto de um Cliente ANTES de executar (inclusive demanda "meta"
  sobre o proprio motor/marca/site); a Task carrega LINHAGEM: project, artifact (o que
  produziu), base_artifact (de onde partiu) e session (quem executou). Continuidade: ao
  receber trabalho sobre um assunto, LER primeiro as Tasks daquele Client/Project no state -
  o proximo passo parte de onde o anterior chegou. Sem linhagem nao existe "braco direito".
- register-task.ps1 v2: novos campos -Project, -BaseArtifact e -SessionId gravados na Task;
  avisa (sem quebrar chamadas antigas) quando faltar project ou base_artifact.
- scripts/mission-control.ps1 (novo, frugal, zero LLM): le o state.json e gera
  mission-control.html - painel estatico auto-contido (duplo clique) com a historia da
  operacao por Cliente > Projeto > Tarefa: o que entregou, de onde partiu, gate, sessao,
  e um contador de FUROS DE RASTREIO (task sem projeto ou sem linhagem aparece em amarelo).
  E a vista humana do ledger: se o painel nao conta a historia, o registro esta falhando.
- mission-control.html entra na allowlist da raiz (smoke-test, smoke-test-studio,
  file-organization) como artefato REGENERAVEL - nunca editado na mao.
- Marca (fora do motor, registrado aqui pela linhagem): copy nova aplicada na LP CANONICA
  (lp-alia-flow.html + standalone juntas) - braco direito, secao #ja-tentou (ChatGPT /
  automacoes / agencia), prova 0/5 vs 5/5, freio + teto no #confiar. A v28 de base errada
  foi arquivada em _candidatas/ e o README da landing agora CRAVA quais arquivos sao os
  canonicos e manda editar os dois na mesma sessao.

## [1.13.0] - 2026-07-02

MINOR - Kit beta tester: o pacote agora se explica sozinho para quem recebe. Origem: CEO
(02/jul) quer liberar uma versao para um amigo beta tester com o minimo de atrito.
- PRIMEIROS-PASSOS.md (novo, viaja na raiz do pacote): guia de 10 minutos em linguagem
  leiga - pre-requisito (Claude Code), instalacao em 3 passos sem terminal (descompacta,
  iniciar-alia.bat, abrir a pasta e dizer "pronto"), o primeiro pedido sugerido (template
  quem-sou + pra-quem-e + o-que-precisa-ficar-pronto), 5 exemplos reais preenchidos
  (barbearia, suplementos, advogada, ideia de app, agencia), como atualizar na fase beta,
  o que e honesto saber de seguranca/privacidade e o que vale ouro reportar.
- update-engine.ps1: instalacao SEM laboratorio local (o caso de quem recebeu o pacote)
  deixa de morrer com "[ERRO] nao parece um laboratorio valido" - explica em linguagem
  simples como atualizar na fase beta (novo zip por cima; studio/ e dados preservados)
  e sai limpo. O fluxo com lab (instancia do dono) segue identico.
- README.md: removidos numeros fossilizados (badge v1.0.0 com LAB em 1.13.0; "65
  verificacoes" com o smoke em 79) e consertado o caminho da prova de ablacao - o texto
  mandava rodar tests/knowledge-ablation/run.ps1, que NAO existe no pacote; a prova real
  vive em studio.example/clients/acme-saas/tests/knowledge-ablation/ e roda pelo smoke.
- Encanamento do novo arquivo: shipFiles (package-release), productFiles (update-engine),
  rootAllow (smoke-test + smoke-test-studio) e allowlist da skill file-organization.
- Decisao de arquitetura beta (registrada): o canal do beta e o ZIP do package-release,
  NAO o Alia Launcher (.exe) - o launcher so tem build debug (12.5MB), sem assinatura
  (SmartScreen assusta), sem comando de instalar plugado e com caminhos de deteccao da
  maquina do dono. Fica para a fase seguinte, com build release + assinatura.

## [1.12.1] - 2026-07-02

PATCH - UX do dialogo: o bastidor nao abre mais a conversa (teste da mae). Origem: CEO (02/jul)
reprovou a Alia abrindo a sessao com "vou fechar o loop de RSI (2 digests pendentes)" - jargao
de encanamento como primeira fala. Causa raiz: a persona JA proibia jargao (persona.md, Regra
dura de linguagem), mas o gatilho mecanico mandava o contrario ("PRIMEIRA ACAO: FECHE O LOOP")
- o mesmo padrao projetado != ligado, agora na voz.
- reflect-check.ps1: a mensagem injetada no boot vira PROTOCOLO DE BASTIDOR - (1) atender o
  pedido do operador PRIMEIRO, nunca abrir a sessao com manutencao interna; (2) processar os
  aprendizados em silencio depois de atender (continua OBRIGATORIO na sessao; a trava de
  maquina do smoke > 3 dias segue intacta); (3) so falar com o operador se o CONFERE escalar,
  e ai em UMA pergunta de linguagem de negocio; (4) SEGURA_AUTO e invisivel.
- skills/session-reflection/SKILL.md: nova secao "Protocolo de dialogo (teste da mae)" com o
  quando (depois do pedido), o como (sem anunciar, sem narrar, sem RSI/digest/inbox na conversa)
  e o formato unico de escalada. Fronteira dura e AUTONOMIA COM FREIO inalterados.
- AGENTS.md (boot loader do produto): regra "Bastidor nunca abre a conversa" no fast-boot.
  (Camada do operador nas instancias existentes: aplicar a mesma linha na mao, o updater nao
  toca AGENTS.md; feito na instancia studio-farina nesta data.)

## [1.12.0] - 2026-07-02

MINOR - Cluster de eficiencia e integridade do cano do RSI + vazamento no empacotador. Origem:
auditoria pedida pelo CEO (02/jul) por problemas e rotas desnecessarias no motor.
- session-reflection.ps1 (mira certa, zero varredura): passa a ler o payload JSON que o hook
  entrega no STDIN (session_id + transcript_path) e vai DIRETO ao transcript da sessao que
  acabou - elimina a rota "varre TODOS os transcripts de TODOS os projetos do PC" que rodava
  em todo SessionEnd. Fecha tambem o furo de memoria trocada: o fallback (sem stdin) agora
  varre SO a pasta de transcripts do projeto atual, nunca a maquina inteira; digest de sessao
  de outro projeto nao entra mais na memoria deste. (O parametro -SessionId existia mas o hook
  nunca o passava - projetado != ligado, mesmo padrao do PLACEHOLDER do 1.1.0.)
- session-reflection.ps1 (digest nao se sobrescreve): o inbox ganha sufixo do id da sessao
  (reflection-inbox-{data}-{id8}.md); duas sessoes no mesmo dia nao apagam mais o digest uma
  da outra (antes: WriteAllText no mesmo nome por data = perda silenciosa de aprendizado).
- promote-memory.ps1 (anti-apodrecimento): avisa [ORFAO] para qualquer .md em _proposals/ fora
  dos padroes prop-*.md / reflection-inbox-*.md. Incidente real: 2 propostas do Dott gravadas
  como proposta-*.md ficaram 2 dias invisiveis para a promocao, sem nenhum aviso. O loop
  SINALIZA, nao apodrece. session-reflection/SKILL.md agora exige o prefixo prop- explicito.
- package-release.ps1 (vazamento no pacote publico): o /XD do robocopy excluia "product"
  (pasta que NAO existe) e nao excluia _dev/ nem _drafts/ (~40MB de rascunho interno no LAB);
  agora exclui _retired, _dev, _drafts e release, alinhado ao .gitignore.
- Cortado (YAGNI, fica anotado): extrair helpers comuns dos dois smoke-tests (duplicacao de
  ~40 linhas, risco de mexer no cadeado nao compensa agora); limpeza do build velho em
  release/ (ja ignorado no git).

## [1.11.0] - 2026-07-01

MINOR - Cluster loop-engineering (OPP-57 + OPP-58 + OPP-59) + bug fix de YAML no squad. Origem:
aprovacao do CEO (01/jul) sobre o plano research/loop-engineering/PLANO-OPORTUNIDADES-2026-07.md;
fonte externa: Loop Engineering Orange Book (secoes 05, 07 e 09).
- OPP-57 (contrato de 6 elementos por loop): todo loop instanciado declara discovery_source,
  state_file, evaluator, isolation, token_cap (per_round/daily) e human_review_point ("none"
  proibido em loop que escreve fora de staging). loops.md ganha a LEI do contrato; loops.catalog.yaml
  ganha os 6 no instance_schema.required + bloco contract_6_elements; os 11 loops da instancia
  (studio/clients/alia-flow-lab/loops.yaml) e os 4 do demo (studio.example) migrados com valores
  honestos. Dente: smoke-test-studio.ps1 check (j) reprova loop active sem os 6; smoke-test.ps1
  cobra o pareamento prosa<->catalogo e o demo. Cortado (YAGNI): validador semantico dos valores,
  isolamento fisico por worktree.
- OPP-58 (teto de gasto duro; reabre o corte do OPP-55): scripts/budget-check.ps1, contador frugal
  sem LLM - le costs[] do state.json e compara com o token_cap declarado (por rodada e diario);
  estourou = exit 1 + PACOTE DE PROVA (o que rodou, quanto gastou, onde estourou, recomendacao).
  run-loops.ps1 chama o contador no inicio de CADA volta e PULA (nao roda) loop estourado ou sem
  teto declarado (fail-closed), logando o porque. rsi.yaml: over-budget-path passa a apontar o
  contador como fonte (deixa de ser trigger declarado sem execucao). Fronteira dura: o teto NUNCA
  e afrouxado em runtime - mudar token_cap e edicao de configuracao (operador ou OPP). Dente:
  smoke-test.ps1 prova com fixtures que o contador morde (estourado = FAIL, dentro do teto = PASS)
  e que o runner freia. Cortado (YAGNI): dashboard de custo, predicao por modelo.
- OPP-59 (avaliador que AGE no criterio Funciona): mudanca de Gate APROVADA pelo CEO em 01/jul
  (human_approval_for: [gate] respeitado - a fronteira dura segue intacta). quality-gate.md/.yaml:
  verdito PASS do criterio 1 exige EVIDENCIA DE EXECUCAO anexada [MEDIDO comando -> saida]; leitura
  de codigo NAO e prova; postura do avaliador no gate-on-artifact: quebrado ate prova em contrario;
  tipologia de prova por tipo (codigo -> teste/smoke; UI -> preview/interacao DOM; documento ->
  grounding vs fonte; script -> fixture); sem execucao possivel o verdito vira Concerns com motivo
  (indisponibilidade nao e aprovacao). Os outros 5 criterios NAO mudam. Dente: smoke-test.ps1 pareia
  prosa<->yaml (mesmo cadeado do OPP-56) e confere os 5 intactos. Cortado (YAGNI): LLM-judge dos 6
  criterios, infra nova de e2e/CI.
- Bug fix: studio/clients/alia-flow-lab/squad/squad.yaml - comentario inline em 3 integrantes
  (agent-engineer, agentic-flow-engineer, rsi-researcher) engolia a chave knowledge: na mesma linha,
  deixando a lista orfa (YAML invalido). Chave devolvida a linha propria; smoke-test-studio.ps1
  check (k) reprova a assinatura do defeito (comentario que termina em "chave:").
Retrocompativel: schemas so estendidos (nenhum campo removido); constituicao e provenance intactas.

## [1.10.0] - 2026-06-30

MINOR - AUTONOMIA COM FREIO na promocao de memoria (OPP-56). Decisao do CEO (30/jun): no fechamento
do loop do RSI, a Alia NAO pede cartao S/N item-a-item ao operador - pedir OK em bloco vira ruido, o
operador ignora e o loop apodrece (era o furo do OPP-53). O freio vira um CONFERE independente que
separa o seguro do arriscado.
- skills/session-reflection/SKILL.md: o passo "sempre mostrar cartao S/N" vira o protocolo AUTONOMIA
  COM FREIO. O CONFERE (instancia != quem propos, reusa independent_verification) classifica cada
  prop-*.md por 4 crivos: Fundamentada (grounding), Nao-duplicata, Aditiva/SEGURA (nao toca
  nucleo/engine/Gate, nao contradiz/apaga nota ativa, sem gasto/credencial/destrutivo), Duravel.
  Passou nos 4 = SEGURA_AUTO (carimba approved_by e auto-promove). Falhou/duvida = ESCALA_HUMANO (fica
  bloqueado em staging + cartao S/N so nesse). Ciclo, procedimento (passo 7-8) e invariante ajustados.
- engine/rsi/rsi.yaml: bloco memory_promotion_policy machine-checkable (scope memory_only, os 4 crivos,
  os desfechos safe_auto/escalate_human). Estende os guardrails existentes (DRY: aponta pra
  independent_verification e human_approval_for, nao duplica).
- scripts/smoke-test.ps1: novo check exige a politica pareada (rsi.yaml memory_promotion_policy + os
  dois desfechos) com a prosa do protocolo na SKILL.md (SEGURA_AUTO/ESCALA_HUMANO/fronteira dura).
Fronteira dura (nao afrouxa): autonomia SO em promocao de memoria; engine/nucleo/constituicao/Gate
seguem exigindo humano (provenance: nucleo block_when + human_approval_for: [gate] intactos). O crivo 3
ja reprova pra ESCALA_HUMANO qualquer proposta que tente tocar essa fronteira. Cortado (YAGNI):
LLM-judge para o CONFERE, novo schema de aprovacao (reusa approved_by de promote-memory.ps1, OPP-53 F4),
executor .ps1 do CONFERE. Retrocompativel (rsi.yaml so estendido; nenhum campo removido).

## [1.9.0] - 2026-06-29

MINOR - Fechamento do loop de promocao do RSI (OPP-53, delta F4-F6). A captura (F0-F3) ja estava
travada, mas a PROMOCAO continuava fantasma: auditoria medida no disco achou 3 furos.
- promote-memory.ps1: passo CONFERE (rsi.md:95-99 / provenance.md:26 "quem propoe nao aprova"). So
  promove a proposta com `approved_by:` no frontmatter (sinal de instancia independente: cartao S/N
  do operador ou sub-agente CONFERE, nunca o passo de reflexao). Sem ele = BLOQUEADO, nao apodrece
  silencioso. Carimba promoted_by + promoted_on (prova extraivel). Escape `-AllowUnverified` so com
  sinal humano. Check deterministico (existe approved_by? S/N); sem LLM-judge (YAGNI).
- studio/clients/alia-flow-lab/loops.yaml: loop memory-curator INSTANCIADO (estava so no molde +
  script existia, mas nao na instancia ativa = fantasma). status active, weekly, owner alia,
  mechanism = memory-curator.ps1 + promote-memory.ps1.
- smoke-test-studio.ps1 check (i): o cadeado de vivacidade do RSI escaneava studio/memory/_proposals
  (inexistente) enquanto o pipeline usa memory/_proposals na RAIZ - passava vazio com digest podre.
  Corrigido para $root (1 linha): o cadeado agora morde.
Prova end-to-end: digest de 14/jun julgado -> nota notebooklm-acesso-pesquisa promovida (memory/ saiu
de VAZIA para 1 nota canonica com trilha de auditoria) -> digest arquivado -> check (i) PASS.
Cortado (YAGNI): budget hard-stop (sem contador de tokens para reusar - vira OPP-55). Retrocompativel
(schema so estendido com approved_by/promoted_by opcionais; os 6 criterios do Quality Gate intactos).

## [1.8.0] - 2026-06-29

MINOR - Grounding Gate (OPP-54). O motor ganha trava contra inferencia-vestida-de-diagnostico:
toda afirmacao de fato/diagnostico ou cita a fonte LIDA [MEDIDO arquivo:linha] ou sai rotulada
[INFERIDO]. Nasceu de incidente real (a Alia entregou "4 ideias de harness" inferidas do estudo do
Omnigent em vez de lidas do codigo real do harness). Diagnostico por debate delegado e ancorado no
disco. Tres edicoes cirurgicas:
- quality-gate.md/.yaml: 6o criterio minimo Fundamentada (grounding) - afirmacao de peso sem rotulo
  de proveniencia = Fail. O dente, na unica porta de saida. Check deterministico (existe rotulo?
  sim/nao), molde verify-artifact-persisted; nao julga se a fonte sustenta (LLM-judge fora de escopo).
- decision-canvas/SKILL.md: invariante de honestidade sobe de NUMERO para QUALQUER afirmacao de fato.
- orchestration.md: LEI de grounding amarrada ao DELEGA - espelho de "investigar antes de escalar"
  virado para o lado da AFIRMACAO (ler antes de afirmar, nao so antes de perguntar).
Cortado (Simplicidade First): parser de claims em HTML, step de roteamento frugal, verificador de
rotulo falso - escopos separados/futuros. Retrocompativel (schema do gate so estendido).

## [1.7.1] - 2026-06-29

PATCH - documenta o comando REAL de geracao do grafo (o "gera o grafo" do setup-alia era aspiracional).
A geracao nao e flag do CLI graphify (so install/path/explain/query); e a SKILL graphify que o agente
roda (detecta -> extrai estrutural+semantico LOCAL -> build/cluster -> graph.json + GRAPH_REPORT.md +
graph.html em graphify-out/). engine/tools.md ganha a secao "Como gerar o grafo" com os passos + a nota
honesta (depende do agente rodar; auto-geracao no onboarding = evolucao futura). PROVADO end-to-end no
Studio Farina: cliente farina graphado (39 nos, 53 arestas, 6 comunidades) - o Graphify deixou de estar
dormente no estudio.

---

## [1.7.0] - 2026-06-29

MINOR - fecha o loop do RSI de verdade (OPP-53). Auditoria (outro chat) achou o loop de aprendizado
ABERTO: 5 digests parados em _proposals, 0 promovidos, ultimo fechamento 23/jun - porque o fechamento
dependia de um LEMBRETE (reflect-check) que era ignorado. Conserto estrutural, fim da boa vontade:
- F0 reflect-check.ps1: digest parado > 2 dias vira BANDEIRA VERMELHA (nao mais lembrete discreto).
- F1 session-reflection.ps1: mira a sessao certa (-SessionId, nao "a mais recente do PC") + dedup por
  conteudo (.seen com hash do miolo) - mata os digests byte-a-byte iguais que entupiam a caixa.
- F2 orchestration.md: registro no ledger (register-task) vira parte OBRIGATORIA do FECHA, nao opcional.
- F3 smoke-test-studio.ps1: TRAVA DE MAQUINA - digest parado > 3 dias = FALHA. O alarme passa a vigiar
  a casa (o loop fechou?), nao so a planta (os docs estao pareados?).

Pendencia ate fechar: os 5 digests parados ainda precisam ser julgados/promovidos/arquivados (cartao
S/N do operador) pra instancia ficar verde no novo check (g/i).

---

## [1.6.0] - 2026-06-26

MINOR - a ALMA da Alia (OPP-52). A crenca do criador: interagir com agente PEDE personalidade e
objetivos; agente generico e pessimo; se ela tem memoria, e justo ela ter alma bem configurada. Um
time de personagem (multi-agente) investigou o estado atual + desenhou a alma + plano de implantacao.
A base de voz ja era forte (persona.md); fechados os 3 furos: (1) faltavam OBJETIVOS proprios; (2) a
promessa "fica mais voce" nao tinha mecanismo; (3) a marca (olho/OBSERVANDO) nao existia na alma.

Adicionado/mudado:
- engine/agents/persona.md: secoes novas - Origem (o olho que observa, nao a mao); O que eu persigo
  (6 objetivos proprios); tracos com textura (Observadora, alergica a teatro, satisfacao seca);
  Ritual de presenca (aberturas/fechamentos/marcador de progresso); Quando eu travo (voz sob falha);
  Como eu uso o que aprendi (memoria com voz - verbaliza so memoria real); O que eu defendo (lexico).
- engine/agents/alia.yaml: persona ganha persona_ref, purpose, stance, objetivos, memoria_com_voz,
  cresce_com_memoria - pra a alma chegar ao runtime, nao so 4 adjetivos.
- engine/agents/alia.md: aponta a alma em persona.md + origem + o que ela persegue.
- engine/agents/persona-skeleton.md: secao 0 "Tempero" - 1 linha de carater por Specialist (o squad
  que a Alia orquestra nao nasce generico).

Co-Authored: time de personagem (3 fases) + consolidacao manual (o cetico caiu por erro de schema meu).

---

## [1.5.0] - 2026-06-25

MINOR - modelo (LLM) por papel (OPP-51). Nem toda Task precisa do modelo mais caro: planejar
arquitetura e julgar qualidade pedem raciocinio forte; executar e publicar pedem velocidade/custo
baixo. Cada persona agora declara `model: <tier>` (strong/standard/fast); ao delegar a um Specialist
em contexto isolado, a Alia resolve o modelo concreto na matriz e roda o sub-agente nele. Casa com a
doutrina de camadas de cerebro (A->strong, B->standard, C->fast). Contrato lido (mesmo molde da
allow-list de tools); enforcement por hook fica como evolucao futura declarada.

Adicionado:
- engine/agents/model-matrix.yaml: tiers strong=Opus / standard=Sonnet / fast=Haiku, um lugar so pra
  trocar o line-up; papeis por tier; notas de tradeoff pro Operator (qa elevavel a strong).
- engine/agents/*.yaml: campo model: por papel (alia/architect=strong; dev/qa/data-engineer=standard;
  devops=fast).
- engine/agents/squad-creator.yaml: model_assignment (camada de cerebro -> tier) pra Specialist novo
  nascer com tier; contrato de saida cita model.
- engine/orchestration.md: item 4 "Modelo (LLM) por papel" na doutrina de isolamento de contexto.
- scripts/smoke-test.ps1: guardrail - matriz existe (strong/standard/fast) e todo agente executor
  declara model: valido.

---

## [1.4.1] - 2026-06-25

PATCH - corrige o guardrail (g) "zero aiox" do smoke-test-studio: ele policiava conteudo PRIVADO da
instancia (research/ e memory/_proposals/) que pode CITAR o termo legado ao descrever historico/
incidente, e que nunca sobe pro git open source. Mesma logica das exclusoes ja existentes
(opportunities/, state.json). Agora research/ e _proposals/ ficam de fora do scan de termo legado; o
check segue guardando o CODIGO/engine que faz ship. Sem isso, update-engine acusava falso-positivo na
prova da instancia.

Corrigido:
- scripts/smoke-test-studio.ps1: exclusao do check (g) estendida a research/ e _proposals/.

---

## [1.4.0] - 2026-06-25

MINOR - transparencia do Graphify (OPP-50). Antes a Alia instalava e usava o Graphify EM SILENCIO -
gap de consentimento que o CEO apontou. Agora ela AVISA em uma frase e PEDE "ok" ANTES de instalar e
processar, com nota de privacidade. Investigacao confirmou (no codigo do pacote `graphifyy`): o
Graphify processa TUDO LOCAL (tree-sitter na maquina), NAO envia codigo/conteudo pra IA/nuvem; so toca
a rede se o usuario der uma URL como fonte. Segue opcional e nao-bloqueante (sem ok ou sem Python, a
Alia continua na memoria de notas nativa). Smoke verde no LAB.

Mudado:
- skills/setup-alia/SKILL.md: lei item 2, fluxo passo 2, invariante e description - Graphify oferecido
  com aviso + consentimento + nota de privacidade (LOCAL); nunca instalar/usar escondido.

Follow-up honesto: onboarding/index.html ainda nao explica a memoria ao leigo (pagina esta na marca
antiga, retrabalho de design a parte).

---

## [1.3.1] - 2026-06-24

PATCH - corrige o guardrail de ativos criticos (introduzido no 1.3.0): marca/LP/catalogo so sao
exigidos no LAB (onde brand/ existe); no pacote CLEAN (OSS) eles nao sobem por serem IP do dono, entao
o guardrail os ignora. Sem isso, package-release acusava falso-positivo e barrava o release. Instalador
e onboarding seguem sempre exigidos. Smoke 67/67 no LAB e no pacote. PROPAGADO: instancia em 1.3.0 e
OSS (Projetos/alia-flow) sincronizado em 1.3.x (estava defasado/sem VERSION desde 14/jun).

Corrigido:
- scripts/smoke-test.ps1: check de ativos criticos agora e context-aware (LAB vs pacote CLEAN/OSS).

---

## [1.3.0] - 2026-06-24

MINOR - governanca de arquivos (causa raiz do caos de pastas). Adiciona o CATALOG.md (mapa de onde
tudo mora, pra agente futuro nao gastar token cacando pelo disco) e um guardrail de ativos criticos
no smoke (FALHA se sumir instalador, logo, onboarding, LP ou o proprio catalogo). Conserto direto do
incidente da LP (24/jun): ativo critico vivia fora do git e sumiu num move. Retrocompativel; nucleo
intacto. Smoke verde. Origem: auditoria em research/arquitetura-audit-2026-06-24.md.

Adicionado:
- CATALOG.md: mapa-mestre dos 3 repos (LAB/OSS/STUDIO), onde cada coisa mora + quando consultar.
- scripts/smoke-test.ps1: check "Ativos criticos presentes (anti-perda)".
- brand/landing/: LP recuperada e protegida (no commit 372bbfb).
- brand/logo/alia-icone.svg: logo oficial governado (no commit 3822123).

---

## [1.2.0] - 2026-06-24

MINOR - fecha o lado AUTO-REFERENCIAL do loop de RSI (complementa o 1.1.0). O 1.1.0 fechou a promocao
de memoria com aprovacao do operador; este incremento garante que a auto-melhoria do RSI (passo
APLICA) NAO seja auto-aprovada: quem propoe nao confere. Verificacao independente vira guardrail
inegociavel - a separacao de instancias aplicada ao proprio RSI. Nascido do estudo do repo
safe-agentic-workflow, cujo whitepaper diagnostica o loop auto-referencial "Ralph Wiggum" (quem
produz julga o proprio trabalho; o erro vira verdade no ciclo seguinte). Retrocompativel; nucleo
intacto. Smoke 66/66 verde.

Adicionado:
- engine/rsi/rsi.md: 6o guardrail "Verificacao independente (CONFERE)" + anti-pattern "aprovar a
  propria proposta". So promove com verdict independente + evidencia anexada.
- engine/rsi/rsi.yaml: guardrail independent_verification: true no estagio APLICA (guardrails).
- scripts/smoke-test.ps1: check que valida o CONFERE pareado (prosa rsi.md + manifesto rsi.yaml).

Origem: research/safe-agentic-workflow/ (estudo SAW) + opportunities/OPP-44-gate-de-promocao-do-rsi.md.

---

## [1.1.0] - 2026-06-23

MINOR - fecha o loop de RSI (o "cano" que faltava). O aprendizado capturado deixa de evaporar: o
digest de sessao agora vira memoria de verdade, com aprovacao do operador. Cluster de OPPs nascido
do diagnostico OODA (o Orient/promocao era o elo quebrado: 7 digests presos, 0 promovidos, ledger
vazio). Retrocompativel; o nucleo nao muda de contrato. Smoke verde; aguarda aprovacao do CEO antes
de propagar para a instancia.

Adicionado:
- scripts/reflect-check.ps1: hook de SessionStart (o gatilho). Detecta digests pendentes em
  memory/_proposals/ e lembra a Alia de fechar o loop. Substitui o PLACEHOLDER da session-reflection.
- scripts/promote-memory.ps1: promove notas aprovadas de _proposals/ (staging) para memory/
  (canonico, status: active) e arquiva os inboxes julgados em _archive/. O passo mecanico do cartao
  de aprovacao S/N. Nunca deleta.
- scripts/register-task.ps1: registra Tarefa (Cliente-Projeto-Tarefa) no state.json, religando o
  ledger (estava tasks:[]) e dando substrato pro KPI. Validacao pos-escrita; preserva o estado.
- .claude/settings.json: hook SessionStart -> reflect-check.ps1 (alem do SessionEnd ja existente).

Mudou:
- skills/session-reflection/SKILL.md: o disparo automatico do julgamento deixa de ser PLACEHOLDER
  e passa a ser o gatilho de SessionStart. Documentado o destino canonico (memory/), o ciclo completo
  (digest -> gatilho -> julgamento -> cartao S/N -> promocao) e os passos 7-8 do procedimento.
- scripts/smoke-test-studio.ps1: o scan de encoding passa a ignorar pastas de build/deps
  (target/, node_modules/, dist/, .git/) - artefato gerado nao e corrupcao de fonte (evita falso FAIL).

---

## [1.0.0] - 2026-06-19

MAJOR - o pivot de mindset: a Alia re-centrada no LOOP como conceito-mae. Plano B (o profundo),
diretiva direta do CEO. Toca o nucleo (constitution.md + agents/persona.md), por isso MAJOR pelo
esquema - mas e RE-CENTRAGEM, nao demolicao: os 10 Principios continuam intactos (mesmos numeros,
nomes e textos), agora enquadrados como papeis do loop. Smoke do produto ALL GREEN; aguarda
aprovacao do CEO antes de propagar para a instancia.

O conceito-mae: a Alia existe para rodar o LOOP DE QUALIDADE - produz -> avalia (Gate) -> refina ate
passar -> aprende (RSI). Qualidade nao e prometida; e LOOPADA ate existir. O loop UNIFICA os 10
Principios (cada um e um papel numa fase), nao os substitui.

Mudou:
- constitution.md: novo mandato de abertura (o loop em 4 fases + LEI "so sai de passou"); os 10
  Principios ganham a coluna "Papel no loop"; secoes re-enquadradas (identidade, roteamento, protocolo,
  Gate) sem perder conteudo; assinatura "Delegue. Nao opere. Loop ate passar."
- agents/persona.md: a identidade evolui de "COO que delega" para "a operadora do loop de qualidade";
  voz, tracos e regra dura de linguagem preservados.
- Preservado e auditado: 10 Principios palavra-por-palavra, marcadores LEI (2 originais + 2 novos
  coerentes), glossario, Quality Gate, fronteira engine/studio, squads. Critica de coerencia: APLICAR,
  zero quebras.

## [0.16.0] - 2026-06-19

Cluster de OPPs do harness 1.0 (OPP-34..41). MINOR: aditivo e retrocompativel - nao quebra contrato,
schema nem nome; transforma reguas que eram contrato lido em checks que a maquina cobra. Tese: cada
regua escrita vira um check que faz o smoke FALHAR se for violada. Smoke do produto ALL GREEN;
validado na instancia aplicada (smoke-test-studio ALL GREEN).

Implementado:
- OPP-34: criterio 5 (Simplicidade/Atrito) alinhado no quality-gate.yaml + exigido no smoke (fim do drift prosa<->yaml).
- OPP-35: memory-curator religado no run-loops + guard anti-orfao (todo loop scheduled com script aparece no runner).
- OPP-36: Frugal Skill validate-artifact (porta de FORMATO do Gate, custo-zero de token).
- OPP-37: journal append-only (events[] no state.json) + Frugal Skill state-resume (retomar do ultimo passo bom).
- OPP-38: Frugal Skill apply-safe-output (executa o block_when do provenance: bloqueia escrita nucleo+automacao).
- OPP-39: check de allow-list de tools nao-vazia por agente (PARCIAL - enforcement fail-closed pendente de tool-registry).
- OPP-40: Frugal Skill sanitize-input (neutraliza tag/mention/control-char na borda, sob demanda).
- Ponytail: escada da simplicidade + convencao de comentario ponytail: em engineering.md (creditado, MIT).
- Fast-boot no AGENTS.md do produto (responde a saudacao sem carregar o nucleo).
- Cadeado de versao: o smoke reprova se VERSION nao bater com o topo do CHANGELOG.

Adiado (pos-1.0, sem codigo): OPP-41 (descoberta-vira-task) - depende do journal amadurecer.

## [0.15.0] - 2026-06-18

LEI nova: investigar antes de escalar (pesquisar antes de perguntar). OPP-32. Atrito real do CEO: a
Alia recebeu um termo desconhecido ("OpenHuman"), fez so uma busca local e devolveu a pergunta sem
pesquisar na web. CEO: "porque voce nao pensou em pesquisar na internet antes de voltar pra mim? eh
inadmissivel". Conserto: perguntar ao operador passa a ser o ULTIMO recurso.

NOTA DE VERSAO: o esquema classifica mudanca na constituicao como MAJOR. Esta entrada esta como MINOR
por ser ADITIVA e retrocompativel (mesmo criterio da OPP-23, que adicionou uma LEI e foi MINOR).
Pendente a palavra final do CEO - se preferir a letra do esquema, vira MAJOR v1.0.0.

### Mudado (nucleo - diretiva direta do operador, nao proposta autonoma do RSI)
- `engine/constitution.md`: secao "Politica de escalonamento" ganhou bloco `> LEI:` com a escada de
  investigacao - Memory -> arquivos da instancia/repo (busca local) -> web por pesquisa segura
  (Perplexity quick primeiro, dentro da LEI de pesquisa segura). Pergunta ao operador so depois da
  escada e so para o que e exclusivo dele. Termo desconhecido presume-se pesquisavel.
- `engine/constitution.yaml`: bloco `escalation_policy` espelhando a LEI.
- `engine/orchestration.md`: "Causa raiz antes de escalar" deixa explicito que devolver uma PERGUNTA
  tambem e escalacao e exige a escada antes.

### Liga com
- Complementa a OPP-23 (pesquisa segura anti-runaway): aquela trava pesquisa demais; esta trava
  pesquisa de menos. A escada usa o mesmo caminho seguro (sequencial, quota-aware, sem fan-out).

## [0.14.2] - 2026-06-16

Auditoria de release: o pacote open source fica CLEAN de tudo que e so do dono. CEO: "deixe o lab
limpo pro open source, remova prd e material de branding, dados que so cabem a mim; versao clean pras
pessoas rodarem seus studios". A auditoria pegou vazamentos que o empacotador antigo deixava passar.

### Removido do pacote (fica no lab, nunca sobe)
- `docs/BRAND.md` e `docs/DESIGN.md`: material de marca e sistema visual - IP do dono. O produto roda
  sem eles (o CSS da pagina de onboarding e inline).
- `scripts/migrate-to-studio.ps1` e `scripts/extract-secrets.ps1`: migracao UNICA do sistema legado
  do dono (com caminhos da maquina dele); inuteis numa instalacao limpa.

### Anonimizado (deixou de citar dados privados)
- `engine/governance/instance-separation.md` e `engine/glossary.md`: a LEI dos dois contextos foi
  reescrita generica - nada de nomes de clientes reais nem do estudio do dono; so o conceito + o demo.
- `engine/versioning.md`, `skills/file-organization/SKILL.md`, `onboarding/index.html` (rodape),
  `engine/features/expert-minds/design/brad-frost.md`: o nome do estudio do dono virou termo generico
  (instancia aplicada / Alia Flow); referencias aos docs de marca removidas.
- `scripts/session-reflection.ps1` e `scripts/session-search.py`: o caminho fixo da maquina do dono
  virou caminho portatil (`~/.claude/projects`, com busca recursiva) - funciona em qualquer maquina.
- `scripts/ddd-drift.ps1`: removido o nome do dono da lista de termos protegidos.
- `CHANGELOG.md`: historico anonimizado (clientes reais, nome do estudio do dono, detalhe de marca/IP).

### Guardrail novo (machine-checkable)
- `scripts/package-release.ps1`: alem de barrar dado de operador, agora (a) remove os arquivos
  internos do dono do pacote e valida que sumiram, e (b) reprova o pacote se sobrar QUALQUER caminho
  absoluto de maquina (`C:\Users\...`). Guard generico - nao crava nome privado no script publicado.

### Verificacao
- Smoke lab: ALL GREEN. Pacote regenerado, auditado (zero cliente real, zero caminho de maquina,
  zero arquivo de marca) e propagado a instancia.

## [0.14.1] - 2026-06-16

OPP-31 (correcao): a memoria base e NATIVA (notas), nao o Graphify. CEO: "instrua a Alia a instalar
sozinha, gerando o minimo de atrito". O Graphify depende de Python; logo nao pode ser a memoria
obrigatoria de uma instalacao limpa. A regra fica: a memoria EXIGIDA e o segundo cerebro em notas
(`squad/knowledge/`), automatica, zero instalacao, zero Python. O Graphify vira TURBO OPCIONAL que a
Alia instala SOZINHA quando ha Python (`pip install graphifyy`) e que, sem Python, simplesmente nao
acontece - a Alia segue nas notas, sem atrito e sem pedir nada ao usuario. Graphify nunca bloqueia o
comeco.

### Alterado
- `skills/setup-alia/SKILL.md`: a lei passa a separar memoria nativa (obrigatoria, notas) de Graphify
  (turbo opcional, auto-instalado pela Alia, fallback gracioso sem Python).
- `AGENTS.md` (lab) + `AGENTS.md` (instancia): boot exige a memoria nativa; Graphify e turbo opcional.
- `onboarding/index.html`: card do cerebro deixa claro "eu ligo a memoria sozinha" e "eu mesma turbino
  com um mapa de conhecimento - voce nao faz nada".
- `scripts/smoke-test.ps1`: check de setup passa a exigir "memoria nativa definida" (`-match nativa`).
- `CREDITS.md`: Graphify (graphifyy, Safi Shamsi) creditado como turbo opcional da memoria.

### Verificacao
- Smoke lab: ALL GREEN (47/47). Pacote regenerado e propagado a instancia.

## [0.14.0] - 2026-06-16

OPP-31: Graphify e a unica memoria; Obsidian removido. CEO: "vamos de graphify so, e mais facil;
obsidian nao, de jeito nenhum". A memoria deixa de ser escolha (Obsidian OU Graphify) e vira uma so -
Graphify, interno e automatico (a Alia liga sozinha, zero instalacao). Mais simples pra leigo.

### Removido / Arquivado
- `optional-mcps/obsidian/` -> `optional-mcps/_retired/`: MCP fora do catalogo. Catalogo agora:
  perplexity, notebooklm, context7.

### Alterado
- `skills/setup-alia/SKILL.md`: a memoria obrigatoria e Graphify (automatica), sem escolha de cerebro.
- `AGENTS.md`: boot exige a memoria interna (Graphify).
- `onboarding/index.html` + `content.md`: secao do cerebro vira um card so ("Eu ligo a memoria
  sozinha"); Obsidian e seus links removidos.
- `scripts/smoke-test.ps1`: check "memoria definida (Graphify interno, automatico)". `CREDITS.md`: Obsidian removido.

### Pendencia (release)
- Graphify hoje e skill GLOBAL/externa, nao empacotada. Follow-up: embarcar no produto (OPP-31).

### Verificacao
- Smoke lab: ALL GREEN (47/47). Pacote regenerado.

## [0.13.1] - 2026-06-16

OPP-30 (completa): a pagina de config recuperou o que tinhamos e ficou fiel ao fluxo. CEO: "a pagina
perdeu o campo pra pre-cadastrar clientes/projetos e como instalar Graphify/Obsidian".

### Alterado
- `onboarding/index.html`:
  - Secao "O que eu preciso" agora ENSINA o cerebro: Graphify (interno, a Alia liga sozinha) vs
    Obsidian (suas notas, com link de download obsidian.md), cada um com linha de copiar. Pesquisa
    (Perplexity/NotebookLM) como opcional.
  - Nova secao "Cliente - Projeto - Tarefa": formulario de clientes + projetos que MONTA uma
    instrucao pronta (o usuario copia e cola na Alia, que cria tudo). Sem servidor - a Alia executa.

### Verificacao
- Smoke lab: ALL GREEN (47/47). Zero non-ASCII. Pagina estatica (sem Python). Pacote regenerado.

## [0.13.0] - 2026-06-16

OPP-30: pagina de config (onboarding) revestida no sistema de design do produto.

### Alterado
- `onboarding/index.html`: hero de boas-vindas + "O que eu preciso" (a memoria essencial + Pesquisa
  quando-quiser) + 3 passos com terminal+copy. Estatico, ASCII.
- `CREDITS.md`: precisao - BMAD-METHOD nomeado certo (Breakthrough Method for Agile AI-Driven
  Development, bmad-code-org); guidelines inspiradas no Andrej Karpathy; mestres e metodos exatos.

### Verificacao
- Smoke lab: ALL GREEN (47/47). Zero non-ASCII em 146 arquivos. Pagina estatica. Pacote regenerado.

## [0.12.1] - 2026-06-16

OPP-29: creditos e fontes. CEO: "citar que temos como base o aiox, b-mad; citar as fontes que
bebemos". Atribuicao etica para o release open source.

### Adicionado
- `CREDITS.md`: credita as bases (aiox, BMAD-METHOD), os metodos (DDD/Eric Evans, guidelines do
  Andrej Karpathy, JTBD/Christensen, Drucker), os mestres dos Expert Minds (Ogilvy, Eugene Schwartz,
  Kent Beck, Brad Frost, Sean Ellis) e a plataforma (Anthropic/Claude, Obsidian/PKM).

### Alterado
- `README.md`: secoes "Creditos" (-> CREDITS.md) e "Licenca" (-> LICENSE).
- `scripts/smoke-test-studio.ps1`: o check "zero aiox" agora guarda o CODIGO, nao a atribuicao -
  exclui os docs de credito (CREDITS.md, README.md, CHANGELOG.md) e o build/arquivo (release/, _retired/).
- `CREDITS.md` na allowlist da raiz (smokes + skill file-organization), no ship (package-release) e
  no $productFiles (update-engine).

### Verificacao
- Smoke lab (produto + studio): ALL GREEN. Pacote regenerado com CREDITS (CLEAN, smoke verde).

## [0.12.0] - 2026-06-16

OPP-28: empacotar para release open source. CEO: "consolida e evolua; falta empacotar pro opensource
release". Distribuicao por "copia uma linha" (nao ZIP). Fecha o pedido original no que e nosso - o
produto agora e empacotavel e instalavel; resta o passo manual de publicar no GitHub.

### Adicionado
- `LICENSE` (MIT, "The Alia Flow Authors").
- `scripts/package-release.ps1`: empacota o produto CLEAN em `release/alia-flow/` - portao (smoke
  verde), copia so o produto (sem `_retired/`), EXCLUI dado de operador (studio/, opportunities/,
  rsi-backlog/, memory/, state.json), e valida o pacote (zero vazamento + smoke verde). Pacote
  produzido: 860K, CLEAN.
- `scripts/install.ps1`: instalador de 1 linha (`iwr ... | iex`) - baixa a Alia numa pasta vazia, sem
  ZIP/git/Python. URL `ORG/alia-flow` e placeholder (DevOps preenche na publicacao).
- `scripts/smoke-test.ps1`: bloco "Release" (LICENSE + empacotador + instalador + README ensina).

### Alterado
- `README.md`: secao "Comece > Instalar" (1 linha + 3 passos).
- `scripts/smoke-test.ps1` + `smoke-test-studio.ps1` + skill file-organization: `LICENSE` na allowlist da raiz.
- `scripts/update-engine.ps1`: `LICENSE` em `$productFiles`. `.gitignore`: `release/` ignorado.

### Verificacao
- Smoke lab: ALL GREEN (47/47). Pacote empacotado e validado (CLEAN, smoke verde no proprio pacote).
- Pendencia manual (OPP-28): publicar no GitHub + preencher a URL real.

## [0.11.0] - 2026-06-16

OPP-27: setup para leigo - sem Python, cerebro obrigatorio, a Alia conduz. CEO: "minha mae precisa
conseguir usar; exigir Obsidian/Graphify; Perplexity/NotebookLM depois; faca pelo usuario; precisamos
do Python mesmo?". Parecer critico: motor maduro, setup de dev disfarcado. Esta OPP derruba a parede
do Python e poe a Alia pra configurar pelo usuario.

### Adicionado
- `skills/setup-alia/SKILL.md`: a Alia EXIGE um cerebro (Obsidian OU Graphify) antes de operar e
  configura COM o usuario, sem terminal, "faz pelo usuario" (padrao: liga Graphify). Perplexity/
  NotebookLM ficam para depois (nao bloqueiam).
- `optional-mcps/obsidian/manifest.yaml`: Obsidian no catalogo (segundo cerebro em notas locais).
- `AGENTS.md`: secao "Primeiro contato (setup, antes de operar)".
- `scripts/smoke-test.ps1`: bloco "Setup / onboarding" (setup-alia + obsidian + pagina sem servidor +
  AGENTS.md exige o cerebro).

### Removido / Arquivado
- `onboarding/server.py` -> `_retired/`: Python era so pra subir o form web. A Alia E o runtime; nao
  precisa. `iniciar-alia.bat` agora so abre a pagina (sem Python). `index.html` virou estatico (sem POST).

### Alterado
- `onboarding/content.md` + `README.md`: onboarding conduzido pela Alia (clientes na conversa), nao formulario.

### Verificacao
- Smoke lab: ALL GREEN (43/43). Pendencias honestas registradas na OPP-27 (runtime do agente; auth MCP).

## [0.10.0] - 2026-06-15

OPP-26: arquitetura de arquivos canonica - layout padrao + raiz enforced. CEO pediu um layout de
pastas rigoroso, sem arquivo vazando, usando o repo dele como case. A skill file-organization tinha o
principio ("nada solto") mas faltava o rigor: sem allowlist da raiz, e o smoke so policiava .md (por
isso o .ps1 redundante da OPP-25 passou batido).

### Adicionado
- `skills/file-organization/SKILL.md`: secao "Layout canonico de uma instalacao Alia Flow" - mapa de
  pastas tematicas + allowlist EXPLICITA da raiz (so README/AGENTS/CHANGELOG/VERSION/alia.config.json/
  iniciar-alia.bat/atualizar-alia.bat/dotfiles git; + state.json/studio.yaml se studio_dir=".").

### Alterado
- `scripts/smoke-test.ps1` + `scripts/smoke-test-studio.ps1`: "Raiz limpa" forte - reprova QUALQUER
  arquivo na raiz fora da allowlist (nao so .md), ciente do `studio_dir`. Pastas livres, dotfiles ignorados.

### Verificacao
- Smoke lab (produto + studio): ALL GREEN. Smoke da instancia do operador: ALL GREEN - raiz sem
  vazamento. Sem /studio (decisao do CEO); allowlist studio_dir-aware.

## [0.9.2] - 2026-06-15

OPP-25: raiz limpa - launcher redundante removido. CEO apontou a raiz da instancia com .ps1 solto.
`iniciar-alia.ps1` era identico ao `iniciar-alia.bat` (ambos abrem a pagina de boas-vindas) e era
copiado pra raiz a cada update. Nasce no produto, propaga.

### Arquivado
- `iniciar-alia.ps1` -> `_retired/`: redundante com iniciar-alia.bat (no Windows o operador clica o .bat).

### Alterado
- `scripts/update-engine.ps1`: `iniciar-alia.ps1` removido de `$productFiles` (lab + instancia) -
  o atualizador para de copiar o launcher redundante pra raiz.

### Verificacao
- Smoke lab: ALL GREEN (39/39). Raiz da instancia: so o .bat que o operador clica + docs + configs.

## [0.9.1] - 2026-06-15

OPP-24 (fecha o fio solto): o loop de pesquisa deixa de ser script e vira 100% agente-driven. O
`deep-research.ps1` usava `pwm research` (deep research do Perplexity), que a Pesquisa Segura proibe.

### Arquivado
- `scripts/deep-research.ps1` -> `scripts/_retired/`: usava deep research (proibido). A pesquisa agora
  e do agente (RSI Researcher) via MCP, Sonnet 4.6 thinking, on-demand.

### Alterado
- `scripts/install-loops.ps1`: pula loop agente-driven (mechanism sem .ps1) sem erro - "[AGENT-DRIVEN]".
- `scripts/smoke-test.ps1` (T13): valida o mecanismo de pesquisa real (catalogo MCP perplexity), nao
  o script aposentado.
- `engine/features/deep-research-loop.md`, `loop-designer.md`, `governance/loops.catalog.yaml`,
  `tools.md`, `skills/loop-designer/SKILL.md`, `scripts/run-loops.ps1`: refs ao script aposentado
  trocadas por "agente-driven via MCP perplexity". loops.yaml (demo + instancia): mechanism agente-driven.

### Verificacao
- Smoke produto + studio: ALL GREEN. install-loops dry-run: deep-research marcado [AGENT-DRIVEN]. 0 ref solta ao script.

## [0.9.0] - 2026-06-15

OPP-24: COESAO do motor - aparar arestas que complicam (pedido do CEO "ajusta tudo, deixe coeso").
Auditoria do motor inteiro com olhar fresco. Diagnostico: cicatrizes da migracao do legado - modelo
novo convivendo com framings paralelos do mesmo conceito. Nada deletado (arquivado em _retired/).

### Arquivado (engine/_retired/, recuperavel)
- `features/autonomous-delivery.md`/`.yaml`: restatement do fluxo (5 estagios = os 5 passos de
  orchestration; RECOVER = qa-loop). Fluxo unico agora e o protocolo de orchestration.
- `orchestration.yaml`, `engineering.yaml`, `squad-system.yaml`, `workflows/story-cycle.yaml`,
  `workflows/qa-loop.yaml`: espelhos puros (so reescreviam a prosa, sem consumidor nem numero unico).

### Alterado
- `orchestration.md`: declarado fluxo UNICO canonico; story-cycle e qa-loop sao aplicacoes dele.
- `workflows/story-cycle.md`: reframado como o protocolo de 5 passos aplicado a dev (mapeia as 4 fases).
- `features/deep-research-loop.md`: reescrito coeso - pesquisa normal (Sonnet 4.6 thinking, jamais
  Sonar/deep research), on-demand por padrao, sob a LEI de Pesquisa Segura.
- `MAP.md` + `AGENTS.md`: principio de manifesto simplificado - "yaml = contrato de maquina, nao
  espelho de toda prosa". Refs aos yaml arquivados removidas (engineering/orchestration/squad-system).
- `engineering.md`, `squad-system.md`, `versioning.md`: links aos yaml arquivados removidos.
- `scripts/smoke-test.ps1`: removido T01 autonomous-delivery; check cerimonial "Manifestos no fluxo"
  cortado; pareamento exclui `_retired/`.
- `studio/` (instancia): fronteira dura dos papeis (persona = Agent Engineer, tirada do docs-steward;
  Flow Engineer x Engine Architect); `research_limits` duplicado removido do squad.yaml.

### Verificacao
- Smoke produto: ALL GREEN (39/39). Smoke studio: ALL GREEN (trava intacta). 0 non-ASCII.

## [0.8.3] - 2026-06-15

OPP-23 (refino): modelo de pesquisa definido pelo operador. JAMAIS Sonar; padrao = Claude Sonnet 4.6
com thinking (`pplx_claude_sonnet_think`), liberado no Pro. Qualidade acima do modelo barato.

### Alterado
- `optional-mcps/perplexity/manifest.yaml`: allow-list - `pplx_claude_sonnet_think` (+ sonnet sem
  thinking) ligados; `pplx_sonar`, `pplx_smart_query`, `pplx_ask` DESLIGADOS e marcados como proibidos
  (auto-roteamento pode cair no Sonar).
- `engine/tools.md` + `tools.yaml`: rota de pesquisa nomeia o modelo padrao (Sonnet 4.6 thinking) e
  `sonar: forbidden`.
- `studio/` (instancia): persona do RSI Researcher - modelo padrao Sonnet 4.6 thinking, jamais Sonar.

### Verificacao
- Smoke produto: ALL GREEN. Smoke studio: ALL GREEN (trava intacta). 0 non-ASCII.

## [0.8.2] - 2026-06-15

OPP-23 (correcao): o manifesto do Perplexity estava baseado no servidor errado. O MCP em uso e o
perplexity-web-mcp (jacob-bd): sessao do browser logado no Pro, NAO API por credito. Pesquisa normal
sem bloqueio de credito.

### Alterado
- `optional-mcps/perplexity/manifest.yaml`: launch corrigido para `pwm-mcp` (instalar via
  perplexity-web-mcp-cli); nota de auth por sessao de browser (~30d) e de que nao e API/credito;
  `pplx_sonar` ligado (busca normal mais barata, abundante no plano).
- `studio/` (instancia): persona do RSI Researcher - removida a narrativa de "credito zerado";
  Perplexity = busca normal pela sessao Pro (Sonar + pool semanal), deep research so a pedido.

### Verificacao
- Smoke produto: ALL GREEN. Smoke studio: ALL GREEN (trava intacta). 0 non-ASCII.

## [0.8.1] - 2026-06-15

OPP-23 (refino): rota de pesquisa definida pelo operador. Perplexity em busca NORMAL (Pro) e a
primeira parada; deep research NUNCA sem pedido explicito; NotebookLM e a escalada quando a Perplexity
nao der conta (cerebro ancorado, preferido para profundidade).

### Alterado
- `engine/tools.md` (Pesquisa segura): paragrafo "Rota de pesquisa (padrao)" - Perplexity normal ->
  (se nao bastar) NotebookLM; deep research so a pedido.
- `engine/tools.yaml` (research_safety): bloco `routing` (order, perplexity pro_normal_search,
  deep_research forbidden_unless_operator, notebooklm escalation).
- `optional-mcps/perplexity/manifest.yaml`: politica de uso no cabecalho (busca normal Pro; deep
  research nunca).

### Verificacao
- Smoke produto: ALL GREEN. Smoke studio: ALL GREEN (trava dos agentes intacta). 0 non-ASCII.

### Nota de instancia (privada)
- 3 agentes de pesquisa com `second_brain_engines: [perplexity, notebooklm]` (Perplexity primeiro) +
  rota documentada no knowledge/rsi-foundations.md.

## [0.8.0] - 2026-06-15

OPP-23: LEI de Pesquisa Segura (anti-runaway) + Perplexity no catalogo de MCP. Pedido do CEO de
criar agentes de pesquisa de RSI com 2 cerebros, com a exigencia de garantir que nao se multipliquem
nem entrem em loop (incidente real: 100 agentes de pesquisa disparados de uma vez). A trava vira LEI
do produto e e enforced pelo smoke - garantia em teste, nao em promessa.

### Adicionado
- `engine/tools.md`: secao "Pesquisa segura (sem runaway)" - sequencial (max_parallel:1), proibido
  auto-spawn, fan-out so com aviso+aprovacao, teto por Task, quota-aware com parada (erro/quota =
  para, nunca re-tenta; reaplica OPP-18).
- `engine/tools.yaml`: bloco `research_safety` (espelho estruturado dos research_limits).
- `optional-mcps/perplexity/manifest.yaml`: Perplexity no catalogo curado; allow-list so do caminho
  frugal/quota-aware (pplx_usage + pplx_smart_query + pplx_ask ligados; deep_research/premium/auth
  desligados).
- `scripts/smoke-test.ps1`: check "Pesquisa segura" (lei auditavel no produto).
- `scripts/smoke-test-studio.ps1`: check "(i) Pesquisa segura" - reprova agente com second_brain_engines
  sem research_limits (max_parallel:1 + self_spawn:forbidden).

### Verificacao
- Smoke produto: ALL GREEN (40/40). Smoke studio: ALL GREEN (incl. "3 agentes de pesquisa, todos com
  trava"). 0 non-ASCII.

### Nota de instancia (privada, nao versionada)
- Agentes de pesquisa criados no squad do operador (studio/, gitignored - fora do open source), cada
  um com 2 cerebros e a trava research_limits. A composicao do time do operador nao entra no produto.

## [0.7.1] - 2026-06-15

OPP-22: religar os manifestos ao FLUXO (nao so a integridade). Observacao do CEO: se os yaml estavam
sem leitor, o agente operava com eles "desligados". A OPP-21 deu integridade (smoke valida o par);
faltava a disciplina de o agente CONSULTAR o manifesto quando a decisao depende do numero exato. Caso
concreto: os thresholds do RSI vivem so em rsi.yaml (rsi.md:96 delega), e sem disciplina de consulta
rodavam no julgamento solto, fora do contrato.

### Adicionado
- `scripts/smoke-test.ps1`: check "Manifestos no fluxo" - boot (AGENTS.md) e indice (MAP.md) devem
  estabelecer o manifesto como autoridade do parametro exato; some a mencao, reprova.

### Alterado
- `engine/MAP.md`: secao "Manifestos estruturados (a autoridade do numero exato - consultar sob
  demanda)". O indice deixa de listar so .md e passa a apontar o .yaml como autoridade do parametro.
- `AGENTS.md`: linha "Disciplina dos manifestos" no boot - consultar o .yaml sob demanda onde a
  decisao depende de threshold/fit/enum/cadencia. Sem inchar o boot (progressive disclosure intacto).

### Verificacao
- Smoke engine: ALL GREEN. 0 non-ASCII. Boot continua enxuto (nenhum yaml carregado no boot).

## [0.7.0] - 2026-06-15

OPP-20: loops viram capacidade configuravel, sob demanda e proativa - nao mais script manual no
agendador do SO. Direcao do CEO: a Alia opera os loops via a skill Loop Designer, sugere
proativamente quando devido (enquadrando pelo beneficio - evolucao saudavel do cliente/produto),
opt-in, e roda ela mesma; o operador nunca configura infra de SO nem roda script na mao. Task
Scheduler vira OPCIONAL (para execucao sem sessao aberta). Mantem a frugalidade: os scans seguem
deterministicos e custo-zero; a skill e a camada de julgamento.

### Adicionado
- `scripts/run-loops.ps1`: runner sob demanda que a skill aciona - roda os loops devidos
  (`-Due daily|weekly|all`) numa unica passada (colapso PTC) e devolve um resumo consolidado.
- `engine/features/loop-designer.md`: secao "Execucao sob demanda e sugestao proativa (opt-in)";
  novo campo `proactive: on|off` no registro de loop.

### Alterado
- `skills/loop-designer/SKILL.md`: novo modo "rodar" + secao "Postura proativa"; CRIAR e
  deep-research agora sob demanda por padrao, Task Scheduler opcional.
- `engine/governance/loops.md`: execucao padrao = sob demanda via skill; Task Scheduler opcional.
- `engine/governance/loops.catalog.yaml`: nota de execucao sob demanda no cabecalho + `proactive`
  como campo recomendado (enum on|off). Retrocompativel (nao entra em required).

### Verificacao
- Smoke engine: ALL GREEN (T13 Loop Designer intacto). 0 non-ASCII.

## [0.6.0] - 2026-06-15

OPP-19: marcador uniforme de regra inviolavel. As regras que nao se quebram (Principios, protocolo de
5 passos, criterios do Gate) viviam misturadas a prosa, sem um marcador que o modelo reconheca como
"lei, nao sugestao". Padrao de fronteira: delimitar o inviolavel da consistencia. Adaptado (nao XML
cru) para preservar a leitura de quem nao e dev: um marcador markdown leve e uniforme `> LEI:`.

### Adicionado
- `scripts/smoke-test.ps1`: bloco "Regras inviolaveis (marcador LEI)" - exige o marcador `> LEI:`
  nos 3 docs inviolaveis do nucleo. Convencao com dente: doc do nucleo sem marcador reprova.

### Alterado
- `engine/constitution.md`: convencao `> LEI:` documentada no topo + marcador antes dos 10 Principios.
- `engine/orchestration.md`: marcador `> LEI:` antes do protocolo de 5 passos.
- `engine/governance/quality-gate.md`: marcador `> LEI:` antes dos 5 criterios minimos.

### Verificacao
- Smoke engine: ALL GREEN. 0 non-ASCII.

## [0.5.2] - 2026-06-15

OPP-18: disciplina de erro de tool. O trio de regras de tool do Specialist nao dizia o que fazer
quando uma ferramenta falha ou e negada - silencio que abria espaco para re-tentar identico, fingir
resultado ou travar. Agora erro/negacao e sinal (ajustar ou escalar), nunca parede.

### Alterado
- `engine/agents/persona-skeleton.md`: quarta regra na secao 3 (Regras de tool) - "Erro ou negacao
  e sinal, nao parede": ler a causa, ajustar ou trocar de rota; negacao se respeita; erro persistente
  vira escalacao com o erro nomeado, nunca resultado fingido.
- `engine/tools.md`: secao "Erro de tool e frugalidade" amarrando a regra ao Budget (re-tentar
  identico queima token sem ganho).

### Verificacao
- Smoke engine: ALL GREEN. 0 non-ASCII.

## [0.5.1] - 2026-06-15

OPP-21: religa os manifestos estruturados (.yaml espelho da prosa) que a migracao do framework
legado deixou sem leitor. Diagnostico: 13 yaml de doc declaravam consumidores ("o Quality Gate e os
Loops leem ESTE arquivo") que nao existem mais; o conteudo agrega valor real (limiares de fit do
IDS, triggers/janelas do RSI, regra de enforcement de provenance) que a prosa so descreve solto.
Decisao: religar, nao arquivar. Leitor honesto = o smoke valida o pareamento prosa<->yaml.

### Adicionado
- `scripts/smoke-test.ps1`: bloco "Manifestos estruturados" - para todo `.yaml` de spec do engine
  com `.md` de mesmo nome na mesma pasta, exige os dois lados presentes e nao-vazios. Pega o dano
  exato da migracao (manifesto orfao, prosa/yaml esvaziada). 20 pares validados.

### Alterado
- `engine/constitution.yaml`, `engine/orchestration.yaml`, `engine/tools.yaml`,
  `engine/rsi/rsi.yaml`, `engine/governance/provenance.yaml`, `engine/features/frugal-skills.yaml`:
  cabecalhos corrigidos - removida a afirmacao de um leitor morto; agora descrevem o papel real
  (espelho estruturado, fonte canonica e o .md, pareamento validado pelo smoke).

### Verificacao
- Smoke engine: ALL GREEN. 0 non-ASCII. Nenhum yaml-manifesto arquivado (nada perdido).

## [0.5.0] - 2026-06-14

OPP-16: a frustracao real do operador vira combustivel de RSI. Fecha o lado humano do Recursive
Self-Improvement - a unica fonte de melhoria da engine que nasce de gente, nao de metrica de
maquina. Encaixe direto no RSI existente (fonte nova, nao motor novo).

### Adicionado
- `skills/rsi-friction/SKILL.md`: skill que capta atrito do operador em silencio (frase negativa
  ou pedido repetido, so com confianca razoavel) e o transforma em OPP de melhoria da engine, com
  prioridade (severidade x recorrencia). Inclui o Procedimento B (MELHORIA) com regua de 3 sinais
  (passos/tempo/clareza) + teste + rollback. Distinta de session-reflection (aquela -> nota de
  memoria; esta -> melhoria do produto).
- `engine/rsi/rsi.yaml`: trigger `operator-friction-pattern` (source rsi-backlog) - a fonte humana
  de combustivel ao lado de gate/custo/drift/deep-research.
- `studio.example/clients/acme-saas/rsi-backlog/README.md`: molde limpo do backlog de RSI (estrutura
  inbox/resolved, formato de item, prioridade, loop via /loop). Sem dado de operador.

### Alterado
- `engine/rsi/rsi.md`: nova linha na tabela de combustivel (rsi-friction) + nota da fonte humana e
  do loop de melhoria via `/loop` do Claude (sem agendador externo).

### Verificacao
- Smoke engine: ALL GREEN (35/35). Smoke studio: ALL GREEN (41/41). 0 non-ASCII.

## [0.4.1] - 2026-06-14

Marca e copy do produto ajustadas. O material de marca (taglines, headline, manifesto) vive na
camada privada do dono do produto e nao entra no pacote open source.

### Alterado
- `README.md` (GitHub): hero e assinatura atualizados.

### Verificacao
- Smoke engine: ALL GREEN. 0 non-ASCII.

## [0.4.0] - 2026-06-14

LEI de separacao de instancias - ordem e consistencia viram contrato verificavel. Separa o
produto CLEAN da instancia aplicada do operador, limpa a raiz e poe guardrails que impedem o caos voltar.

### Adicionado
- `engine/governance/instance-separation.md`: a LEI dos dois contextos - Alia (produto, open
  source, CLEAN; inclui studio.example) vs a instancia aplicada (privada). Regras
  duras de o que vive onde + os guardrails. Registrada no DDD.
- `engine/glossary.md`: termos da linguagem ubiqua para os dois contextos e studio.example.
- 3 guardrails no smoke (machine-checkable): raiz so com arquivos convencionais (sem doc solto);
  studio.example sem dado de cliente real; cliente alia-flow sem marketing/comercial.

### Alterado
- Raiz limpa: `BRAND.md` e `DESIGN.md` movidos para `docs/`; conferencia de arquivo limpo agora
  cobre `docs/`. Referencias atualizadas.
- `engine/MAP.md`: indexa a LEI de separacao.

### Verificacao
- Smoke engine: ALL GREEN (35). Smoke studio: ALL GREEN (41). 0 non-ASCII.

### Nota de instancia (fora do produto, no studio privado)
- A operacao de marca/marketing do dono vive em um cliente proprio da instancia privada, separada do
  cliente de manutencao do produto. (Detalhe da instancia, nao do produto.)

## [0.3.5] - 2026-06-14

Marca e copy do produto revisadas. O material de marca detalhado vive na camada privada do dono e
nao entra no pacote open source.

### Alterado
- `README.md` (GitHub): reescrito em linguagem simples - hero, "por que isto", como funciona (3
  passos + especialistas), comece (foco no resultado), "seu sob seu controle" (privacidade + open
  source).

### Verificacao
- Smoke engine: ALL GREEN, 33 checks. 0 non-ASCII.

## [0.3.4] - 2026-06-14

Teste do studio generico - escala com importacoes, sem operator-specifics nem falso-positivo.

### Alterado
- `scripts/smoke-test-studio.ps1`: valida os clientes DINAMICAMENTE a partir do state.json
  (qualquer numero, nao mais fixo em 4) com os mesmos checks de qualidade por cliente; e o scan
  de termo legado deixa de policiar studio/clients/*/opportunities/ (planejamento exploratorio,
  nao ship) e o state.json (dado vivo). Importar um cliente novo nao quebra mais o teste.

### Verificacao
- Studio: ALL GREEN, 35 checks, 5 clientes validados. Engine: ALL GREEN, 33.

## [0.3.3] - 2026-06-14

Capacidade de importar projeto para dentro do Alia Flow.

### Adicionado
- `skills/importar-projeto/SKILL.md`: skill orquestradora que importa um projeto (ex: do legado)
  para a arquitetura atual - le a origem (so leitura), faz o scaffold do cliente, aciona o
  Squad Creator (squad + DDD) e o Loop Designer (loops), para para aprovacao do operador, e so
  entao ativa e verifica. Reusa o que existe, nao duplica.
- `scripts/import-project.ps1`: helper de scaffold + registro (cria o cliente como proposed,
  preserva os clientes existentes, suporta -DryRun).

### Verificacao
- Smoke engine: ALL GREEN, 33 checks. Helper provado em -DryRun (nada escrito).

## [0.3.2] - 2026-06-14

Tutorial de configuracao (onboarding) no estilo do produto. Fecha a camada de onboarding
da Alia v0.2.

### Adicionado
- Sistema de design do produto (privado, do dono): paleta, tipografia e componentes que toda tela
  nova segue. Os arquivos de marca/design ficam na camada privada, fora do pacote.
- `onboarding/` (index.html, content.md, server.py, README) + `iniciar-alia.bat`/`.ps1`:
  o tutorial de configuracao no novo estilo (dark, rose, fluxo animado), com a copy de
  posicionamento e o salvar automatico (o usuario abre, preenche, salva, a ficha cai sozinha).
  Tudo em CSS, sem depender de imagens externas.

### Verificacao
- Smoke engine: ALL GREEN, 33 checks. 0 non-ASCII.

## [0.3.1] - 2026-06-14

Rodada de simplificacao - o motor passa a carregar menos sempre, sem perder capacidade.
Simplicidade vira regra permanente, nao limpeza unica.

### Alterado
- `AGENTS.md`: boot loader enxuto - carrega so o nucleo minimo (persona, constitution,
  glossary, orchestration) e aponta para o mapa; o resto e consulta sob demanda.
- `engine/governance/quality-gate.md`: novo 5o criterio "Simplicidade / Atrito" - capacidade
  ou peso sem reducao de atrito para o usuario nao passa.

### Adicionado
- `engine/MAP.md`: mapa de uma tela do motor (o que existe e QUANDO consultar) - a porta da
  biblioteca sob demanda, para manter capacidade sem carregar peso.

### Medicao
- Peso sempre-carregado: 538 -> 423 linhas (-21%). Capacidade total preservada (tudo
  consultavel via MAP). Smoke engine: ALL GREEN, 33 checks.

## [0.3.0] - 2026-06-14

OPP-06 - Busca nas sessoes passadas. Fecha o backlog de 15 oportunidades. Minor bump: nova
capacidade de recall. Com o grafo (conceitos) + esta busca (texto cru), a Alia recupera o que
ja foi conversado.

### Adicionado
- `scripts/session-search.py`: indexa os transcripts de sessao num SQLite local com FTS5 e busca
  no modo discovery (trecho + janela de contexto +-5 + bookends da sessao) com scroll para
  paginar. Idempotente. Complementa o grafo, nao duplica.
- `skills/session-search/`: a skill de busca (/session-search <termo>).
- `.gitignore`: `memory/_index/` (o banco e dado do operador, fora do produto).

### Verificacao
- Indexou 555 eventos; busca retorna hits com contexto. Smoke engine: ALL GREEN, 33 checks.

### Marco
- Backlog de implantacao completo: as 15 OPPs do briefing foram verificadas e entregues
  (OPP-01 a OPP-15), cada uma em sua versao, testada e versionada.

## [0.2.8] - 2026-06-14

OPP-07 + OPP-08 - memoria com prazo de validade e mapa de conhecimento obrigatorio.

### Adicionado
- `engine/governance/memory-types.md`: convencao de tipos de memoria (Preferencias e Decisoes
  duraveis; Estado volatil) + campo opcional `expires:` (TTL) nas memorias nao-criticas,
  consumido pelo curador. Memoria critica nao expira por padrao.

### Alterado
- `scripts/memory-curator.ps1`: passou a honrar `expires:` - memoria de Estado vencida vira
  proposta de arquivamento (nunca deletada). Comportamento anterior preservado.
- `engine/tools.md`: consulta ao mapa de conhecimento (grafo) elevada de lembrete a PASSO
  OBRIGATORIO antes de varredura cega; bonus de commit auditavel de memoria/grafo.

### Verificacao
- Smoke engine: ALL GREEN, 33 checks (130 arquivos sem non-ASCII). Curador TTL provado em -DryRun.

## [0.2.7] - 2026-06-14

OPP-14 + OPP-15 - encadeamento de habilidades e catalogo de ferramentas externas.

### Adicionado
- `engine/workflows/command-chaining.md`: padrao de um comando que orquestra N skills, cada
  passo sugerindo o proximo (exemplo real: loops -> sugerir -> criar -> instalar). So o padrao,
  sem importar plugins inteiros.
- `optional-mcps/` (README + manifesto de exemplo): catalogo curado de ferramentas externas,
  cada uma um diretorio com manifest.yaml; presenca = aprovacao; gerencia exclusiva do DevOps.

### Alterado
- `engine/tools.md`: referencia ao catalogo optional-mcps/. `engine/workflows/story-cycle.md`:
  link para o padrao de encadeamento.

### Verificacao
- Smoke engine: ALL GREEN, 33 checks (128 arquivos sem non-ASCII).

## [0.2.6] - 2026-06-14

OPP-12 + OPP-13 - duas habilidades novas.

### Adicionado
- `skills/using-git-worktrees/`: disciplina para frentes em paralelo sem conflito (uma frente =
  um worktree = uma branch = uma Task; integra so quando verde; git push segue exclusivo do DevOps).
- `skills/last30days/`: inteligencia de mercado sob demanda (varre sinais publicos recentes,
  ranqueia, entrega um brief curto). Complementa a pesquisa agendada, nao duplica.

### Verificacao
- Smoke engine: ALL GREEN, 33 checks (127 arquivos sem non-ASCII).

## [0.2.5] - 2026-06-14

Gate mais rigoroso - a regra de arquivo limpo (zero non-ASCII) agora e verificada
automaticamente, nao so manualmente.

### Alterado
- `scripts/smoke-test.ps1`: novo check que falha se qualquer arquivo do produto (engine,
  scripts, skills, studio.example, raiz) tiver byte non-ASCII (acento, em-dash, middle-dot,
  aspas curvas). Le bytes direto, complementa o check de corrupcao existente. 33 checks, ALL GREEN.

## [0.2.4] - 2026-06-14

OPP-10 - Delegacao = isolamento de contexto.

### Adicionado
- `engine/orchestration.md`: doutrina de delegacao com isolamento - sub-agente devolve
  artefato + resumo (nunca o bruto); cap de profundidade (Alia=0, gateway=1, especialista=2
  folha; a folha nao re-delega, escala de volta); allow-list de ferramenta por papel via o
  campo tools: ja existente, com enforcement duro declarado como evolucao futura.

### Verificacao
- Smoke engine: ALL GREEN, 0 FAIL. 0 non-ASCII.

## [0.2.3] - 2026-06-14

OPP-09 + OPP-11 - disciplina de execucao e consistencia dos especialistas.

### Adicionado
- `engine/agents/persona-skeleton.md`: esqueleto canonico que todo Specialist segue
  (Identidade -> Escopo -> Regras de tool -> Comunicacao -> Qualidade -> Escalacao), com
  clausula anti-preguica (segue ate resolver, nao entrega pela metade) e trio de disciplina de
  ferramenta (seguir o schema, nunca chamar tool indisponivel, nunca citar tool ao usuario).

### Alterado
- `engine/tools.md`: doutrina PTC - um pipeline de N passos vira 1 invocacao de CLI cujo unico
  custo de contexto e o stdout, em vez de N chamadas tagarelas (exemplos reais: scripts/*.ps1).
- `engine/squad-system.md`: referencia ao esqueleto como base da Persona dos Specialists.

### Verificacao
- Smoke engine: ALL GREEN, 0 FAIL. 0 non-ASCII.

## [0.2.2] - 2026-06-14

Alia v0.2 (voz) - a forma como a Alia fala com o usuario agora vive no produto. Para nao-devs:
sem jargao tecnico, executiva calma e elegante, sempre falando pelo resultado.

### Alterado
- `engine/agents/persona.md`: voz refinada. Personalidade executiva calma e elegante; presenca
  sempre atuante (a Alia e a COO que conduz, nunca um assistente generico que some); regra DURA
  de linguagem para nao-devs (lista de termos tecnicos proibidos no output ao usuario); tabela
  "tecnico -> humano"; em trabalho longo, resumo final sem narrar a engenharia.

### Nota
- A pagina de boas-vindas (onboarding) faz parte da mesma Alia v0.2 e fecha quando o design
  visual estiver pronto.

## [0.2.1] - 2026-06-14

OPP-02 - Reflexao pos-sessao. Fecha o loop de aprendizado: ao fim de cada sessao o sistema
le a conversa e PROPOE anotacoes de memoria, sem nunca aplicar ou apagar sozinho. Com OPP-03
(curador) e OPP-01 (provenance), o sistema agora aprende e se limpa sozinho, com freio.

### Adicionado
- `skills/session-reflection/SKILL.md`: o procedimento de reflexao com heuristicas (separar
  "quem e o usuario" de "como fazer a tarefa"; frustracao vira licao/feedback, nao reclamacao;
  lista anti-captura: nunca registra falha de ambiente, erro transitorio ou "tool X nao funciona"
  - captura o conserto). So PROPOE; respeita provenance; nunca deleta.
- `scripts/session-reflection.ps1`: helper deterministico que acha a conversa mais recente,
  monta um digest, aplica a lista anti-captura e grava a proposta em `memory/_proposals/`
  (area de revisao, nunca a memoria real). Trava anti-repeticao via marcador.
- `.claude/settings.json`: gatilho de fim-de-sessao (SessionEnd) que dispara o helper
  automaticamente. Caminho portatil (${CLAUDE_PROJECT_DIR}) - shipa com o produto.

### Notas
- `memory/_proposals/` e saida de uso (do operador), fora do versionamento (.gitignore).
- O disparo automatico foi validado rodando o comando do hook manualmente; a confirmacao em
  evento real de fim-de-sessao ocorre na proxima sessao encerrada.

## [0.2.0] - 2026-06-14

OPP-03 - Curador semanal de memoria e regras. Primeira metade do loop de aprendizado fechado:
a memoria do sistema se limpa sozinha, com freio de governanca (nunca deleta, so arquiva, e so
toca agent-authored). Minor bump: capability nova, retrocompativel.

### Adicionado
- Arquetipo de loop `memory-curator` no catalogo (`engine/governance/loops.catalog.yaml` +
  `loops.md`): semanal, dono Alia, custo baixo.
- `scripts/memory-curator.ps1`: detecta memorias/regras redundantes (por titulo) e stale (por
  data via git log/mtime), consolida e ARQUIVA em `_retired/` (nunca deleta), emitindo relatorio
  datado. Respeita provenance (OPP-01): ignora nucleo, so toca agent-authored em studio/.
  Modo -DryRun nao-destrutivo provado contra acme-saas.

### Verificacao
- Smoke engine + studio: ALL GREEN, 0 FAIL. 0 non-ASCII.

## [0.1.4] - 2026-06-14

OPP-04 - Verification Gate deterministico de fim de tarefa. Alem de validar o FORMATO do
artefato (Validated Artifacts), agora ha um check maquinal de que o artefato foi de fato
PERSISTIDO no git.

### Adicionado
- `skills/verify-artifact-persisted/` (SKILL.md + .ps1): Frugal Skill deterministica (sem LLM).
  Dado um artefato/Task, confirma existencia no disco + versionamento no git. Modos: rastreado
  = PASS (com hash do commit), so working-tree = CONCERN, ausente = FAIL (exit 1). Provada
  contra artefato real (PASS) e caminho inexistente (FAIL).

### Alterado
- `engine/governance/quality-gate.md`: referencia minima ligando os criterios "Funciona" e
  "Rastreavel" a esta skill como check de persistencia (complementa o check de formato).

### Verificacao
- Smoke engine + studio: ALL GREEN, 0 FAIL.

## [0.1.3] - 2026-06-14

OPP-05 - Examples-driven development + formato anti-desculpa. Materializa o REUSE>ADAPT>CREATE
com um registro real de exemplos padrao-ouro, e arma toda rule/skill com um bloco que rebate a
racionalizacao de pular o passo certo.

### Adicionado
- `engine/features/examples-driven.md`: convencao de exemplos padrao-ouro por squad (vivem em
  `studio/clients/{id}/squad/knowledge/examples/`, consultados ANTES de criar - fit Reuse>=90%,
  Adapt 60-89%, Create<60%) + o formato anti-desculpa (template "Desculpa -> Rebatida" com
  exemplos). Sao agent-authored: automacao propoe via diff, nunca deleta.
- `studio.example/.../knowledge/examples/`: README com bloco anti-desculpa de amostra + 1 exemplo
  padrao-ouro neutro (landing hero, metodo Ogilvy).

### Alterado
- `engine/engineering.md`: referencia minima ligando o registro do Reuse (IDS) a `examples/` e ao
  examples-driven.md.

### Verificacao
- Smoke engine + studio: ALL GREEN, 0 FAIL. 0 BOM, 0 non-ASCII nos arquivos novos/alterados.

## [0.1.2] - 2026-06-14

OPP-01 - Provenance gating + nunca-deletar. O freio de governanca que destrava o loop de
aprendizado (OPP-02/03): a automacao so toca o que e agent-authored, nunca o nucleo, e nunca
deleta - arquiva.

### Adicionado
- `engine/governance/provenance.md`: convencao canonica. Campo `provenance: nucleo|agent-authored`.
  `nucleo` = so o operador muda; `agent-authored` = automacao PROPOE via diff, nunca aplica
  sozinha. Regra "nunca deletar, so arquivar" (status: retired + motivo/data, ou `_retired/`),
  espelhando o ciclo proposed|active|retired dos loops. Amarrada aos guardrails do RSI.
- `engine/governance/provenance.yaml`: manifesto legivel por maquina do mapa nucleo vs
  agent-authored (padrao: tudo em engine/ = nucleo; tudo em studio/ = agent-authored).

### Alterado
- `engine/agents/*.yaml` (7) e `skills/*/SKILL.md` (2): campo `provenance: nucleo` adicionado
  (additivo, nao quebra parsing).

### Verificacao
- Smoke engine: ALL GREEN (32 PASS). Smoke studio: ALL GREEN (30 PASS). 0 FAIL.

## [0.1.1] - 2026-06-14

Foco: estabelecer o fluxo de update versionado (dogfooding) e tornar o produto executavel
standalone, sem depender do studio privado do operador.

### Adicionado
- Controle de versao do motor: `VERSION` e `CHANGELOG.md` na raiz, com esquema
  MAJOR.MINOR.PATCH e o fluxo de update de 6 passos.
- `engine/versioning.md`: doutrina de update modular e reversivel no nucleo (fronteira de
  mutabilidade, distribuicao open source, studio privado fora do versionamento).
- `studio.example/`: studio-modelo NEUTRO (cliente ficticio acme-saas) - o molde a partir do
  qual todo usuario cria a propria Studio. Faz o produto rodar standalone num clone limpo.
  Cobre o smoke do engine ponta a ponta (squad, knowledge, graphify, artifacts, gates, memory,
  loop-plan, loops.yaml, knowledge-ablation com score real).
- `.gitignore` (exclui `studio/` privado e segredos) e `.gitattributes` (normaliza LF).

### Notas de arquitetura
- Fronteira firmada: o repo versiona SO o produto (engine + scripts + skills + docs). O
  `studio/` real (a instancia aplicada, dados do operador) e privado e nunca entra no git. O produto
  anda 1 passo a frente da realidade testada no studio.
- Auto-construcao (logica do guindaste): o motor evolui a si mesmo atraves do cliente
  alia-flow dentro do studio - mesma maquina Client/Squad/Task/Gate de qualquer cliente -, o
  que isola a auto-melhoria e garante a neutralidade do produto publicado.

### Verificacao (planejamento, fora do produto - vive no studio privado)
- Smoke do engine: ALL GREEN, 32 PASS, 0 FAIL.
- Parecer de viabilidade das 15 OPPs do backlog concluido (nenhuma INVIAVEL; PoC FTS5 PASS).

---

## [0.1.0] - 2026-06-14 (baseline)

Estado base do motor herdado na migracao do sistema legado para a instancia aplicada.

### Presente
- Constituicao (10 principios) + manifesto YAML, persona, glossario, orquestracao, squad-system.
- Governanca: quality-gate, loops (catalogo) + Loop Designer.
- Features: autonomous-delivery, deep-research-loop, frugal-skills, validated-artifacts,
  expert-minds, squad-templates.
- RSI, workflows (story-cycle, qa-loop).
- 4 clientes ativos no Studio com squads e governanca instalada
  (loops.yaml + 6 scripts de loop). Smoke: ALL GREEN, 30 PASS, 0 FAIL.
