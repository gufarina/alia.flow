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
$leiFiles = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $EngineDir) {
    $mdFiles = Get-ChildItem -LiteralPath $EngineDir -Recurse -Filter "*.md" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch "[\\/](_retired)[\\/]" }
    foreach ($f in $mdFiles) {
        $relPath = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
        $lines = [System.IO.File]::ReadAllLines($f.FullName)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*>\s*LEI\s*:' -or $lines[$i] -match '^\s*#{1,3}\s*LEI\b') {
                $leiFiles.Add([pscustomobject]@{ rel = $relPath; line = ($i + 1); text = $lines[$i].Trim() })
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
Write-Host ""

# ---------------------------------------------------------------------------
# (B) PONTEIRO PODRE: script:linha `Check "texto"` citado no ledger bate com o disco?
# ---------------------------------------------------------------------------
Write-Host "--- (B) Ponteiros de teste (script:linha) contra o disco ---"

# Scripts com dependencia dura conhecida que impede rodar NESTA instancia (nao a oficina/lab).
# smoke-test.ps1: espera studio.example/ na raiz (a Studio-modelo do produto) - esta instancia
# aplicada nao tem essa pasta (e a instancia REAL do operador, nao o demo), entao o script morre
# com ErrorActionPreference Stop antes do fim (medido 09/08/2026, Push-Location: Cannot find path).
$semMaquinaAqui = @{
    "scripts/smoke-test.ps1" = "espera studio.example/ na raiz (Studio-modelo do produto) - ausente nesta instancia aplicada; o script comeca mas MORRE antes do fim (Push-Location: Cannot find path), medido 09/08/2026"
}

$refPattern = '([A-Za-z0-9_./\\-]+\.ps1):(\d+)\s*`(Check\s+"[^"]*")'
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
    # prefixo ate 40 chars sem as aspas externas.
    $needle = $snippet -replace '^Check\s+"', '' -replace '"$', ''
    $needle = $needle.Substring(0, [Math]::Min(30, $needle.Length))
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
$personaRootPath = Join-Path $EngineDir "agents\persona.md"
$personaLabPath = Join-Path $root "clients\alia-flow-lab\engine\agents\persona.md"
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
    Check "L31 formato: persona.md (oficina) declara o mesmo marcador de LEI da resposta por decisao + o anti-padrao" ($personaLabTxt.Contains($l31Marcador) -and $personaLabTxt.Contains($l31AntiPadrao))
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
