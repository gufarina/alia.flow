<#
  import-project.ps1 - Helper deterministico da skill importar-projeto (skills/importar-projeto/SKILL.md).
  Faz SO a parte bracal dos passos 2 e 6 da receita: SCAFFOLD do cliente novo + REGISTRO no state.json.
  NAO monta squad nem knowledge (isso e o Squad Creator). NAO desenha loops (isso e o Loop Designer).
  NAO marca active - o cliente nasce status "proposed" e so o operador o promove (aprovacao humana).

  O que faz:
    - cria studio/clients/{Id}/squad/agents/ e studio/clients/{Id}/squad/knowledge/ VAZIAS
      (para o Squad Creator preencher depois).
    - cria um client.md minimo (id, name, sector, source) em UTF-8 sem BOM, sem acentos/emojis.
    - registra o cliente em studio/state.json com status "proposed", SEM apagar nada do que ja existe
      (le, adiciona, grava; preserva os clientes e as tasks existentes).
    - em -DryRun: so mostra o que faria, nada e escrito.

  Origem (SourcePath) e SO referencia - este script NUNCA escreve na origem.
  Escrita .NET UTF-8 sem BOM. ErrorActionPreference Stop. Sem acentos, sem emojis.
#>
param(
  [Parameter(Mandatory = $true)][string]$Id,
  [Parameter(Mandatory = $true)][string]$Name,
  [Parameter(Mandatory = $true)][string]$Sector,
  [string]$SourcePath = "",
  [ValidateSet("ativo", "pontual", "arquivado")][string]$State = "ativo",
  [switch]$DryRun
)
# -State (OPP-77): o Client ja nasce com ESTADO declarado no registro. "ativo" cobra tudo (squad,
# mapa, Tasks com linhagem); "pontual" e a ideia tocada uma vez, que nao cobra squad nem mapa.
# Mudar depois: scripts/client-state.ps1 -Client <id> -State <novo> (com quem/quando registrados).

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "_studio.ps1")
$studioRoot = Get-StudioRoot $root

$utf8  = New-Object System.Text.UTF8Encoding($false)
$today = (Get-Date).ToString("yyyy-MM-dd")

function Write-Utf8NoBom {
  param([string]$path, [string]$content)
  [System.IO.File]::WriteAllText($path, $content, $utf8)
}

$mode = if ($DryRun) { "DRY-RUN (nada e escrito)" } else { "RUN (escreve em studio/)" }
Write-Host "=== Import Project (scaffold + registro) ==="
Write-Host ("id: " + $Id + " | name: " + $Name + " | sector: " + $Sector)
Write-Host ("source: " + $(if ($SourcePath) { $SourcePath + " (SO LEITURA)" } else { "(nao informada)" }))
Write-Host ("modo: " + $mode)
Write-Host ""

# Alvos do scaffold (sempre dentro da pasta de dados - nunca origem, nunca engine/).
$clientDir = Join-Path $studioRoot ("clients\" + $Id)
$squadDir  = Join-Path $clientDir "squad"
$agentsDir = Join-Path $squadDir "agents"
$knowDir   = Join-Path $squadDir "knowledge"
$clientMd  = Join-Path $clientDir "client.md"
$statePath = Join-Path $studioRoot "state.json"

# Guardrail: nao sobrescrever um cliente que ja existe.
if ((Test-Path -LiteralPath $clientDir) -and -not $DryRun) {
  Write-Host ("[ERRO] cliente ja existe: " + $clientDir + " (abortando para nao sobrescrever)")
  exit 1
}

# state.json e pre-requisito do registro.
if (-not (Test-Path -LiteralPath $statePath)) {
  Write-Host ("[ERRO] state.json ausente: " + $statePath)
  exit 1
}

# Ler o state atual e checar duplicidade de id (le, adiciona, grava - nunca apaga).
$stateTxt = [System.IO.File]::ReadAllText($statePath)
$state = $stateTxt | ConvertFrom-Json
$existingIds = @($state.clients | ForEach-Object { $_.id })
if ($existingIds -contains $Id) {
  Write-Host ("[ERRO] id ja registrado em state.json: " + $Id)
  exit 1
}

# Conteudo do client.md minimo (ASCII / UTF-8 sem BOM).
$srcLine = if ($SourcePath) { $SourcePath } else { "(nao informada)" }
$clientMdContent = @"
# Client - $Name

- id: $Id
- name: $Name
- sector: $Sector
- source: $srcLine
- status: proposed
- state: $State
- imported: $today

> Cliente importado para o Alia Flow. Scaffold criado pelo helper import-project.ps1.
> O squad em camadas e o knowledge (DDD: glossario + bounded contexts) serao montados pelo
> Squad Creator; os loops pelo Loop Designer. Status proposed ate a aprovacao do operador.
"@

# Novo registro no state.json (status proposed, sem squad ainda - o Squad Creator preenche).
$newClient = [ordered]@{
  id          = $Id
  name        = $Name
  domain      = $Sector
  status      = "proposed"
  source      = $srcLine
  state       = $State
  state_since = $today
  state_by    = $(if ("$env:USERNAME" -ne "") { "$env:USERNAME" } else { "operador" })
}

Write-Host "--- Acoes ---"
Write-Host ("[dir]   " + $agentsDir + " (vazia, para o Squad Creator)")
Write-Host ("[dir]   " + $knowDir + " (vazia, para o Squad Creator)")
Write-Host ("[file]  " + $clientMd + " (client.md minimo)")
Write-Host ("[state] studio/state.json += cliente '" + $Id + "' status=proposed state=" + $State + " (preserva " + $existingIds.Count + " cliente(s) + tasks)")
Write-Host ""

if ($DryRun) {
  Write-Host "--- client.md (preview) ---"
  Write-Host $clientMdContent
  Write-Host ""
  Write-Host "DRY-RUN: nada foi escrito."
  Write-Host "Proximos passos: Squad Creator (squad+DDD) -> Loop Designer (loops) -> aprovacao -> smoke."
  exit 0
}

# --- Escrita real (so fora de DryRun) ---
New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null
New-Item -ItemType Directory -Path $knowDir -Force | Out-Null
Write-Utf8NoBom -path $clientMd -content $clientMdContent

# Adicionar o cliente preservando o resto do state (clientes + tasks).
$clientsList = New-Object System.Collections.Generic.List[object]
foreach ($c in $state.clients) { $clientsList.Add($c) }
$clientsList.Add([pscustomobject]$newClient)
$state.clients = $clientsList.ToArray()

$json = $state | ConvertTo-Json -Depth 100
Write-Utf8NoBom -path $statePath -content $json

Write-Host ("[OK] scaffold criado e cliente '" + $Id + "' registrado como proposed.")
Write-Host "Proximos passos: Squad Creator (squad+DDD) -> Loop Designer (loops) -> aprovacao -> smoke."
exit 0
