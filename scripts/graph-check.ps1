<#
  graph-check.ps1 - Grafo do segundo cerebro presente em TODO Client (OPP-68).
  Varre <studio>/clients/*/squad/knowledge/graphify-out/ e REPROVA (exit 1) qualquer squad sem grafo
  valido: exige GRAPH_REPORT.md + graph.json com >0 nos. Torna a geracao do grafo requisito
  verificavel por Client - nao mais "sob demanda, facil de esquecer" (nota honesta em engine/tools.md).

  A GERACAO em si roda pela skill graphify (precisa do agente); este script so CONFERE a presenca -
  e o mesmo padrao dos outros mecanismos frugais (custo zero de token, deterministico).

  Uso:  powershell -ExecutionPolicy Bypass -File scripts/graph-check.ps1 [-StudioDir <caminho>]
        default StudioDir: studio.example na raiz do produto.
  exit 0 se todo squad tem grafo; 1 se algum falta. Sem acentos, sem emojis.
#>
param(
  [string]$StudioDir = ""
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StudioDir)) { $StudioDir = Join-Path $root "studio.example" }
$utf8 = New-Object System.Text.UTF8Encoding($false)

$clientsDir = Join-Path $StudioDir "clients"
if (-not (Test-Path $clientsDir)) {
  Write-Host ("[ERRO] pasta de clientes nao encontrada: " + $clientsDir)
  exit 1
}

$missing = @()
$ok = @()
$clients = Get-ChildItem -Path $clientsDir -Directory -ErrorAction SilentlyContinue
foreach ($c in $clients) {
  $gout = Join-Path $c.FullName "squad\knowledge\graphify-out"
  $report = Join-Path $gout "GRAPH_REPORT.md"
  $graph  = Join-Path $gout "graph.json"
  $nodes = 0
  if (Test-Path $graph) {
    try { $nodes = ((([System.IO.File]::ReadAllText($graph, $utf8) | ConvertFrom-Json).nodes) | Measure-Object).Count } catch { $nodes = 0 }
  }
  if ((Test-Path $report) -and ($nodes -gt 0)) {
    $ok += ($c.Name + " (" + $nodes + " nos)")
  } else {
    $why = @()
    if (-not (Test-Path $report)) { $why += "sem GRAPH_REPORT.md" }
    if ($nodes -le 0) { $why += "graph.json vazio/ausente" }
    $missing += ($c.Name + ": " + ($why -join ", "))
  }
}

Write-Host ("=== graph-check: " + $clients.Count + " Client(s) ===")
foreach ($o in $ok) { Write-Host ("[OK]   " + $o) }
foreach ($m in $missing) { Write-Host ("[FALTA] " + $m) }

if ($missing.Count -gt 0) {
  Write-Host ("[FAIL] " + $missing.Count + " squad(s) sem grafo. Gere com a skill graphify antes de operar.")
  exit 1
}
Write-Host "[PASS] todo Client tem grafo do segundo cerebro."
exit 0
