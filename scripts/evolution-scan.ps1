<#
  evolution-scan.ps1 - Mecanismo do loop agendado evolution-scan (cadence: weekly, owner: alia).
  Spec: engine/governance/loops.catalog.yaml (scheduled_loops: evolution-scan).
  Pergunta que responde: o projeto avancou desde o ultimo ciclo? (sinal de estagnacao)
  Olha o artifact mais recente (mtime de arquivos do Client) e as Tasks do Client em state.json
  (campo created). Se nada mudou dentro da janela, levanta sinal de estagnacao. Frugal: so le mtime
  e parseia o state. Reporta, nao corrige. Escrita .NET UTF-8 sem BOM.
  O RSI propoe, o Quality Gate aprova.
#>
param(
  [Parameter(Mandatory = $true)][string]$Client,
  [int]$StaleDays = 7,
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
$now   = Get-Date

Write-Host "=== Evolution Scan Loop ==="
Write-Host ("client: " + $Client + " | data: " + $today + " | limiar de estagnacao: " + $StaleDays + " dia(s)")
Write-Host ("modo: " + $(if ($DryRun) { "DRY-RUN (so analisa, nao grava relatorio)" } else { "RUN" }))
Write-Host ""

if (-not (Test-Path -LiteralPath $clientDir)) {
  Write-Host ("[ERRO] diretorio do Client ausente: " + $clientDir)
  exit 1
}

# (1) Artifact mais recente: maior mtime entre os arquivos do Client (exclui relatorios de loop).
$files = @(Get-ChildItem -LiteralPath $clientDir -File -Recurse -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '\\loop-reports\\' })
$lastArtifact = $null
$lastArtifactName = "(nenhum)"
if ($files.Count -gt 0) {
  $newest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $lastArtifact = $newest.LastWriteTime
  $lastArtifactName = $newest.FullName.Substring($clientDir.Length).TrimStart('\')
}

$daysArtifact = if ($null -ne $lastArtifact) { [math]::Round(($now - $lastArtifact).TotalDays, 1) } else { 99999 }
Write-Host ("[OK] artifact mais recente: " + $lastArtifactName + " (ha " + $daysArtifact + " dia(s))")

# (2) Tasks do Client em state.json: data de created mais recente.
$lastTaskDate = $null
$lastTaskTitle = "(nenhuma)"
$taskCount = 0
if (Test-Path -LiteralPath $statePath) {
  try {
    $state = [System.IO.File]::ReadAllText($statePath) | ConvertFrom-Json
    $tasks = @($state.tasks | Where-Object { $_.client -eq $Client })
    $taskCount = $tasks.Count
    foreach ($t in $tasks) {
      $d = $t.created -as [datetime]
      if ($null -ne $d) {
        if ($null -eq $lastTaskDate -or $d -gt $lastTaskDate) { $lastTaskDate = $d; $lastTaskTitle = [string]$t.title }
      }
    }
  } catch {
    Write-Host ("[ERRO] state.json invalido: " + $_.Exception.Message)
  }
}
$daysTask = if ($null -ne $lastTaskDate) { [math]::Round(($now - $lastTaskDate).TotalDays, 1) } else { 99999 }
Write-Host ("[OK] tasks do Client: " + $taskCount + " | mais recente: " + $lastTaskTitle + " (ha " + $daysTask + " dia(s))")

# Sinal: estagnado se o sinal MAIS recente (artifact ou task) for mais velho que o limiar.
$mostRecentDays = [math]::Min($daysArtifact, $daysTask)
$stale = ($mostRecentDays -gt $StaleDays)
$verdict = if ($stale) { "ESTAGNADO" } else { "EVOLUINDO" }

Write-Host ""
Write-Host ("Resumo: atividade mais recente ha " + $mostRecentDays + " dia(s) | veredito: " + $verdict)
if ($stale) {
  Write-Host ("[ERRO] sinal de estagnacao: nada mudou nos ultimos " + $StaleDays + " dia(s).")
} else {
  Write-Host ("[OK] projeto avancou dentro da janela de " + $StaleDays + " dia(s).")
}

if (-not $DryRun) {
  $outDir = Join-Path $knowDir "loop-reports"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $outFile = Join-Path $outDir ($today + "-evolution-scan.md")
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("# Evolution Scan - " + $Client + " (" + $today + ")")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("> Mecanismo: scripts/evolution-scan.ps1. Sinal de estagnacao, nao veredito final.")
  [void]$sb.AppendLine("> Veredito: " + $verdict + " | limiar: " + $StaleDays + " dia(s)")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("| Sinal | Valor | Idade (dias) |")
  [void]$sb.AppendLine("|-------|-------|--------------|")
  [void]$sb.AppendLine("| Artifact mais recente | " + $lastArtifactName + " | " + $daysArtifact + " |")
  [void]$sb.AppendLine("| Task mais recente | " + $lastTaskTitle + " | " + $daysTask + " |")
  [System.IO.File]::WriteAllText($outFile, $sb.ToString(), $utf8)
  Write-Host ("[OK] relatorio: " + $outFile)
}

# Estagnacao e sinal, nao falha de execucao: exit 0 quando rodou bem.
exit 0
