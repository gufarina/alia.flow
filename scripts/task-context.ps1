<#
  task-context.ps1 - Continuidade: mostra o historico de Tasks de um Cliente (ou Cliente+Projeto)
  ANTES de comecar um trabalho novo. E o mecanismo que materializa a LEI de continuidade
  (engine/orchestration.md): "ao receber trabalho sobre um assunto, LER primeiro as Tasks daquele
  Client/Project - o proximo passo parte de onde o anterior chegou, nunca do palpite".

  Sem isto, ler o historico era um grep manual no state.json (caro e faceis de esquecer). Aqui e
  uma invocacao barata que devolve so a LINHAGEM que importa: o que cada Task entregou, DE ONDE
  partiu (base_artifact) e qual sessao executou - a "ultima revisao" pronta pra Alia citar.
  Alinhado ao Frugality Check passo 2 (grafo/indice antes de varredura cega) e a leitura seletiva.

  Uso:  powershell -ExecutionPolicy Bypass -File scripts/task-context.ps1 -Client <id> [-Project <p>]
        [-StateFile <caminho>]  (default: state.json na raiz da instancia)
  Le JSON UTF-8. Sem acentos, sem emojis. exit 0 (mesmo sem Tasks: continuidade vazia e informacao).
#>
param(
  [Parameter(Mandatory=$true)][string]$Client,
  [string]$Project = "",
  [string]$StateFile = ""
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StateFile)) { $StateFile = Join-Path $root "state.json" }
if (-not (Test-Path -LiteralPath $StateFile)) {
  Write-Host ("[ERRO] state.json nao encontrado: " + $StateFile)
  exit 1
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$st = [System.IO.File]::ReadAllText($StateFile, $utf8) | ConvertFrom-Json
$tasks = @(); if ($st.tasks) { $tasks = @($st.tasks) }

function Field($t, $name) {
  $v = $null; try { $v = $t.PSObject.Properties[$name].Value } catch { }
  if ($null -eq $v) { return "" } else { return "$v" }
}

$hits = @($tasks | Where-Object { (Field $_ 'client') -eq $Client })
if ($Project -ne "") { $hits = @($hits | Where-Object { (Field $_ 'project') -eq $Project }) }

$scope = "cliente '" + $Client + "'" + $(if ($Project -ne "") { " / projeto '" + $Project + "'" } else { "" })
Write-Host ("=== Continuidade: " + $scope + " ===")

if ($hits.Count -eq 0) {
  Write-Host "Nenhuma Task anterior. Ponto de partida limpo - registre a primeira e siga."
  exit 0
}

Write-Host ($hits.Count.ToString() + " Task(s) anterior(es). Parta da ultima, nao do palpite:")
Write-Host ""
foreach ($t in ($hits | Sort-Object { Field $_ 'id' })) {
  Write-Host ("- " + (Field $t 'id') + " [" + (Field $t 'status') + "] " + (Field $t 'title'))
  Write-Host ("    projeto:  " + $(if ((Field $t 'project') -eq '') { "(sem projeto - FURO de rastreio)" } else { Field $t 'project' }))
  Write-Host ("    entregou: " + $(if ((Field $t 'artifact') -eq '') { "(nao registrado)" } else { Field $t 'artifact' }))
  Write-Host ("    partiu de:" + " " + $(if ((Field $t 'base_artifact') -eq '') { "(nao registrado - FURO de rastreio)" } else { Field $t 'base_artifact' }))
  Write-Host ("    gate:     " + $(if ((Field $t 'gate_verdict') -eq '') { "(sem veredito)" } else { Field $t 'gate_verdict' }) + " | sessao: " + $(if ((Field $t 'session') -eq '') { "(nao registrada)" } else { Field $t 'session' }))
}

# A ultima Task e a base natural do proximo passo (a "ultima revisao" que a Alia cita).
$last = ($hits | Sort-Object { Field $_ 'id' })[-1]
Write-Host ""
Write-Host ("ULTIMA REVISAO: " + (Field $last 'id') + " -> entregou '" + (Field $last 'artifact') + "'. O proximo passo parte DAQUI.")
exit 0
