<#
  health-check.ps1 - Mecanismo do loop agendado health-check (cadence: daily, owner: squad-owner).
  Spec: engine/governance/loops.catalog.yaml (scheduled_loops: health-check).
  Pergunta que responde: o projeto esta vivo e consistente?
  Verifica, para o Client: squad.yaml existe, knowledge/ nao vazio, loops.yaml valido (parse YAML
  minimo: campos obrigatorios por loop), state.json parseavel e com o Client registrado.
  Frugal: so le; nao reprocessa. Escrita .NET UTF-8 sem BOM.

  Nao corrige nada: reporta o status. O RSI propoe, o Quality Gate aprova.
#>
param(
  [Parameter(Mandatory = $true)][string]$Client,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "_studio.ps1")
$studioRoot = Get-StudioRoot $root

$clientDir = Join-Path $studioRoot ("clients\" + $Client)
$squadDir  = Join-Path $clientDir "squad"
$squadYaml = Join-Path $squadDir "squad.yaml"
$knowDir   = Join-Path $squadDir "knowledge"
$loopsYaml = Join-Path $clientDir "loops.yaml"
$statePath = Join-Path $studioRoot "state.json"

$utf8  = New-Object System.Text.UTF8Encoding($false)
$today = (Get-Date).ToString("yyyy-MM-dd")

Write-Host "=== Health Check Loop ==="
Write-Host ("client: " + $Client + " | data: " + $today)
Write-Host ("raiz: " + $root)
Write-Host ("modo: " + $(if ($DryRun) { "DRY-RUN (so verifica, nao grava relatorio)" } else { "RUN" }))
Write-Host ""

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check {
  param([string]$name, [bool]$ok, [string]$detail = "")
  $status = if ($ok) { "[OK]" } else { "[ERRO]" }
  $line = $status + " " + $name + $(if ($detail) { " - " + $detail } else { "" })
  Write-Host $line
  $script:checks.Add([pscustomobject]@{ name = $name; ok = $ok; detail = $detail })
}

# (1) diretorio do Client existe
Add-Check "diretorio do Client existe" (Test-Path -LiteralPath $clientDir) $clientDir

# (2) squad/squad.yaml existe
Add-Check "squad/squad.yaml existe" (Test-Path -LiteralPath $squadYaml)

# (3) knowledge/ nao vazio
$kOk = $false
$kCount = 0
if (Test-Path -LiteralPath $knowDir) {
  $kfiles = @(Get-ChildItem -LiteralPath $knowDir -File -ErrorAction SilentlyContinue)
  $kCount = $kfiles.Count
  $kOk = ($kCount -gt 0)
}
Add-Check "knowledge/ nao vazio" $kOk ($kCount.ToString() + " arquivo(s)")

# (4) loops.yaml existe e e valido (parse minimo: cada loop tem os campos obrigatorios)
$loopsOk = $false
$loopsDetail = "ausente"
if (Test-Path -LiteralPath $loopsYaml) {
  $txt = [System.IO.File]::ReadAllText($loopsYaml)
  # Conta blocos de loop (linhas "  - id:") e checa presenca dos campos obrigatorios em cada um.
  $required = @("id", "trigger", "cadence", "owner", "status", "review_on")
  $lines = $txt -split "`r?`n"
  $blocks = New-Object System.Collections.Generic.List[hashtable]
  $current = $null
  foreach ($ln in $lines) {
    if ($ln -match '^\s*-\s+id\s*:\s*(\S+)') {
      if ($null -ne $current) { $blocks.Add($current) }
      $current = @{ id = $matches[1]; fields = @{ id = $true } }
    } elseif ($null -ne $current -and $ln -match '^\s+([a-zA-Z_]+)\s*:') {
      $current.fields[$matches[1]] = $true
    } elseif ($ln -match '^\S' -and $null -ne $current -and $ln -notmatch '^\s*#') {
      # saiu da lista loops para uma chave de topo
      $blocks.Add($current); $current = $null
    }
  }
  if ($null -ne $current) { $blocks.Add($current) }

  $missing = New-Object System.Collections.Generic.List[string]
  foreach ($b in $blocks) {
    foreach ($r in $required) {
      if (-not $b.fields.ContainsKey($r)) { $missing.Add($b.id + ":" + $r) }
    }
  }
  $loopsOk = ($blocks.Count -gt 0 -and $missing.Count -eq 0)
  $loopsDetail = $blocks.Count.ToString() + " loop(s)" + $(if ($missing.Count -gt 0) { "; faltando: " + ($missing -join ", ") } else { "; campos obrigatorios OK" })
}
Add-Check "loops.yaml valido" $loopsOk $loopsDetail

# (5) state.json parseavel e com o Client registrado
$stateOk = $false
$stateDetail = "ausente"
if (Test-Path -LiteralPath $statePath) {
  try {
    $state = [System.IO.File]::ReadAllText($statePath) | ConvertFrom-Json
    $ids = @($state.clients | ForEach-Object { $_.id })
    $stateOk = ($ids -contains $Client)
    $stateDetail = $(if ($stateOk) { "Client registrado" } else { "Client NAO esta em state.json (clients=" + ($ids -join ",") + ")" })
  } catch {
    $stateDetail = "JSON invalido: " + $_.Exception.Message
  }
}
Add-Check "state.json parseavel + Client registrado" $stateOk $stateDetail

# Resumo
$okCount  = @($checks | Where-Object { $_.ok }).Count
$errCount = @($checks | Where-Object { -not $_.ok }).Count
$verdict  = if ($errCount -eq 0) { "VIVO E CONSISTENTE" } else { "INCONSISTENTE" }

Write-Host ""
Write-Host ("Resumo: " + $okCount + " OK, " + $errCount + " ERRO | veredito: " + $verdict)

# Relatorio (so quando nao for DryRun)
if (-not $DryRun) {
  $outDir = Join-Path $knowDir "loop-reports"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $outFile = Join-Path $outDir ($today + "-health-check.md")
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("# Health Check - " + $Client + " (" + $today + ")")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("> Mecanismo: scripts/health-check.ps1. Pra revisao - RSI propoe, Gate aprova.")
  [void]$sb.AppendLine("> Veredito: " + $verdict + " (" + $okCount + " OK, " + $errCount + " ERRO)")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("| Check | Status | Detalhe |")
  [void]$sb.AppendLine("|-------|--------|---------|")
  foreach ($c in $checks) {
    $st = if ($c.ok) { "OK" } else { "ERRO" }
    [void]$sb.AppendLine("| " + $c.name + " | " + $st + " | " + $c.detail + " |")
  }
  [System.IO.File]::WriteAllText($outFile, $sb.ToString(), $utf8)
  Write-Host ("[OK] relatorio: " + $outFile)
}

if ($errCount -eq 0) { exit 0 } else { exit 1 }
