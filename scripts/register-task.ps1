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
  Desde a 1.39.0, -Project e OBRIGATORIO (sem ele o script sai com exit 1): chamadas antigas sem
  -Project passam a falhar de proposito. O Mission Control (scripts/mission-control.ps1) le os campos.

  LIMITACAO ACEITA (1.39.0): a regra "revisao done exige -GateVerdict" so vale NO ATO do registro.
  Se a Task for registrada open e o status for atualizado pra done fora deste script (edicao direta
  do state.json), a regra nao dispara - o guarda dessa janela e o smoke/gate, nao este script.

  LIMITACAO ACEITA (M3, "o ledger para de mentir"): -Specialist perdeu o default "alia" e passou a
  ser validado contra o squad.yaml do Client NO ATO do registro. Cliente sem squad.yaml recebe so
  AVISO (nao trava Task nova). A unica excecao legitima a lei DELEGA (engine/orchestration.md) e
  ordem explicita do Operator: -OperatorOrder permite registrar "alia" como executora e grava
  operator_order:true na Task, tornando a excecao auditavel em vez de silenciosa. Como toda regra
  deste script, so vale NO ATO do registro - edicao direta do state.json continua fora do alcance,
  o guarda dessa janela e o smoke, nao este script.

  Adiciona uma entrada ao array "tasks" (preservando clients/ e o resto do estado intactos) e
  carimba "updated". Le e grava JSON UTF-8 sem BOM. Forca "tasks" a permanecer um ARRAY mesmo
  com um unico item (contorna o bug do ConvertTo-Json no PowerShell 5.1). -DryRun so mostra. exit 0.
#>
param(
  [Parameter(Mandatory=$true)][string]$Client,
  [Parameter(Mandatory=$true)][string]$Title,
  [string]$Project = "",
  [string]$Specialist = "",
  [string]$Artifact = "",
  [string]$BaseArtifact = "",
  [string]$SessionId = "",
  [string]$Status = "open",
  [string]$GateVerdict = "",
  [ValidateSet("pesquisa","construcao","revisao")][string]$Type = "construcao",
  [string]$StateFile = "",
  [switch]$OperatorOrder,
  [switch]$DryRun
)
# Contrato de task tipado (1.39.0, auditoria de fluxo): -Type declara a natureza da Task e liga
# UMA regra dura por tipo no ato do registro (nao so no smoke, tarde demais):
#   pesquisa   - dispensa base_artifact (leitura nasce do zero; mata o aviso falso)
#   construcao - padrao; pede base_artifact quando ha artifact (linhagem)
#   revisao    - fechada como done EXIGE -GateVerdict (revisar sem verdito nao fecha)
# Status default virou "open": registrar ANTES de executar e a LEI - "done" e excecao declarada.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StateFile)) { $StateFile = Join-Path $root "state.json" }
$utf8 = New-Object System.Text.UTF8Encoding($false)

# Ids do squad do Client, pra validar -Specialist NO ATO do registro (mesma tecnica de parse leve
# usada em squad-report.ps1: blocos "  - id:" de squad.yaml). Sem squad.yaml -> lista vazia (AVISO,
# nao bloqueia).
function Get-SquadMemberIds {
  param([Parameter(Mandatory=$true)][string]$SquadYamlPath)
  $ids = New-Object System.Collections.Generic.List[string]
  if (Test-Path -LiteralPath $SquadYamlPath) {
    $lines = [System.IO.File]::ReadAllText($SquadYamlPath) -split "`r?`n"
    foreach ($ln in $lines) {
      if ($ln -match '^\s*-\s+id\s*:\s*(\S+)') { $ids.Add($matches[1]) }
    }
  }
  return $ids
}
# studioRoot = a pasta que contem o -StateFile de verdade (nao mais via alia.config.json/
# Get-StudioRoot). clients/<id>/squad/squad.yaml sempre vive irmao do state.json em que a Task
# esta sendo gravada: studio/state.json + studio/clients/ na instalacao real, studio.example/
# state.json + studio.example/clients/ no demo. Derivar do -StateFile real (em vez de assumir
# "studio/" fixo por config) e o que deixa a validacao de -Specialist funcionar tanto rodando na
# oficina quanto dentro do pacote publico (onde nao existe studio/ nenhum, so studio.example/).
$studioRoot = Split-Path -Parent $StateFile
$squadYaml  = Join-Path $studioRoot ("clients\" + $Client + "\squad\squad.yaml")
$squadIds   = @(Get-SquadMemberIds $squadYaml)

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
  Write-Host "[ERRO] Task sem -Project: a hierarquia e Cliente > Projeto > Tarefa. A LEI da rastreabilidade exige a linhagem completa no registro."
  exit 1
}
if ($Type -ne "pesquisa" -and [string]::IsNullOrWhiteSpace($BaseArtifact) -and -not [string]::IsNullOrWhiteSpace($Artifact)) {
  Write-Host "[AVISO] Task com artifact mas sem -BaseArtifact: registre de ONDE partiu (arquivo/versao-base). Foi a falta disso que gerou o incidente da LP (02/jul)."
}
if ($Type -eq "revisao" -and $Status -eq "done" -and [string]::IsNullOrWhiteSpace($GateVerdict)) {
  Write-Host "[ERRO] Task de revisao fechada como done sem -GateVerdict: revisao sem verdito nao fecha."
  exit 1
}

# LEI DELEGA (engine/orchestration.md): quem executou tem que estar declarado - sem default pra
# "alia". Sem -Specialist e o caminho mais facil e o que viola a lei; por isso vira erro, nao mais
# um valor silencioso. Valida NO ATO do registro (nunca retroativo - mesmo espirito do -Project
# obrigatorio da 1.39.0).
if ([string]::IsNullOrWhiteSpace($Specialist)) {
  Write-Host "[ERRO] Task sem -Specialist: quem executou tem que estar declarado, sempre (lei DELEGA, engine/orchestration.md - alia coordena, nao executa)."
  if ($squadIds.Count -gt 0) {
    Write-Host ("       especialistas do squad de '" + $Client + "': " + ($squadIds -join ", "))
  } else {
    Write-Host ("       squad.yaml nao encontrado para '" + $Client + "' (" + $squadYaml + "): informe mesmo assim o id de quem executou.")
  }
  exit 1
}
if ($Specialist -eq "alia") {
  if (-not $OperatorOrder) {
    Write-Host "[ERRO] -Specialist alia sem -OperatorOrder: a unica excecao legitima a lei DELEGA e ordem explicita do Operator (engine/orchestration.md). Se foi o Operator quem mandou a coordenadora executar direto, repita com -OperatorOrder pra tornar a excecao auditavel."
    exit 1
  }
} elseif ($squadIds.Count -gt 0) {
  if (-not ($squadIds -contains $Specialist)) {
    Write-Host ("[ERRO] -Specialist '" + $Specialist + "' nao consta no squad de '" + $Client + "'. Ids validos: " + ($squadIds -join ", "))
    exit 1
  }
} else {
  Write-Host ("[AVISO] squad.yaml nao encontrado para '" + $Client + "' (" + $squadYaml + "): nao deu pra validar -Specialist '" + $Specialist + "' contra o time. Prosseguindo (cliente sem squad nao trava Task nova).")
}

$task = [PSCustomObject][ordered]@{
  id             = $id
  client         = $Client
  project        = $Project
  title          = $Title
  specialist     = $Specialist
  type           = $Type
  status         = $Status
  artifact       = $Artifact
  base_artifact  = $BaseArtifact
  session        = $SessionId
  gate_verdict   = $GateVerdict
  operator_order = $OperatorOrder.IsPresent
  created        = $now
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
