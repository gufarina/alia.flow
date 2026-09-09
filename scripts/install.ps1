<#
  install.ps1 - instala o Alia Flow na pasta atual (o "copia uma linha").
  O usuario cola UMA linha no Claude Code (ou no PowerShell), dentro de uma pasta vazia:

    iwr -useb https://raw.githubusercontent.com/gufarina/alia.flow/main/scripts/install.ps1 | iex

  Baixa o Alia Flow e descompacta aqui. Depois e so abrir esta pasta no Claude Code e dizer: pronto.
  Nao precisa de git nem de Python - so o PowerShell (ja vem no Windows).
  Precisa de um coding agent (Claude Code, Codex ou OpenCode) - links no fim.

  TRANSACIONAL (instalar sem medo):
    - Se ja existir conteudo na pasta destino que colidiria com a instalacao, faz backup
      timestampado antes de copiar (.alia-backup-<yyyyMMdd-HHmmss>/).
    - Se a copia falhar no meio, faz ROLLBACK: remove o que foi copiado parcialmente e
      devolve os arquivos originais a partir do backup. Nunca deixa a pasta num estado parcial.
    - Erros de download e extracao sao classificados e reportados com [ERRO] + motivo.

  -Dest <pasta>: instala numa pasta especifica em vez da pasta atual (default = pasta atual,
    o one-liner "iwr|iex" continua identico - Dest so importa quando o launcher chama o script
    direto com -Dest).
  -EventLog <arquivo>: emite progresso em JSONL append-only (fases download|extract|guard|
    backup|copy|smoke|rollback|done) para a UI do launcher fazer tail. Sem -EventLog, o
    comportamento de Write-Host de hoje fica identico. Contrato completo:
    docs/product/alia-launcher-specs/contrato-launcher-motor.md secao 3. UTF-8 sem BOM.
#>
param(
  [string]$Dest = (Get-Location).Path,
  [string]$EventLog
)

$ErrorActionPreference = "Stop"

# Repo publico do Alia Flow (open source). Branch main.
$repo   = "gufarina/alia.flow"
$branch = "main"
$zip    = "https://github.com/$repo/archive/refs/heads/$branch.zip"
$dest   = $Dest

# Fases do protocolo de progresso (contrato secao 3) - enum fixo, os 8 valores validos de "phase".
$eventPhases = @("download","extract","guard","backup","copy","smoke","rollback","done")

# Camada do operador, intocada por qualquer coisa que venha do pacote (mesma lista do
# update-online.ps1 - reuse-first, nao inventa nome novo).
$protected = @("studio","clients","state.json","studio.yaml","alia.config.json","memory",".git")

if ($repo -eq "ORG/alia-flow") {
  Write-Host "[AVISO] Este instalador ainda nao foi publicado (repo placeholder)."
  Write-Host "        O DevOps troca ORG/alia-flow pelo repo real antes de divulgar a linha."
  exit 1
}

# ---------------------------------------------------------------------------
# Funcoes do miolo transacional - testaveis isoladamente, sem baixar nada.
# ---------------------------------------------------------------------------

function Get-CollidingItems {
  # Retorna os itens de $SourceDir que colidiriam (mesmo nome) com algo ja existente em $DestDir.
  param(
    [Parameter(Mandatory)][string]$SourceDir,
    [Parameter(Mandatory)][string]$DestDir
  )
  $colliding = @()
  $sourceItems = Get-ChildItem -Path $SourceDir -Force
  foreach ($item in $sourceItems) {
    $destPath = Join-Path $DestDir $item.Name
    if (Test-Path -LiteralPath $destPath) {
      $colliding += $item.Name
    }
  }
  return $colliding
}

function Backup-Dest {
  # Copia os itens colidentes de $DestDir para uma pasta de backup timestampada dentro do proprio
  # $DestDir. Retorna o caminho do backup, ou $null se nao havia nada para backupear.
  param(
    [Parameter(Mandatory)][string]$DestDir,
    [Parameter(Mandatory)][string[]]$Items
  )
  if ($Items.Count -eq 0) {
    return $null
  }
  $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $backupDir = Join-Path $DestDir (".alia-backup-" + $stamp)
  New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
  foreach ($name in $Items) {
    $src = Join-Path $DestDir $name
    if (Test-Path -LiteralPath $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $backupDir $name) -Recurse -Force
    }
  }
  return $backupDir
}

function Restore-Dest {
  # Rollback: remove de $DestDir os itens que a instalacao teria copiado (estado parcial) e
  # devolve os itens originais a partir de $BackupDir. Se $BackupDir e $null, so limpa o parcial
  # (caso a pasta destino estivesse vazia antes - nao ha nada para restaurar).
  param(
    [Parameter(Mandatory)][string]$DestDir,
    [string]$BackupDir,
    [Parameter(Mandatory)][string[]]$Items
  )
  foreach ($name in $Items) {
    $target = Join-Path $DestDir $name
    if (Test-Path -LiteralPath $target) {
      $targetFull = (Get-Item -LiteralPath $target).FullName
      Remove-Item -LiteralPath $targetFull -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  if ($BackupDir -and (Test-Path -LiteralPath $BackupDir)) {
    Get-ChildItem -Path $BackupDir -Force | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $DestDir $_.Name) -Recurse -Force
    }
  }
}

function Copy-AliaContent {
  # Copia todo o conteudo de $SourceDir para $DestDir (usada tanto no fluxo real quanto no teste).
  param(
    [Parameter(Mandatory)][string]$SourceDir,
    [Parameter(Mandatory)][string]$DestDir
  )
  Copy-Item -Path (Join-Path $SourceDir "*") -Destination $DestDir -Recurse -Force
}

function Assert-SafeInstallSet {
  # Guarda de seguranca (furo 1 do contrato): aborta ANTES de copiar se algum item VINDO DO
  # PACOTE colide de nome com algo protegido que JA EXISTE no destino. Ate hoje a protecao era
  # 100% implicita (o zip nunca contem studio/clients/state.json por omissao) - isto fecha o furo
  # de forma explicita, no mesmo espirito do Assert-SafeCopySet do update-online.ps1.
  param(
    [Parameter(Mandatory)][string]$SourceDir,
    [Parameter(Mandatory)][string]$DestDir,
    [Parameter(Mandatory)][string[]]$Protected
  )
  $sourceNames = @(Get-ChildItem -Path $SourceDir -Force | Select-Object -ExpandProperty Name)
  $violations = @()
  foreach ($name in $Protected) {
    if (($sourceNames -contains $name) -and (Test-Path -LiteralPath (Join-Path $DestDir $name))) {
      $violations += $name
    }
  }
  if ($violations.Count -gt 0) {
    throw [System.Exception]::new("PHASE:GUARD|instalacao tentaria sobrescrever dado protegido do operador: " + ($violations -join ", "))
  }
}

function Test-UnsafeDestPath {
  # Guarda de destino: recusa raiz de drive (C:\, D:\...) ou pasta de sistema conhecida
  # (Windows, Program Files, Program Files (x86), System32) - furo do contrato secao 4/5.
  param([Parameter(Mandatory)][string]$Path)
  $norm = $Path.TrimEnd('\', '/')
  if ($norm -match '^[A-Za-z]:$') { return $true }
  $unsafeLeaves = @("windows", "program files", "program files (x86)", "system32")
  $leaf = Split-Path -Path $norm -Leaf
  if ($unsafeLeaves -contains $leaf.ToLower()) { return $true }
  return $false
}

function Write-InstallEvent {
  # Emite uma linha JSONL de progresso em $EventLogPath (contrato secao 3). Fail-soft: se a
  # escrita falhar por qualquer motivo, engole o erro e segue - emitir evento NUNCA pode
  # quebrar o fluxo de instalacao. Sem $EventLogPath, e um no-op silencioso.
  param(
    [string]$EventLogPath,
    [Parameter(Mandatory)][string]$Phase,
    [Parameter(Mandatory)][int]$Pct,
    [Parameter(Mandatory)][string]$Message,
    [string]$Result,
    [object]$Detail
  )
  if (-not $EventLogPath) { return }
  try {
    $evt = [ordered]@{
      ts      = (Get-Date).ToUniversalTime().ToString("o")
      phase   = $Phase
      pct     = $Pct
      message = $Message
    }
    if ($Phase -eq "done") {
      $evt.result = $Result
      $evt.detail = $Detail
    }
    $line = ($evt | ConvertTo-Json -Depth 5 -Compress)
    Add-Content -LiteralPath $EventLogPath -Value $line -Encoding UTF8
  } catch {
    # fail-soft de proposito - evento perdido nunca derruba a instalacao.
  }
}

# Se o script foi apenas "dot-sourced" para testar as funcoes acima, para aqui.
if ($env:ALIA_INSTALL_TEST_ONLY -eq "1") {
  return
}

# ---------------------------------------------------------------------------
# Fluxo real de instalacao
# ---------------------------------------------------------------------------

# Guarda de destino (contrato secao 4/5): recusa raiz de drive ou pasta de sistema antes de
# tocar em qualquer coisa - nada e baixado, nada e criado.
if (Test-UnsafeDestPath -Path $dest) {
  Write-Host ("[ERRO] destino nao permitido (raiz de drive ou pasta de sistema): " + $dest)
  Write-InstallEvent -EventLogPath $EventLog -Phase "guard" -Pct 0 -Message "destino invalido" -Result "error" -Detail ([ordered]@{ dest = $dest })
  exit 1
}

Write-Host "Alia - baixando e instalando nesta pasta..."
Write-InstallEvent -EventLogPath $EventLog -Phase "download" -Pct 10 -Message "baixando o motor mais recente"
$tmpZip = Join-Path $env:TEMP ("alia-" + [System.Guid]::NewGuid().ToString("N") + ".zip")
$tmpDir = Join-Path $env:TEMP ("alia-x-" + [System.Guid]::NewGuid().ToString("N"))
$backupDir = $null
$collidingItems = @()

try {
  try {
    Invoke-WebRequest -UseBasicParsing -Uri $zip -OutFile $tmpZip
  } catch {
    Write-Host ("[ERRO] download falhou (rede/URL): " + $_.Exception.Message)
    Write-InstallEvent -EventLogPath $EventLog -Phase "done" -Pct 100 -Message "download falhou" -Result "error" -Detail ([ordered]@{ dest = $dest })
    exit 1
  }

  Write-InstallEvent -EventLogPath $EventLog -Phase "extract" -Pct 30 -Message "extraindo o pacote"
  try {
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
  } catch {
    Write-Host ("[ERRO] extracao falhou (zip corrompido?): " + $_.Exception.Message)
    Write-InstallEvent -EventLogPath $EventLog -Phase "done" -Pct 100 -Message "extracao falhou" -Result "error" -Detail ([ordered]@{ dest = $dest })
    exit 1
  }

  # O zip do GitHub tem uma pasta raiz (ex: alia-flow-main/). O conteudo dela vai pra $dest.
  $inner = Get-ChildItem -Directory $tmpDir | Select-Object -First 1
  if ($null -eq $inner) {
    Write-Host "[ERRO] o pacote baixado nao tem a pasta raiz esperada (zip vazio ou formato inesperado) - nada tocado."
    Write-InstallEvent -EventLogPath $EventLog -Phase "done" -Pct 100 -Message "pacote sem pasta raiz" -Result "error" -Detail ([ordered]@{ dest = $dest })
    exit 1
  }

  Write-InstallEvent -EventLogPath $EventLog -Phase "guard" -Pct 40 -Message "conferindo integridade e colisoes"

  # Integridade (contrato secao 5 item 6): se o pacote extraido tem MANIFEST.sha256, confere
  # ANTES de copiar. Sem manifesto no pacote, segue normal (nao inventa exigencia).
  #
  # CONSERTO (code review adversarial, 31/08/2026 - BLOQUEADOR DE RELEASE): a versao anterior
  # resolvia o verificador por `Join-Path $PSScriptRoot "verify-manifest.ps1"`. No jeito
  # DIVULGADO de instalar - `iwr -useb .../install.ps1 | iex`, a unica linha que o README manda
  # colar - NAO EXISTE arquivo de script, entao $PSScriptRoot e VAZIO e Join-Path lanca
  # "Cannot bind argument to parameter 'Path' because it is an empty string" (MEDIDO). Com
  # $ErrorActionPreference = "Stop" isso derrubava a instalacao inteira com erro cru de
  # PowerShell, sem [ERRO], logo depois de baixar e extrair - e o MANIFEST.sha256 esta na raiz
  # do repo publico, entao o Test-Path abaixo da VERDADE em toda instalacao real. Nada era
  # corrompido (a copia ainda nao tinha comecado), mas ninguem conseguia instalar.
  # A correcao certa nao e so "nao quebrar": o verificador que vale e o que veio DENTRO do
  # pacote baixado (mesma versao do manifesto que ele confere), nao o da maquina de quem roda.
  $manifestPath = Join-Path $inner.FullName "MANIFEST.sha256"
  if (Test-Path -LiteralPath $manifestPath) {
    $verifyScript = ""
    $verifyDoPacote = Join-Path $inner.FullName "scripts\verify-manifest.ps1"
    if (Test-Path -LiteralPath $verifyDoPacote) {
      $verifyScript = $verifyDoPacote
    } elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
      $localCandidato = Join-Path $PSScriptRoot "verify-manifest.ps1"
      if (Test-Path -LiteralPath $localCandidato) { $verifyScript = $localCandidato }
    }
    if ([string]::IsNullOrWhiteSpace($verifyScript)) {
      # Fail-soft honesto: o pacote traz manifesto mas nao traz verificador. Avisa e segue - o
      # contrario (abortar) deixaria o usuario sem instalacao nenhuma por um arquivo ausente do
      # pacote, e a conferencia continua disponivel depois (docs/INTEGRIDADE.md).
      Write-Host "[AVISO] o pacote tem MANIFEST.sha256 mas nao trouxe scripts\verify-manifest.ps1 - integridade nao conferida agora (ver docs\INTEGRIDADE.md)."
    } else {
      & $verifyScript -Dir $inner.FullName | Out-Null
      if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERRO] integridade do pacote falhou (MANIFEST.sha256 nao bate) - nada tocado."
        Write-InstallEvent -EventLogPath $EventLog -Phase "done" -Pct 100 -Message "integridade falhou" -Result "error" -Detail ([ordered]@{ dest = $dest })
        exit 1
      }
    }
  }

  # Guarda explicita (furo 1): aborta ANTES de copiar se algo do pacote colide com nome
  # protegido que JA EXISTE no destino.
  try {
    Assert-SafeInstallSet -SourceDir $inner.FullName -DestDir $dest -Protected $protected
  } catch {
    Write-Host ("[ABORTADO] " + $_.Exception.Message.Substring(12))
    Write-InstallEvent -EventLogPath $EventLog -Phase "done" -Pct 100 -Message "guarda de seguranca abortou" -Result "error" -Detail ([ordered]@{ dest = $dest })
    exit 1
  }

  # Deteccao de estado previo: o que ja existe em $dest e colidiria com a copia.
  $collidingItems = Get-CollidingItems -SourceDir $inner.FullName -DestDir $dest

  if ($collidingItems.Count -eq 0) {
    Write-Host "Pasta destino vazia (sem colisao) - instalando sem backup."
  } else {
    Write-InstallEvent -EventLogPath $EventLog -Phase "backup" -Pct 55 -Message "salvando conteudo anterior"
    $backupDir = Backup-Dest -DestDir $dest -Items $collidingItems
    Write-Host ("[OK] backup do conteudo anterior salvo em: " + $backupDir)
  }

  Write-InstallEvent -EventLogPath $EventLog -Phase "copy" -Pct 75 -Message "copiando o motor"
  try {
    Copy-AliaContent -SourceDir $inner.FullName -DestDir $dest
  } catch {
    Write-Host ("[ERRO] copia falhou no meio: " + $_.Exception.Message)
    Restore-Dest -DestDir $dest -BackupDir $backupDir -Items $collidingItems
    Write-Host "[ROLLBACK] estado anterior restaurado."
    Write-InstallEvent -EventLogPath $EventLog -Phase "rollback" -Pct 90 -Message "restaurando estado anterior"
    Write-InstallEvent -EventLogPath $EventLog -Phase "done" -Pct 100 -Message "instalacao revertida" -Result "rolledback" -Detail ([ordered]@{ dest = $dest; backupDir = $backupDir })
    exit 1
  }
} finally {
  Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-InstallEvent -EventLogPath $EventLog -Phase "done" -Pct 100 -Message "instalado" -Result "ok" -Detail ([ordered]@{ dest = $dest; backupDir = $backupDir; collidingItems = $collidingItems })
Write-Host "[OK] Alia Flow instalado"
if ($backupDir) {
  Write-Host ("      backup do conteudo anterior mantido em: " + $backupDir)
} else {
  Write-Host "      nao houve backup (pasta destino estava vazia)."
}

# Mapa de conhecimento (graphify) - REQUISITO da instalacao (mandato do CEO, 10/08/2026), nao
# mais turbo opcional: sem mapa, todo trabalho no codigo do cliente varre as cegas e gasta muito
# mais token. Cadeia fail-soft (scripts/ensure-graphify.ps1): nunca trava esta instalacao, nunca
# imprime Python/pip/uv/nome de pacote - so a frase abaixo, e se tudo falhar, uma frase honesta.
Write-Host ""
Write-Host "Preparando o mapa de conhecimento do seu projeto (deixa meu trabalho mais rapido e mais barato pra voce)..."
$ensureGraphify = Join-Path $dest "scripts\ensure-graphify.ps1"
if (Test-Path -LiteralPath $ensureGraphify) {
  try { & powershell -ExecutionPolicy Bypass -File $ensureGraphify } catch { }
}

# Estrutura inicial do operador: cria studio/ a partir do modelo (so na primeira vez).
# Ja deixa pastas + config + um exemplo prontos - zero atrito.
$studioDir = Join-Path $dest "studio"
if (-not (Test-Path $studioDir)) {
  $example = Join-Path $dest "studio.example"
  if (Test-Path $example) {
    Copy-Item -Path $example -Destination $studioDir -Recurse -Force
    Write-Host "Estrutura pronta: studio/ criado com um exemplo para voce olhar."
  }
}

Write-Host ""
Write-Host "Pronto. Abrindo a pagina de boas-vindas no seu navegador..."

# Zero atrito: abre o onboarding automaticamente. Sem precisar clicar em nada.
$welcome = Join-Path $dest "onboarding\index.html"
if (Test-Path $welcome) {
  Start-Process $welcome
} else {
  Write-Host "Abra onboarding\index.html no navegador para comecar."
}
Write-Host "Depois e so abrir esta pasta no Claude Code e dizer: pronto."
Write-Host "Cadastre um cliente OU uma ideia - simples assim. A Alia cuida do resto."
Write-Host ""
Write-Host "Precisa de um coding agent? Escolha um e instale (a Alia mora dentro dele):"
Write-Host "  Claude Code : https://claude.com/claude-code"
Write-Host "  Codex       : https://github.com/openai/codex"
Write-Host "  OpenCode    : https://opencode.ai"
