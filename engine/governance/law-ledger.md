# Law Ledger - registro de toda LEI declarada no motor (M4)

> Regra de formacao: lei nova SO entra neste motor com um teste que possa ficar vermelho, citado
> aqui na mesma Task que a declara. Se o teste ainda nao existe, a lei entra IGUAL - mas nasce
> marcada `SEM TESTE` (divida visivel), nunca vira a 23a lei so-em-prosa.
> Crivo de poda (uma pergunta): a lei tem teste? Sim -> `COBERTA`. Nao, e sem reincidencia
> documentada -> candidata a `HISTORICA`. Nao, e com reincidencia documentada -> vira teste (P0).
> Levantamento: `grep -rn "^> LEI\|^## LEI\|^# LEI\|\bLEI\b" engine/` + leitura de cada ocorrencia
> (14 arquivos citam "LEI"; 25 sao declaracao normativa, o resto e mencao/referencia cruzada).
> CONSERTO (auditoria forense, defeito 8, 09/08/2026): o levantamento e os ponteiros deste arquivo
> eram mantidos A MAO e apodreceram (todo ponteiro de linha citado estava errado; 20 das 29 leis
> apontavam so para um script que nao roda nesta instancia). `scripts/law-ledger-check.ps1` agora
> CONFERE este arquivo contra o disco: (A) reprova se algum marcador de LEI em `engine/**.md` nao
> tiver entrada na coluna "onde vive" (foi ele que pegou L30/persona.md faltando); (B) reprova
> ponteiro `script.ps1:linha` cujo texto citado nao bate com a linha real do script. Rode-o antes
> de confiar neste arquivo; `scripts/smoke-test-studio.ps1` secao (m) ja o chama.
> Sem acentos, sem emojis. UTF-8 sem BOM.

---

## Registro

| id | lei (resumo) | onde vive | teste que a reprova | veredito |
|----|---------------|-----------|----------------------|----------|
| L01 | Artifact so sai de "produz" quando passou no Gate | engine/constitution.md:19 | scripts/smoke-test.ps1:178 `Check "E2E: cada Task tem artifact + gate PASS + memoria"` [SEM MAQUINA NESTA INSTANCIA - ver nota] | COBERTA (produto) - SEM MAQUINA NESTA INSTANCIA |
| L02 | Os 10 Principios da constituicao sao inviolaveis | engine/constitution.md:48 | scripts/law-ledger-check.ps1 `Check "L02 formato: constitution.md declara o marcador de LEI dos 10 Principios e a tabela tem 10 linhas (I-X)"` (roda direto nesta instancia) - CHECK DE FORMATO (marcador + a tabela tem as 10 linhas), nao confere se o Quality Gate de fato bloqueou uma violacao real | COBERTA (formato, poda 09/08/2026) - nucleo protegido, nao podada |
| L03 | Perguntar ao operador e o ultimo recurso (escada Memory->local->web antes) | engine/constitution.md:128 | scripts/law-ledger-check.ps1 `Check "L03 formato: constitution.md declara o marcador de LEI do escalonamento e os 3 degraus da escada (Memory/local/web)"` (roda direto nesta instancia) - CHECK DE FORMATO (marcador + os 3 degraus nomeados), nao confere se a escada foi de fato esgotada antes de uma pergunta real | COBERTA (formato, poda 09/08/2026) - nucleo protegido, nao podada |
| L04 | RSI nunca toca o nucleo do Engine nem a Constituicao | engine/constitution.md:183 | scripts/guard-core.ps1 (sentinela de hash contra `.core-baseline.sha256`, roda direto nesta instancia) + scripts/smoke-test.ps1:1024 `Check "Nucleo: integro vs baseline (sentinela; mudanca de nucleo exige -AllowCore)"` [SEM MAQUINA NESTA INSTANCIA - ver nota] | COBERTA (guard-core.ps1 roda aqui; o wrapper smoke-test.ps1 nao) |
| L05 | LEI 1 - Knowledge-first: carregar fonte curada ANTES de produzir | engine/governance/client-truth.md:12 | scripts/law-ledger-check.ps1 `Check "L05 formato: client-truth.md declara LEI 1 (Knowledge-first) com a hierarquia de 4 fontes numerada"` (roda direto nesta instancia) - CHECK DE FORMATO (o bloco e a hierarquia de 4 fontes existem no arquivo), nao confere se o produtor de fato CARREGOU a fonte antes de produzir (isso continua sem trilha automatizada, e trabalho do Gate/criterio 6) | COBERTA (formato, poda 09/08/2026) |
| L06 | LEI 2 - Claims Registry: fato publico so com fonte aprovada, veto nunca ressuscita | engine/governance/client-truth.md:34 | scripts/semantic-lint.ps1 (roda direto nesta instancia) + scripts/smoke-test.ps1:1073 `Check "Guard: CLAIMS.md declara termos proibidos (GUARD:)"`, :1081 `Check "Guard: veto ausente do motor -> /pattern/"`, :1173-1174 (Guard publico) e :1233-1234 (Guard scripts) [SEM MAQUINA NESTA INSTANCIA - ver nota] - cobrem a clausula mais grave (veto ressuscitado); fabricacao de numero por soma de fontes e feature-nao-lancada NAO tem check dedicado, ficam para julgamento humano/LLM do Gate | COBERTA (parcial; semantic-lint.ps1 roda aqui, o wrapper smoke-test.ps1 nao - ver nota) |
| L07 | LEI 3 - Escopo publico vs interno: vocabulario de bastidor nao vaza pra peca | engine/governance/client-truth.md:51 | scripts/law-ledger-check.ps1 `Check "L07 formato: client-truth.md declara LEI 3 (escopo publico vs interno) com a pergunta-gatilho QUEM LE ISTO"` (roda direto nesta instancia) - CHECK DE FORMATO (o bloco e a pergunta-gatilho existem no arquivo); so o subconjunto "termo vetado" continua pego em CONTEUDO real pelo Guard de L06 - vocabulario de bastidor em geral segue sem varredura de conteudo | COBERTA (formato, poda 09/08/2026) |
| L08 | LEI 4 - Reuse-first de ativos: inventariar antes de criar ativo de marca | engine/governance/client-truth.md:62 | scripts/law-ledger-check.ps1 `Check "L08 formato: client-truth.md declara LEI 4 (reuse-first) com o mandato INVENTARIAR antes de criar"` (roda direto nesta instancia) - CHECK DE FORMATO (o bloco e o mandato existem no arquivo), nao confere se o inventario de fato aconteceu antes de criar um ativo real | COBERTA (formato, poda 09/08/2026) |
| L09 | Todo loop instanciado declara os 6 campos do contrato (OPP-57) | engine/governance/loops.md:65 | scripts/smoke-test-studio.ps1 `Check ($cid + ": " + $activeCount + " loop(s) active com os 6 elementos (OPP-57)")` (roda contra os loops REAIS desta instancia) + scripts/smoke-test.ps1:356 `Check "Loops: contrato de 6 elementos (OPP-57) em todo loop do demo"` e :846 `Check "Loops: contrato de 6 elementos pareado em loops.md + loops.catalog.yaml"` [SEM MAQUINA NESTA INSTANCIA - ver nota] | COBERTA (via smoke-test-studio.ps1 nesta instancia) |
| L10 | Git e vitrine, nao gaveta - so produto publico entra no repo | engine/governance/public-surface.md:8 | scripts/check-public-surface.ps1 (reprova arquivo de desenvolvimento rastreado + oficina com remoto); nao roda dentro do smoke, roda antes de publicar (mandato do CEO 01/08) | COBERTA |
| L11 | Os 6 criterios do Quality Gate sao inegociaveis | engine/governance/quality-gate.md:18 | scripts/smoke-test.ps1:892 `Check "Gate: criterio Funciona exige execucao, pareado em quality-gate.md + .yaml"` + :893 `Check "Gate: os outros 5 criterios seguem intactos"` [SEM MAQUINA NESTA INSTANCIA - ver nota] | COBERTA (produto) - SEM MAQUINA NESTA INSTANCIA |
| L12 | Os 5 passos do protocolo (IDENTIFICA/REGISTRA/DELEGA/MONITORA/FECHA) sao ciclo de vida inviolavel | engine/orchestration.md:22 | scripts/smoke-test.ps1:178 (E2E artifact+gate+memoria), :201 (linhagem completa), scripts/register-task.ps1 (roda direto nesta instancia) validado em scripts/smoke-test.ps1:968-972 (Status default open = REGISTRA antes de executar; -Type ValidateSet; erro sem -Project) [SEM MAQUINA NESTA INSTANCIA - ver nota] | COBERTA (produto; register-task.ps1 roda aqui, o wrapper smoke-test.ps1 nao) |
| L13 | Rastreabilidade e continuidade: toda demanda vira Task com linhagem (project+base_artifact+session) | engine/orchestration.md:47 | scripts/smoke-test-studio.ps1:590 `Check ("Linhagem: rastro sem regressao no ledger real (orfas=" + N + ", ids repetidos=" + N + ")")` (roda contra o ledger REAL desta instancia) + scripts/smoke-test.ps1:201 `Check "Rastreabilidade: toda Task com artifact tem linhagem completa (project+base_artifact+session)"`, :206 (task-context.ps1 presente), :1488 `Check "Linhagem: -Health acusa em NUMERO o que o rastro tem de furado"` e :1508 `Check "Ledger: register-task GARANTE id unico no ato"` [SEM MAQUINA NESTA INSTANCIA - ver nota] - o ledger REAL passou a ser lido como grafo por scripts/lineage-graph.ps1 | COBERTA (via smoke-test-studio.ps1 nesta instancia) |
| L14 | Grounding: afirmar fato exige LEU (Specialist) ou rotulo [INFERIDO] | engine/orchestration.md:62 | scripts/response-guard.ps1 REGRA 2 (hook de Stop, roda a CADA turno de verdade nesta instancia, `mode: bloqueio` desde 09/08/2026): 3+ afirmacoes de peso (referencia a arquivo por extensao ou padrao arquivo:linha) no texto final sem rotulo `[MEDIDO`/`[INFERIDO`/`[LIDO` bloqueia o turno - doutrina em engine/governance/response-guard.md | COBERTA (achado na poda 09/08/2026: ja existia maquina viva, o ledger e que estava desatualizado - nao e mais SEM TESTE) |
| L15 | Fonte de verdade do cliente antes de produzir Artifact (mirror combinado de L05+L06) | ~~engine/orchestration.md~~ (removido 09/08/2026) | era duplicata textual pura de L05+L06 (client-truth.md); a poda 09/08/2026 tirou o marcador `> LEI` e o texto duplicado de orchestration.md e deixou so uma frase de amarracao apontando pra client-truth.md (LEI 1/LEI 2, ja COBERTA/formato) - nenhuma protecao real se perde, a lei de fato continua viva em L05+L06 | SAIU (podada - duplicata pura; ver "Candidatas a poda") |
| L16 | Devolver pergunta ao operador E escalacao - mesma regra da escada (duplicata textual de L03) | engine/orchestration.md:184 (ponteiro corrigido 10/08/2026 apos OPP-42/squad-bridge.ps1 entrar em orchestration.md, +5 linhas antes deste bloco) | era LEI propria duplicando L03 (constitution.md); a poda 09/08/2026 tirou o marcador `> LEI` - o texto (que tem uma clausula unica, "rodada de alinhamento NAO e escalacao", nao presente em L03) virou orientacao no corpo de orchestration.md em vez de lei separada | VIRA ORIENTACAO (podada - deixou de ser LEI propria; conteudo unico preservado) |
| L17 | Olhos da Alia: Tasks paradas tem que ter alguem olhando (OPP-70) | engine/orchestration.md:200 (ponteiro corrigido 10/08/2026, mesmo motivo de L16, +5 linhas) | scripts/smoke-test.ps1:315 (stale-tasks.ps1 + fixture), :320 (determinismo pega antiga/ignora recente), :325 (mission-control tem KPI de paradas), :328 `Check "Paradas: LEI 'olhos da Alia' em orchestration.md (no bastidor)"` [SEM MAQUINA NESTA INSTANCIA - ver nota] | COBERTA (produto) - SEM MAQUINA NESTA INSTANCIA |
| L18 | Squad Owner e dono ativo, nao roteador passivo (OPP-67, 4 tracos de owner_soul) | engine/squad-system.md:57 | scripts/smoke-test.ps1:230 `Check "Owner soul: contrato owner_soul (4 tracos) em squad-creator.yaml + doutrina em squad-system.md"` + :249 `Check ("Owner soul: Gateway do demo (" + owner + ") carrega os 4 tracos na persona")` [SEM MAQUINA NESTA INSTANCIA - ver nota] | COBERTA (produto) - SEM MAQUINA NESTA INSTANCIA |
| L19 | Todo Client carrega Especificacao de Entrega no segundo cerebro (OPP-68) | engine/squad-system.md:136 | scripts/smoke-test.ps1:264 `Check "Consistencia: Especificacao de Entrega presente no knowledge do demo + LEI em squad-system.md"` [SEM MAQUINA NESTA INSTANCIA - ver nota] | COBERTA (produto) - SEM MAQUINA NESTA INSTANCIA |
| L20 | Grafo do graphify e pre-condicao operacional de todo Client (OPP-68) | engine/squad-system.md:145 | scripts/smoke-test-studio.ps1 secao (l.1) `Check "Mapa: graph-check roda contra os Clients REAIS e nao ha mapa FALSO/AUSENTE novo"` (roda contra os Clients desta instancia) + scripts/graph-check.ps1 (roda direto) + scripts/smoke-test.ps1:269 (script presente), :272 (aprova Client com grafo), :279 `Check "Grafo: graph-check REPROVA client sem grafo (exit 1)"` [este trio, so no produto - ver nota] | COBERTA (via smoke-test-studio.ps1 nesta instancia) |
| L21 | Pesquisa segura: agente de pesquisa nao se multiplica nem entra em loop | engine/tools.md:195 + engine/tools.yaml:58 | scripts/smoke-test-studio.ps1:346 `Check ("Pesquisa segura: escopo enxerga agente(s) de verdade")` + :359 `Check ("Pesquisa segura: " + N + " agente(s) de pesquisa ..., todos com trava (max_parallel:1 + self_spawn:forbidden)")` (testa os 44+ agentes REAIS desta instancia) + scripts/smoke-test.ps1:799 `Check "LEI de pesquisa segura documentada (tools.md + tools.yaml)"` [SEM MAQUINA NESTA INSTANCIA - ver nota] | COBERTA (via smoke-test-studio.ps1 nesta instancia) |
| L22 | Produto so produto: Contexto Produto nunca contem dado do operador (regra geral) | engine/governance/instance-separation.md:55 | nenhum guardrail dedicado cobre o caso geral; so as 3 instancias especificas abaixo (L23-L25) tem check - uma nova pasta em engine/ ou scripts/ com dado de cliente escaparia das 3 | VIRA ORIENTACAO (podada 09/08/2026 - deixou de ser item numerado da LEI; os 3 vetores concretos abaixo continuam leis testadas) |
| L23 | Raiz so convencional: nenhum .md solto fora da allowlist | engine/governance/instance-separation.md:61 | scripts/smoke-test-studio.ps1:212 `Check "Raiz limpa: so a allowlist canonica (nenhum arquivo vaza)"` (roda contra a raiz REAL desta instancia; ponteiro corrigido 09/08/2026, estava :209) + scripts/smoke-test.ps1:478 (mesmo check no lado do produto) [este ultimo, so no produto - ver nota] | COBERTA (via smoke-test-studio.ps1 nesta instancia) |
| L24 | studio.example limpa: clients/ contem SO o demo acme-saas | engine/governance/instance-separation.md:64 | scripts/smoke-test.ps1:489 `Check "studio.example limpa: so o demo acme-saas em clients/"` - NAO SE APLICA a esta instancia (instancia aplicada nao tem studio.example nenhum, e conceito e so do repo produto) | SEM MAQUINA NESTA INSTANCIA (nao se aplica aqui por desenho) |
| L25 | Marca/go-to-market fora do produto: nunca pasta marketing/comercial no cliente de manutencao | engine/governance/instance-separation.md:66 | scripts/smoke-test-studio.ps1 secao (h) `Check "alia-flow CLEAN: check-public-surface no estagio de propagacao (release/alia-flow) sem vazamento de marca/GTM"` - conserto de 09/08/2026: media CONTEUDO vetado (via scripts/check-public-surface.ps1) no estagio real de propagacao clients/alia-flow-lab/release/alia-flow, nao mais nome de PASTA dentro da oficina (a oficina nunca se chamou "marketing" - o check antigo validava populacao errada) | COBERTA |
| L26 | Mapa forjado ou podre nao vale como mapa (autenticidade + idade do grafo, OPP-76) | engine/tools.md:87 | scripts/smoke-test.ps1 `Check "Mapa: graph-check DISCRIMINA grafo FORJADO (JSON a mao com nos > 0 sai [FAKE] e reprova)"` + `Check "Mapa: graph-check DISCRIMINA grafo PODRE ..."` (fixtures temporarias) [SEM MAQUINA NESTA INSTANCIA - ver nota] + scripts/smoke-test-studio.ps1 secao (l.1) `Check "Mapa: graph-check roda contra os Clients REAIS e nao ha mapa FALSO/AUSENTE novo"` e (conserto 09/08/2026) `Check "Mapa: nenhum grafo PODRE novo fora da baseline"` - FAKE/FALTA e agora tambem STALE/PODRE viram ratchet real contra os 9 Clients de verdade, nao so a fixture | COBERTA (via smoke-test-studio.ps1 nesta instancia) |
| L27 | Adocao da lei do grafo e MEDIDA por par (sessao, escopo); sensor desligado reprova (OPP-76) | engine/tools.md:118 | scripts/smoke-test.ps1 `Check "Adocao: hook PreToolUse do sensor LIGADO em .claude/settings.json COM matcher ..."` + `Check "Adocao: o sensor MEDE ..."` + `Check "Adocao: o contador ACUSA o furo ..."` + `Check "Adocao: ledger AUSENTE reprova como sensor desligado ..."` [SEM MAQUINA NESTA INSTANCIA - ver nota]; scripts/smoke-test-studio.ps1 secao (l.2) repete o check do hook na instancia E (conserto 09/08/2026) a TAXA em si virou `Check` de verdade (nao mais Warn incondicional) - medido 09/08/2026: 43 pares, adocao 9.3%, REPROVA (amostra >= 5 e abaixo do alvo de 70%, limiares em scripts/graph-usage.ps1: MIN_AMOSTRA/ALVO_PCT) | COBERTA (via smoke-test-studio.ps1 nesta instancia; a taxa REPROVA hoje - divida real, nao lacuna) |
| L28 | Fato de memoria nunca se apaga, se marca: nota com tarja de morte e janela aberta reprova (OPP-76) | engine/governance/memory-types.md:69 | scripts/smoke-test.ps1 `Check "Memoria: -Validade REPROVA fato morto se passando por vigente ([FATO-MORTO-VIVO] + RESULTADO: FAIL)"` + `Check "Memoria: -Validade deriva os 3 estados do cabecalho ..."` [SEM MAQUINA NESTA INSTANCIA - ver nota] + scripts/smoke-test-studio.ps1 secao (l.3) `Check "Memoria: nenhum fato morto se passando por vigente nos cofres do operador (-Validade)"` (os cofres REAIS) e (conserto 09/08/2026) `Check "Memoria: sem-declaracao-de-validade nao cresce alem do baseline"` (ratchet, 115 notas medidas 09/08/2026) | COBERTA (via smoke-test-studio.ps1 nesta instancia) |
| L29 | Fronteira fato-vs-decisao: fato a Alia investiga; decisao com risco >= piso ela pergunta em rodada curta com recomendacao, teto 4 perguntas / 2 rodadas | engine/constitution.md:138 + skills/alinhamento/SKILL.md | scripts/smoke-test.ps1 `Check "Alinhamento: a regua declara os 4 fatores e o piso NUMERICO"`, `Check "Alinhamento: tetos de 4 perguntas e 2 rodadas declarados"`, `Check "Alinhamento: a escada de investigacao e pre-condicao"`, `Check "Alinhamento: todo exemplo de pergunta traz recomendacao e a saida 'voce decide'"`, `Check "Alinhamento: skill sem acento, sem emoji e sem termo da lista proibida"` [SEM MAQUINA NESTA INSTANCIA - ver nota] | COBERTA (produto) - SEM MAQUINA NESTA INSTANCIA |
| L30 | LEI do formato de plano: todo PLANO/DIAGNOSTICO/DECISAO/RELATORIO DE STATUS e pagina HTML pronta, com TLDR no topo, e a Alia TERMINA e MOSTRA (nunca pergunta antes de entregar) (mandato do CEO, 09/08/2026) | engine/agents/persona.md:263-266 (identico em clients/alia-flow-lab/engine/agents/persona.md:263-266, hash conferido; ponteiro corrigido 09/08/2026 apos a LEI L31 ser inserida acima dela no arquivo) | scripts/smoke-test-studio.ps1 secao (n) `Check "Persona (formato): raiz engine/agents/persona.md declara a LEI do formato de plano"` + `Check "Persona (formato): copia da oficina ... declara a mesma LEI"` - CHECK DE FORMATO (confere que o bloco de texto existe nas 2 copias); nenhum mecanismo confere se a Alia de fato ENTREGA em HTML/TLDR/sem-pergunta em cada resposta real - isso e julgamento de conteudo | SEM TESTE (comportamento) - so o FORMATO do bloco tem maquina |
| L31 | LEI da resposta por decisao: resposta padrao e DECISAO TOMADA + POR QUE, nunca relato da cadeia de especialistas; pergunta e excecao (so decisao que exige o dono), vem UMA, curta, com info pronta e a recomendacao da Alia (mandato do CEO, 09/08/2026) | engine/agents/persona.md:249-264 (identico em clients/alia-flow-lab/engine/agents/persona.md:249-264, hash conferido) | scripts/law-ledger-check.ps1 secao (C) `Check "L31 formato: persona.md (raiz) declara o marcador de LEI da resposta por decisao + o anti-padrao"` + `Check "L31 formato: persona.md (oficina) declara o mesmo marcador ..."` (roda direto nesta instancia) - CHECK DE FORMATO (marcador + o bloco anti-padrao presentes nas 2 copias), nao confere se a Alia de fato entrega resultado+porque em vez de narrar a cadeia de especialistas em cada resposta real - isso e julgamento de conteudo | COBERTA (formato, nasce com maquina 09/08/2026) - comportamento SEM TESTE, mesmo molde de L30 |
| L32 | Raiz limpa cobre PASTA, nao so arquivo: pasta nova fora da allowlist canonica reprova pelo NOME dela, mesmo mecanismo que ja valia so pra arquivo (LEI da instancia aplicada, especifica de studio-farina - nao e o L23 do produto, que declara "Pastas sao livres" por desenho em `engine/governance/instance-separation.md:62`) | skills/file-organization/SKILL.md, secao "Pastas tematicas (na raiz)" + "Regras" item 7 ("Nada nasce na raiz") | scripts/smoke-test-studio.ps1:223 `Check "Raiz limpa (pasta): so a allowlist canonica (nenhuma pasta vaza)"` (roda contra a raiz REAL desta instancia; allowlist de 13 pastas + dotfolders ignorados) - PROVADO PELO NEGATIVO em 10/08/2026: pasta de teste criada na raiz reprovou citando o proprio nome, removida, voltou a passar | COBERTA (via smoke-test-studio.ps1 nesta instancia; nasce com maquina, causa raiz da poda de 10/08/2026 - `Get-ChildItem -File` nunca cobrava pasta, so arquivo) |

Nota sobre L29 (OPP-78): nasce `COBERTA` pela mesma regra de formacao - os 5 checks foram escritos na
Task que declara a lei. O que os checks mordem e o FORMATO (os 4 fatores nomeados, o piso e os tetos
como numero, a escada citada como pre-condicao, recomendacao e saida em todo exemplo, zero jargao
nos exemplos). Nenhum check julga se a NOTA da regua foi honesta num pedido real - isso e julgamento,
nao formato; a auditabilidade da nota entra na onda 2 (campo `briefing` na Task). Divida declarada,
nao escondida. L29 tambem NAO promove L03/L16 a `COBERTA`: a escada continua sem verificacao
automatica, e dizer o contrario seria mentir no ledger.

Nota sobre L26-L28 (OPP-76): as tres nascem `COBERTA` porque o teste foi escrito na mesma Task que
declara a lei - a regra de formacao deste ledger. As tres tem, de proposito, uma fatia que entra
como AVISO e nao como FAIL (grafo PODRE em cliente real; taxa de adocao sem amostra; ponteiro morto
no rastro): reprovar por divida acumulada nao pega regressao nova, e regenerar grafo de cliente real
custa modelo - e decisao do operador, nunca do smoke. A divida fica visivel em
`studio/graph-map-baseline.txt` (camada do operador) e no proprio OPP-76.

Nota sobre L22-L25: `instance-separation.md` declara a LEI num arquivo dedicado ("As regras duras (a
LEI)"), sem usar o marcador `> LEI:` do resto do motor - por isso o grep estrito por esse marcador
NAO pegou essas 4 regras; so apareceram na varredura ampla por `\bLEI\b` seguida de leitura. Foram
incluidas aqui porque sao declaracao normativa real, nao mencao, e 3 das 4 ja tem guardrail citado
no proprio arquivo (tabela "Os guardrails que fazem a LEI cumprir").

Nota sobre L21: tools.md:195 (prosa) e tools.yaml:58 (comentario sobre o contrato `research_safety`)
sao a MESMA lei em duas formas (prosa + config); o proprio scripts/smoke-test.ps1:799 as testa
juntas num unico Check (so no produto - ver nota SEM MAQUINA abaixo). Nesta instancia quem morde os
agentes REAIS e scripts/smoke-test-studio.ps1:346-359 (conserto de 09/08/2026, ver defeito 3 da
auditoria forense). Contadas aqui como uma linha, nao duas, por isso o total abaixo nao conta 29.

Nota SEM MAQUINA NESTA INSTANCIA (auditoria forense, defeito 8, 09/08/2026): scripts/smoke-test.ps1
e o smoke do **produto** (repo `alia-flow` / a oficina `clients/alia-flow-lab`) - ele espera
`studio.example/` na raiz (a Studio-modelo do produto, so o demo `acme-saas`). Esta instancia
aplicada (`studio-farina`, a operacao REAL do operador) nao tem `studio.example` - por desenho, e a
instancia real, nao o demo. Rodar `scripts/smoke-test.ps1` aqui **comeca mas morre antes do fim**
(`Push-Location: Cannot find path ...studio.example\clients\acme-saas\...`, medido 09/08/2026, ver
`scripts/law-ledger-check.ps1`). Toda lei cujo UNICO teste citado vive em `smoke-test.ps1` esta
`COBERTA` **no produto**, mas **NAO tem maquina rodando nesta instancia aplicada** - marcado em
cada linha como `[SEM MAQUINA NESTA INSTANCIA]` na coluna de teste e no veredito. Onde a mesma lei
tambem tem um check em `scripts/smoke-test-studio.ps1` (que RODA aqui, contra os dados REAIS do
operador) o veredito fica `COBERTA (via smoke-test-studio.ps1 nesta instancia)` sem ressalva - essa
e cobertura de verdade, nao promessa. `scripts/law-ledger-check.ps1` e a maquina que prova os
ponteiros linha-a-linha e que nenhuma LEI nova (marcador `> LEI:`/`## LEI`/`# LEI` em
`engine/**.md`) fica sem entrada aqui - rode antes de confiar neste arquivo.

## Placar

- Total de leis JA REGISTRADAS neste ledger, historico incluido: **32**. Apos a poda de 09/08/2026
  (decisao do CEO, mandato de corte - ver "Poda executada" abaixo), **29 continuam sendo LEI hoje**:
  L15 SAIU (era duplicata pura de L05+L06, apagada de orchestration.md); L16 e L22 VIRARAM
  ORIENTACAO (deixaram de carregar o marcador `> LEI`, o texto ficou como recomendacao no corpo).
  As linhas de L15/L16/L22 continuam nesta tabela como registro historico da poda, mas nao contam
  mais como LEI ativa nos totais abaixo.
- **COBERTA: 27** (L01, L02, L03, L04, L05, L06-parcial, L07, L08, L09, L10, L11, L12, L13, L14, L17,
  L18, L19, L20, L21, L23, L25, L26, L27, L28, L29, L31, L32) - destas, **8 so no produto**
  (`[SEM MAQUINA NESTA INSTANCIA]`: L01, L11, L12, L17, L18, L19, L29 e a metade smoke-test.ps1 de
  L06) e **19 rodam de verdade nesta instancia** (as 11 de antes - L04, L06-parcial, L09, L10, L13,
  L20, L21, L23, L25, L26, L27, L28 - mais as **7 que ganharam maquina na poda de 09/08/2026 e no
  mesmo mandato**: L02, L03, L05, L07, L08, L31 via `scripts/law-ledger-check.ps1` secao (C) - CHECK
  DE FORMATO, rotulado como tal - e L14 via `scripts/response-guard.ps1` REGRA 2, que ja rodava e
  enforcava de verdade a cada turno mas o ledger nao credita-la; achado na poda - mais **L32, nova
  em 10/08/2026** via `scripts/smoke-test-studio.ps1` secao (e), a extensao da poda de raiz pra
  pasta).
- **SEM TESTE (comportamento): 1** (L30) - o BLOCO da lei tem um check de FORMATO (presenca do
  texto nas 2 copias de persona.md, em `smoke-test-studio.ps1` secao n), mas nenhum mecanismo
  confere se a Alia de fato ENTREGA em HTML/TLDR/sem-pergunta em cada resposta - isso e julgamento
  de conteudo, sem maquina hoje. Fora da poda: mandato do CEO fresco (09/08/2026), sem reincidencia
  documentada ainda pra julgar. L31 (mesmo mandato) nasce diferente: o check de FORMATO ja existe
  desde o dia 1 (ver secao C acima), entao entra `COBERTA (formato)` em vez de `SEM TESTE` - o
  comportamento (a Alia de fato responder por decisao+porque) continua sem maquina, igual a L30.
- **SEM MAQUINA NESTA INSTANCIA: 1** (L24 - `studio.example limpa` nao se aplica a uma instancia
  aplicada, que por definicao nao tem `studio.example`; rebaixada de `COBERTA` porque afirmar
  cobertura de uma lei que nem se aplica aqui seria mentir no ledger)
- **HISTORICA: 0** (nenhuma lei encontrada e decisao pontual ja absorvida; toda LEI viva no motor e
  regra operacional continua, nao um registro de decisao passada)
- **SAIU: 1** (L15 - duplicata pura, apagada) | **VIRA ORIENTACAO: 2** (L16, L22 - deixaram de ser
  LEI, o texto virou recomendacao)

---

## Poda executada (09/08/2026, mandato do CEO)

Principio aplicado: **"Nao e lei se nao houver maquina."** Toda lei antes marcada `SEM TESTE` (mais
a secao "Candidatas a poda" que ficara sem decisao por semanas) recebeu UMA das 3 saidas abaixo,
com justificativa. Nada foi cortado do nucleo (L01-L04, `engine/constitution.md`) sem justificativa
forte - pelo contrario, L02 e L03 (que estavam `SEM TESTE`) GANHARAM maquina em vez de serem podadas,
exatamente porque sao do nucleo.

| id | lei | destino | motivo |
|----|-----|---------|--------|
| L02 | 10 Principios inviolaveis (guarda-chuva) | **GANHOU MAQUINA** (check de formato) | e do nucleo (constitution.md, um dos 4 protegidos) - corte exigiria justificativa muito forte que nao existe aqui; escrever um check de formato barato (marcador + tabela com as 10 linhas) foi mais honesto que apagar ou fingir cobertura |
| L03 | Pergunta ao operador e ultimo recurso (escada Memory->local->web) | **GANHOU MAQUINA** (check de formato) | mesma razao de L02: nucleo, protegido. O par L16 (duplicata fora do nucleo) e que foi podado - a lei em si, no nucleo, ficou coberta em vez de cortada |
| L05 | Knowledge-first (carregar fonte antes de produzir) | **GANHOU MAQUINA** (check de formato) | citada como fonte-da-verdade no proprio CLAUDE.md deste studio ("LEI - consultar a fonte ANTES de produzir") - peso demais pra virar so orientacao; o check de formato (bloco + hierarquia de 4 fontes presentes) e barato e honesto |
| L07 | Escopo publico vs interno (vocabulario de bastidor) | **GANHOU MAQUINA** (check de formato) | protege a fronteira publico/interno que ja causou incidente real (07/jul); demov-la sem cobertura repetiria o padrao que fez a Delegacao reincidir 2x antes do hook |
| L08 | Reuse-first de ativos | **GANHOU MAQUINA** (check de formato) | mandato explicito citado em CLAUDE.md ("Ativos que ja existem - nao reinventar - LEI reuse-first"); recriar ativo de marca por descuido e caro pra reverter, vale o check barato |
| L14 | Grounding: afirmar fato exige LEU ou rotulo [INFERIDO] | **JA TINHA MAQUINA** (achado, nao cortado) | o ledger dizia SEM TESTE mas `scripts/response-guard.ps1` REGRA 2 ja e maquina viva de verdade (nao so formato - comportamento real, bloqueia turno) desde que o modo virou bloqueio; era o ledger que estava desatualizado, nao a lei que faltava protecao |
| L15 | Fonte de verdade do cliente (mirror em orchestration.md) | **SAIU** | duplicata textual PURA de L05+L06 (client-truth.md) - mesma hierarquia, mesmas travas, mesma excecao de ordem do Operator, so que copiada num segundo arquivo. Nenhuma protecao real se perde: L05/L06 continuam vivas na fonte canonica. E o candidato mais seguro que o proprio ledger ja apontava |
| L16 | Pergunta ao operador E escalacao (duplicata de L03) | **VIRA ORIENTACAO** | quase-duplicata de L03 (nucleo, ja coberta), mas carrega uma clausula unica ("rodada de alinhamento NAO e escalacao") que L03 nao tem - por isso nao saiu limpo como L15, virou recomendacao no corpo de orchestration.md em vez de LEI separada |
| L22 | Produto so produto (regra geral de instance-separation) | **VIRA ORIENTACAO** | guarda-chuva sem check proprio; os 3 vetores concretos que a violam de fato (raiz, studio.example, marca/GTM = L23-L25) ja tem guardrail testado. Rebaixada a intro de paragrafo antes da lista numerada 1-3 (que agora comeca em L23, nao mais em L22) |

Nenhuma das 9 leis acima tinha reincidencia documentada no motor (nenhuma cita um OPP de
reincidencia), entao nenhuma foi automaticamente protegida contra corte por esse criterio - a
escolha em cada linha seguiu peso doutrinario (nucleo, citacao em CLAUDE.md, incidente historico
real) e nao "e mais facil apagar".

Leitura do CEO recomendada antes de decidir: L15 e a poda mais segura (duplicata pura, zero perda
real). L03/L16, L05 e L08 sao as que mais se parecem com o padrao que fez a Delegacao reincidir -
poda-las sem antes cobrir com teste repete o erro que este movimento existe pra fechar.
