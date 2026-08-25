<#
  law-ledger-check.ps1 - a maquina que confere engine/governance/law-ledger.md contra o disco.

  Por que existe (auditoria forense, defeito 8, 09/08/2026): o ledger e mantido A MAO. Ponteiro a
  mao apodrece - a auditoria mediu TODOS os ponteiros de linha errados (":168 deveria ser :178",
  ":942 deveria ser :1024", ":468 e linha em branco"), e 20 das 29 leis apontavam para
  scripts/smoke-test.ps1, que NAO RODA nesta instancia (procura studio.example, que nao existe
  aqui, e morre com ErrorActionPreference Stop). Este script prova as duas coisas com maquina:

  (A) LEI SEM REGISTRO: varre engine/**.md atras de marcador de lei (`> LEI:`, `## LEI`, `# LEI`)
      e reprova se achar um arquivo com marcador de lei que o ledger NUNCA cita na coluna
      "onde vive". Foi este exato buraco que deixou persona.md (LEI do formato de plano,
      09/08/2026) fora do ledger ate um humano notar.
  (B) PONTEIRO PODRE: para cada linha do ledger que cita "arquivo.ps1:NNN `Check "texto"`",
      confere se o texto citado EXISTE de verdade no script e relata a linha REAL (se != NNN,
      e o ponteiro podre que a auditoria mediu). Script referenciado que nao existe na instancia,
      ou que existe mas tem uma dependencia dura conhecida por nao rodar aqui (smoke-test.ps1 sem
      studio.example), sai como [SEM MAQUINA NESTA INSTANCIA] - honestidade, nao "COBERTA" de
      mentira.

  Uso: scripts/law-ledger-check.ps1 [-LedgerPath <caminho>]
  Sem acentos, sem emojis. UTF-8 sem BOM. So leitura: nunca escreve no ledger.
#>
[CmdletBinding()]
param(
    [string]$LedgerPath = "",
    [string]$EngineDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($LedgerPath)) { $LedgerPath = Join-Path $root "engine/governance/law-ledger.md" }
if ([string]::IsNullOrWhiteSpace($EngineDir)) { $EngineDir = Join-Path $root "engine" }

$fail = 0
$warn = 0
function Bad($msg)  { Write-Host ("[FAIL] " + $msg); $script:fail++ }
function Ok($msg)   { Write-Host ("[PASS] " + $msg) }
function Warn2($msg) { Write-Host ("[AVISO] " + $msg); $script:warn++ }
function Check([string]$desc, [bool]$cond) { if ($cond) { Ok $desc } else { Bad $desc } }

if (-not (Test-Path -LiteralPath $LedgerPath)) {
    Write-Host ("[FAIL] Ledger nao encontrado: " + $LedgerPath)
    exit 1
}
$ledgerTxt = [System.IO.File]::ReadAllText($LedgerPath)

Write-Host "=== law-ledger-check: o ledger confere com o disco? ==="
Write-Host ("ledger: " + $LedgerPath)
Write-Host ("engine: " + $EngineDir)
Write-Host ""

# ---------------------------------------------------------------------------
# (A) LEI SEM REGISTRO: todo arquivo com marcador de lei precisa aparecer na coluna "onde vive".
# ---------------------------------------------------------------------------
Write-Host "--- (A) Lei sem registro no ledger ---"
# MARCADOR FORTE (reprova de verdade, FAIL): "> LEI:" e "> LEI (..." (bracket - CONSERTO TASK-157:
# o regex antigo so pegava "LEI:", perdendo "> LEI (olhos da Alia - OPP-70):" - L17 inteiro ficava
# invisivel pra este proprio scan) + "## LEI"/"# LEI" (cabecalho).
# MARCADOR FRACO (TASK-157, pedido do CEO via Alia apos a auditoria WARDEN): "Invariante:" e
# "lei dura" sao peso de lei em prosa que NAO usa o marcador `> LEI` - ate agora INVISIVEIS pra
# este scan (foi assim que loops.md "Frugalidade (lei dura)", examples-driven.md "Invariante:" e
# squad-system.md "## Invariantes" ficaram fora do ledger sem ninguem notar). Marcador fraco
# reprova como AVISO (nao FAIL) - pesa menos que o marcador `> LEI` explicito, mas nao fica mais
# invisivel: lei nova nao nasce sem ninguem ver.
$leiFiles = New-Object System.Collections.Generic.List[object]
$weakLeiFiles = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $EngineDir) {
    # CONSERTO TASK-157 (achado ao provar o marcador FRACO pelo negativo): o proprio law-ledger.md
    # mora dentro de engine/governance/**.md e CITA "lei dura"/"Invariante:" na sua propria prosa
    # explicativa (ex.: a linha do L35 que descreve a lei de loops.md) - sem excluir, o scan
    # apontava o ledger como fonte-sem-registro de si mesmo. O ledger e o REGISTRO, nunca uma fonte
    # de marcador a registrar.
    $mdFiles = Get-ChildItem -LiteralPath $EngineDir -Recurse -Filter "*.md" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch "[\\/](_retired)[\\/]" -and $_.FullName -ne $LedgerPath }
    foreach ($f in $mdFiles) {
        $relPath = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
        $lines = [System.IO.File]::ReadAllLines($f.FullName)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            # -cmatch (case-sensitive): a convencao da casa e SEMPRE "LEI" maiusculo como marcador
            # formal ("> LEI:", "> LEI (...)"). CONSERTO TASK-157 (achado ao ligar este proprio
            # check): -match do PowerShell e case-INSENSITIVE por padrao - sem -cmatch, prosa
            # incidental como "este documento e a lei do update" (engine/versioning.md) virava
            # falso-positivo de marcador forte. "Invariante"/"lei dura" (fraco) mantem -match
            # normal (case-insensitive tolerado de proposito - marcador fraco, risco menor).
            $ln = $lines[$i]
            if ($ln -cmatch '^\s*>\s*LEI\b' -or $ln -cmatch '^\s*#{1,3}\s*LEI\b') {
                $leiFiles.Add([pscustomobject]@{ rel = $relPath; line = ($i + 1); text = $ln.Trim() })
            } elseif ($ln -match '^\s*Invariante\s*:' -or $ln -match '^\s*#{1,3}\s*Invariantes\b' -or $ln -match '(?i)\blei dura\b') {
                $weakLeiFiles.Add([pscustomobject]@{ rel = $relPath; line = ($i + 1); text = $ln.Trim() })
            }
        }
    }
}

# Arquivos ja citados na coluna "onde vive" do ledger (heuristica por caminho, nao por linha).
$ledgerFilesCited = @([regex]::Matches($ledgerTxt, '\b(engine/[A-Za-z0-9_./\-]+\.md)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)

$semRegistro = @($leiFiles | Where-Object { $ledgerFilesCited -notcontains $_.rel } | Select-Object -Property rel -Unique)
if ($semRegistro.Count -eq 0) {
    Ok ("Todo arquivo com marcador de LEI (" + (@($leiFiles | Select-Object -Property rel -Unique).Count) + " arquivo(s), " + $leiFiles.Count + " marcador(es)) aparece na coluna 'onde vive' do ledger")
} else {
    foreach ($sr in $semRegistro) {
        $marcadores = @($leiFiles | Where-Object { $_.rel -eq $sr.rel })
        foreach ($m in $marcadores) {
            Bad ($sr.rel + ":" + $m.line + " tem marcador de LEI (" + $m.text + ") sem entrada correspondente na coluna 'onde vive' do ledger - registre com id novo, teste (ou SEM TESTE explicito)")
        }
    }
}

$semRegistroFraco = @($weakLeiFiles | Where-Object { $ledgerFilesCited -notcontains $_.rel } | Select-Object -Property rel -Unique)
if ($semRegistroFraco.Count -eq 0) {
    Ok ("Todo arquivo com marcador FRACO de lei (Invariante:/lei dura, " + (@($weakLeiFiles | Select-Object -Property rel -Unique).Count) + " arquivo(s), " + $weakLeiFiles.Count + " marcador(es)) aparece na coluna 'onde vive' do ledger")
} else {
    foreach ($sr in $semRegistroFraco) {
        $marcadores = @($weakLeiFiles | Where-Object { $_.rel -eq $sr.rel })
        foreach ($m in $marcadores) {
            Warn2 ($sr.rel + ":" + $m.line + " tem marcador FRACO de lei (" + $m.text + ") sem entrada correspondente na coluna 'onde vive' do ledger - lei nova em prosa nao nasce invisivel, registre com id novo (ou SEM TESTE explicito)")
        }
    }
}
Write-Host ""

# ---------------------------------------------------------------------------
# (A2) PONTEIRO PODRE em "onde vive": a coluna 3 do ledger cita `arquivo.md:NNN` (as vezes
# `NNN-MMM`) - confere se existe um marcador de lei (forte OU fraco) DENTRO de +-3 linhas do
# numero citado. TOLERANCIA CURTA porque o marcador raramente e a linha exata do cabecalho da
# secao (o texto normativo comeca 1-2 linhas abaixo do titulo) - mas 3 linhas nao escondem um
# ponteiro que apodreceu de verdade (edicao empurrou o bloco dezenas de linhas pra baixo).
# ---------------------------------------------------------------------------
Write-Host "--- (A2) Ponteiros 'onde vive' (arquivo:linha) contra o disco ---"
# [array] em vez de @(...) + @(...): concatenar array vazio com List[object] via @() causa
# "Argument types do not match" nesta versao do PowerShell (medido ao provar este check pelo
# negativo) - [array] converte de forma estavel mesmo com uma das listas vazia.
$allMarkers = [array]$leiFiles + [array]$weakLeiFiles
$TOLERANCIA = 3
$rowPattern = '(?m)^\|\s*(L\d+)\s*\|([^\|]*)\|([^\|]*)\|(.*)$'
$rowMatches = [regex]::Matches($ledgerTxt, $rowPattern)
$a2Checked = 0
$a2Bad = 0
foreach ($rm in $rowMatches) {
    $lawId = $rm.Groups[1].Value.Trim()
    $ondeVive = $rm.Groups[3].Value
    $restoDaLinha = $rm.Groups[4].Value

    # PODADA/HISTORICA: linha que "SAIU" ou "VIRA ORIENTACAO" (L15, L16, L22) mantem a citacao de
    # onde o texto MORAVA por registro historico, mas o marcador `> LEI`/fraco foi REMOVIDO de
    # proposito na poda - nao ha nada pra bater tolerancia contra, e isso e o esperado, nao um
    # ponteiro podre. Pular estas linhas evita falso-positivo (achado ao provar este check pelo
    # negativo, TASK-157).
    if ($restoDaLinha -match '\bVIRA ORIENTACAO\b' -or $restoDaLinha -match '\|\s*SAIU\b') { continue }

    $citPattern = '(engine/[A-Za-z0-9_./\-]+\.md):(\d+)(?:-(\d+))?'
    foreach ($cm in [regex]::Matches($ondeVive, $citPattern)) {
        $citFile = $cm.Groups[1].Value
        $citStart = [int]$cm.Groups[2].Value
        $citEnd = if ($cm.Groups[3].Success) { [int]$cm.Groups[3].Value } else { $citStart }

        $markersHere = @($allMarkers | Where-Object { $_.rel -eq $citFile })
        if ($markersHere.Count -eq 0) {
            # Arquivo sem NENHUM marcador conhecido (forte ou fraco) - nao da pra validar tolerancia
            # contra nada; nao e culpa do ponteiro, e limite deste scan (marcador em formato novo).
            continue
        }
        $a2Checked++
        $windowLo = $citStart - $TOLERANCIA
        $windowHi = $citEnd + $TOLERANCIA
        $hit = @($markersHere | Where-Object { $_.line -ge $windowLo -and $_.line -le $windowHi })
        if ($hit.Count -eq 0) {
            $a2Bad++
            $nearest = ($markersHere | Sort-Object { [Math]::Abs($_.line - $citStart) } | Select-Object -First 1)
            Bad ($lawId + ": onde-vive cita " + $citFile + ":" + $cm.Groups[2].Value + $(if ($cm.Groups[3].Success) { "-" + $cm.Groups[3].Value } else { "" }) + " mas o marcador real mais proximo esta em :" + $nearest.line + " (" + $nearest.text.Substring(0, [Math]::Min(60, $nearest.text.Length)) + "...) - corrija o ledger")
        }
    }
}
if ($a2Bad -eq 0) {
    Ok ("Todos os " + $a2Checked + " ponteiro(s) 'onde vive' verificaveis batem com um marcador real (tolerancia +-" + $TOLERANCIA + " linhas)")
}
Write-Host ("resumo (A2): " + ($a2Checked - $a2Bad) + " ponteiro(s) OK | " + $a2Bad + " podre(s) | citacoes sem marcador conhecido no arquivo nao contam (limite do scan, nao erro de ponteiro)")
Write-Host ""

# ---------------------------------------------------------------------------
# (B) PONTEIRO PODRE: script:linha `Check "texto"` citado no ledger bate com o disco?
# ---------------------------------------------------------------------------
Write-Host "--- (B) Ponteiros de teste (script:linha) contra o disco ---"

# Scripts com dependencia dura conhecida que impede rodar NESTA instancia (nao a oficina/lab).
# smoke-test.ps1: espera studio.example/ na raiz (a Studio-modelo do produto) - MEDIDO NO ATO
# (TASK-213, item 4 - antes era uma tabela hardcoded, "sempre ausente", mesmo em instancias como
# a propria oficina que TEM studio.example/ de verdade; era vira de sino de fe travestida de
# medida). Test-Path aqui, agora: instancia com studio.example/ presente -> o script RODA de
# verdade e os ponteiros dele voltam a ser conferidos igual a qualquer outro; instancia sem
# studio.example/ (a aplicada, real, do operador) -> continua [SEM MAQUINA NESTA INSTANCIA],
# mesma mensagem de sempre, so que agora provada, nao presumida.
$temStudioExample = Test-Path -LiteralPath (Join-Path $root "studio.example")
$semMaquinaAqui = @{}
if (-not $temStudioExample) {
    $semMaquinaAqui["scripts/smoke-test.ps1"] = "espera studio.example/ na raiz (Studio-modelo do produto) - AUSENTE nesta instancia (medido no ato: Test-Path " + (Join-Path $root "studio.example") + " = False); o script comeca mas MORRE antes do fim (Push-Location: Cannot find path)"
}

# smoke-test-studio.ps1: por DESENHO nunca viaja no pacote publico (package-release.ps1,
# $scriptsAllow, comentario "Fora de proposito" - e o smoke DA INSTANCIA Studio Farina, le
# clientes/squads REAIS do operador; nao existe "Studio Farina" numa instalacao limpa). Achado
# TASK-283 fechamento: rodar este checker DENTRO do pacote empacotado (release/alia-flow, onde o
# arquivo de fato nao existe por desenho) contava a ausencia como [FAIL] "nao existe nesta
# instancia" - falso positivo, mesmo padrao ja resolvido acima para smoke-test.ps1/studio.example,
# nunca replicado pra este script. Ausencia aqui e esperada sempre que o arquivo nao esta em disco
# (oficina e instancia aplicada real O TEM; so o pacote publico nao) - medido no ato via Test-Path,
# nao presumido.
$temSmokeStudio = Test-Path -LiteralPath (Join-Path $root "scripts/smoke-test-studio.ps1")
if (-not $temSmokeStudio) {
    $semMaquinaAqui["scripts/smoke-test-studio.ps1"] = "smoke DA INSTANCIA Studio Farina - por desenho nao viaja no pacote publico (package-release.ps1, allowlist scripts/, comentario 'Fora de proposito'); AUSENTE aqui e esperado (medido no ato: Test-Path " + (Join-Path $root "scripts/smoke-test-studio.ps1") + " = False), nao ponteiro podre"
}

# CONSERTO TASK-157: aceita as 2 formas de chamada do helper Check(...) usadas no motor -
# `Check "texto"` (nome direto) E `Check ("texto" + $var + ...)` (posicional, string concatenada -
# o molde de smoke-test-studio.ps1). So a PRIMEIRA string entre aspas apos "Check" vira o needle
# (mesma logica de antes: prefixo, ate 30 chars, casado literal no disco) - o resto da concatenacao
# (variavel, mais texto) nunca precisa bater, so o prefixo fixo que identifica a linha.
$refPattern = '([A-Za-z0-9_./\\-]+\.ps1):(\d+)\s*`Check\s*\(?\s*"([^"]*)"'
$refs = [regex]::Matches($ledgerTxt, $refPattern)
Write-Host ("citacoes encontradas: " + $refs.Count)
Write-Host ""

$scriptCache = @{}
$mismatches = 0
$missing = 0
$semMaquinaCount = 0
$ok = 0
foreach ($m in $refs) {
    $scriptRelRaw = $m.Groups[1].Value
    $lineCited = [int]$m.Groups[2].Value
    $snippet = $m.Groups[3].Value

    # normaliza para caminho relativo canonico "scripts/xxx.ps1"
    $scriptRel = $scriptRelRaw
    if ($scriptRel -notmatch '^scripts/') { $scriptRel = "scripts/" + ($scriptRel -replace '^.*[\\/]', '') }
    $scriptPath = Join-Path $root $scriptRel

    if ($semMaquinaAqui.ContainsKey($scriptRel)) {
        Write-Host ("[SEM MAQUINA NESTA INSTANCIA] " + $scriptRel + " - " + $semMaquinaAqui[$scriptRel])
        $semMaquinaCount++
        continue
    }

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Bad ($scriptRel + " (citado com :" + $lineCited + ") nao existe nesta instancia")
        $missing++
        continue
    }

    if (-not $scriptCache.ContainsKey($scriptPath)) {
        $scriptCache[$scriptPath] = [System.IO.File]::ReadAllText($scriptPath)
    }
    $content = $scriptCache[$scriptPath]

    # a citacao traz so o INICIO do texto entre aspas (pode estar truncada por "..."); casa o
    # prefixo ate 30 chars. $snippet ja e o texto puro (grupo 3 do regex, sem "Check"/parenteses/
    # aspas ao redor - CONSERTO TASK-157, cobre as 2 formas Check "..." e Check ("..." + $var)).
    $needle = $snippet.Substring(0, [Math]::Min(30, $snippet.Length))
    $idx = $content.IndexOf($needle)
    if ($idx -lt 0) {
        Bad ($scriptRel + ":" + $lineCited + " - texto citado (" + $snippet.Substring(0, [Math]::Min(50, $snippet.Length)) + "...) NAO encontrado no script - ponteiro morto ou texto mudou")
        $missing++
        continue
    }
    $realLine = ($content.Substring(0, $idx) -split "`n").Count
    if ($realLine -ne $lineCited) {
        Bad ($scriptRel + ": ponteiro cita :" + $lineCited + " mas o texto esta em :" + $realLine + " - corrija o ledger")
        $mismatches++
    } else {
        $ok++
    }
}
Write-Host ""
Write-Host ("resumo (B): " + $ok + " ponteiro(s) OK | " + $mismatches + " linha(s) errada(s) | " + $missing + " ausente(s)/nao encontrado(s) | " + $semMaquinaCount + " sem maquina nesta instancia (nao contam como erro, contam como divida de honestidade se o ledger disser COBERTA)")

# ---------------------------------------------------------------------------
# (C) CHECKS DE FORMATO - poda do law-ledger (09/08/2026): leis que eram SEM TESTE e ganharam
# maquina nesta correcao (L02, L03, L05, L07, L08). "Nao e lei se nao houver maquina" - mas honesto:
# isto e CHECK DE FORMATO (confere que o BLOCO/marcador/estrutura existe no arquivo), no MESMO
# molde ja usado pra L30 (persona.md) - nao confere COMPORTAMENTO (se a Alia de fato consultou a
# escada, ou carregou a fonte, antes de agir). Julgamento de conteudo continua sendo trabalho do
# Gate/revisao humana, nao de regex.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- (C) Checks de formato (leis que ganharam maquina na poda de 09/08/2026) ---"

$constitutionPath = Join-Path $EngineDir "constitution.md"
$clientTruthPath = Join-Path $EngineDir "governance\client-truth.md"

if (Test-Path -LiteralPath $constitutionPath) {
    $constTxt = [System.IO.File]::ReadAllText($constitutionPath)

    # L02 - os 10 Principios: marcador presente + a tabela tem exatamente 10 linhas de dado (I..X).
    $l02Marcador = $constTxt.Contains("os 10 Principios abaixo sao inviolaveis")
    $l02Linhas = @([regex]::Matches($constTxt, '(?m)^\|\s*(I{1,3}|IV|VI{0,3}|IX|X)\s*\|'))
    Check "L02 formato: constitution.md declara o marcador de LEI dos 10 Principios e a tabela tem 10 linhas (I-X)" ($l02Marcador -and ($l02Linhas.Count -eq 10))

    # L03 - escalonamento: marcador + os 3 degraus nomeados da escada (Memory / local / web).
    $l03Marcador = $constTxt.Contains("perguntar ao operador e o ULTIMO recurso")
    $l03Escada = $constTxt.Contains("(1) Memory e o contexto") -and $constTxt.Contains("(2) os arquivos da instancia") -and $constTxt.Contains("(3) a web por pesquisa segura")
    Check "L03 formato: constitution.md declara o marcador de LEI do escalonamento e os 3 degraus da escada (Memory/local/web)" ($l03Marcador -and $l03Escada)
} else {
    Bad ("constitution.md nao encontrado em " + $constitutionPath + " - L02/L03 sem como conferir formato")
}

if (Test-Path -LiteralPath $clientTruthPath) {
    $ctTxt = [System.IO.File]::ReadAllText($clientTruthPath)

    # L05 - Knowledge-first: cabecalho da LEI 1 + a hierarquia de 4 fontes numerada.
    $l05Cabecalho = $ctTxt.Contains("LEI 1 - Knowledge-first")
    $l05Hierarquia = @([regex]::Matches($ctTxt, '(?m)^\d+\.\s+\*\*'))
    Check "L05 formato: client-truth.md declara LEI 1 (Knowledge-first) com a hierarquia de 4 fontes numerada" ($l05Cabecalho -and ($l05Hierarquia.Count -ge 4))

    # L07 - Escopo publico vs interno: cabecalho da LEI 3 + a pergunta-gatilho "QUEM LE ISTO".
    $l07Cabecalho = $ctTxt.Contains("LEI 3 - Escopo publico vs interno")
    $l07Gatilho = $ctTxt.Contains("QUEM LE ISTO")
    Check "L07 formato: client-truth.md declara LEI 3 (escopo publico vs interno) com a pergunta-gatilho QUEM LE ISTO" ($l07Cabecalho -and $l07Gatilho)

    # L08 - Reuse-first: cabecalho da LEI 4 + o mandato INVENTARIAR antes de criar.
    $l08Cabecalho = $ctTxt.Contains("LEI 4 - Reuse-first")
    $l08Mandato = $ctTxt.Contains("INVENTARIAR")
    Check "L08 formato: client-truth.md declara LEI 4 (reuse-first) com o mandato INVENTARIAR antes de criar" ($l08Cabecalho -and $l08Mandato)
} else {
    Bad ("client-truth.md nao encontrado em " + $clientTruthPath + " - L05/L07/L08 sem como conferir formato")
}

# L31 - LEI da resposta por decisao (mandato do CEO, 09/08/2026): marcador + anti-padrao presentes
# nas 2 copias de persona.md (raiz + oficina), mesmo molde de L30 - CHECK DE FORMATO, nao confere
# se a Alia de fato responde por decisao+porque em vez de narrar a cadeia de especialistas.
#
# CONSERTO (TASK-159): $personaLabPath assumia SEMPRE que $root era a raiz do STUDIO (onde
# "clients/alia-flow-lab" e subpasta valida da instancia aplicada) - rodando este script de
# DENTRO da propria oficina, $root JA E a oficina, e o Join-Path virava um caminho fantasma
# duplicado (".../alia-flow-lab/clients/alia-flow-lab/..."), sempre [FAIL] "nao encontrado".
# Bug pre-existente reportado pela auditoria WARDEN (TASK-146) e nunca corrigido ate agora.
# Resolucao: detecta ONDE $root esta ANTES de montar o caminho da "copia oficina".
#   - $root E a propria oficina (tem engine/constitution.md E o nome da pasta e "alia-flow-lab"):
#     nao ha copia aninhada pra comparar - raiz e oficina sao o MESMO arquivo local (a oficina
#     e a fonte quando rodada standalone). Reusa o mesmo caminho, nao inventa um 2o arquivo.
#   - $root e a raiz do studio (instancia aplicada, a oficina fica aninhada em clients/): mantem
#     o comportamento original, a copia aninhada existe de verdade e e comparada de forma
#     independente (pode ter driftado da raiz - e o caso que este check protege).
$personaRootPath = Join-Path $EngineDir "agents\persona.md"
$rootIsOficina = (Test-Path -LiteralPath (Join-Path $root "engine\constitution.md")) -and
                 ((Split-Path -Leaf $root) -eq "alia-flow-lab")
# TERCEIRO contexto medido no fechamento do TASK-283, pacote publico empacotado
# (release/alia-flow): nao e a oficina standalone (leaf != "alia-flow-lab") NEM a raiz do studio
# com a oficina aninhada em clients/alia-flow-lab (o pacote nunca ship-a essa pasta - o produto e
# UM motor, nao um studio com oficina dentro). Sem essa 3a deteccao, o codigo caia no ramo "else"
# de sempre, montava um caminho fantasma e reprovava [FAIL] "nao encontrado" - falso positivo, nao
# ponteiro podre nem drift real (nao ha 2a copia pra comparar aqui, igual ao caso oficina==raiz).
$temOficinaAninhada = Test-Path -LiteralPath (Join-Path $root "clients\alia-flow-lab\engine\agents\persona.md")
$ehPacotePublico = (-not $rootIsOficina) -and (-not $temOficinaAninhada)
if ($rootIsOficina -or $ehPacotePublico) {
    $personaLabPath = $personaRootPath
    $personaLabLabel = if ($rootIsOficina) {
        "L31 formato: persona.md (oficina == raiz nesta execucao, rodando de dentro de clients/alia-flow-lab - so 1 copia local, sem aninhada pra comparar) declara o mesmo marcador de LEI da resposta por decisao + o anti-padrao"
    } else {
        "L31 formato: persona.md (pacote publico - so 1 copia, sem oficina aninhada por desenho, clients/alia-flow-lab nunca viaja no pacote) declara o mesmo marcador de LEI da resposta por decisao + o anti-padrao"
    }
} else {
    $personaLabPath = Join-Path $root "clients\alia-flow-lab\engine\agents\persona.md"
    $personaLabLabel = "L31 formato: persona.md (oficina) declara o mesmo marcador de LEI da resposta por decisao + o anti-padrao"
}
$l31Marcador = "> LEI: a resposta padrao e DECISAO TOMADA + POR QUE"
$l31AntiPadrao = "Anti-padrao (nunca faco):"
if (Test-Path -LiteralPath $personaRootPath) {
    $personaRootTxt = [System.IO.File]::ReadAllText($personaRootPath)
    Check "L31 formato: persona.md (raiz) declara o marcador de LEI da resposta por decisao + o anti-padrao" ($personaRootTxt.Contains($l31Marcador) -and $personaRootTxt.Contains($l31AntiPadrao))
} else {
    Bad ("persona.md (raiz) nao encontrado em " + $personaRootPath + " - L31 sem como conferir formato")
}
if (Test-Path -LiteralPath $personaLabPath) {
    $personaLabTxt = [System.IO.File]::ReadAllText($personaLabPath)
    Check $personaLabLabel ($personaLabTxt.Contains($l31Marcador) -and $personaLabTxt.Contains($l31AntiPadrao))
} else {
    Bad ("persona.md (oficina) nao encontrado em " + $personaLabPath + " - L31 sem como conferir formato")
}

Write-Host ""
Write-Host "=== Resumo ==="
Write-Host ("FAIL: " + $fail)
Write-Host ("AVISO: " + $warn)
if ($fail -eq 0) {
    Write-Host ""
    Write-Host "LEDGER CONFERE COM O DISCO"
    exit 0
} else {
    Write-Host ""
    Write-Host ("LEDGER PODRE - " + $fail + " problema(s), corrija antes de confiar no ledger")
    exit 1
}
