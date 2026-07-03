<#
  install.ps1 - instala o Alia Flow na pasta atual (o "copia uma linha").
  O usuario cola UMA linha no Claude Code (ou no PowerShell), dentro de uma pasta vazia:

    iwr -useb https://raw.githubusercontent.com/gufarina/alia.flow/main/scripts/install.ps1 | iex

  Baixa o Alia Flow e descompacta aqui. Depois e so abrir esta pasta no Claude Code e dizer: pronto.
  Nao precisa de git nem de Python - so o PowerShell (ja vem no Windows).
  Precisa de um coding agent (Claude Code, Codex ou OpenCode) - links no fim.
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

Write-Host "Alia - baixando e instalando nesta pasta..."
$tmpZip = Join-Path $env:TEMP ("alia-" + [System.Guid]::NewGuid().ToString("N") + ".zip")
$tmpDir = Join-Path $env:TEMP ("alia-x-" + [System.Guid]::NewGuid().ToString("N"))
Invoke-WebRequest -UseBasicParsing -Uri $zip -OutFile $tmpZip
Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

# O zip do GitHub tem uma pasta raiz (ex: alia-flow-main/). Move o conteudo dela pra ca.
$inner = Get-ChildItem -Directory $tmpDir | Select-Object -First 1
Copy-Item -Path (Join-Path $inner.FullName "*") -Destination $dest -Recurse -Force
Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

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
