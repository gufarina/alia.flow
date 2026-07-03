<#
  budget-check.ps1 - Contador frugal de orcamento por loop/Task (OPP-58, sem LLM).
  Le o custo realizado em state.json (costs[]: { id, tokens, ts }) e compara com o token_cap
  declarado no loops.yaml da instancia (per_round e daily). Estourou -> exit 1 + PACOTE DE PROVA
  (o que rodou, quanto gastou, onde estourou, recomendacao). Dentro do teto -> exit 0.

  Politica de parada (fronteira dura): o teto NUNCA e afrouxado em runtime. Mudar token_cap e
  edicao de configuracao da instancia (operador ou OPP), nao decisao do agente. Volta que ja
  nasce estourada NAO roda (run-loops.ps1 chama este check no inicio de cada volta e PULA).
  rsi.yaml (trigger over-budget-path) aponta este contador como fonte.

  Semantica (deterministica):
    - gasto diario = soma de costs[].tokens do Id na data (-Date, default hoje);
    - ultima volta = tokens da entrada mais recente do dia;
    - estouro se: gasto diario >= CapDaily (nao ha orcamento para nova volta)
                  OU ultima volta > CapRound (a volta anterior furou o teto por rodada).
  state.json sem costs[] = gasto 0 (o contador conta o realizado; predicao e outra conversa).

  Uso:
    budget-check.ps1 -Id <loop-ou-task> -CapRound <n> -CapDaily <n> [-StatePath <state.json>] [-Date yyyy-MM-dd]
  Escrita .NET UTF-8 sem BOM. Sem acentos, sem emojis.
#>
param(
  [Parameter(Mandatory = $true)][string]$Id,
  [Parameter(Mandatory = $true)][int]$CapRound,
  [Parameter(Mandatory = $true)][int]$CapDaily,
  [string]$StatePath = "",
  [string]$Date = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "_studio.ps1")
if ($StatePath -eq "") { $StatePath = Join-Path (Get-StudioRoot $root) "state.json" }
if ($Date -eq "") { $Date = (Get-Date).ToString("yyyy-MM-dd") }

$entries = @()
if (Test-Path -LiteralPath $StatePath) {
  $StatePath = (Resolve-Path -LiteralPath $StatePath).Path   # .NET le pelo cwd do processo; ancora o caminho
  try {
    $state = [System.IO.File]::ReadAllText($StatePath) | ConvertFrom-Json
    if ($null -ne $state.costs) {
      $entries = @($state.costs | Where-Object { $_.id -eq $Id -and "$($_.ts)".StartsWith($Date) })
    }
  } catch {
    Write-Host ("[ERRO] state.json ilegivel: " + $_.Exception.Message)
    exit 2
  }
}

$daySpend = 0
foreach ($e in $entries) { $daySpend += [int]$e.tokens }
$lastRound = 0
if ($entries.Count -gt 0) {
  $last = $entries | Sort-Object { "$($_.ts)" } | Select-Object -Last 1
  $lastRound = [int]$last.tokens
}

$breach = ""
if ($daySpend -ge $CapDaily) { $breach = "daily" }
elseif ($lastRound -gt $CapRound) { $breach = "per_round" }

if ($breach -eq "") {
  Write-Host ("[PASS] orcamento ok: " + $Id + " | dia=" + $daySpend + "/" + $CapDaily + " tokens | ultima volta=" + $lastRound + "/" + $CapRound)
  exit 0
}

Write-Host "=== PACOTE DE PROVA (orcamento estourado) ==="
Write-Host ("id: " + $Id)
Write-Host ("data: " + $Date + " | fonte: " + $StatePath)
Write-Host ("o que rodou: " + $entries.Count + " volta(s) no dia")
foreach ($e in ($entries | Sort-Object { "$($_.ts)" })) {
  Write-Host ("  - ts=" + $e.ts + " tokens=" + $e.tokens)
}
Write-Host ("quanto gastou: dia=" + $daySpend + " (teto " + $CapDaily + ") | ultima volta=" + $lastRound + " (teto " + $CapRound + ")")
Write-Host ("onde estourou: " + $breach)
Write-Host "recomendacao: NAO rodar nova volta; escalar ao operador com este pacote. O teto nao se afrouxa em runtime - ajuste de token_cap so por edicao de configuracao (operador ou OPP)."
exit 1
