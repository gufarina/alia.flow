<#
  rsi-apply.ps1 - PECA 1 do motor de RSI: o portao do estagio APLICA.

  Uma proposta de melhoria a um arquivo do motor (persona, regra, skill, prompt) NUNCA edita o
  arquivo vivo direto. Ela nasce como candidato em engine/rsi/_candidates/<slug>/:
    manifest.md   - frontmatter (target, what, why, motivated_by)
    proposed      - o conteudo INTEIRO que o arquivo vivo teria se a proposta fosse aceita
    test.ps1      - o caso de teste ESPECIFICO do comportamento (param -Root; exit 0 = passa,
                    exit 1 = falha). Hoje, contra o VIVO, tem que FALHAR - e a prova pelo negativo
                    de que a proposta resolve algo real.

  -Candidate <slug> roda o portao:
    (a) test.ps1 contra o VIVO -> tem que FALHAR (senao: proposta desnecessaria, REJEITADA)
    (b) aplica o candidato numa COPIA TEMPORARIA isolada (New-RsiLightCopy - nunca no vivo)
    (c) test.ps1 contra a COPIA -> tem que PASSAR (senao: candidato nao resolve o proprio
        problema, REJEITADO)
    (d) smoke-test-studio.ps1 + smoke-test.ps1 (oficina) contra a COPIA -> nada pode regredir
        (comparado com a MESMA prova rodada contra o VIVO, antes de qualquer mudanca)
    (e) rsi-heldout.ps1 contra a COPIA -> nenhuma decisao do dono pode ser violada
    (f) SO ENTAO promove: se o alvo e NUCLEO (constitution/persona/orchestration/glossary),
        o portao PARA aqui e exige -ApproveCore explicito (imprime o resumo, nao mexe no vivo).
        Sem nucleo, ou com -ApproveCore: o arquivo vivo vai para engine/rsi/_archive/<data>-<slug>/
        (NUNCA se apaga), o candidato assume o lugar do vivo, e LINEAGE.md registra a cadeia.

  -Rollback <slug> desfaz uma promocao: restaura o arquivo arquivado por cima do vivo, byte a
  byte, e registra a reversao no LINEAGE.md. O arquivo promovido that foi substituido NUNCA
  desaparece (fica no proprio _archive, com o registro). UTF-8 sem BOM.
#>
param(
  [string]$Candidate = "",
  [string]$Rollback = "",
  [switch]$ApproveCore,
  [string]$Root = ""
)
$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $scriptRoot }
. (Join-Path $scriptRoot "_rsi-lib.ps1")

$utf8 = New-Object System.Text.UTF8Encoding($false)
$candidatesDir = Join-Path $Root "engine/rsi/_candidates"
$archiveDir    = Join-Path $Root "engine/rsi/_archive"
$lineageFile   = Join-Path $archiveDir "LINEAGE.md"

# Arquivos de NUCLEO (mesma lista que scripts/guard-core.ps1 protege) - relativo a QUALQUER pasta
# "engine" (a instancia OU a oficina, ja que ambas tem a mesma estrutura).
$coreSuffixes = @(
  "engine/constitution.md",
  "engine/glossary.md",
  "engine/agents/persona.md",
  "engine/orchestration.md"
)
function Test-IsCoreTarget([string]$target) {
  $norm = $target -replace '\\', '/'
  foreach ($suf in $coreSuffixes) {
    if ($norm -eq $suf -or $norm.EndsWith("/" + $suf)) { return $true }
  }
  return $false
}

# Alvo permitido: so arquivo do motor (persona/regra/skill/prompt), na instancia ou na oficina.
$allowedPrefixes = @("engine/", "scripts/", "skills/", "clients/alia-flow-lab/")
function Test-IsAllowedTarget([string]$target) {
  $norm = $target -replace '\\', '/'
  foreach ($p in $allowedPrefixes) { if ($norm.StartsWith($p)) { return $true } }
  return $false
}

function Read-Manifest([string]$path) {
  $txt = [System.IO.File]::ReadAllText($path)
  $m = [regex]::Match($txt, '(?s)^---\s*\r?\n(.*?)\r?\n---')
  if (-not $m.Success) { throw "manifest.md sem frontmatter --- ... ---: $path" }
  $fm = $m.Groups[1].Value
  $fields = @{}
  foreach ($line in ($fm -split "`r?`n")) {
    if ($line -match '^\s*([A-Za-z_]+)\s*:\s*(.*)$') {
      $fields[$Matches[1]] = $Matches[2].Trim()
    }
  }
  return $fields
}

function Get-SmokeSummary([string]$output) {
  # dois formatos de resumo coexistem no motor: smoke-test-studio.ps1 imprime "PASS: N" / "FAIL: N"
  # em linhas separadas; o smoke-test.ps1 da oficina imprime "Checks: N PASS, M FAIL" numa linha so.
  $passM = [regex]::Match($output, '(?m)^PASS:\s*(\d+)')
  $failM = [regex]::Match($output, '(?m)^FAIL:\s*(\d+)')
  if (-not $passM.Success -or -not $failM.Success) {
    $oneLine = [regex]::Match($output, '(?m)Checks:\s*(\d+)\s*PASS,\s*(\d+)\s*FAIL')
    if ($oneLine.Success) {
      $passM = [PSCustomObject]@{ Success = $true; Groups = @{ 1 = [PSCustomObject]@{ Value = $oneLine.Groups[1].Value } } }
      $failM = [PSCustomObject]@{ Success = $true; Groups = @{ 1 = [PSCustomObject]@{ Value = $oneLine.Groups[2].Value } } }
    }
  }
  $names = @()
  foreach ($mm in [regex]::Matches($output, '(?m)^\s*-\s*(.+)$')) {
    # so as linhas dentro do bloco FAILURES: (apos "FAILURES:" ate o fim) - aproximacao: qualquer
    # linha "  - texto" que venha depois da ultima ocorrencia de "FAILURES:" no texto.
  }
  $failuresBlock = ""
  $idx = $output.IndexOf("FAILURES:")
  if ($idx -ge 0) { $failuresBlock = $output.Substring($idx) }
  foreach ($mm in [regex]::Matches($failuresBlock, '(?m)^\s*-\s*(.+)$')) { $names += $mm.Groups[1].Value.Trim() }
  return [PSCustomObject]@{
    Pass   = if ($passM.Success) { [int]$passM.Groups[1].Value } else { -1 }
    Fail   = if ($failM.Success) { [int]$failM.Groups[1].Value } else { -1 }
    Names  = $names
    Output = $output
  }
}

function Invoke-Smokes([string]$root) {
  $studioScript = Join-Path $root "scripts/smoke-test-studio.ps1"
  $labScript    = Join-Path $root "clients/alia-flow-lab/scripts/smoke-test.ps1"
  $studioOut = if (Test-Path -LiteralPath $studioScript) { (& $studioScript 6>&1 2>&1) -join "`n" } else { "" }
  $labOut    = if (Test-Path -LiteralPath $labScript)    { (& $labScript 6>&1 2>&1) -join "`n" }    else { "" }
  return [PSCustomObject]@{
    Studio = Get-SmokeSummary $studioOut
    Lab    = Get-SmokeSummary $labOut
  }
}

function Compare-NoRegression($before, $after, [string]$label) {
  $novos = @($after.Names | Where-Object { $before.Names -notcontains $_ })
  $ok = ($novos.Count -eq 0) -and ($after.Fail -le $before.Fail -or $before.Fail -lt 0)
  return [PSCustomObject]@{ Ok = $ok; Label = $label; Novos = $novos; Before = $before; After = $after }
}

function Append-Lineage([string]$text) {
  New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null
  if (-not (Test-Path -LiteralPath $lineageFile)) {
    [System.IO.File]::WriteAllText($lineageFile, "# LINEAGE - RSI (engine/rsi/_archive)`r`n`r`n> Cadeia de toda promocao/rollback aplicado por scripts/rsi-apply.ps1. NUNCA editado a mao;`r`n> so por append do proprio script.`r`n`r`n", $utf8)
  }
  [System.IO.File]::AppendAllText($lineageFile, $text, $utf8)
}

# CONSERTO (TASK-285, gap achado na auditoria RSI TASK-284): promocao e rollback nunca limpavam
# engine/rsi/_candidates/<slug> - o desfecho ficava so no LINEAGE, a pasta do candidato continuava
# la parada, e em poucos dias virava "[CANDIDATO] PARADO" falso-positivo pro check novo do smoke
# (secao i). Fecha o candidato de verdade: os arquivos que restam (proposed, test.ps1) vao para
# DENTRO do mesmo _archive/<data>-<slug>/ que ja guarda manifest.md + original (um so lugar por
# desfecho, nao dois), depois a pasta em _candidates/ e removida. Chamado no fim do passo (f) e
# no fim do -Rollback - os dois pontos onde um candidato deixa de estar "pendente de decisao".
function Close-Candidate([string]$slug, [string]$archiveEntryPath) {
  $cDir = Join-Path $candidatesDir $slug
  if (-not (Test-Path -LiteralPath $cDir)) { return }
  foreach ($leftover in @("proposed", "test.ps1")) {
    $lp = Join-Path $cDir $leftover
    if (Test-Path -LiteralPath $lp) {
      Copy-Item -LiteralPath $lp -Destination (Join-Path $archiveEntryPath $leftover) -Force
    }
  }
  Remove-Item -LiteralPath $cDir -Recurse -Force
  Write-Host ("     candidato removido de _candidates/: " + $slug + " (arquivado em " + (Split-Path -Leaf $archiveEntryPath) + ")")
}

# ===========================================================================
# -Rollback
# ===========================================================================
if (-not [string]::IsNullOrWhiteSpace($Rollback)) {
  Write-Host "=== rsi-apply -Rollback $Rollback ==="
  $archived = Get-ChildItem -LiteralPath $archiveDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match [regex]::Escape($Rollback) + '$' -or $_.Name -eq $Rollback } |
    Sort-Object Name -Descending
  if (-not $archived -or $archived.Count -eq 0) {
    Write-Host ("[ERRO] nenhum candidato arquivado bate com '" + $Rollback + "' em " + $archiveDir)
    exit 1
  }
  $entry = $archived[0]
  $manifestPath = Join-Path $entry.FullName "manifest.md"
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-Host ("[ERRO] " + $entry.FullName + " nao tem manifest.md - arquivo corrompido ou nao gerado por rsi-apply.")
    exit 1
  }
  $fields = Read-Manifest $manifestPath
  $target = $fields["target"]
  $archivedFile = Join-Path $entry.FullName "original"
  $liveFile = Join-Path $Root $target
  if (-not (Test-Path -LiteralPath $archivedFile)) {
    Write-Host ("[ERRO] " + $archivedFile + " nao existe - nada para restaurar.")
    exit 1
  }
  $beforeHash = if (Test-Path -LiteralPath $liveFile) { (Get-FileHash -LiteralPath $liveFile -Algorithm SHA256).Hash } else { "(inexistente)" }
  Copy-Item -LiteralPath $archivedFile -Destination $liveFile -Force
  $afterHash = (Get-FileHash -LiteralPath $liveFile -Algorithm SHA256).Hash
  $expectHash = (Get-FileHash -LiteralPath $archivedFile -Algorithm SHA256).Hash
  $byteExact = ($afterHash -eq $expectHash)
  Write-Host ("[OK] restaurado: " + $target)
  Write-Host ("     hash antes (vivo, candidato):    " + $beforeHash)
  Write-Host ("     hash depois (vivo, restaurado):  " + $afterHash)
  Write-Host ("     hash do arquivo/original arquivado: " + $expectHash)
  Write-Host ("     byte-exato: " + $byteExact)
  $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  Append-Lineage(
    "`r`n## ROLLBACK - " + $entry.Name + " - " + $stamp + "`r`n`r`n" +
    "- target: " + $target + "`r`n" +
    "- restaurado de: engine/rsi/_archive/" + $entry.Name + "/original`r`n" +
    "- hash restaurado: " + $afterHash + " (bate com o arquivado: " + $byteExact + ")`r`n`r`n"
  )
  if (-not $byteExact) { Write-Host "[FALHA] restauracao NAO bateu byte a byte"; exit 1 }
  $rollbackSlug = $entry.Name -replace '^\d{4}-\d{2}-\d{2}-', ''
  Close-Candidate -slug $rollbackSlug -archiveEntryPath $entry.FullName
  Write-Host ""
  Write-Host "ROLLBACK: OK (restaurado byte a byte)"
  exit 0
}

# ===========================================================================
# -Candidate
# ===========================================================================
if ([string]::IsNullOrWhiteSpace($Candidate)) {
  Write-Host "Uso: rsi-apply.ps1 -Candidate <slug> [-ApproveCore]  OU  rsi-apply.ps1 -Rollback <slug>"
  exit 1
}

Write-Host ("=== rsi-apply -Candidate " + $Candidate + " ===")
$candDir = Join-Path $candidatesDir $Candidate
$manifestPath = Join-Path $candDir "manifest.md"
$proposedPath = Join-Path $candDir "proposed"
$testPath     = Join-Path $candDir "test.ps1"

foreach ($p in @($manifestPath, $proposedPath, $testPath)) {
  if (-not (Test-Path -LiteralPath $p)) {
    Write-Host ("[ERRO] candidato incompleto - falta: " + $p)
    exit 1
  }
}

$fields = Read-Manifest $manifestPath
$target = $fields["target"]
if ([string]::IsNullOrWhiteSpace($target)) { Write-Host "[ERRO] manifest.md sem campo 'target'"; exit 1 }
$target = $target -replace '\\', '/'
Write-Host ("target:       " + $target)
Write-Host ("what:         " + $fields["what"])
Write-Host ("why:          " + $fields["why"])
Write-Host ("motivated_by: " + $fields["motivated_by"])
Write-Host ""

if (-not (Test-IsAllowedTarget $target)) {
  Write-Host ("[REJEITADO] target fora do escopo do motor (engine/ scripts/ skills/ clients/alia-flow-lab/): " + $target)
  exit 1
}
$liveTarget = Join-Path $Root $target
if (-not (Test-Path -LiteralPath $liveTarget)) {
  Write-Host ("[REJEITADO] target nao existe no vivo (candidato so edita arquivo existente): " + $liveTarget)
  exit 1
}
$isCore = Test-IsCoreTarget $target
Write-Host ("nucleo (exige -ApproveCore antes de promover): " + $isCore)
Write-Host ""

# (a) teste especifico contra o VIVO - tem que FALHAR.
Write-Host "--- (a) test.ps1 contra o VIVO (tem que FALHAR) ---"
& $testPath -Root $Root
$beforeLiveExit = $LASTEXITCODE
Write-Host ("exit code: " + $beforeLiveExit)
if ($beforeLiveExit -eq 0) {
  Write-Host ""
  Write-Host "[REJEITADO] o caso de teste especifico JA PASSA no vivo - a proposta e desnecessaria."
  exit 1
}
Write-Host "[OK] falha no vivo, como esperado - a proposta tem algo real para resolver."
Write-Host ""

# Baseline de smoke contra o VIVO (sem nenhuma mudanca) - referencia para nao-regressao.
Write-Host "--- baseline: smokes contra o VIVO (antes de qualquer mudanca) ---"
$before = Invoke-Smokes $Root
Write-Host ("smoke-test-studio (vivo): PASS=" + $before.Studio.Pass + " FAIL=" + $before.Studio.Fail)
Write-Host ("smoke-test oficina (vivo): PASS=" + $before.Lab.Pass + " FAIL=" + $before.Lab.Fail)
Write-Host ""

# (b) aplica em COPIA TEMPORARIA.
Write-Host "--- (b) aplicando o candidato numa COPIA TEMPORARIA (o vivo nao e tocado) ---"
$copy = New-RsiLightCopy -Root $Root -Label "rsi-apply-$Candidate"
$copyTarget = Join-Path $copy.Path $target
try {
  Copy-Item -LiteralPath $proposedPath -Destination $copyTarget -Force
  Write-Host ("[OK] candidato aplicado em: " + $copy.Path)
  Write-Host ""

  # (c) teste especifico contra a COPIA - tem que PASSAR.
  Write-Host "--- (c) test.ps1 contra a COPIA (tem que PASSAR) ---"
  & $testPath -Root $copy.Path
  $afterCopyExit = $LASTEXITCODE
  Write-Host ("exit code: " + $afterCopyExit)
  if ($afterCopyExit -ne 0) {
    Write-Host ""
    Write-Host "[REJEITADO] o candidato NAO resolve o proprio caso de teste na copia."
    exit 1
  }
  Write-Host "[OK] passa na copia."
  Write-Host ""

  # (d) smokes contra a COPIA - nada pode regredir.
  Write-Host "--- (d) smokes contra a COPIA (nada pode regredir vs baseline do vivo) ---"
  $after = Invoke-Smokes $copy.Path
  Write-Host ("smoke-test-studio (copia): PASS=" + $after.Studio.Pass + " FAIL=" + $after.Studio.Fail)
  Write-Host ("smoke-test oficina (copia): PASS=" + $after.Lab.Pass + " FAIL=" + $after.Lab.Fail)
  $cmpStudio = Compare-NoRegression $before.Studio $after.Studio "smoke-test-studio"
  $cmpLab    = Compare-NoRegression $before.Lab    $after.Lab    "smoke-test oficina"
  if (-not $cmpStudio.Ok) {
    Write-Host ("[REJEITADO] smoke-test-studio regrediu. Novo(s) FAIL: " + ($cmpStudio.Novos -join "; "))
    exit 1
  }
  if (-not $cmpLab.Ok) {
    Write-Host ("[REJEITADO] smoke-test da oficina regrediu. Novo(s) FAIL: " + ($cmpLab.Novos -join "; "))
    exit 1
  }
  Write-Host "[OK] nenhuma regressao nos dois smokes."
  Write-Host ""

  # (e) held-out contra a COPIA - nenhuma decisao do dono pode ser violada.
  Write-Host "--- (e) rsi-heldout.ps1 contra a COPIA ---"
  $heldoutScript = Join-Path $Root "scripts/rsi-heldout.ps1"
  & $heldoutScript -Root $copy.Path
  $heldoutExit = $LASTEXITCODE
  if ($heldoutExit -ne 0) {
    Write-Host ""
    Write-Host "[REJEITADO] o candidato viola pelo menos uma decisao do dono (held-out)."
    exit 1
  }
  Write-Host "[OK] held-out intacto."
  Write-Host ""

  # (f) promove - ou para para aprovacao humana, se nucleo.
  Write-Host "--- (f) promocao ---"
  if ($isCore -and -not $ApproveCore) {
    Write-Host "[PARADO] alvo e NUCLEO do motor. Nucleo nunca se auto-modifica sem humano."
    Write-Host ""
    Write-Host "RESUMO PARA APROVACAO:"
    Write-Host ("  target:       " + $target)
    Write-Host ("  what:         " + $fields["what"])
    Write-Host ("  why:          " + $fields["why"])
    Write-Host ("  motivated_by: " + $fields["motivated_by"])
    Write-Host ("  provas: teste especifico falha no vivo / passa na copia; smokes sem regressao; held-out intacto.")
    Write-Host ""
    Write-Host "Rode de novo com -ApproveCore para promover (o vivo AINDA NAO foi tocado)."
    exit 2
  }

  $today = (Get-Date).ToString("yyyy-MM-dd")
  $archiveEntry = Join-Path $archiveDir ($today + "-" + $Candidate)
  New-Item -ItemType Directory -Force -Path $archiveEntry | Out-Null
  Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $archiveEntry "manifest.md") -Force
  # o VIVO original vai pra _archive ANTES de ser substituido - nunca se apaga.
  Copy-Item -LiteralPath $liveTarget -Destination (Join-Path $archiveEntry "original") -Force
  $origHash = (Get-FileHash -LiteralPath (Join-Path $archiveEntry "original") -Algorithm SHA256).Hash

  # o candidato assume o lugar do vivo.
  Copy-Item -LiteralPath $proposedPath -Destination $liveTarget -Force
  $newHash = (Get-FileHash -LiteralPath $liveTarget -Algorithm SHA256).Hash

  $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  Append-Lineage(
    "`r`n## APLICADO - " + $today + "-" + $Candidate + " - " + $stamp + "`r`n`r`n" +
    "- target: " + $target + "`r`n" +
    "- what: " + $fields["what"] + "`r`n" +
    "- why: " + $fields["why"] + "`r`n" +
    "- motivated_by: " + $fields["motivated_by"] + "`r`n" +
    "- nucleo: " + $isCore + $(if ($isCore) { " (aprovado com -ApproveCore)" } else { "" }) + "`r`n" +
    "- provas: (a) falhou no vivo antes; (c) passou na copia depois; (d) smoke-test-studio PASS=" + $after.Studio.Pass + "/FAIL=" + $after.Studio.Fail + " sem regressao, smoke oficina PASS=" + $after.Lab.Pass + "/FAIL=" + $after.Lab.Fail + " sem regressao; (e) held-out intacto`r`n" +
    "- original arquivado em: engine/rsi/_archive/" + $today + "-" + $Candidate + "/original (hash " + $origHash + ")`r`n" +
    "- novo hash do vivo: " + $newHash + "`r`n" +
    "- rollback: rsi-apply.ps1 -Rollback " + $Candidate + "`r`n`r`n"
  )

  Write-Host ("[OK] promovido: " + $target)
  Write-Host ("     original arquivado em engine/rsi/_archive/" + $today + "-" + $Candidate + "/original")
  Write-Host ("     LINEAGE.md atualizado: engine/rsi/_archive/LINEAGE.md")
  Close-Candidate -slug $Candidate -archiveEntryPath $archiveEntry
  Write-Host ""
  Write-Host "APLICADO: OK"
  exit 0
}
finally {
  Remove-RsiLightCopy -Copy $copy
}
