<#
  client-state.ps1 - Declara e muda o ESTADO de um Client no registro (OPP-77).

  O Alia Flow so conhecia UM tipo de Client: toda pasta em clients/ era cobrada como operacao viva
  (squad, mapa de conhecimento, Tasks com linhagem). Ideia tocada uma vez aparecia como CLIENTE
  REPROVADO nas provas, e a operacao do operador ficava suja de falha que nao e falha.

  Os tres estados (clients[].state no state.json - camada do operador, nunca do motor):
    ativo      operacao viva. Cobra tudo: squad, mapa de conhecimento, Tasks com linhagem.
    pontual    ideia tocada uma vez, experimento, prova de conceito. NAO cobra squad nem mapa.
               Aparece nas visoes como linha informativa, nunca como reprovacao. Vira ativo quando
               o operador quiser.
    arquivado  encerrado. Sai das cobrancas e do painel do dia a dia; o historico e as Tasks
               continuam intactos e rastreaveis (nada e apagado, nunca).

  Client sem estado declarado = ativo (compatibilidade: nada quebra, nenhuma migracao forcada).
  Mudar de estado NAO altera nada do que ja foi feito: Task antiga continua valendo e visivel.

  AUDITAVEL, nunca edicao a mao de JSON: toda mudanca grava state_since (quando), state_by (quem) e
  state_note (por que), e imprime a transicao. Registrar tambem e funcao deste comando: pasta em
  clients/ que nunca entrou no registro (os 4 Clients invisiveis da auditoria de 04/08) entra por
  aqui, com estado declarado desde o primeiro dia.

  Uso:
    # ver o registro inteiro (estado por Client + pastas em disco fora do registro)
    powershell -ExecutionPolicy Bypass -File scripts/client-state.ps1

    # declarar/mudar o estado (registra o Client se a pasta existe e ele ainda nao esta no registro)
    powershell -ExecutionPolicy Bypass -File scripts/client-state.ps1 -Client acme-saas -State pontual `
      -By "operador" -Note "ideia tocada uma vez em jun/2026"

  -DryRun mostra a transicao sem gravar. Le e grava JSON UTF-8 sem BOM, preservando tasks[] e todo
  o resto do estado. exit 0 no sucesso, 1 no erro. Sem acentos, sem emojis.
#>
param(
  [string]$Client = "",
  [ValidateSet("ativo", "pontual", "arquivado")][string]$State = "",
  [string]$By = "",
  [string]$Note = "",
  [string]$Name = "",
  [string]$Domain = "",
  [string]$StateFile = "",
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "_studio.ps1")
$studioRoot = Get-StudioRoot $root
if ([string]::IsNullOrWhiteSpace($StateFile)) { $StateFile = Join-Path $studioRoot "state.json" }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$today = (Get-Date).ToString("yyyy-MM-dd")

if (-not (Test-Path -LiteralPath $StateFile)) {
  Write-Host ("[ERRO] state.json nao encontrado: " + $StateFile)
  exit 1
}
$json = [System.IO.File]::ReadAllText($StateFile) | ConvertFrom-Json
if ($null -eq ($json.PSObject.Properties.Name | Where-Object { $_ -eq 'clients' })) {
  $json | Add-Member -NotePropertyName clients -NotePropertyValue @() -Force
}
$clients = @($json.clients)
$clientsDir = Join-Path (Split-Path -Parent $StateFile) "clients"
$diskIds = @()
if (Test-Path -LiteralPath $clientsDir) {
  $diskIds = @(Get-ChildItem -LiteralPath $clientsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
}

function StateOf($c) {
  $s = ""
  if (($c.PSObject.Properties.Name) -contains 'state') { $s = "$($c.state)".Trim().ToLower() }
  if ($s -eq "") { return "ativo (nao declarado)" }
  return $s
}

# --- Modo leitura: sem -Client, o comando so MOSTRA o registro -------------------------------
if ([string]::IsNullOrWhiteSpace($Client)) {
  Write-Host ("=== Estado dos Clients (" + $StateFile + ") ===")
  if ($clients.Count -eq 0) { Write-Host "(registro vazio)" }
  foreach ($c in ($clients | Sort-Object { "$($_.id)" })) {
    $line = "  " + ("$($c.id)").PadRight(16) + " " + (StateOf $c).PadRight(22)
    if (($c.PSObject.Properties.Name) -contains 'state_since') { $line += " desde " + "$($c.state_since)" }
    if (($c.PSObject.Properties.Name) -contains 'state_by')    { $line += " por " + "$($c.state_by)" }
    Write-Host $line
  }
  $stIds = @($clients | ForEach-Object { "$($_.id)" })
  $fora = @($diskIds | Where-Object { $stIds -notcontains $_ })
  $semPasta = @($stIds | Where-Object { $diskIds -notcontains $_ })
  Write-Host ("--- " + $clients.Count + " Client(s) no registro | " + $diskIds.Count + " pasta(s) em clients/ ---")
  if ($fora.Count -gt 0) {
    Write-Host ("[AVISO] " + $fora.Count + " pasta(s) FORA do registro (invisiveis para as provas): " + ($fora -join ", "))
    Write-Host ("        declare o estado de cada uma: scripts/client-state.ps1 -Client <id> -State <ativo|pontual|arquivado>")
  }
  if ($semPasta.Count -gt 0) { Write-Host ("[AVISO] " + $semPasta.Count + " Client(s) no registro sem pasta em disco: " + ($semPasta -join ", ")) }
  exit 0
}

# --- Modo escrita: declarar/mudar o estado ----------------------------------------------------
if ([string]::IsNullOrWhiteSpace($State)) {
  Write-Host "[ERRO] -Client informado sem -State. Diga o estado: ativo | pontual | arquivado."
  exit 1
}
if ([string]::IsNullOrWhiteSpace($By)) {
  $By = if ("$env:USERNAME" -ne "") { "$env:USERNAME" } else { "operador" }
}

$alvo = @($clients | Where-Object { "$($_.id)" -eq $Client })
$novo = $false
if ($alvo.Count -eq 0) {
  # Client fora do registro: so entra se a pasta existe em disco (fechar o furo dos invisiveis).
  # Cliente NOVO de verdade nasce pelo scripts/import-project.ps1 (scaffold + registro).
  if ($diskIds -notcontains $Client) {
    Write-Host ("[ERRO] Client '" + $Client + "' nao esta no registro e nao tem pasta em " + $clientsDir + ".")
    Write-Host "       Cliente novo nasce em scripts/import-project.ps1 (scaffold + registro); este comando so declara o estado de quem ja existe."
    exit 1
  }
  $novo = $true
}

$antes = if ($novo) { "(fora do registro)" } else { StateOf $alvo[0] }
Write-Host "=== Estado do Client ==="
Write-Host ("registro: " + $StateFile)
Write-Host ("client:   " + $Client + $(if ($novo) { " (pasta em disco, ainda sem registro)" } else { "" }))
Write-Host ("transicao: " + $antes + " -> " + $State)
Write-Host ("por: " + $By + " | quando: " + $today + $(if ($Note -ne "") { " | motivo: " + $Note } else { "" }))

if ($DryRun) {
  Write-Host "[DRY-RUN] nada foi gravado."
  exit 0
}

if ($novo) {
  $entrada = [ordered]@{
    id     = $Client
    name   = $(if ($Name -ne "") { $Name } else { $Client })
    domain = $(if ($Domain -ne "") { $Domain } else { "(nao declarado)" })
    status = "active"
  }
  $obj = [pscustomobject]$entrada
  $clients = @($clients + $obj)
  $alvo = @($obj)
} else {
  if ($Name -ne "")   { $alvo[0] | Add-Member -NotePropertyName name   -NotePropertyValue $Name   -Force }
  if ($Domain -ne "") { $alvo[0] | Add-Member -NotePropertyName domain -NotePropertyValue $Domain -Force }
}

$alvo[0] | Add-Member -NotePropertyName state       -NotePropertyValue $State -Force
$alvo[0] | Add-Member -NotePropertyName state_since -NotePropertyValue $today -Force
$alvo[0] | Add-Member -NotePropertyName state_by    -NotePropertyValue $By    -Force
if ($Note -ne "") { $alvo[0] | Add-Member -NotePropertyName state_note -NotePropertyValue $Note -Force }

$json.clients = @($clients)
if ($json.PSObject.Properties.Name -contains 'updated') { $json.updated = $today }
[System.IO.File]::WriteAllText($StateFile, ($json | ConvertTo-Json -Depth 32), $utf8)

# Validacao pos-escrita: re-parse e confere que o estado gravado e o pedido (e que tasks[] sobreviveu).
$check = [System.IO.File]::ReadAllText($StateFile) | ConvertFrom-Json
$gravado = @($check.clients | Where-Object { "$($_.id)" -eq $Client })
$okEstado = ($gravado.Count -eq 1) -and ("$($gravado[0].state)" -eq $State)
if (-not $okEstado) {
  Write-Host "[ERRO] validacao pos-escrita falhou: o estado nao ficou consistente. Confira o state.json."
  exit 1
}
Write-Host ("[OK] " + $Client + " agora e " + $State + " (por " + $By + " em " + $today + ") | " + @($check.clients).Count + " Client(s) no registro, " + @($check.tasks).Count + " Task(s) intactas.")
exit 0
