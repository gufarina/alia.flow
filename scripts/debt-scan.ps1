<#
  debt-scan.ps1 - Mecanismo do loop agendado debt-scan (cadence: weekly, owner: alia).
  Spec: engine/governance/loops.catalog.yaml (scheduled_loops: debt-scan).
  Pergunta que responde: ha Concerns abertos sem resolucao? (debito acumulado)
  Conforme o Quality Gate (quality-gate.md), um verdict "Concerns" e divida assumida: se nao virar
  correcao, vira debito - cobrado aqui. Varre o estado/memory do Client (state.json + knowledge/*.md
  + loops.yaml) por marcacoes de Concern/ressalva/TODO/FIXME/PENDENTE nao resolvidas. Frugal: so le.
  Reporta, nao corrige. Escrita .NET UTF-8 sem BOM. RSI propoe, Gate aprova.
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
$knowDir   = Join-Path $clientDir "squad\knowledge"
$statePath = Join-Path $studioRoot "state.json"

$utf8  = New-Object System.Text.UTF8Encoding($false)
$today = (Get-Date).ToString("yyyy-MM-dd")

Write-Host "=== Debt Scan Loop ==="
Write-Host ("client: " + $Client + " | data: " + $today)
Write-Host ("modo: " + $(if ($DryRun) { "DRY-RUN (so analisa, nao grava relatorio)" } else { "RUN" }))
Write-Host ""

if (-not (Test-Path -LiteralPath $clientDir)) {
  Write-Host ("[ERRO] diretorio do Client ausente: " + $clientDir)
  exit 1
}

# Padrao de marcacao de debito. "resolvido"/"resolved" na mesma linha indica que ja foi tratado.
$debtPattern = '(?i)\b(concern|concerns|ressalva|ressalvas|todo|fixme|pendente|debito|debt)\b'
$resolvedPattern = '(?i)\b(resolvid[oa]|resolved|fechad[oa]|done|concluid[oa])\b'

$open = New-Object System.Collections.Generic.List[object]

function Scan-File {
  param([string]$path, [string]$label)
  if (-not (Test-Path -LiteralPath $path)) { return }
  $i = 0
  foreach ($ln in ([System.IO.File]::ReadAllText($path) -split "`r?`n")) {
    $i++
    if ($ln -match $debtPattern -and $ln -notmatch $resolvedPattern) {
      $script:open.Add([pscustomobject]@{ source = $label; line = $i; text = $ln.Trim() })
    }
  }
}

# (1) Arquivos de memory/knowledge do Client (exclui relatorios de loop para nao auto-detectar).
$mdFiles = @(Get-ChildItem -LiteralPath $clientDir -Filter "*.md" -File -Recurse -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '\\loop-reports\\' })
foreach ($f in $mdFiles) {
  Scan-File $f.FullName ($f.FullName.Substring($clientDir.Length).TrimStart('\'))
}

# (2) loops.yaml (mecanismos PENDENTE contam como debito de loop).
Scan-File (Join-Path $clientDir "loops.yaml") "loops.yaml"

# (3) Tasks do Client em state.json: status nao concluido com ressalva/in_progress conta sinal.
$openTasks = 0
if (Test-Path -LiteralPath $statePath) {
  try {
    $state = [System.IO.File]::ReadAllText($statePath) | ConvertFrom-Json
    foreach ($t in @($state.tasks | Where-Object { $_.client -eq $Client })) {
      if ([string]$t.status -ne "done") {
        $openTasks++
        $script:open.Add([pscustomobject]@{ source = "state.json:task " + $t.id; line = 0; text = "[" + $t.status + "] " + $t.title })
      }
    }
  } catch {
    Write-Host ("[ERRO] state.json invalido: " + $_.Exception.Message)
  }
}

if ($open.Count -eq 0) {
  Write-Host "[OK] nenhum Concern/ressalva aberto detectado - sem debito aparente."
} else {
  Write-Host ("[ERRO] itens de debito abertos: " + $open.Count + " (tasks abertas: " + $openTasks + ")")
  foreach ($o in $open) {
    $loc = if ($o.line -gt 0) { $o.source + ":" + $o.line } else { $o.source }
    $t = if ($o.text.Length -gt 100) { $o.text.Substring(0, 100) + "..." } else { $o.text }
    Write-Host ("    - " + $loc + " | " + $t)
  }
}

Write-Host ""
Write-Host ("Resumo: " + $open.Count + " item(ns) de debito aberto(s).")

if (-not $DryRun) {
  $outDir = Join-Path $knowDir "loop-reports"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $outFile = Join-Path $outDir ($today + "-debt-scan.md")
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("# Debt Scan - " + $Client + " (" + $today + ")")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("> Mecanismo: scripts/debt-scan.ps1. Concerns abertos = divida rastreada (Gate).")
  [void]$sb.AppendLine("> Itens de debito abertos: " + $open.Count + " | tasks abertas: " + $openTasks)
  [void]$sb.AppendLine("")
  if ($open.Count -eq 0) {
    [void]$sb.AppendLine("Nenhum Concern/ressalva aberto detectado.")
  } else {
    [void]$sb.AppendLine("| Origem | Linha | Trecho |")
    [void]$sb.AppendLine("|--------|-------|--------|")
    foreach ($o in $open) {
      $txt = ($o.text -replace '\|', '\').Trim()
      if ($txt.Length -gt 120) { $txt = $txt.Substring(0, 120) + "..." }
      [void]$sb.AppendLine("| " + $o.source + " | " + $o.line + " | " + $txt + " |")
    }
  }
  [System.IO.File]::WriteAllText($outFile, $sb.ToString(), $utf8)
  Write-Host ("[OK] relatorio: " + $outFile)
}

# Debito e sinal, nao falha de execucao: exit 0 quando rodou bem.
exit 0
