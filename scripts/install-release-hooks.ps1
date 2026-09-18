# install-release-hooks.ps1 - instala o hook pre-push que torna IMPOSSIVEL empurrar sem o
# release-gate.ps1 verde (TASK-617, mandato do CEO, 17/09/2026).
#
# Por que este script existe: o portao (release-gate.ps1) ja existia antes desta Task e foi
# pulado - `git push` rodou por fora dele. O portao sozinho nao evita isso de novo; so um hook
# git IMPEDE o push no ato. `.git/hooks` NUNCA viaja no clone (limitacao do proprio git - hooks
# sao locais, nao versionados), entao este script tem que ser reexecutado toda vez que o
# repositorio do produto for clonado de novo, ou se `.git` for recriado. Documentado tambem em
# docs/INTEGRIDADE.md, secao "Hook pre-push (TASK-617)".
#
# Uso: powershell -File scripts/install-release-hooks.ps1 -Repo <caminho do repo do produto>

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Repo
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Repo -PathType Container)) {
  Write-Host ("[ERRO] pasta do repo nao encontrada: " + $Repo)
  exit 1
}

$repoFull = (Get-Item -LiteralPath $Repo).FullName
$hooksDir = Join-Path $repoFull ".git\hooks"

if (-not (Test-Path -LiteralPath $hooksDir)) {
  Write-Host ("[ERRO] " + $hooksDir + " nao existe - " + $repoFull + " nao parece ser a raiz de um repositorio git")
  exit 1
}

$here = Split-Path -Parent $PSCommandPath
$gateScriptItem = Get-Item -LiteralPath (Join-Path $here "release-gate.ps1")
$gateScriptFwd = $gateScriptItem.FullName -replace '\\', '/'
$repoFullFwd = $repoFull -replace '\\', '/'
$hookPath = Join-Path $hooksDir "pre-push"

$hookLines = @(
  '#!/bin/sh'
  '# Instalado por scripts/install-release-hooks.ps1 (TASK-617) - NAO editar a mao.'
  '# .git/hooks nunca viaja no clone: se este repo for clonado de novo, ou .git for recriado,'
  '# reinstale com: powershell -ExecutionPolicy Bypass -File scripts/install-release-hooks.ps1 -Repo <repo>'
  '# (o script do gate mora na oficina, caminho gravado no ato da instalacao abaixo)'
  ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $gateScriptFwd + '" -Repo "' + $repoFullFwd + '"')
  'STATUS=$?'
  'if [ "$STATUS" -ne 0 ]; then'
  '  echo "release-gate.ps1 REPROVOU - push abortado (TASK-617). Rode o gate a mao para ver o motivo." >&2'
  '  exit 1'
  'fi'
  'exit 0'
)
$hookContent = ($hookLines -join "`n") + "`n"

[System.IO.File]::WriteAllText($hookPath, $hookContent, [System.Text.UTF8Encoding]::new($false))

Write-Host ("[OK] pre-push instalado: " + $hookPath)
Write-Host ("  gate chamado: " + $gateScriptFwd)
Write-Host ("  repo alvo:    " + $repoFullFwd)
exit 0
