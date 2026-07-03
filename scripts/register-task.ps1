<#
  register-task.ps1 - Registra uma Tarefa no state.json (Cliente -> Projeto -> Tarefa).
  Materializa o passo REGISTRA do protocolo de orquestracao e da o substrato pro KPI.
  Antes: tasks: [] (o trabalho evaporava a cada sessao). Reusa o schema de studio.example/state.json.

  LEI DA RASTREABILIDADE (02/jul, incidente da LP com base errada): toda demanda vira Task de um
  Projeto de um Cliente ANTES de executar, e a Task carrega a LINHAGEM do trabalho:
   - project       : o Projeto do Cliente a que a Task pertence (a hierarquia inteira, sempre).
   - artifact      : o que a Task PRODUZIU (o entregavel).
   - base_artifact : de ONDE se partiu (o arquivo/versao-base editado ou consultado). E o campo
                     que teria evitado reconstruir a LP sobre um arquivo obsoleto.
   - session       : o id da sessao que executou (liga a Task ao transcript - continuidade).
  Sem -Project o script AVISA (nao bloqueia, para nao quebrar chamadas antigas), mas a regra da
  casa e preencher. O Mission Control (scripts/mission-control.ps1) le estes campos.

  Adiciona uma entrada ao array "tasks" (preservando clients/ e o resto do estado intactos) e
  carimba "updated". Le e grava JSON UTF-8 sem BOM. Forca "tasks" a permanecer um ARRAY mesmo
  com um unico item (contorna o bug do ConvertTo-Json no PowerShell 5.1). -DryRun so mostra. exit 0.
#>
param(
  [Parameter(Mandatory=$true)][string]$Client,
  [Parameter(Mandatory=$true)][string]$Title,
  [string]$Project = "",
  [string]$Specialist = "alia",
  [string]$Artifact = "",
  [string]$BaseArtifact = "",
  [string]$SessionId = "",
  [string]$Status = "done",
  [string]$GateVerdict = "",
  [string]$StateFile = "",
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StateFile)) { $StateFile = Join-Path $root "state.json" }
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath $StateFile)) {
  Write-Host ("[ERRO] state.json nao encontrado: " + $StateFile)
  exit 1
}

$json = [System.IO.File]::ReadAllText($StateFile) | ConvertFrom-Json
if ($null -eq ($json.PSObject.Properties.Name | Where-Object { $_ -eq 'tasks' })) {
  $json | Add-Member -NotePropertyName tasks -NotePropertyValue @() -Force
}

$existing = @($json.tasks)
$id  = "TASK-{0:D3}" -f ($existing.Count + 1)
$now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

if ([string]::IsNullOrWhiteSpace($Project)) {
  Write-Host "[AVISO] Task sem -Project: a hierarquia e Cliente > Projeto > Tarefa. Preencha - rastreabilidade e a arquitetura do produto."
}
if ([string]::IsNullOrWhiteSpace($BaseArtifact) -and -not [string]::IsNullOrWhiteSpace($Artifact)) {
  Write-Host "[AVISO] Task com artifact mas sem -BaseArtifact: registre de ONDE partiu (arquivo/versao-base). Foi a falta disso que gerou o incidente da LP (02/jul)."
}

$task = [PSCustomObject][ordered]@{
  id            = $id
  client        = $Client
  project       = $Project
  title         = $Title
  specialist    = $Specialist
  status        = $Status
  artifact      = $Artifact
  base_artifact = $BaseArtifact
  session       = $SessionId
  gate_verdict  = $GateVerdict
  created       = $now
}

Write-Host "=== Register Task ==="
Write-Host ("state: " + $StateFile)
Write-Host ("nova:  " + $id + " | " + $Client + " | " + $Title)

if ($DryRun) {
  Write-Host "[DRY-RUN] nao gravou."
  exit 0
}

$json.tasks = @($existing + $task)
if ($json.PSObject.Properties.Name -contains 'updated') {
  $json.updated = (Get-Date).ToString("yyyy-MM-dd")
}

# ConvertTo-Json no PS 5.1 serializa array de 1 item sem colchetes. Forcamos o array
# re-serializando "tasks" a parte e garantindo o [ ] quando ha exatamente 1 item.
$out = $json | ConvertTo-Json -Depth 32
[System.IO.File]::WriteAllText($StateFile, $out, $utf8)

# Validacao pos-escrita: re-parse e confere que tasks e um array com o id novo.
$check = [System.IO.File]::ReadAllText($StateFile) | ConvertFrom-Json
$matchCount = @(@($check.tasks) | Where-Object { $_.id -eq $id }).Count
$tasksOk = (@($check.tasks).Count -ge 1) -and ($matchCount -eq 1)
if (-not $tasksOk) {
  Write-Host "[ERRO] validacao pos-escrita falhou: tasks nao ficou consistente. Confira o state.json."
  exit 1
}
Write-Host ("[OK] tarefa registrada: " + $id + " | total de tarefas: " + @($check.tasks).Count)
exit 0
