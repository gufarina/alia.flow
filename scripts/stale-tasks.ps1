<#
  stale-tasks.ps1 - Os olhos da Alia no que EMPACOU (OPP-70).
  Le o state.json e devolve as Tasks PARADAS: status diferente de 'done' e criadas ha mais de
  -StaleDays dias. E a fila de cobranca do Squad Owner (motor ativo, squad-system.md) e o que o
  Mission Control marca como "paradas / em risco". Prato caindo tem que ter alguem olhando.

  Determinismo: -Now permite fixar a data de referencia (o smoke passa uma data fixa). Task sem
  campo 'created' nao entra (sem data nao da pra medir idade) e e reportada a parte.

  ESTADO DO CLIENT (OPP-77): a fila de cobranca e so do Client ATIVO. Task de Client pontual (ideia
  tocada uma vez) ou arquivado sai da lista de paradas e vira uma linha informativa no fim - a Task
  continua no ledger, visivel e rastreavel; o que muda e a COBRANCA. Client sem estado declarado =
  ativo (compatibilidade).

  Uso:  powershell -ExecutionPolicy Bypass -File scripts/stale-tasks.ps1 [-StateFile <p>] [-StaleDays 7] [-Now 2026-07-03]
  exit 0 sempre (e um relatorio; parada nao e erro de execucao, e sinal pra acao). Sem acentos, sem emojis.
#>
param(
  [string]$StateFile = "",
  [int]$StaleDays = 7,
  [string]$Now = ""
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "_studio.ps1")   # Get-ClientStates: o estado do Client (OPP-77)
if ([string]::IsNullOrWhiteSpace($StateFile)) { $StateFile = Join-Path $root "state.json" }
if (-not (Test-Path -LiteralPath $StateFile)) { Write-Host ("[ERRO] state.json nao encontrado: " + $StateFile); exit 1 }
$nowDate = if ([string]::IsNullOrWhiteSpace($Now)) { (Get-Date) } else { [datetime]::Parse($Now) }
$utf8 = New-Object System.Text.UTF8Encoding($false)

$st = [System.IO.File]::ReadAllText($StateFile, $utf8) | ConvertFrom-Json
$tasks = @(); if ($st.tasks) { $tasks = @($st.tasks) }
function Field($t, $name) { $v = $null; try { $v = $t.PSObject.Properties[$name].Value } catch {}; if ($null -eq $v) { return "" } else { return "$v" } }

$clientStates = Get-ClientStates $StateFile

$stale = @()
$noDate = @()
$foraDaCobranca = @()
foreach ($t in $tasks) {
  if ((Field $t 'status') -eq 'done') { continue }
  $created = Field $t 'created'
  if ($created -eq "") { $noDate += (Field $t 'id'); continue }
  $age = ($nowDate - [datetime]::Parse($created)).Days
  if ($age -gt $StaleDays) {
    $cst = Get-ClientStateOf $clientStates (Field $t 'client')
    if ($cst -ne 'ativo') {
      $foraDaCobranca += ((Field $t 'id') + " (" + (Field $t 'client') + ": " + $cst + ")")
      continue
    }
    $stale += [PSCustomObject]@{ id=(Field $t 'id'); title=(Field $t 'title'); client=(Field $t 'client'); project=(Field $t 'project'); age=$age }
  }
}

Write-Host ("=== Tarefas paradas (parado > " + $StaleDays + " dias, ref " + $nowDate.ToString("yyyy-MM-dd") + ") ===")
Write-Host ("PARADAS: " + $stale.Count)
foreach ($s in ($stale | Sort-Object -Property age -Descending)) {
  Write-Host ("- " + $s.id + " [" + $s.age + "d parada] " + $s.title + " (" + $s.client + " / " + $s.project + ")")
}
if ($noDate.Count -gt 0) { Write-Host ("SEM DATA (nao medivel): " + ($noDate -join ", ")) }
if ($foraDaCobranca.Count -gt 0) {
  Write-Host ("FORA DA COBRANCA (Client pontual/arquivado, informativo - a Task segue no ledger): " + ($foraDaCobranca -join ", "))
}
if ($stale.Count -eq 0) { Write-Host "Nenhum prato caindo. Roda girando." }
exit 0
