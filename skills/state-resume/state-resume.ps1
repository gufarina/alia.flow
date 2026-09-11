# Alia Flow - Frugal Skill: state-resume
# Le o journal append-only de eventos (events[]) do state.json e, por Task, aponta o ULTIMO
# passo bom e o ponto de retomada - de forma deterministica (sem LLM, custo zero de token).
# REUSE do PADRAO journal: nao importa runtime; so le os eventos que o estado ja grava.
#
# Dois modos:
#   (default)   resume   - por Task, emite o ultimo passo bom e de onde retomar.
#   -Validate            - confere o schema do journal: cada evento tem os campos
#                          obrigatorios e a cadeia e append-only/monotonica (ts nao
#                          retrocede, nem global nem por Task). PASS exit 0 / FAIL exit 1.
#
# Saida:
#   contrato cumprido  -> [PASS] exit 0
#   contrato violado   -> [FAIL] exit 1 com o desvio exato apontado (deviation)
# Molde: scripts/memory-curator.ps1 e skills/validate-artifact/validate-artifact.ps1.
# Português correto, com acentos. Arquivo salvo em UTF-8 sem BOM; o único erro é caractere corrompido. Emoji continua fora de peça pública.

param(
  [string]$StatePath = "",
  [switch]$Validate
)

$ErrorActionPreference = "Stop"

function ReadText([string]$p) {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($p, $utf8)
}

$script:deviations = @()
function Deviate([string]$msg) { $script:deviations += $msg }

# Os 5 passos do protocolo (engine/orchestration.md) sao contrato com o estado. A ordem
# e fixa: o ponto de retomada e o proximo passo apos o ultimo passo bom registrado.
$script:steps = @("IDENTIFICA", "REGISTRA", "DELEGA", "MONITORA", "FECHA")
$script:validTypes = @("started", "delegated", "artifact", "gate", "escalated", "done")

# Resolve o state.json: -StatePath explicito, senao o studio.example do produto.
if ($StatePath -eq "") {
  $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  $StatePath = Join-Path $root "studio.example\state.json"
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

# events[] e aditivo: estado antigo (so tasks[]) segue valido - journal vazio nao e erro.
$events = @()
if ($state.PSObject.Properties.Name -contains "events" -and $null -ne $state.events) {
  $events = @($state.events)
}

# Ordem do passo (indice no protocolo); -1 = passo desconhecido.
function StepIndex([string]$s) {
  for ($i = 0; $i -lt $script:steps.Count; $i++) {
    if ($script:steps[$i] -eq $s) { return $i }
  }
  return -1
}

# ---------------------------------------------------------------------------
# MODO -Validate: schema append-only/monotonico do events[].
# ---------------------------------------------------------------------------
if ($Validate) {
  Write-Host "=== state-resume (validate) ==="
  Write-Host ("State:  " + $StatePath)
  Write-Host ("Eventos: " + $events.Count)

  $i = 0
  $prevTsGlobal = $null
  $lastTsByTask = @{}
  foreach ($e in $events) {
    $i++
    # (a) campos obrigatorios do evento.
    foreach ($field in @("ts", "task_id", "step", "type", "ref")) {
      $val = $e.$field
      if ($null -eq $val -or ("" + $val).Trim() -eq "") {
        Deviate ("evento #" + $i + ": campo obrigatorio ausente/vazio: " + $field)
      }
    }
    # (b) step e type dentro do vocabulario contratado.
    if ($null -ne $e.step -and (StepIndex ([string]$e.step)) -lt 0) {
      Deviate ("evento #" + $i + ": step fora do protocolo (5 passos): " + $e.step)
    }
    if ($null -ne $e.type -and ($script:validTypes -notcontains [string]$e.type)) {
      Deviate ("evento #" + $i + ": type fora do vocabulario: " + $e.type)
    }
    # (c) ts parseavel e monotonico (append-only: nunca retrocede).
    $ts = $null
    if ($null -ne $e.ts) { $ts = ([string]$e.ts) -as [datetime] }
    if ($null -eq $ts) {
      Deviate ("evento #" + $i + ": ts nao e data/hora valida: " + $e.ts)
    } else {
      if ($null -ne $prevTsGlobal -and $ts -lt $prevTsGlobal) {
        Deviate ("evento #" + $i + ": ts retrocede (append-only global violado): " + $e.ts + " < " + $prevTsGlobal.ToString("o"))
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

# ---------------------------------------------------------------------------
# MODO resume (default): por Task, ultimo passo bom + ponto de retomada.
# ---------------------------------------------------------------------------
Write-Host "=== state-resume ==="
Write-Host ("State:  " + $StatePath)
Write-Host ("Eventos: " + $events.Count)
Write-Host ""

if ($events.Count -eq 0) {
  Write-Host "[OK] journal vazio (events[]): nada a retomar."
  exit 0
}

# Por Task: o evento mais recente (maior ts) e o ultimo passo bom registrado.
# events[] e append-only, entao a ordem do array ja e cronologica; ainda assim
# resolvemos por ts para nao depender da ordem de leitura.
$byTask = @{}
foreach ($e in $events) {
  $tid = [string]$e.task_id
  if (-not $byTask.ContainsKey($tid)) { $byTask[$tid] = New-Object System.Collections.Generic.List[object] }
  $byTask[$tid].Add($e)
}

foreach ($tid in ($byTask.Keys | Sort-Object)) {
  $list = $byTask[$tid]
  $last = $null
  $lastTs = $null
  foreach ($e in $list) {
    $ts = ([string]$e.ts) -as [datetime]
    if ($null -eq $ts) { continue }
    if ($null -eq $lastTs -or $ts -ge $lastTs) { $lastTs = $ts; $last = $e }
  }
  if ($null -eq $last) {
    Write-Host ("[" + $tid + "] sem evento com ts valido: nao da pra apontar retomada.")
    continue
  }

  $lastStep = [string]$last.step
  $lastType = [string]$last.type
  $idx = StepIndex $lastStep

  if ($lastType -eq "done") {
    Write-Host ("[" + $tid + "] COMPLETA - ultimo passo: " + $lastStep + " (done). Nada a retomar.")
    continue
  }

  # Ponto de retomada: se o ultimo passo bom ainda nao terminou (sem 'done'), retoma DELE
  # (continua o passo corrente); MONITORA so avanca pra FECHA quando ha gate+memoria.
  $resumeStep = $lastStep
  if ($idx -lt 0) {
    Write-Host ("[" + $tid + "] INTERROMPIDA - ultimo passo desconhecido: '" + $lastStep + "'. Revisar manualmente.")
    continue
  }
  Write-Host ("[" + $tid + "] INTERROMPIDA - ultimo passo bom: " + $lastStep +
    " (" + $lastType + ", ref=" + $last.ref + ")")
  Write-Host ("    -> RETOMAR de: " + $resumeStep + " (nao re-rodar passos anteriores)")
}

exit 0
