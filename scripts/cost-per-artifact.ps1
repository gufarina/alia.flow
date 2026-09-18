<#
  cost-per-artifact.ps1 - PECA nova do RSI: calcula avg_tokens_per_artifact (rsi.yaml -> metric),
  ate hoje NUNCA computada em lugar nenhum (medido na auditoria TASK-284).

  HONESTIDADE OBRIGATORIA (mandato do CEO, TASK-285): o numero aqui e CUSTO-PROXY POR MB DE
  TRANSCRICAO (dayTotalMB de scripts/cost-sensor.ps1), NUNCA token faturado. E o mesmo proxy que
  cost-sensor.ps1 ja usa (MB de transcript e proxy direto de token porque cada volta reenvia o
  historico inteiro). NUNCA apresentar como medicao de fatura - so como tendencia relativa
  (sobe/desce) do custo-proxy por entrega ao longo do tempo, que e o que rsi.yaml -> metric pede
  (direction: down).

  Cruza studio/cost-log.jsonl (1 linha por dia, escrita por cost-sensor.ps1) com state.json
  (Tasks com campo 'artifact' preenchido e 'created' naquele dia = proxy de Artifact entregue -
  nao ha campo 'closed_at' no schema hoje, ver TASK-285). Sob demanda, sem agendador (LEI
  zero-agendamento) - roda quando alguem pede, nunca sozinho.

  Uso: cost-per-artifact.ps1 [-Date yyyy-MM-dd] [-Root <path>] UTF-8 sem BOM.
#>
param(
  [string]$Date = "",
  [string]$Root = ""
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$costLogPath = Join-Path $Root "studio/cost-log.jsonl"
$statePath   = Join-Path $Root "state.json"

Write-Host "=== cost-per-artifact (custo-proxy por entrega) ==="
Write-Host "AVISO: numero abaixo e MB de transcricao por Artifact (proxy), NUNCA token faturado."
Write-Host ""

if (-not (Test-Path -LiteralPath $costLogPath)) {
  Write-Host "[SEM DADO] studio/cost-log.jsonl nao existe ainda - cost-sensor.ps1 nunca rodou nesta instancia."
  exit 0
}
$lines = @(Get-Content -LiteralPath $costLogPath -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne "" })
if ($lines.Count -eq 0) {
  Write-Host "[SEM DADO] studio/cost-log.jsonl existe mas esta vazio."
  exit 0
}
$entries = @($lines | ForEach-Object { $_ | ConvertFrom-Json })

if ([string]::IsNullOrWhiteSpace($Date)) {
  $entry = ($entries | Sort-Object date -Descending | Select-Object -First 1)
} else {
  $entry = ($entries | Where-Object { $_.date -eq $Date } | Select-Object -First 1)
}
if (-not $entry) {
  Write-Host ("[SEM DADO] nenhum registro de custo para a data pedida" + $(if ($Date) { " (" + $Date + ")" } else { "" }) + ".")
  exit 0
}
$dia = $entry.date
Write-Host ("Data:              " + $dia)
Write-Host ("Sessoes no dia:    " + $entry.sessionCount)
Write-Host ("MB de transcricao: " + $entry.dayTotalMB + " (custo-proxy do dia inteiro)")
Write-Host ("Subagentes no dia: " + $entry.dayTotalSubagents)
Write-Host ("Estouro no dia:    " + $entry.dailyEstouro)
Write-Host ""

$artifactCount = 0
if (Test-Path -LiteralPath $statePath) {
  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $tasksDoDia = @($state.tasks | Where-Object { $_.created -like ($dia + "*") -and $_.artifact -and $_.artifact.Trim() -ne "" })
  $artifactCount = $tasksDoDia.Count
  Write-Host ("Tasks criadas no dia com campo 'artifact' preenchido: " + $artifactCount + " (proxy de Artifact entregue - state.json nao tem 'closed_at', ver manifest sq-residual)")
  if ($artifactCount -gt 0) { Write-Host ("  - " + (($tasksDoDia | Select-Object -ExpandProperty id) -join ", ")) }
} else {
  Write-Host "[SEM DADO] state.json nao encontrado - nao da pra cruzar com Artifacts."
}
Write-Host ""

if ($artifactCount -gt 0) {
  $proxy = [math]::Round(([double]$entry.dayTotalMB / $artifactCount), 2)
  Write-Host ("avg_MB_transcricao_por_artifact (proxy de avg_tokens_per_artifact): " + $proxy + " MB/artifact")
  Write-Host ""
  Write-Host "LIMITACAO (declarada, nao omitir): amostra de 1 dia so, denominador conta Tasks com"
  Write-Host "'artifact' preenchido no dia (nao 'status=done' - quase nenhuma Task fecha done no"
  Write-Host "mesmo dia que abre neste ledger). NAO e faturamento, e NAO e tendencia ainda - e o"
  Write-Host "PRIMEIRO ponto de uma serie que so vira metrica de verdade (rsi.yaml: direction down,"
  Write-Host "janela 30d) depois de varios dias acumulados em studio/cost-log.jsonl."
} else {
  Write-Host "[SEM RAZAO] nenhuma Task com artifact preenchido nesse dia ainda - nao da pra dividir."
  Write-Host ("Numero cru disponivel: " + $entry.dayTotalMB + " MB de transcricao / " + $entry.sessionCount + " sessoes.")
}
exit 0
