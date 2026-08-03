# Alia Flow - Doctor (diagnostico read-only)
# Diagnostico read-only da instalacao do Alia Flow - confere estrutura e roda o trilho.
# Nao modifica nada. Autocura (--fix) fica para depois.
# Sem acentos, sem emojis. UTF-8 sem BOM.

param([switch]$Json)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot          # raiz do alia/
$engine = Join-Path $root "engine"

$script:checks = @()

function Check([string]$name, [bool]$ok) {
  $script:checks += [PSCustomObject]@{ name = $name; ok = $ok }
}

# 1. Nucleo do engine presente
$nucleoFiles = @(
  "constitution.md",
  "glossary.md",
  "orchestration.md",
  "MAP.md",
  "agents\persona.md"
)
$nucleoOk = $true
foreach ($f in $nucleoFiles) {
  if (-not (Test-Path (Join-Path $engine $f))) { $nucleoOk = $false }
}
Check "Nucleo do engine presente" $nucleoOk

# 2. Pastas do engine presentes
$engineFolders = @("agents", "features", "governance", "workflows")
$foldersOk = $true
foreach ($f in $engineFolders) {
  if (-not (Test-Path (Join-Path $engine $f) -PathType Container)) { $foldersOk = $false }
}
Check "Pastas do engine presentes" $foldersOk

# 3. VERSION existe e nao esta vazio
$versionPath = Join-Path $root "VERSION"
$version = ""
$versionOk = $false
if (Test-Path $versionPath) {
  $version = (Get-Content $versionPath -Raw).Trim()
  if ($version.Length -gt 0) { $versionOk = $true }
}
Check "VERSION existe e nao esta vazio" $versionOk

# 4. VERSION bate com o topo do CHANGELOG.md
$changelogPath = Join-Path $root "CHANGELOG.md"
$changelogOk = $false
if ((Test-Path $changelogPath) -and $versionOk) {
  $changelogLines = Get-Content $changelogPath
  $topEntry = $changelogLines | Where-Object { $_ -match '^\s*##\s*\[([^\]]+)\]' } | Select-Object -First 1
  if ($topEntry -match '^\s*##\s*\[([^\]]+)\]') {
    $changelogVersion = $matches[1].Trim()
    if ($changelogVersion -eq $version) { $changelogOk = $true }
  }
}
Check "VERSION bate com o topo do CHANGELOG" $changelogOk

# 5. alia.config.json existe e e JSON valido
$configPath = Join-Path $root "alia.config.json"
$configOk = $false
if (Test-Path $configPath) {
  try {
    Get-Content $configPath -Raw | ConvertFrom-Json | Out-Null
    $configOk = $true
  } catch {
    $configOk = $false
  }
}
Check "alia.config.json existe e e JSON valido" $configOk

# 6. Scripts essenciais presentes
$essentialScripts = @("smoke-test.ps1", "package-release.ps1", "install.ps1")
$scriptsOk = $true
foreach ($s in $essentialScripts) {
  if (-not (Test-Path (Join-Path $PSScriptRoot $s))) { $scriptsOk = $false }
}
Check "Scripts essenciais presentes" $scriptsOk

# 7. Roda o smoke (check mais pesado - por ultimo)
$smokeGreen = $false
try {
  & (Join-Path $PSScriptRoot "smoke-test.ps1") *> $null
  $smokeGreen = ($LASTEXITCODE -eq 0)
} catch {
  $smokeGreen = $false
}
Check "Smoke test verde" $smokeGreen

$okCount = ($script:checks | Where-Object { $_.ok }).Count
$failCount = ($script:checks | Where-Object { -not $_.ok }).Count
$healthy = ($failCount -eq 0) -and $smokeGreen

if ($Json) {
  $result = [PSCustomObject]@{
    version    = $version
    checks     = $script:checks
    smokeGreen = $smokeGreen
    healthy    = $healthy
  }
  $result | ConvertTo-Json -Depth 5
} else {
  Write-Host "=== Alia Flow Doctor ==="
  foreach ($c in $script:checks) {
    if ($c.ok) {
      Write-Host ("[OK] " + $c.name)
    } else {
      Write-Host ("[FALHA] " + $c.name)
    }
  }
  Write-Host ""
  Write-Host ("$okCount OK, $failCount falhas")
  if ($healthy) {
    Write-Host "SAUDAVEL"
  } else {
    Write-Host "PROBLEMAS ENCONTRADOS"
  }
}

if ($healthy) { exit 0 } else { exit 1 }
