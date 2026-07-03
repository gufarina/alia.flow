# Alia Flow - Install Loops
# Le studio/clients/{id}/loops.yaml e instala os loops AGENDADOS no Windows Task Scheduler.
# Dry-run por padrao (so mostra o que faria). Use -Install para registrar de verdade.
# Loops de evento sao cobertos pelo engine - este script so cuida dos agendados.
# Sem acentos, sem emojis. Leitura UTF-8 sem BOM.
#
# Subconjunto de YAML suportado pelo parser (igual filosofia do score.py):
#   - cada loop comeca em "  - id: <valor>"
#   - campos lidos: trigger, cadence, owner, status, mechanism, review_on
#   - 1 campo por linha, no formato "  <chave>: <valor>" (sem aninhamento)
#   - valores podem vir entre aspas simples ou duplas (sao removidas)
#   - NAO suporta valores multi-linha, blocos, ou ':' dentro de valor sem aspas
# Qualquer loop scheduled sem review_on, cadence ou mechanism aborta a instalacao.

param(
  [Parameter(Mandatory = $true)][string]$Client,
  [string]$StudioRoot = "",
  [switch]$Install
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "_studio.ps1")

# Resolve a raiz do studio: -StudioRoot manual vence; senao le studio_dir da config.
# Se nao houver loops.yaml ali, faz fallback para 'studio.example' (layout do exemplo).
$studioRootPath = if ($StudioRoot -ne "") { Join-Path $root $StudioRoot } else { Get-StudioRoot $root }
$loopsFile = Join-Path $studioRootPath ("clients\" + $Client + "\loops.yaml")
if (-not (Test-Path $loopsFile)) {
  $exampleFile = Join-Path $root ("studio.example\clients\" + $Client + "\loops.yaml")
  if (($StudioRoot -ne "studio.example") -and (Test-Path $exampleFile)) {
    Write-Host ("[AVISO] nao achei loops.yaml no studio; usando o exemplo: studio.example")
    $loopsFile = $exampleFile
  }
}

if (-not (Test-Path $loopsFile)) {
  Write-Host ("[ERRO] loops.yaml nao encontrado: " + $loopsFile)
  exit 1
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$text = [System.IO.File]::ReadAllText($loopsFile, $utf8)
$lines = $text -split "`n"

# Remove aspas simples OU duplas que envolvam o valor (YAML aceita ambas).
function Unquote([string]$v) { return $v.Trim().Trim('"').Trim("'") }

# Parser simples: cada loop comeca em "  - id:"
$loops = @()
$cur = $null
foreach ($raw in $lines) {
  $line = $raw.TrimEnd()
  if ($line -match '^\s*-\s*id:\s*(.+)$') {
    if ($cur) { $loops += $cur }
    $cur = @{ id = (Unquote $matches[1]); trigger = ""; cadence = ""; mechanism = ""; status = ""; owner = ""; review_on = "" }
  } elseif ($cur -and $line -match '^\s+trigger:\s*(.+)$') { $cur.trigger = (Unquote $matches[1]) }
  elseif ($cur -and $line -match '^\s+cadence:\s*(.+)$') { $cur.cadence = (Unquote $matches[1]) }
  elseif ($cur -and $line -match '^\s+status:\s*(.+)$') { $cur.status = (Unquote $matches[1]) }
  elseif ($cur -and $line -match '^\s+owner:\s*(.+)$') { $cur.owner = (Unquote $matches[1]) }
  elseif ($cur -and $line -match '^\s+review_on:\s*(.+)$') { $cur.review_on = (Unquote $matches[1]) }
  elseif ($cur -and $line -match '^\s+mechanism:\s*(.+)$') { $cur.mechanism = (Unquote $matches[1]) }
}
if ($cur) { $loops += $cur }

# Schema guard - fonte unica de verdade com o smoke test (T13):
# todo loop deve ter review_on (lei do CEO). Recusa a instalacao se faltar.
$noReview = $loops | Where-Object { -not $_.review_on }
if ($noReview.Count -gt 0) {
  Write-Host ("[ERRO] loop(s) sem review_on (obrigatorio): " + (($noReview | ForEach-Object { $_.id }) -join ", "))
  exit 1
}

$scheduled = @($loops | Where-Object { $_.trigger -eq "scheduled" -and $_.status -eq "active" })
$events    = @($loops | Where-Object { $_.trigger -eq "event" })

Write-Host ("=== Install Loops - cliente: " + $Client + " ===")
Write-Host ("Total de loops: " + $loops.Count + " | agendados ativos: " + $scheduled.Count + " | de evento: " + $events.Count)
Write-Host ("Modo: " + $(if ($Install) { "INSTALL (registra no Task Scheduler)" } else { "DRY-RUN (so mostra; use -Install para valer)" }))
Write-Host ""

$installErrors = @()
foreach ($l in $scheduled) {
  $taskName = "AliaFlow-" + $Client + "-" + $l.id
  $sched = switch ($l.cadence) { "daily" { "DIARIO 08:00" } "weekly" { "SEMANAL seg 08:00" } default { $l.cadence } }

  # Validacao de campos minimos (SCRIPTS-05): loop agendado sem cadence ou
  # mechanism viraria tarefa vazia. Aborta com mensagem clara.
  if (-not $l.cadence) { $installErrors += ($l.id + ": cadence vazio"); continue }
  if (-not $l.mechanism) { $installErrors += ($l.id + ": mechanism vazio"); continue }

  # O campo mechanism e texto livre (ex: "scripts/health-check.ps1 via Task Scheduler").
  # Extrai o caminho do .ps1 para registrar a tarefa de verdade.
  $mechScript = $null
  if ($l.mechanism -match '([^\s"'']+\.ps1)') { $mechScript = Join-Path $root $matches[1] }

  # Loop agente-driven: mechanism sem .ps1 = rodado sob demanda pelo agente (ex: via MCP),
  # nao instalavel no Task Scheduler. Pula sem erro.
  if (-not $mechScript) {
    Write-Host ("[AGENT-DRIVEN] " + $l.id + " -> sob demanda pelo agente; fora do Task Scheduler")
    continue
  }

  if ($Install) {
    # INTEGRACAO-02: so registra se o script de mecanismo existir; caso contrario
    # falha explicito em vez de imprimir sucesso falso.
    if (-not $mechScript -or -not (Test-Path $mechScript)) {
      $installErrors += ($l.id + ": mecanismo ausente (" + $l.mechanism + ")")
      Write-Host ("[ERRO] " + $taskName + " -> mecanismo ausente: " + $l.mechanism)
      continue
    }
    $action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ("-NoProfile -ExecutionPolicy Bypass -File `"" + $mechScript + "`"")
    $trigger = if ($l.cadence -eq "daily") { New-ScheduledTaskTrigger -Daily -At 8am }
               else { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 8am }
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Force | Out-Null
    Write-Host ("[INSTALL] " + $taskName + " (" + $sched + ") -> " + $mechScript)
  } else {
    $mechShow = if ($mechScript -and (Test-Path $mechScript)) { $l.mechanism } else { $l.mechanism + "  [AVISO: script de mecanismo nao encontrado]" }
    Write-Host ("[DRY-RUN] criaria tarefa " + $taskName + " (" + $sched + ") -> " + $mechShow)
  }
}

if ($installErrors.Count -gt 0) {
  Write-Host ""
  Write-Host ("[ERRO] " + $installErrors.Count + " loop(s) nao instalados:")
  foreach ($e in $installErrors) { Write-Host ("  - " + $e) }
  exit 1
}

Write-Host ""
Write-Host ("Loops de evento (sem agendamento - cobertos pelo engine): " + (($events | ForEach-Object { $_.id }) -join ", "))
Write-Host ""
Write-Host "OK"
exit 0
