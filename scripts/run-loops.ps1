<#
  run-loops.ps1 - Runner sob demanda dos loops agendados de um Client.
  A Alia chama este runner via a skill loop-designer quando os loops do dia/semana estao "devidos"
  e o operador aceita rodar (opt-in). NAO e para o operador rodar na mao: e o motor mecanico que a
  skill aciona. Colapsa os scans num unico passo (regra PTC: pipeline deterministico = 1 invocacao)
  e devolve um resumo consolidado, em vez de N execucoes soltas no agendador do SO.

  Cada scan individual continua gravando seu relatorio detalhado em knowledge/loop-reports/.
  Este runner agrega o veredito de cada um. Frugal: so le, nao corrige. RSI propoe, Gate aprova.
  Escrita .NET UTF-8 sem BOM. Sem acentos, sem emojis.

  Uso (acionado pela skill, nao manual):
    run-loops.ps1 -Client {id} [-Due daily|weekly|all] [-DryRun]
#>
param(
  [Parameter(Mandatory = $true)][string]$Client,
  [ValidateSet("daily", "weekly", "all")][string]$Due = "all",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$today = (Get-Date).ToString("yyyy-MM-dd")
. (Join-Path $PSScriptRoot "_studio.ps1")
$studioRoot = Get-StudioRoot $root

# Mapa cadencia -> scans mecanicos (deep-research fica fora: e agente-driven, RSI Researcher via MCP).
$daily  = @("health-check", "ddd-drift")
$weekly = @("debt-scan", "evolution-scan", "squad-report", "memory-curator")

# Teto de gasto duro (OPP-58): antes de CADA volta, budget-check.ps1 compara o gasto realizado
# (state.json costs[]) com o token_cap declarado no loops.yaml da instancia. Volta que ja nasce
# estourada NAO roda (PULADO, com o porque no resumo). Sem token_cap declarado = fail-closed
# (OPP-57 obriga o campo). O teto nunca e afrouxado aqui - so por edicao de configuracao.
$loopIdMap = @{ "ddd-drift" = "ddd-drift-scan" }   # basename do script -> id do loop no loops.yaml
$loopsYamlPath = Join-Path $studioRoot ("clients\" + $Client + "\loops.yaml")
$loopsYamlTxt = if (Test-Path -LiteralPath $loopsYamlPath) { [System.IO.File]::ReadAllText($loopsYamlPath) } else { "" }
function Get-TokenCap([string]$loopId) {
  # bloco do loop: de "- id: <loopId>" ate o proximo "- id:" (ou fim); extrai token_cap inline.
  $m = [regex]::Match($loopsYamlTxt, '(?ms)^\s*-\s*id:\s*' + [regex]::Escape($loopId) + '\s*$(.*?)(?=^\s*-\s*id:|\z)')
  if (-not $m.Success) { return $null }
  $cap = [regex]::Match($m.Groups[1].Value, "token_cap:\s*\{\s*per_round:\s*(\d+)\s*,\s*daily:\s*(\d+)\s*\}")
  if (-not $cap.Success) { return $null }
  return @{ per_round = [int]$cap.Groups[1].Value; daily = [int]$cap.Groups[2].Value }
}
switch ($Due) {
  "daily"  { $loops = $daily }
  "weekly" { $loops = $weekly }
  default  { $loops = $daily + $weekly }
}

Write-Host "=== Run Loops (sob demanda, via skill) ==="
Write-Host ("client: " + $Client + " | devidos: " + $Due + " | data: " + $today)
Write-Host ("modo: " + $(if ($DryRun) { "DRY-RUN" } else { "RUN" }))
Write-Host ""

$results = @()
foreach ($id in $loops) {
  $scriptPath = Join-Path $PSScriptRoot ($id + ".ps1")
  if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-Host ("[ERRO] mecanismo ausente: " + $id + ".ps1")
    $results += [pscustomobject]@{ loop = $id; status = "ERRO"; nota = "script ausente" }
    continue
  }
  # freio de orcamento (OPP-58): estourou ou sem teto declarado -> PULA, nao roda.
  $loopId = if ($loopIdMap.ContainsKey($id)) { $loopIdMap[$id] } else { $id }
  $cap = Get-TokenCap $loopId
  if ($null -eq $cap) {
    Write-Host ("[PULADO] " + $id + ": sem token_cap declarado no loops.yaml (fail-closed, OPP-57/58)")
    $results += [pscustomobject]@{ loop = $id; status = "PULADO"; nota = "sem token_cap declarado" }
    continue
  }
  & (Join-Path $PSScriptRoot "budget-check.ps1") -Id $loopId -CapRound $cap.per_round -CapDaily $cap.daily | Out-Host
  if ($LASTEXITCODE -ne 0) {
    Write-Host ("[PULADO] " + $id + ": orcamento estourado (token_cap) - pacote de prova acima; escalar ao operador")
    $results += [pscustomobject]@{ loop = $id; status = "PULADO"; nota = "orcamento estourado (token_cap)" }
    continue
  }
  Write-Host ("-- " + $id + " --")
  try {
    if ($DryRun) {
      & $scriptPath -Client $Client -DryRun | Out-Host
    } else {
      & $scriptPath -Client $Client | Out-Host
    }
    $ok = ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
    $results += [pscustomobject]@{ loop = $id; status = $(if ($ok) { "OK" } else { "FALHA" }); nota = "" }
  } catch {
    Write-Host ("[ERRO] " + $id + ": " + $_.Exception.Message)
    $results += [pscustomobject]@{ loop = $id; status = "ERRO"; nota = $_.Exception.Message }
  }
  Write-Host ""
}

# Resumo consolidado (a visao unica que a skill leva ao operador, em linguagem dele).
Write-Host "=== Resumo dos loops ==="
foreach ($r in $results) {
  Write-Host (("{0,-16}" -f $r.loop) + " " + $r.status + $(if ($r.nota) { " - " + $r.nota } else { "" }))
}
$falhas = @($results | Where-Object { $_.status -ne "OK" })
Write-Host ""
Write-Host (("loops rodados: " + $results.Count + " | com problema: " + $falhas.Count))
if ($falhas.Count -gt 0) { exit 1 } else { exit 0 }
