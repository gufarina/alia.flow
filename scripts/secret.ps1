<#
  secret.ps1 - a PORTA UNICA para segredo (chave de API, token de deploy, senha) no motor.

  Por que existe (incidente real, 08/09/2026): um VERCEL_TOKEN precisou entrar no motor. A Alia
  pediu para colar no .env; o operador colou na CONVERSA por engano. A Alia pediu para gerar outro
  e revogar o vazado - o operador reagiu, com razao: "se eu pegar outro voce vai dar a mesma
  resposta, nao tem logica" (o canal continua sendo o mesmo chat, pedir rotacao so repete a
  exposicao), e fechou: "SEJA RESPONSAVEL E GUARDE ESSA MERDA COM AUDITORIA". O defeito era do
  MOTOR: nao existia lugar seguro pra um segredo entrar, nem registro de quem usou o que e quando.
  Isto fecha esse buraco.

  DESENHO (dois arquivos, papeis diferentes, nunca confundir):
    - COFRE  ({studio}/.secrets/vault.json): guarda o VALOR. Fora do git (studio/ e .secrets/ ja
      cobertos por .gitignore, defesa em profundidade). So este script LE/ESCREVE nele.
    - LEDGER ({studio}/secrets-ledger.jsonl): append-only, NUNCA guarda o valor - so nome, escopo,
      acao (set/use/revoke/get/leak/fail), quando, quem pediu (-Who), pra que (-Reason) e a
      IMPRESSAO DIGITAL do valor (sha256 truncado, nunca o valor em si - nem parcial). Qualquer
      agente pode LER o ledger (e prova); nenhum agente le o cofre direto (so via este script).

  A REGRA DE OURO: o normal e USAR sem VER. -Use injeta o segredo numa variavel de ambiente do
  comando FILHO e nunca imprime o valor - o agente publica sem jamais ver o token. -Get (o
  caminho excepcional) existe mas exige -IAcceptExposure + -Reason, e grita no ledger quando usado.

  O VALOR NUNCA VEM POR ARGUMENTO DE LINHA DE COMANDO (argumento vaza em historico de shell, em
  log de hook, no transcript). Por isso NAO HA parametro -Value neste script - de proposito. -Set
  le o valor por STDIN (pipe) ou de um -File que o script LE E DEPOIS APAGA. Tentar passar
  -Value da erro de parametro do proprio PowerShell (prova pelo negativo, ver smoke-test.ps1).

  VERBOS (mutuamente exclusivos, um por chamada):
    -Set     -Name <nome> [-Scope <escopo>] [-File <caminho>] [-Reason <texto>] [-Who <texto>]
             Grava no cofre. Sem -File, le do STDIN. Loga "set" no ledger.
    -Use     -Name <nome> [-Scope <escopo>] -Command <texto> -Reason <texto> [-EnvVar <nome>] [-Who <texto>]
             Roda um comando FILHO (cmd /c) com o segredo injetado em $env:<EnvVar> (default =
             -Name). Nunca imprime o valor. Propaga o exit code do filho. Loga "use" no ledger.
    -List    Mostra nome, escopo, quando entrou, ultimo uso e a impressao digital. Nunca o valor.
    -Revoke  -Name <nome> [-Scope <escopo>] -Reason <texto> [-Who <texto>]
             Tira do cofre. Loga "revoke" no ledger (o segredo continua no LEDGER como historico -
             so some do cofre).
    -Get     -Name <nome> [-Scope <escopo>] -Reason <texto> -IAcceptExposure [-Who <texto>]
             Caminho EXCEPCIONAL: imprime o valor puro, uma vez, com aviso. Sem -IAcceptExposure
             (ou sem -Reason), RECUSA sem tocar o ledger - nada de risco aconteceu, nada a logar.
             Com os dois, loga "get" no ledger com risky:true (ruidoso de proposito).
    -MarkLeaked -Name <nome> -Reason <texto> [-Scope <escopo>] [-Who <texto>]
             Registra um vazamento conhecido (ex.: segredo colado na conversa por engano) SEM
             mexer no cofre - a doutrina da casa (mandato do CEO, 08/09/2026): trocar de canal nao
             limpa o vazamento se o canal continua o mesmo; o motor registra, usa o que tem, e
             oferece UMA vez o caminho seguro - nunca cobra rotacao pelo mesmo canal que expos.

  Parametros de teste (WARDEN): -Root, -VaultPath, -LedgerPath sao overrides SO para fixture de
  smoke test (mesmo padrao de -Root em delegation-gate.ps1). A chamada de producao nunca os passa. Escrita .NET UTF-8 sem BOM.
#>
[CmdletBinding(DefaultParameterSetName = 'List')]
param(
  [Parameter(ParameterSetName = 'Set', Mandatory = $true)][switch]$Set,
  [Parameter(ParameterSetName = 'Use', Mandatory = $true)][switch]$Use,
  [Parameter(ParameterSetName = 'List', Mandatory = $true)][switch]$List,
  [Parameter(ParameterSetName = 'Revoke', Mandatory = $true)][switch]$Revoke,
  [Parameter(ParameterSetName = 'Get', Mandatory = $true)][switch]$Get,
  [Parameter(ParameterSetName = 'MarkLeaked', Mandatory = $true)][switch]$MarkLeaked,

  [Parameter(ParameterSetName = 'Set')]
  [Parameter(ParameterSetName = 'Use')]
  [Parameter(ParameterSetName = 'Revoke')]
  [Parameter(ParameterSetName = 'Get')]
  [Parameter(ParameterSetName = 'MarkLeaked')]
  [string]$Name = "",

  [string]$Scope = "global",

  [Parameter(ParameterSetName = 'Set')][string]$File = "",
  [Parameter(ParameterSetName = 'Use')][string]$Command = "",
  [Parameter(ParameterSetName = 'Use')][string]$EnvVar = "",
  [Parameter(ParameterSetName = 'Get')][switch]$IAcceptExposure,

  [Parameter(ParameterSetName = 'Set')]
  [Parameter(ParameterSetName = 'Use')]
  [Parameter(ParameterSetName = 'Revoke')]
  [Parameter(ParameterSetName = 'Get')]
  [Parameter(ParameterSetName = 'MarkLeaked')]
  [string]$Reason = "",

  [string]$Who = "",

  [string]$Root = "",
  [string]$VaultPath = "",
  [string]$LedgerPath = ""
)

$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding($false)

$root = if (-not [string]::IsNullOrWhiteSpace($Root)) { $Root } else { Split-Path -Parent $PSScriptRoot }
# _studio.ps1 e sempre o irmao REAL deste arquivo em disco (PSScriptRoot nunca muda com -Root,
# que so redireciona ONDE os DADOS do studio ficam - fixture de teste nao copia o resto de scripts/).
. (Join-Path $PSScriptRoot "_studio.ps1")
$studioRoot = Get-StudioRoot -Root $root

$vaultFile = if (-not [string]::IsNullOrWhiteSpace($VaultPath)) { $VaultPath } else { Join-Path $studioRoot ".secrets\vault.json" }
$ledgerFile = if (-not [string]::IsNullOrWhiteSpace($LedgerPath)) { $LedgerPath } else { Join-Path $studioRoot "secrets-ledger.jsonl" }

function Fail([string]$msg) {
  Write-Host ("[FAIL] " + $msg) -ForegroundColor Red
  exit 1
}

function Get-Fingerprint([string]$value) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)
    $hash = $sha.ComputeHash($bytes)
    $hex = -join ($hash | ForEach-Object { $_.ToString("x2") })
    return "sha256:" + $hex.Substring(0, 12)
  } finally { $sha.Dispose() }
}

function Get-Actor {
  if (-not [string]::IsNullOrWhiteSpace($Who)) { return $Who }
  $u = "$($env:USERNAME)"
  if ([string]::IsNullOrWhiteSpace($u)) { $u = "desconhecido" }
  return $u + " (sessao/Task nao informada - passe -Who '<sessao/Task/agente>')"
}

function Read-Vault {
  if (-not (Test-Path -LiteralPath $vaultFile)) {
    return [ordered]@{ secrets = [ordered]@{} }
  }
  $raw = [System.IO.File]::ReadAllText($vaultFile)
  if ([string]::IsNullOrWhiteSpace($raw)) { return [ordered]@{ secrets = [ordered]@{} } }
  $obj = $raw | ConvertFrom-Json
  $out = [ordered]@{ secrets = [ordered]@{} }
  if ($null -ne $obj -and ($obj.PSObject.Properties.Name -contains 'secrets')) {
    foreach ($p in $obj.secrets.PSObject.Properties) {
      $out.secrets[$p.Name] = $p.Value
    }
  }
  return $out
}

function Save-Vault($vault) {
  $dir = Split-Path -Parent $vaultFile
  if (-not [string]::IsNullOrWhiteSpace($dir)) { New-Item -ItemType Directory -Force -Path $dir -ErrorAction SilentlyContinue | Out-Null }
  $json = $vault | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($vaultFile, $json, $utf8)
  $readme = Join-Path $dir "README.md"
  if (-not (Test-Path -LiteralPath $readme)) {
    $txt = "# .secrets/ - COFRE DE SEGREDOS`r`n`r`nGuarda VALOR de segredo (chave, token). NUNCA versionar (ja coberto por .gitignore:" +
      " studio/, .secrets/, **/.secrets/). Unico leitor/escritor legitimo: scripts/secret.ps1.`r`n" +
      "Auditoria de uso mora em studio/secrets-ledger.jsonl (esse sim, qualquer agente pode ler).`r`n"
    [System.IO.File]::WriteAllText($readme, $txt, $utf8)
  }
}

function Write-LedgerLine([hashtable]$fields) {
  $dir = Split-Path -Parent $ledgerFile
  if (-not [string]::IsNullOrWhiteSpace($dir)) { New-Item -ItemType Directory -Force -Path $dir -ErrorAction SilentlyContinue | Out-Null }
  $entry = [ordered]@{ ts = (Get-Date).ToUniversalTime().ToString("o") }
  foreach ($k in @("secret", "scope", "action", "who", "reason", "fingerprint", "risky", "command")) {
    if ($fields.ContainsKey($k)) { $entry[$k] = $fields[$k] }
  }
  # defesa: nunca deixa um campo "value"/"valor" escapar pro ledger, mesmo por engano de chamador futuro.
  if ($fields.ContainsKey("value") -or $fields.ContainsKey("valor")) { Fail "recusa interna: tentativa de gravar VALOR no ledger (bug do proprio script, nunca deveria acontecer)" }
  $line = ($entry | ConvertTo-Json -Compress) + "`n"
  [System.IO.File]::AppendAllText($ledgerFile, $line, $utf8)
}

function Test-NameValido([string]$n) {
  return ($n -match '^[A-Za-z0-9_.-]+$')
}

function Get-Key([string]$scope, [string]$name) { return $scope + "::" + $name }

# --- validacoes comuns ---
if ($Set -or $Use -or $Revoke -or $Get -or $MarkLeaked) {
  if ([string]::IsNullOrWhiteSpace($Name)) { Fail "-Name e obrigatorio" }
  if (-not (Test-NameValido $Name)) { Fail "-Name invalido ('$Name') - so letras, numeros, ponto, hifen e underscore" }
  if (-not (Test-NameValido $Scope)) { Fail "-Scope invalido ('$Scope') - so letras, numeros, ponto, hifen e underscore" }
}

$key = Get-Key $Scope $Name

# =========================================================================================
# -Set
# =========================================================================================
if ($Set) {
  $value = ""
  if (-not [string]::IsNullOrWhiteSpace($File)) {
    if (-not (Test-Path -LiteralPath $File)) { Fail ("-File nao existe: " + $File) }
    $value = [System.IO.File]::ReadAllText($File).TrimEnd("`r", "`n")
    try { Remove-Item -LiteralPath $File -Force } catch { Write-Host "[AVISO] nao consegui apagar $File depois de ler - apague manualmente." -ForegroundColor Yellow }
  } else {
    if (-not [Console]::IsInputRedirected) {
      Fail "sem -File e sem STDIN redirecionado - forneca o valor por pipe (ex.: Get-Content x.txt -Raw | secret.ps1 -Set -Name X) ou -File <caminho>. O valor NUNCA vai por argumento de linha de comando."
    }
    $raw = ""
    try {
      $readTask = [Console]::In.ReadToEndAsync()
      if ($readTask.Wait(10000)) { $raw = $readTask.Result } else { $raw = "" }
    } catch { $raw = "" }
    $value = $raw.TrimEnd("`r", "`n")
  }
  if ([string]::IsNullOrWhiteSpace($value)) { Fail "valor vazio - nada gravado" }

  $vault = Read-Vault
  $reasonSet = if ([string]::IsNullOrWhiteSpace($Reason)) { "(sem motivo informado)" } else { $Reason }
  $now = (Get-Date).ToUniversalTime().ToString("o")
  $existed = $vault.secrets.Contains($key)
  $createdAt = $now
  if ($existed) { try { $createdAt = "$($vault.secrets[$key].created_at)" } catch { $createdAt = $now } }
  $fp = Get-Fingerprint $value
  $vault.secrets[$key] = [ordered]@{
    name = $Name; scope = $Scope; value = $value
    created_at = $createdAt; updated_at = $now; last_used_at = $null
    fingerprint = $fp
  }
  Save-Vault $vault
  Write-LedgerLine @{ secret = $Name; scope = $Scope; action = "set"; who = (Get-Actor); reason = $reasonSet; fingerprint = $fp }
  Write-Host ("[OK] segredo '" + $Name + "' (escopo " + $Scope + ") gravado no cofre. fingerprint=" + $fp)
  exit 0
}

# =========================================================================================
# -Use
# =========================================================================================
if ($Use) {
  if ([string]::IsNullOrWhiteSpace($Command)) { Fail "-Command e obrigatorio para -Use" }
  if ([string]::IsNullOrWhiteSpace($Reason)) { Fail "-Reason e obrigatorio para -Use (para que precisa do segredo)" }
  $vault = Read-Vault
  if (-not $vault.secrets.Contains($key)) {
    Write-LedgerLine @{ secret = $Name; scope = $Scope; action = "fail"; who = (Get-Actor); reason = "use: segredo nao encontrado no cofre" }
    Fail ("segredo '" + $Name + "' (escopo " + $Scope + ") nao existe no cofre")
  }
  $entry = $vault.secrets[$key]
  $value = "$($entry.value)"
  $envName = if (-not [string]::IsNullOrWhiteSpace($EnvVar)) { $EnvVar } else { $Name }

  $prevValue = [Environment]::GetEnvironmentVariable($envName)
  [Environment]::SetEnvironmentVariable($envName, $value)
  $exitCode = 0
  try {
    & cmd /c $Command
    $exitCode = $LASTEXITCODE
  } catch {
    $exitCode = 1
  } finally {
    [Environment]::SetEnvironmentVariable($envName, $prevValue)
  }

  $vault.secrets[$key].last_used_at = (Get-Date).ToUniversalTime().ToString("o")
  Save-Vault $vault
  $cmdShort = if ($Command.Length -gt 80) { $Command.Substring(0, 80) + "..." } else { $Command }
  Write-LedgerLine @{ secret = $Name; scope = $Scope; action = "use"; who = (Get-Actor); reason = $Reason; fingerprint = "$($entry.fingerprint)"; command = $cmdShort }
  exit $exitCode
}

# =========================================================================================
# -List
# =========================================================================================
if ($List) {
  $vault = Read-Vault
  $items = @($vault.secrets.Values)
  if ($items.Count -eq 0) { Write-Host "Nenhum segredo no cofre."; exit 0 }
  Write-Host ("{0,-24} {1,-16} {2,-24} {3,-24} {4}" -f "NOME", "ESCOPO", "CRIADO_EM", "ULTIMO_USO", "FINGERPRINT")
  foreach ($it in ($items | Sort-Object { "$($_.scope)::$($_.name)" })) {
    $lastUsed = if ($null -eq $it.last_used_at -or [string]::IsNullOrWhiteSpace("$($it.last_used_at)")) { "(nunca usado)" } else { "$($it.last_used_at)" }
    Write-Host ("{0,-24} {1,-16} {2,-24} {3,-24} {4}" -f "$($it.name)", "$($it.scope)", "$($it.created_at)", $lastUsed, "$($it.fingerprint)")
  }
  exit 0
}

# =========================================================================================
# -Revoke
# =========================================================================================
if ($Revoke) {
  if ([string]::IsNullOrWhiteSpace($Reason)) { Fail "-Reason e obrigatorio para -Revoke" }
  $vault = Read-Vault
  if (-not $vault.secrets.Contains($key)) { Fail ("segredo '" + $Name + "' (escopo " + $Scope + ") nao existe no cofre") }
  $fp = "$($vault.secrets[$key].fingerprint)"
  $vault.secrets.Remove($key)
  Save-Vault $vault
  Write-LedgerLine @{ secret = $Name; scope = $Scope; action = "revoke"; who = (Get-Actor); reason = $Reason; fingerprint = $fp }
  Write-Host ("[OK] segredo '" + $Name + "' (escopo " + $Scope + ") removido do cofre (continua no ledger como historico)")
  exit 0
}

# =========================================================================================
# -Get (caminho excepcional)
# =========================================================================================
if ($Get) {
  if (-not $IAcceptExposure -or [string]::IsNullOrWhiteSpace($Reason)) {
    Fail "-Get exige -IAcceptExposure E -Reason (o caminho excepcional e barrado por padrao - use -Use para injetar sem ver o valor). Nada foi logado - nenhum risco aconteceu."
  }
  $vault = Read-Vault
  if (-not $vault.secrets.Contains($key)) { Fail ("segredo '" + $Name + "' (escopo " + $Scope + ") nao existe no cofre") }
  $entry = $vault.secrets[$key]
  Write-LedgerLine @{ secret = $Name; scope = $Scope; action = "get"; who = (Get-Actor); reason = $Reason; fingerprint = "$($entry.fingerprint)"; risky = $true }
  Write-Host "[AVISO] CAMINHO EXCEPCIONAL: valor exposto abaixo, uma vez. Registrado no ledger como risky." -ForegroundColor Yellow
  Write-Output "$($entry.value)"
  exit 0
}

# =========================================================================================
# -MarkLeaked
# =========================================================================================
if ($MarkLeaked) {
  if ([string]::IsNullOrWhiteSpace($Reason)) { Fail "-Reason e obrigatorio para -MarkLeaked (o que vazou e por onde)" }
  $vault = Read-Vault
  $fp = if ($vault.secrets.Contains($key)) { "$($vault.secrets[$key].fingerprint)" } else { "(nao esta no cofre)" }
  Write-LedgerLine @{ secret = $Name; scope = $Scope; action = "leak"; who = (Get-Actor); reason = $Reason; fingerprint = $fp; risky = $true }
  Write-Host ("[REGISTRADO] vazamento de '" + $Name + "' (escopo " + $Scope + ") no ledger. Doutrina: nao pedir rotacao pelo mesmo canal que expos - use scripts/secret.ps1 -Set uma vez, por canal seguro, se/quando o operador oferecer.")
  exit 0
}
