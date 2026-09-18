<#
  squad-report.ps1 - Mecanismo do loop agendado squad-report (cadence: weekly, owner: squad-owner).
  Spec: engine/governance/loops.catalog.yaml (scheduled_loops: squad-report).
  Pergunta que responde: qual o status do squad para o Tier 2 (Alia)?
  Compila: membros do squad (squad.yaml: id, role, camada, gateway), loops ativos (loops.yaml:
  status active), e ultimas Tasks do Client (state.json). Frugal: so le e agrega. Escrita .NET
  UTF-8 sem BOM. RSI propoe, Gate aprova.
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
$squadYaml = Join-Path $clientDir "squad\squad.yaml"
$loopsYaml = Join-Path $clientDir "loops.yaml"
$knowDir   = Join-Path $clientDir "squad\knowledge"
$statePath = Join-Path $studioRoot "state.json"

$utf8  = New-Object System.Text.UTF8Encoding($false)
$today = (Get-Date).ToString("yyyy-MM-dd")

# ESTADO DO CLIENT (OPP-77): pontual (ideia tocada uma vez) e arquivado (encerrado) nao tem squad
# cobrado. O relatorio continua saindo - com o estado declarado no topo -, mas a ausencia de time
# deixa de ser lida como buraco: e o desenho. Client sem estado declarado = ativo.
$clientStates = Get-ClientStates $statePath
$clientState = Get-ClientStateOf $clientStates $Client

Write-Host "=== Squad Report Loop ==="
Write-Host ("client: " + $Client + " | data: " + $today + " | estado: " + $clientState)
Write-Host ("modo: " + $(if ($DryRun) { "DRY-RUN (so compila, nao grava relatorio)" } else { "RUN" }))
if ($clientState -ne "ativo") {
  Write-Host ("[INFO] Client '" + $clientState + "': nao cobra squad nem mapa de conhecimento (OPP-77). O que existir e registrado abaixo como informacao.")
}
Write-Host ""

if (-not (Test-Path -LiteralPath $clientDir)) {
  Write-Host ("[ERRO] diretorio do Client ausente: " + $clientDir)
  exit 1
}

# (1) Membros do squad (parse leve de squad.yaml: blocos "  - id:").
$members = New-Object System.Collections.Generic.List[object]
$gateway = "(desconhecido)"
if (Test-Path -LiteralPath $squadYaml) {
  $lines = [System.IO.File]::ReadAllText($squadYaml) -split "`r?`n"
  $cur = $null
  foreach ($ln in $lines) {
    if ($ln -match '^\s*gateway\s*:\s*(\S+)\s*$' -and $null -eq $cur) { $gateway = $matches[1] }
    if ($ln -match '^\s*-\s+id\s*:\s*(\S+)') {
      if ($null -ne $cur) { $members.Add($cur) }
      $cur = [pscustomobject]@{ id = $matches[1]; role = ""; camada = ""; gateway = "false" }
    } elseif ($null -ne $cur) {
      if ($ln -match '^\s+role\s*:\s*(.+?)\s*$')    { $cur.role = $matches[1] }
      elseif ($ln -match '^\s+camada\s*:\s*(\S+)')  { $cur.camada = $matches[1] }
      elseif ($ln -match '^\s+gateway\s*:\s*(\S+)') { $cur.gateway = $matches[1] }
      elseif ($ln -match '^\S') { $members.Add($cur); $cur = $null }
    }
  }
  if ($null -ne $cur) { $members.Add($cur) }
}
Write-Host ("[OK] gateway: " + $gateway + " | membros: " + $members.Count)
foreach ($m in $members) {
  $tag = if ($m.gateway -eq "true") { " (gateway)" } else { "" }
  Write-Host ("    - " + $m.id + " [" + $m.camada + "] " + $m.role + $tag)
}

# (2) Loops ativos (parse leve de loops.yaml: blocos com status active).
$activeLoops = New-Object System.Collections.Generic.List[string]
$totalLoops = 0
if (Test-Path -LiteralPath $loopsYaml) {
  $lines = [System.IO.File]::ReadAllText($loopsYaml) -split "`r?`n"
  $curId = $null; $curStatus = $null
  foreach ($ln in $lines) {
    if ($ln -match '^\s*-\s+id\s*:\s*(\S+)') {
      if ($null -ne $curId) { $totalLoops++; if ($curStatus -eq "active") { $activeLoops.Add($curId) } }
      $curId = $matches[1]; $curStatus = $null
    } elseif ($null -ne $curId -and $ln -match '^\s+status\s*:\s*(\S+)') {
      $curStatus = $matches[1]
    } elseif ($ln -match '^\S' -and $null -ne $curId) {
      $totalLoops++; if ($curStatus -eq "active") { $activeLoops.Add($curId) }
      $curId = $null; $curStatus = $null
    }
  }
  if ($null -ne $curId) { $totalLoops++; if ($curStatus -eq "active") { $activeLoops.Add($curId) } }
}
Write-Host ""
Write-Host ("[OK] loops ativos: " + $activeLoops.Count + "/" + $totalLoops + " | " + (@($activeLoops) -join ", "))

# (3) Ultimas Tasks do Client (state.json).
$tasks = @()
if (Test-Path -LiteralPath $statePath) {
  try {
    $state = [System.IO.File]::ReadAllText($statePath) | ConvertFrom-Json
    $tasks = @($state.tasks | Where-Object { $_.client -eq $Client } |
      Sort-Object { $_.created } -Descending | Select-Object -First 5)
  } catch {
    Write-Host ("[ERRO] state.json invalido: " + $_.Exception.Message)
  }
}
Write-Host ""
Write-Host ("[OK] ultimas tasks (ate 5): " + $tasks.Count)
foreach ($t in $tasks) {
  Write-Host ("    - " + $t.id + " [" + $t.status + "] " + $t.title)
}

Write-Host ""
Write-Host ("Resumo: " + $members.Count + " membro(s), " + $activeLoops.Count + " loop(s) ativo(s), " + $tasks.Count + " task(s) recente(s).")

if (-not $DryRun) {
  $outDir = Join-Path $knowDir "loop-reports"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $outFile = Join-Path $outDir ($today + "-squad-report.md")
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("# Squad Report - " + $Client + " (" + $today + ")")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("> Mecanismo: scripts/squad-report.ps1. Status do squad para o Tier 2 (Alia).")
  [void]$sb.AppendLine("> Gateway: " + $gateway)
  [void]$sb.AppendLine("> Estado do Client: " + $clientState + $(if ($clientState -ne "ativo") { " (nao cobra squad nem mapa - OPP-77)" } else { "" }))
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("## Membros")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("| Id | Camada | Papel | Gateway |")
  [void]$sb.AppendLine("|----|--------|-------|---------|")
  foreach ($m in $members) {
    [void]$sb.AppendLine("| " + $m.id + " | " + $m.camada + " | " + $m.role + " | " + $m.gateway + " |")
  }
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("## Loops ativos (" + $activeLoops.Count + "/" + $totalLoops + ")")
  [void]$sb.AppendLine("")
  if ($activeLoops.Count -eq 0) { [void]$sb.AppendLine("(nenhum)") }
  foreach ($l in $activeLoops) { [void]$sb.AppendLine("- " + $l) }
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("## Ultimas tasks")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("| Id | Status | Titulo | Criada |")
  [void]$sb.AppendLine("|----|--------|--------|--------|")
  foreach ($t in $tasks) {
    [void]$sb.AppendLine("| " + $t.id + " | " + $t.status + " | " + $t.title + " | " + $t.created + " |")
  }
  [System.IO.File]::WriteAllText($outFile, $sb.ToString(), $utf8)
  Write-Host ("[OK] relatorio: " + $outFile)
}

exit 0
