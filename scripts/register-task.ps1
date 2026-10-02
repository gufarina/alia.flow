<#
  register-task.ps1 - WRAPPER FINO da CLI `alia`. Nao tem regra propria.

  Antes: 638 linhas, o escritor FROUXO do state.json (projeto em texto livre, veredito so em Task de revisao,
  specialist sem prova). Agora cada chamada vira UMA chamada de `v2/bin/alia.py`, que e quem recusa:
    sem -Id  -> `alia task open` (projeto tem que estar cadastrado: `alia project add`); se -Status done|review,
                em seguida `alia task close` (veredito + artifact que existe + evidencia no ledger).
    com -Id  -> `alia task close --id` (so fecha Task existente; nunca cria).
  O exit code e a saida JSON sao os da CLI. As Tasks ja registradas nao sao tocadas por esta mudanca.
  Parametros que a CLI nao conhece mais (-Executor -Plan -BaseArtifact -ArtifactNote -Tokens -ToolUses -Budget)
  sao aceitos e IGNORADOS com aviso (custo vem do ledger no close). -Specialist tambem: o agente e registrado por
  `alia task dispatch` quando e acionado. -OperatorOrder vira coordenacao:true (unico jeito de a Alia executar).
#>
param(
  [Parameter(Mandatory=$true)][string]$Client,
  [string]$Title = "",
  [string]$Id = "",
  [string]$Project = "",
  [string]$Specialist = "",
  [string]$Executor = "",
  [string]$Artifact = "",
  [string]$ArtifactNote = "",
  [string]$BaseArtifact = "",
  [string]$Plan = "",
  [string]$SessionId = "",
  [string]$Status = "open",
  [string]$GateVerdict = "",
  [ValidateSet("pesquisa","construcao","revisao","correcao")][string]$Type = "construcao",
  [string]$RootCause = "",
  [string]$StateFile = "",
  [switch]$OperatorOrder,
  [int]$Tokens = -1,
  [int]$ToolUses = -1,
  [int]$Budget = -1,
  [switch]$DryRun,
  [string]$Paths = "",
  [string]$Consumidor = "",
  [string]$Destino = "",
  [string]$ExemploFalha = "",
  [ValidateSet("superada","abandonada")][string]$Motivo = "superada"
)
$ErrorActionPreference = "Stop"
$alia = Join-Path (Split-Path -Parent $PSScriptRoot) "v2\bin\alia.py"
$py = if (Get-Command python -ErrorAction SilentlyContinue) { "python" } else { "py" }
$ignorados = @(); foreach ($k in "Executor","Plan","BaseArtifact","ArtifactNote","Specialist") { if ((Get-Variable $k).Value) { $ignorados += "-$k" } }
if ($Tokens -ge 0) { $ignorados += "-Tokens" }; if ($ToolUses -ge 0) { $ignorados += "-ToolUses" }; if ($Budget -ge 0) { $ignorados += "-Budget" }
if ($ignorados) { Write-Host ("[AVISO] ignorado (a CLI alia nao tem): " + ($ignorados -join " ")) }

function Invoke-Alia([string[]]$CliArgs) {
  $global = @(); if ($StateFile) { $global = @("--state", $StateFile) }
  $out = & $py $alia @global @CliArgs 2>&1 | Out-String
  Write-Host $out.Trim()
  return @{ code = $LASTEXITCODE; json = ($out | ConvertFrom-Json -ErrorAction SilentlyContinue) }
}

$fecha = $Status -in @("done","review")
$veredito = ""
if ($fecha) {
  # o veredito e obrigatorio para fechar, em qualquer tipo de Task (TASK-845 virou regra do nucleo)
  $primeira = ($GateVerdict.Trim() -split "\s+")[0].ToUpperInvariant()
  if ($primeira -notin @("PASS","FAIL","CONCERN")) {
    Write-Host "[ERRO] -Status $Status exige -GateVerdict PASS|FAIL|CONCERN (recebido: '$GateVerdict')."
    exit 1
  }
  $veredito = $primeira
}
if ($DryRun) { Write-Host "[DRYRUN] alia task $(if ($Id) { 'close' } else { 'open' }) client=$Client project=$Project status=$Status"; exit 0 }

if ($Status -eq "retired") {
  # 2.1.6: retirar uma Task aberta (superada/abandonada). Sem -Id nao ha o que retirar: falha ALTO, nunca abre Task nova.
  if (-not $Id) { Write-Host "[ERRO] -Status retired exige -Id da Task a retirar."; exit 1 }
  $r = Invoke-Alia @("task","retire","--id",$Id,"--motivo",$Motivo)
  if ($r.code -eq 0 -and $r.json -and $r.json.ok -ne $false) { exit 0 }
  exit $(if ($r.code -ne 0) { $r.code } else { 1 })
}
if ($Status -notin @("open","done","review")) { Write-Host "[ERRO] -Status $Status nao e suportado pela CLI alia (open, done, review, retired)."; exit 1 }
$alvo = $Id
if (-not $alvo) {
  $brief = [ordered]@{ client = $Client; project = $Project; objetivo = $Title; paths = $Paths; consumidor = $Consumidor
                       destino = $Destino; exemplo_falha = $ExemploFalha; type = $Type }
  if ($OperatorOrder) { $brief.coordenacao = $true; $brief.ordem_operator = $true }
  if (-not $SessionId) { Write-Host "[AVISO] sem -SessionId: a Task nao vira a Task corrente de nenhuma sessao (so _last)" }
  $arqBrief = [System.IO.Path]::GetTempFileName()
  [System.IO.File]::WriteAllText($arqBrief, ($brief | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
  $args1 = @("task","open","--brief-file",$arqBrief)
  if ($SessionId) { $args1 += @("--session", $SessionId) }
  $r = Invoke-Alia $args1
  Remove-Item -LiteralPath $arqBrief -ErrorAction SilentlyContinue
  if ($r.code -ne 0) { exit $r.code }
  if (-not $r.json) { Write-Host "[ERRO] a CLI nao devolveu JSON"; exit 1 }
  $alvo = if ($r.json.task) { $r.json.task.id } elseif ($r.json.tasks) { $r.json.tasks[0].id } else { Write-Host "[ERRO] a CLI nao devolveu a Task"; exit 1 }
}
if ($fecha) {
  $args2 = @("task","close","--id",$alvo,"--artifact",$Artifact,"--veredito",$veredito)
  if ($RootCause) { $args2 += @("--root-cause", $RootCause) }
  $r = Invoke-Alia $args2
  exit $r.code
}
exit 0
