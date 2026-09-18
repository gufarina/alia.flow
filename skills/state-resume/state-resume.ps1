# Alia Flow - Frugal Skill: state-resume
# Le o journal append-only de eventos (studio/events.jsonl, escrito por register-task.ps1 via
# Add-Event, TASK-579) e, por Task, aponta o ULTIMO passo bom e o ponto de retomada - de forma
# deterministica (sem LLM, custo zero de token). REUSE do PADRAO journal: nao importa runtime;
# so le os eventos que o estado ja grava.
#
# FONTE UNICA DO DIARIO (TASK-585): antes lia state.events de DENTRO do state.json, enquanto
# register-task.ps1 grava em studio/events.jsonl - leitor e escritor em arquivos diferentes
# (furo transferido pelo gate da Fatia A, TASK-579). Agora le SEMPRE studio/events.jsonl,
# irmao do -StatePath (mesma pasta, nome fixo events.jsonl - mesma convencao de
# register-task.ps1). O campo events[] de DENTRO do state.json fica FROZEN: 10 entradas
# legadas (a mais antiga de 2026-06-20, task_id fora do padrao TASK-NNN, type fora do
# vocabulario aceito aqui, ex. delegated-self) nunca foram migradas de proposito -
# migrar exigiria inventar um type novo so pra elas passarem no -Validate, ou reescrever a
# palavra original (as duas opcoes forjam historico). Decisao e justificativa completas em
# engine/governance/persistence-catalog.md. Journal ausente ou vazio nao e erro.
#
# COMPATIBILIDADE (Tasks historicas sem evento, PROIBIDO migrar retroativamente): quando uma
# Task nao tem nenhum evento no journal, o fallback usa o campo status que ja existe em
# tasks[]: done fecha; doing/review avisa anterior ao diario, sem historico de passo,
# conferir a mao; qualquer outro status so reporta o status, sem inventar passo.
#
# PLANO (TASK-585): campo opcional plan em tasks[] aponta pra uma Task-mae (id). -Plan <id>
# lista as etapas (Tasks com plan == id), o estado de cada uma (evento ou fallback por status)
# e a PROXIMA etapa (a primeira, em ordem de id, que ainda nao fechou done) - sem modelar grafo
# de precedencia entre etapas, so o vinculo etapa->mae.
#
# Portugues correto, com acentos. Arquivo salvo em UTF-8 sem BOM. Emoji fora de peca publica.

param(
  [string]$StatePath = "",
  [switch]$Validate,
  [string]$Plan = ""
)

$ErrorActionPreference = "Stop"

function ReadText([string]$p) {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($p, $utf8)
}

function ReadEvents([string]$dir) {
  $f = Join-Path $dir "events.jsonl"
  $out = New-Object System.Collections.Generic.List[object]
  if (-not (Test-Path -LiteralPath $f)) { return $out.ToArray() }
  $lines = (ReadText $f) -split "`r`n|`n" | Where-Object { $_.Trim() -ne "" }
  foreach ($ln in $lines) {
    try { $out.Add(($ln | ConvertFrom-Json)) } catch { }
  }
  return $out.ToArray()
}

$script:deviations = @()
function Deviate([string]$msg) { $script:deviations += $msg }

$script:steps = @("IDENTIFICA", "REGISTRA", "DELEGA", "MONITORA", "FECHA")
$script:validTypes = @("started", "delegated", "artifact", "gate", "escalated", "done")

if ($StatePath -eq "") {
  $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  $StatePath = Join-Path $root "studio.example"
  $StatePath = Join-Path $StatePath "state.json"
}

if (-not (Test-Path -LiteralPath $StatePath)) {
  Write-Host "=== state-resume ==="
  Write-Host ("State:  " + $StatePath)
  Write-Host "[FAIL] schema do journal violado"
  Write-Host "  deviation: state.json ausente: caminho nao existe no disco"
  exit 1
}

$state = $null
try { $state = (ReadText $StatePath) | ConvertFrom-Json }
catch {
  Write-Host "=== state-resume ==="
  Write-Host ("State:  " + $StatePath)
  Write-Host "[FAIL] schema do journal violado"
  Write-Host "  deviation: state.json nao e JSON parseavel"
  exit 1
}

$eventsDir = Split-Path -Parent $StatePath
$events = @(ReadEvents $eventsDir)

$tasksById = @{}
if ($state.PSObject.Properties.Name -contains "tasks" -and $null -ne $state.tasks) {
  foreach ($t in @($state.tasks)) { $tasksById[[string]$t.id] = $t }
}

function StepIndex([string]$s) {
  for ($i = 0; $i -lt $script:steps.Count; $i++) {
    if ($script:steps[$i] -eq $s) { return $i }
  }
  return -1
}

if ($Validate) {
  Write-Host "=== state-resume (validate) ==="
  Write-Host ("State:  " + $StatePath)
  Write-Host ("Eventos: " + $events.Count)

  $i = 0
  $prevTsGlobal = $null
  $lastTsByTask = @{}
  foreach ($e in $events) {
    $i++
    foreach ($field in @("ts", "task_id", "step", "type", "ref")) {
      $val = $e.$field
      if ($null -eq $val -or ("" + $val).Trim() -eq "") {
        Deviate ("evento #" + $i + ": campo obrigatorio ausente/vazio: " + $field)
      }
    }
    if ($null -ne $e.step -and (StepIndex ([string]$e.step)) -lt 0) {
      Deviate ("evento #" + $i + ": step fora do protocolo (5 passos): " + $e.step)
    }
    if ($null -ne $e.type -and ($script:validTypes -notcontains [string]$e.type)) {
      Deviate ("evento #" + $i + ": type fora do vocabulario: " + $e.type)
    }
    $ts = $null
    if ($null -ne $e.ts) { $ts = ([string]$e.ts) -as [datetime] }
    if ($null -eq $ts) {
      Deviate ("evento #" + $i + ": ts nao e data/hora valida: " + $e.ts)
    } else {
      if ($null -ne $prevTsGlobal -and $ts -lt $prevTsGlobal) {
        Deviate ("evento #" + $i + ": ts retrocede (append-only global violado): " + $e.ts + " menor que " + $prevTsGlobal.ToString("o"))
      }
      $prevTsGlobal = $ts
      $tid = [string]$e.task_id
      if ($lastTsByTask.ContainsKey($tid) -and $ts -lt $lastTsByTask[$tid]) {
        Deviate ("evento #" + $i + " (task " + $tid + "): ts retrocede na Task (monotonico por Task violado)")
      }
      $lastTsByTask[$tid] = $ts
    }
  }

  if ($script:deviations.Count -eq 0) {
    Write-Host "[PASS] journal append-only/monotonico, schema completo"
    exit 0
  } else {
    Write-Host "[FAIL] schema do journal violado"
    foreach ($d in $script:deviations) { Write-Host ("  deviation: " + $d) }
    exit 1
  }
}

$byTask = @{}
foreach ($e in $events) {
  $tid = [string]$e.task_id
  if (-not $byTask.ContainsKey($tid)) { $byTask[$tid] = New-Object System.Collections.Generic.List[object] }
  $byTask[$tid].Add($e)
}

function Resolve-TaskLine([string]$tid) {
  if ($byTask.ContainsKey($tid)) {
    $list = $byTask[$tid]
    $last = $null
    $lastTs = $null
    foreach ($e in $list) {
      $ts = ([string]$e.ts) -as [datetime]
      if ($null -eq $ts) { continue }
      if ($null -eq $lastTs -or $ts -ge $lastTs) { $lastTs = $ts; $last = $e }
    }
    if ($null -eq $last) {
      return @{ text = "sem evento com ts valido: nao da pra apontar retomada."; done = $false; fonte = "evento" }
    }
    $lastStep = [string]$last.step
    $lastType = [string]$last.type
    $idx = StepIndex $lastStep
    if ($lastType -eq "done") {
      return @{ text = ("COMPLETA - ultimo passo: " + $lastStep + " (done, ref=" + $last.ref + "). Nada a retomar."); done = $true; fonte = "evento" }
    }
    if ($idx -lt 0) {
      return @{ text = ("INTERROMPIDA - ultimo passo desconhecido: " + $lastStep + ". Revisar manualmente."); done = $false; fonte = "evento" }
    }
    return @{ text = ("INTERROMPIDA - ultimo passo bom: " + $lastStep + " (" + $lastType + ", ref=" + $last.ref + "). RETOMAR de: " + $lastStep + " (nao re-rodar passos anteriores)"); done = $false; fonte = "evento" }
  }

  $st = ""
  if ($tasksById.ContainsKey($tid)) { $st = [string]$tasksById[$tid].status }
  if ($st -eq "done") {
    return @{ text = "COMPLETA (fallback por status: done). Sem evento no diario."; done = $true; fonte = "status" }
  }
  if ($st -eq "doing" -or $st -eq "review") {
    return @{ text = ("status=" + $st + " - anterior ao diario, sem historico de passo, conferir a mao."); done = $false; fonte = "status" }
  }
  if ($tasksById.ContainsKey($tid)) {
    return @{ text = ("sem evento no diario, status=" + $st + "."); done = $false; fonte = "status" }
  }
  return @{ text = "sem evento no diario e sem Task correspondente em tasks[]."; done = $false; fonte = "nenhuma" }
}

if (-not [string]::IsNullOrWhiteSpace($Plan)) {
  Write-Host "=== state-resume (plano) ==="
  Write-Host ("State:  " + $StatePath)
  Write-Host ("Plano:  " + $Plan)
  Write-Host ""

  if (-not $tasksById.ContainsKey($Plan)) {
    Write-Host ("[AVISO] Task-mae " + $Plan + " nao encontrada em tasks[] - segue mesmo assim (etapas podem existir sem a mae estar visivel neste state).")
  }

  $etapas = @($tasksById.Values | Where-Object { "$($_.plan)" -eq $Plan } | Sort-Object { [string]$_.id })
  if ($etapas.Count -eq 0) {
    Write-Host "[OK] nenhuma etapa aponta pra esta Task-mae (plan vazio ou id errado)."
    exit 0
  }

  $proxima = $null
  foreach ($et in $etapas) {
    $tid = [string]$et.id
    $r = Resolve-TaskLine $tid
    Write-Host ("[" + $tid + "] " + [string]$et.title + " -> " + $r.text + " (fonte: " + $r.fonte + ")")
    if (-not $r.done -and $null -eq $proxima) { $proxima = $tid }
  }

  Write-Host ""
  if ($null -ne $proxima) {
    Write-Host ("PROXIMA ETAPA: " + $proxima)
  } else {
    Write-Host "PROXIMA ETAPA: nenhuma - todas as etapas listadas estao fechadas (done)."
  }
  exit 0
}

Write-Host "=== state-resume ==="
Write-Host ("State:  " + $StatePath)
Write-Host ("Eventos: " + $events.Count)
Write-Host ""

if ($events.Count -eq 0) {
  Write-Host "[OK] journal vazio (studio/events.jsonl): nada a retomar."
  exit 0
}

foreach ($tid in ($byTask.Keys | Sort-Object)) {
  $r = Resolve-TaskLine $tid
  Write-Host ("[" + $tid + "] " + $r.text)
}

exit 0
