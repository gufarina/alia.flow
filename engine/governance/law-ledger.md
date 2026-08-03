# Law Ledger - registro de toda LEI declarada no motor (M4)

> Regra de formacao: lei nova SO entra neste motor com um teste que possa ficar vermelho, citado
> aqui na mesma Task que a declara. Se o teste ainda nao existe, a lei entra IGUAL - mas nasce
> marcada `SEM TESTE` (divida visivel), nunca vira a 23a lei so-em-prosa.
> Crivo de poda (uma pergunta): a lei tem teste? Sim -> `COBERTA`. Nao, e sem reincidencia
> documentada -> candidata a `HISTORICA`. Nao, e com reincidencia documentada -> vira teste (P0).
> Levantamento: `grep -rn "^> LEI\|^## LEI\|^# LEI\|\bLEI\b" engine/` + leitura de cada ocorrencia
> (14 arquivos citam "LEI"; 25 sao declaracao normativa, o resto e mencao/referencia cruzada).
> Sem acentos, sem emojis. UTF-8 sem BOM.

---

## Registro

| id | lei (resumo) | onde vive | teste que a reprova | veredito |
|----|---------------|-----------|----------------------|----------|
| L01 | Artifact so sai de "produz" quando passou no Gate | engine/constitution.md:19 | smoke-test.ps1:168 `Check "E2E: cada Task tem artifact + gate PASS + memoria"` | COBERTA |
| L02 | Os 10 Principios da constituicao sao inviolaveis | engine/constitution.md:48 | nenhum script testa o guarda-chuva; sub-principios tem cobertura PARCIAL e dispersa (Delegation via L12/hook OPP-74; Gate via L11) mas a assercao "os 10 sao inviolaveis" em si nao tem teste proprio | SEM TESTE |
| L03 | Perguntar ao operador e o ultimo recurso (escada Memory->local->web antes) | engine/constitution.md:128 | nenhum script verifica se a escada foi esgotada antes de uma pergunta | SEM TESTE |
| L04 | RSI nunca toca o nucleo do Engine nem a Constituicao | engine/constitution.md:171 | scripts/guard-core.ps1 (sentinela de hash contra `.core-baseline.sha256`) + smoke-test.ps1:942 `Check "Nucleo: integro vs baseline (sentinela; mudanca de nucleo exige -AllowCore)"` | COBERTA |
| L05 | LEI 1 - Knowledge-first: carregar fonte curada ANTES de produzir | engine/governance/client-truth.md:12 | nenhum script confere se o produtor CARREGOU a fonte antes de produzir (depende de disciplina do agente, nao ha trilha verificavel automatizada) | SEM TESTE |
| L06 | LEI 2 - Claims Registry: fato publico so com fonte aprovada, veto nunca ressuscita | engine/governance/client-truth.md:34 | scripts/semantic-lint.ps1 + smoke-test.ps1:974 `Check "Guard: CLAIMS.md declara termos proibidos (GUARD:)"`, :981 `Check "Guard: veto ausente do motor -> /pattern/"`, :1067-1068 (Guard publico) e :1127-1128 (Guard scripts) - cobrem a clausula mais grave (veto ressuscitado); fabricacao de numero por soma de fontes e feature-nao-lancada NAO tem check dedicado, ficam para julgamento humano/LLM do Gate | COBERTA (parcial - ver nota) |
| L07 | LEI 3 - Escopo publico vs interno: vocabulario de bastidor nao vaza pra peca | engine/governance/client-truth.md:51 | nenhum script varre peca publica atras de jargao interno generico (so o subconjunto "termo vetado" e pego pelo Guard de L06, nao o vocabulario de bastidor em geral) | SEM TESTE |
| L08 | LEI 4 - Reuse-first de ativos: inventariar antes de criar ativo de marca | engine/governance/client-truth.md:62 | nenhum script confere inventario-antes-de-criar | SEM TESTE |
| L09 | Todo loop instanciado declara os 6 campos do contrato (OPP-57) | engine/governance/loops.md:65 | smoke-test.ps1:346 `Check "Loops: contrato de 6 elementos (OPP-57) em todo loop do demo"` + :764 `Check "Loops: contrato de 6 elementos pareado em loops.md + loops.catalog.yaml"` | COBERTA |
| L10 | Git e vitrine, nao gaveta - so produto publico entra no repo | engine/governance/public-surface.md:8 | scripts/check-public-surface.ps1 (reprova arquivo de desenvolvimento rastreado + oficina com remoto); nao roda dentro do smoke, roda antes de publicar (mandato do CEO 01/08) | COBERTA |
| L11 | Os 6 criterios do Quality Gate sao inegociaveis | engine/governance/quality-gate.md:18 | smoke-test.ps1:810 `Check "Gate: criterio Funciona exige execucao, pareado em quality-gate.md + .yaml"` + :811 `Check "Gate: os outros 5 criterios seguem intactos"` | COBERTA |
| L12 | Os 5 passos do protocolo (IDENTIFICA/REGISTRA/DELEGA/MONITORA/FECHA) sao ciclo de vida inviolavel | engine/orchestration.md:22 | smoke-test.ps1:168 (E2E artifact+gate+memoria), :191 (linhagem completa), scripts/register-task.ps1 validado em smoke-test.ps1:886-894 (Status default open = REGISTRA antes de executar; -Type ValidateSet; erro sem -Project) | COBERTA |
| L13 | Rastreabilidade e continuidade: toda demanda vira Task com linhagem (project+base_artifact+session) | engine/orchestration.md:43 | smoke-test.ps1:191 `Check "Rastreabilidade: toda Task com artifact tem linhagem completa (project+base_artifact+session)"` + :196-205 (task-context.ps1 aponta ultima revisao) | COBERTA |
| L14 | Grounding: afirmar fato exige LEU (Specialist) ou rotulo [INFERIDO] | engine/orchestration.md:58 | quality-gate.yaml declara `check: grounding-label-present` como se fosse deterministico, mas nenhum script em scripts/ ou skills/ implementa essa verificacao por artefato (confirmado por grep - so aparece como texto de contrato em skills de marketing, nao como enforcement); smoke-test.ps1 so confere PRESENCA do texto no doc, nao a substancia por artefato | SEM TESTE |
| L15 | Fonte de verdade do cliente antes de produzir Artifact (mirror combinado de L05+L06) | engine/orchestration.md:70 | mesma cobertura de L06 so alcanca a clausula de veto; a parte "quem produz CARREGA as fontes curadas" (equivalente a L05) segue sem verificacao automatica | SEM TESTE |
| L16 | Devolver pergunta ao operador E escalacao - mesma regra da escada (duplicata textual de L03) | engine/orchestration.md:175 | nenhum script verifica a escada antes da pergunta (mesma lacuna de L03) | SEM TESTE |
| L17 | Olhos da Alia: Tasks paradas tem que ter alguem olhando (OPP-70) | engine/orchestration.md:187 | smoke-test.ps1:305 (stale-tasks.ps1 + fixture), :310 (determinismo pega antiga/ignora recente), :315 (mission-control tem KPI de paradas), :318 `Check "Paradas: LEI 'olhos da Alia' em orchestration.md (no bastidor)"` | COBERTA |
| L18 | Squad Owner e dono ativo, nao roteador passivo (OPP-67, 4 tracos de owner_soul) | engine/squad-system.md:57 | smoke-test.ps1:220 `Check "Owner soul: contrato owner_soul (4 tracos) em squad-creator.yaml + doutrina em squad-system.md"` + :239 `Check "Owner soul: Gateway do demo carrega os 4 tracos na persona"` | COBERTA |
| L19 | Todo Client carrega Especificacao de Entrega no segundo cerebro (OPP-68) | engine/squad-system.md:136 | smoke-test.ps1:254 `Check "Consistencia: Especificacao de Entrega presente no knowledge do demo + LEI em squad-system.md"` + :256 (squad-creator fecha com spec, step g) | COBERTA |
| L20 | Grafo do graphify e pre-condicao operacional de todo Client (OPP-68) | engine/squad-system.md:145 | scripts/graph-check.ps1 + smoke-test.ps1:259 (script presente), :262 (aprova Client com grafo), :269 `Check "Grafo: graph-check REPROVA client sem grafo (exit 1)"` | COBERTA |
| L21 | Pesquisa segura: agente de pesquisa nao se multiplica nem entra em loop | engine/tools.md:143 + engine/tools.yaml:58 | smoke-test.ps1:717 `Check "LEI de pesquisa segura documentada (tools.md + tools.yaml)"` + smoke-test-studio.ps1:299 `Check "Pesquisa segura: N agente(s) ... todos com trava (max_parallel:1 + self_spawn:forbidden)"` (este ultimo testa os agentes REAIS, nao so a prosa) | COBERTA |
| L22 | Produto so produto: Contexto Produto nunca contem dado do operador (regra geral) | engine/governance/instance-separation.md:56 | nenhum guardrail dedicado cobre o caso geral; so as 3 instancias especificas abaixo (L23-L25) tem check - uma nova pasta em engine/ ou scripts/ com dado de cliente escaparia das 3 | SEM TESTE |
| L23 | Raiz so convencional: nenhum .md solto fora da allowlist | engine/governance/instance-separation.md:58 | smoke-test.ps1:468 `Check "Raiz limpa: so a allowlist canonica (nenhum arquivo vaza)"` + smoke-test-studio.ps1:178 (mesmo check no lado da instancia) | COBERTA |
| L24 | studio.example limpa: clients/ contem SO o demo acme-saas | engine/governance/instance-separation.md:61 | smoke-test.ps1:479 `Check "studio.example limpa: so o demo acme-saas em clients/"` | COBERTA |
| L25 | Marca/go-to-market fora do produto: nunca pasta marketing/comercial no cliente de manutencao | engine/governance/instance-separation.md:63 | smoke-test-studio.ps1:272 `Check "alia-flow CLEAN: sem pasta marketing/comercial"` | COBERTA |

Nota sobre L22-L25: `instance-separation.md` declara a LEI num arquivo dedicado ("As regras duras (a
LEI)"), sem usar o marcador `> LEI:` do resto do motor - por isso o grep estrito por esse marcador
NAO pegou essas 4 regras; so apareceram na varredura ampla por `\bLEI\b` seguida de leitura. Foram
incluidas aqui porque sao declaracao normativa real, nao mencao, e 3 das 4 ja tem guardrail citado
no proprio arquivo (tabela "Os guardrails que fazem a LEI cumprir").

Nota sobre L21: tools.md:143 (prosa) e tools.yaml:58 (comentario sobre o contrato `research_safety`)
sao a MESMA lei em duas formas (prosa + config); o proprio smoke-test.ps1:717 as testa juntas num
unico Check. Contadas aqui como uma linha, nao duas, por isso o total abaixo fecha em 25 e nao 26.

## Placar

- Total de leis registradas: **25** (21 pelo marcador convencional `> LEI:`/`## LEI`/`# LEI`
  reduzido de 22 matches de grep para 21 linhas por a L21 fundir tools.md+tools.yaml; mais 4 de
  `instance-separation.md`, achadas so na varredura ampla).
- **COBERTA: 16** (L01, L04, L06-parcial, L09, L10, L11, L12, L13, L17, L18, L19, L20, L21, L23, L24, L25)
- **SEM TESTE: 9** (L02, L03, L05, L07, L08, L14, L15, L16, L22)
- **HISTORICA: 0** (nenhuma lei encontrada e decisao pontual ja absorvida; toda LEI viva no motor e
  regra operacional continua, nao um registro de decisao passada)

---

## Candidatas a poda - aguardando decisao

Nenhuma lei aqui foi apagada. Lista abaixo = SEM TESTE + sem reincidencia documentada no proprio
motor (evidencia de reincidencia teria que aparecer como comentario de incidente/OPP em algum
script, do jeito que L12/Delegacao cita OPP-74 e L17 cita OPP-70). As que TEM reincidencia
documentada (nenhuma das SEM TESTE atuais cita um OPP de reincidencia no motor) ficam de fora desta
lista de poda e vao direto pro "5 mais perigosas" do relatorio de entrega - a poda so serve pra
quem nunca reincidiu.

| id | lei | o que se perde virando HISTORICA |
|----|-----|-----------------------------------|
| L02 | 10 Principios inviolaveis (guarda-chuva) | perde-se o unico lugar que afirma "os 10 juntos sao um pacote inegociavel"; os sub-principios com teste proprio (Delegation, Gate) continuam protegidos, mas a leitura de conjunto vira so historico |
| L03/L16 | Pergunta ao operador e ultimo recurso (a mesma regra, 2 locais) | perde-se o freio textual contra "perguntar de primeira"; sem ele, e sem teste, o unico freio que resta e a memoria de sessao do agente - o mesmo padrao que fez a Delegacao reincidir 2x antes do hook |
| L05 | Knowledge-first (carregar fonte antes de produzir) | perde-se o mandato explicito que nasceu do dia 07/jul; sem ele, so resta o criterio 6 do Gate (Fundamentada) como rede de seguranca indireta |
| L07 | Escopo publico vs interno (vocabulario de bastidor) | perde-se a regra que impede jargao interno de vazar pra peca fora dos termos ja vetados (que o Guard pega); o resto do vocabulario interno fica sem guarda nenhuma |
| L08 | Reuse-first de ativos | perde-se o mandato contra recriar ativo de marca por descuido; nenhum mecanismo substitui |
| L15 | Fonte de verdade do cliente (mirror em orchestration.md) | e duplicata textual de L05+L06 num arquivo diferente; rebaixar so ela (mantendo L05/L06 vivas em client-truth.md) NAO perde protecao real - e a candidata mais segura desta lista |
| L22 | Produto so produto (regra geral de instance-separation) | perde-se a cobertura do caso GENERICO; os 3 vetores concretos (raiz, studio.example, marca/GTM) continuam testados por L23-L25 |

Leitura do CEO recomendada antes de decidir: L15 e a poda mais segura (duplicata pura, zero perda
real). L03/L16, L05 e L08 sao as que mais se parecem com o padrao que fez a Delegacao reincidir -
poda-las sem antes cobrir com teste repete o erro que este movimento existe pra fechar.
