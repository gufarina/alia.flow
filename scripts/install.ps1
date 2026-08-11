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

  Sem acentos, sem emojis. UTF-8 sem BOM.
#>
$ErrorActionPreference = "Stop"

# Repo publico do Alia Flow (open source). Branch main.
$repo   = "gufarina/alia.flow"
$branch = "main"
$zip    = "https://github.com/$repo/archive/refs/heads/$branch.zip"
$dest   = (Get-Location).Path

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

# Se o script foi apenas "dot-sourced" para testar as funcoes acima, para aqui.
if ($env:ALIA_INSTALL_TEST_ONLY -eq "1") {
  return
}

# ---------------------------------------------------------------------------
# Fluxo real de instalacao
# ---------------------------------------------------------------------------

Write-Host "Alia - baixando e instalando nesta pasta..."
$tmpZip = Join-Path $env:TEMP ("alia-" + [System.Guid]::NewGuid().ToString("N") + ".zip")
$tmpDir = Join-Path $env:TEMP ("alia-x-" + [System.Guid]::NewGuid().ToString("N"))
$backupDir = $null
$collidingItems = @()

try {
  try {
    Invoke-WebRequest -UseBasicParsing -Uri $zip -OutFile $tmpZip
  } catch {
    Write-Host ("[ERRO] download falhou (rede/URL): " + $_.Exception.Message)
    exit 1
  }

  try {
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
  } catch {
    Write-Host ("[ERRO] extracao falhou (zip corrompido?): " + $_.Exception.Message)
    exit 1
  }

  # O zip do GitHub tem uma pasta raiz (ex: alia-flow-main/). O conteudo dela vai pra $dest.
  $inner = Get-ChildItem -Directory $tmpDir | Select-Object -First 1

  # Deteccao de estado previo: o que ja existe em $dest e colidiria com a copia.
  $collidingItems = Get-CollidingItems -SourceDir $inner.FullName -DestDir $dest

  if ($collidingItems.Count -eq 0) {
    Write-Host "Pasta destino vazia (sem colisao) - instalando sem backup."
  } else {
    $backupDir = Backup-Dest -DestDir $dest -Items $collidingItems
    Write-Host ("[OK] backup do conteudo anterior salvo em: " + $backupDir)
  }

  try {
    Copy-AliaContent -SourceDir $inner.FullName -DestDir $dest
  } catch {
    Write-Host ("[ERRO] copia falhou no meio: " + $_.Exception.Message)
    Restore-Dest -DestDir $dest -BackupDir $backupDir -Items $collidingItems
    Write-Host "[ROLLBACK] estado anterior restaurado."
    exit 1
  }
} finally {
  Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

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
