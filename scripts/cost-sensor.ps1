<#
  cost-sensor.ps1 - Ralo n.3 do TASK-283 fechado: custo sem sensor vira custo MEDIDO (WARDEN).

  Mede o custo-proxy do dia (MB de transcript + contagem de subagentes) a partir dos transcripts
  locais que o proprio Claude Code ja grava em disco - deterministico, ZERO chamada de LLM. Nao
  inventa telemetria nova: le $ProjectsDir\<slug>\*.jsonl (sessao) e $ProjectsDir\<slug>\<id>\
  subagents\agent-*.jsonl (cada subagente, achado real: pasta da sessao tem subpasta "subagents",
  1 par .jsonl+.meta.json por spawn - medido em disco na sessao 8b403537, TASK-283).

  Unidade de medida (proxy, nao token exato): MB de transcript por sessao (arquivo principal +
  subagents/) e contagem de arquivos agent-*.jsonl (= subagentes spawnados). MB de transcript e
  proxy direto de token gasto porque cada volta reenvia o historico inteiro (custo quadratico) -
  e exatamente o padrao medido no Ralo n.1 do mandato do CEO (25/08/2026).

  Teto configuravel (nunca afrouxado em runtime - mesma politica de budget-check.ps1):
    -CapSubagents (default 20)  -> sessao com mais subagentes que isso acusa [ESTOURO]
    -CapSessionMB (default 30)  -> sessao com mais MB que isso acusa [ESTOURO]
    -CapDailyMB   (default 80)  -> soma do dia acima disso acusa [ESTOURO] (nivel dia)

  -WhatIf: modo de PROVA (usado pelo smoke-test.ps1 da oficina). Mede e reporta normalmente, mas
  NUNCA escreve em studio/cost-log.jsonl - fixture/dry-run nao pode sujar a serie historica real.

  Sem agendador (LEI zero-agendamento): este script nao se auto-chama. Numa instancia real, quem
  pendura a chamada e scripts/smoke-test-studio.ps1 (mesmo padrao de memory-curator.ps1 -Validade -
  a rotina anda de carona no pipeline que ja roda sempre, engine/tools.md "Pipeline em CLI"). Na
  oficina, sem instancia real rodando, o smoke SO valida que o script existe e roda em -WhatIf.

  Uso:
    cost-sensor.ps1 [-ProjectsDir <path>] [-Slug <slug>] [-Date yyyy-MM-dd]
                     [-CapSubagents 20] [-CapSessionMB 30] [-CapDailyMB 80] [-Top 5] [-WhatIf]
  Escrita .NET UTF-8 sem BOM. Sem acentos, sem emojis.
#>
param(
  [string]$ProjectsDir = "",
  [string]$Slug = "",
  [string]$Date = "",
  [int]$CapSubagents = 20,
  [int]$CapSessionMB = 30,
  [int]$CapDailyMB = 80,
  [int]$Top = 5,
  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "_studio.ps1")

if ($ProjectsDir -eq "") { $ProjectsDir = Join-Path $env:USERPROFILE ".claude/projects" }
if ($Slug -eq "") { $Slug = ($PWD.Path -replace '[^a-zA-Z0-9]', '-') }
if ($Date -eq "") { $Date = (Get-Date).ToString("yyyy-MM-dd") }

$sessDir = Join-Path $ProjectsDir $Slug

Write-Host "=== Cost Sensor (custo-proxy por sessao/dia) ==="
Write-Host ("slug: " + $Slug + " | data: " + $Date + " | fonte: " + $sessDir)
Write-Host ("tetos: subagentes/sessao=" + $CapSubagents + " | MB/sessao=" + $CapSessionMB + " | MB/dia=" + $CapDailyMB)
Write-Host ""

if (-not (Test-Path -LiteralPath $sessDir)) {
  Write-Host ("[INFO] sem transcript para este slug/dia (pasta nao existe: " + $sessDir + ") - nada a medir")
  exit 0
}

$sessions = @()
$jsonlFiles = Get-ChildItem -LiteralPath $sessDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue
foreach ($f in $jsonlFiles) {
  $mDate = $f.LastWriteTime.ToString("yyyy-MM-dd")
  if ($mDate -ne $Date) { continue }
  $sid = $f.BaseName
  $mainMB = [math]::Round($f.Length / 1MB, 2)
  $subCount = 0
  $subMB = 0.0
  $subDir = Join-Path $sessDir (Join-Path $sid "subagents")
  if (Test-Path -LiteralPath $subDir) {
    $subFiles = Get-ChildItem -LiteralPath $subDir -Filter "agent-*.jsonl" -File -ErrorAction SilentlyContinue
    $subCount = @($subFiles).Count
    foreach ($sf in $subFiles) { $subMB += $sf.Length }
    $subMB = [math]::Round($subMB / 1MB, 2)
  }
  $totalMB = [math]::Round($mainMB + $subMB, 2)
  $sessions += [pscustomobject]@{
    id = $sid; mainMB = $mainMB; subMB = $subMB; totalMB = $totalMB; subagents = $subCount
  }
}

$sessionCount = @($sessions).Count
$dayTotalMB = [math]::Round((($sessions | Measure-Object -Property totalMB -Sum).Sum), 2)
if ($null -eq $dayTotalMB) { $dayTotalMB = 0 }
$dayTotalSub = ($sessions | Measure-Object -Property subagents -Sum).Sum
if ($null -eq $dayTotalSub) { $dayTotalSub = 0 }

Write-Host ("sessoes no dia: " + $sessionCount + " | MB total: " + $dayTotalMB + " | subagentes total: " + $dayTotalSub)
Write-Host ""

$sessionEstouros = @()
if ($sessionCount -gt 0) {
  Write-Host ("-- Top " + $Top + " ofensores (por MB) --")
  $topSessions = $sessions | Sort-Object -Property totalMB -Descending | Select-Object -First $Top
  foreach ($s in $topSessions) {
    $flag = ""
    if (($s.subagents -gt $CapSubagents) -or ($s.totalMB -gt $CapSessionMB)) { $flag = " [ESTOURO]" }
    Write-Host ("  " + $s.id + " | " + $s.totalMB + " MB (main=" + $s.mainMB + " + sub=" + $s.subMB + ") | " + $s.subagents + " subagente(s)" + $flag)
  }
  foreach ($s in $sessions) {
    if (($s.subagents -gt $CapSubagents) -or ($s.totalMB -gt $CapSessionMB)) { $sessionEstouros += $s.id }
  }
}

$dailyEstouro = ($dayTotalMB -gt $CapDailyMB)

Write-Host ""
if ($sessionEstouros.Count -gt 0) {
  Write-Host ("[ESTOURO] " + $sessionEstouros.Count + " sessao(oes) acima do teto por sessao: " + ($sessionEstouros -join ", "))
}
if ($dailyEstouro) {
  Write-Host ("[ESTOURO] dia " + $Date + " acima do teto diario: " + $dayTotalMB + " MB > " + $CapDailyMB + " MB")
}
if (($sessionEstouros.Count -eq 0) -and (-not $dailyEstouro)) {
  Write-Host "[PASS] dentro dos tetos configurados"
}

if (-not $WhatIf) {
  # Ledger de freio sempre em <root>/studio/ (literal), igual aos outros ledgers de governanca
  # (graph-usage-log.jsonl, response-guard-log.jsonl, smoke-log.jsonl) - NUNCA via Get-StudioRoot,
  # que resolve studio_dir (config de onde vive o DADO DE CLIENTE, ex. "." nesta instancia). Bug
  # medido TASK-283 fechamento: usar Get-StudioRoot aqui gravou em <raiz>/cost-log.jsonl na
  # instancia real (studio_dir="."), divergindo do doc (CHANGELOG, persistence-catalog, tools.md).
  $logPath = Join-Path (Join-Path $root "studio") "cost-log.jsonl"
  $logDir = Split-Path -Parent $logPath
  if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
  $line = [pscustomobject]@{
    ts = (Get-Date).ToString("o")
    date = $Date
    slug = $Slug
    sessionCount = $sessionCount
    dayTotalMB = $dayTotalMB
    dayTotalSubagents = $dayTotalSub
    sessionEstouros = $sessionEstouros
    dailyEstouro = $dailyEstouro
  } | ConvertTo-Json -Compress
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::AppendAllText($logPath, $line + "`n", $utf8NoBom)
  Write-Host ("[LOG] linha gravada em " + $logPath)
} else {
  Write-Host "[WHATIF] modo de prova - nada gravado em cost-log.jsonl"
}

if (($sessionEstouros.Count -gt 0) -or $dailyEstouro) { exit 1 }
exit 0
