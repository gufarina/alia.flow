<#
  task-context.ps1 - Continuidade: mostra o historico de Tasks de um Cliente (ou Cliente+Projeto)
  ANTES de comecar um trabalho novo. E o mecanismo que materializa a LEI de continuidade
  (engine/orchestration.md): "ao receber trabalho sobre um assunto, LER primeiro as Tasks daquele
  Client/Project - o proximo passo parte de onde o anterior chegou, nunca do palpite".

  Sem isto, ler o historico era um grep manual no state.json (caro e faceis de esquecer). Aqui e
  uma invocacao barata que devolve so a LINHAGEM que importa: o que cada Task entregou, DE ONDE
  partiu (base_artifact) e qual sessao executou - a "ultima revisao" pronta pra Alia citar.
  Alinhado ao Frugality Check passo 2 (grafo/indice antes de varredura cega) e a leitura seletiva.

  PECA 5 do motor de RSI (engine/rsi/rsi.md) - reflexao por TIPO de tarefa (padrao Reflexion,
  minimo viavel): -TaskType <tipo> devolve tambem as notas de memory/*.md (canonico, so o
  nivel raiz - nunca _proposals/) cujo frontmatter declara `aplica_a: <tipo>` que CASA com o
  tipo pedido (match simples por campo, sem banco, sem embedding). Quando uma Task de um tipo
  comeca (landing, auditoria, release, delegacao...), as licoes daquele tipo chegam juntas -
  sem isso, a licao fica enterrada na memoria e so aparece se alguem lembrar de procurar.

 ENXUTO POR PADRAO (M4, orcamento de contexto): so as -Last (default 5) Tasks mais recentes do
 escopo entram no historico, 3 linhas cada (id+status+titulo / entregou+partiu de / gate+sessao).
 -Full volta ao comportamento antigo (todas as Tasks, 4 linhas cada) - use so quando a
 investigacao exigir o historico inteiro.

  Uso:  powershell -ExecutionPolicy Bypass -File scripts/task-context.ps1 -Client <id> [-Project <p>]
        [-TaskType <tipo>] [-StateFile <caminho>] [-MemoryDir <caminho>]
        (default StateFile: state.json na raiz da instancia; default MemoryDir: memory/ na raiz)
 Le JSON UTF-8. exit 0 (mesmo sem Tasks: continuidade vazia e informacao).
#>
param(
  [Parameter(Mandatory=$true)][string]$Client,
  [string]$Project = "",
  [string]$TaskType = "",
  [string]$StateFile = "",
 [string]$MemoryDir = "",
 [int]$Last = 5,
 [switch]$Full
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StateFile)) { $StateFile = Join-Path $root "state.json" }
if ([string]::IsNullOrWhiteSpace($MemoryDir)) { $MemoryDir = Join-Path $root "memory" }
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
} else {
 $sorted = @($hits | Sort-Object { Field $_ 'id' })
 $shown = if ($Full) { $sorted } else { $sorted | Select-Object -Last $Last }
 $omitted = $sorted.Count - $shown.Count
 Write-Host ($hits.Count.ToString() + " Task(s) anterior(es)" + $(if ($omitted -gt 0) { " (mostrando as ultimas " + $Last + "; " + $omitted + " mais antiga(s) omitida(s) - use -Full pra ver todas)" } else { "" }) + ". Parta da ultima, nao do palpite:")
  Write-Host ""
 foreach ($t in $shown) {
    Write-Host ("- " + (Field $t 'id') + " [" + (Field $t 'status') + "] " + (Field $t 'title'))
 Write-Host (" entregou: " + $(if ((Field $t 'artifact') -eq '') { "(nao registrado)" } else { Field $t 'artifact' }) + " | partiu de: " + $(if ((Field $t 'base_artifact') -eq '') { "(nao registrado)" } else { Field $t 'base_artifact' }))
 if ($Full) {
    Write-Host ("    projeto:  " + $(if ((Field $t 'project') -eq '') { "(sem projeto - FURO de rastreio)" } else { Field $t 'project' }))
    Write-Host ("    gate:     " + $(if ((Field $t 'gate_verdict') -eq '') { "(sem veredito)" } else { Field $t 'gate_verdict' }) + " | sessao: " + $(if ((Field $t 'session') -eq '') { "(nao registrada)" } else { Field $t 'session' }))
  }

}

  # A ultima Task e a base natural do proximo passo (a "ultima revisao" que a Alia cita).
 # $lastTask (nao $last) - PowerShell e case-insensitive e $last colidia com o param -Last (int).
 $lastTask = $sorted[-1]
  Write-Host ""
 Write-Host ("ULTIMA REVISAO: " + (Field $lastTask 'id') + " -> entregou '" + (Field $lastTask 'artifact') + "'. O proximo passo parte DAQUI.")
}

# ---------------------------------------------------------------------------------------------
# PECA 5 (RSI): reflexao por TIPO de tarefa. So roda se -TaskType foi passado - match SIMPLES do
# campo `aplica_a:` no frontmatter das notas CANONICAS (memory/*.md, nivel raiz - nunca
# _proposals/, que e staging nao aprovado). Sem banco, sem embedding: string igual (case-
# insensitive, trim), ou o valor do TaskType aparecendo numa lista `aplica_a: [a, b]`.

# ---------------------------------------------------------------------------------------------
if ($TaskType -ne "") {
  Write-Host ""
  Write-Host ("=== Licoes que se aplicam ao tipo '" + $TaskType + "' ===")
  if (-not (Test-Path -LiteralPath $MemoryDir)) {
    Write-Host ("Sem memory/ nesta instancia (" + $MemoryDir + ") - nada a buscar.")
    exit 0

  }

  $notes = @(Get-ChildItem -LiteralPath $MemoryDir -Filter "*.md" -File -ErrorAction SilentlyContinue)
  $matches = New-Object System.Collections.Generic.List[object]
  foreach ($n in $notes) {
    $txt = [System.IO.File]::ReadAllText($n.FullName)
    $m = [regex]::Match($txt, '(?im)^\s*aplica_a\s*:\s*(.+?)\s*$')
    if (-not $m.Success) { continue }
    $raw = $m.Groups[1].Value.Trim()
    $vals = @($raw -replace '[\[\]]', '' -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ -ne '' })
    if ($vals -contains $TaskType.Trim().ToLowerInvariant()) {
      $descM = [regex]::Match($txt, '(?m)^\s*description:\s*(.+?)\s*$')
      $desc = if ($descM.Success) { $descM.Groups[1].Value.Trim() } else { "" }
      $matches.Add([PSCustomObject]@{ Name = $n.BaseName; Desc = $desc })
    }

  }

  if ($matches.Count -eq 0) {
    Write-Host ("Nenhuma nota com aplica_a: " + $TaskType + " ainda. Nao e erro - so nao ha licao marcada para este tipo.")
  } else {
    Write-Host ($matches.Count.ToString() + " nota(s) marcada(s) para o tipo '" + $TaskType + "':")
    foreach ($mt in $matches) {
      Write-Host ("  - " + $mt.Name + $(if ($mt.Desc -ne "") { " - " + $mt.Desc } else { "" }))
    }

  }

}
exit 0
