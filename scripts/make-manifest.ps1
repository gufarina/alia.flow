# Alia Flow - Make Manifest (integridade do pacote, supply-chain leve)
# Gera MANIFEST.sha256 na raiz de uma pasta: uma linha por arquivo, no formato
# "<sha256>  <caminho relativo>" (padrao sha256sum), ordenado por caminho.
# Exclui o proprio MANIFEST.sha256, .git e studio/ (regra em _manifest-exclude.ps1, TASK-567).
# Isto e um manifesto de INTEGRIDADE (hash), nao de autenticidade de origem (PKI).
# Ver docs/INTEGRIDADE.md.
#
# TASK-618 (mandato do CEO, 17/09/2026): se $Dir e um repositorio git, a lista de arquivos vem de
# `git ls-files` (o que sera PUBLICADO), nao de Get-ChildItem no disco. Causa raiz medida: o disco
# pode ter arquivo que o git nunca vai empacotar (ex.: .opencode/.gitignore se auto-ignora - "git
# check-ignore -v" confirma - e o ZIP do GitHub nunca o entrega), e o manifesto antigo prometia um
# arquivo que o pacote publicado nao continha. Fora de um repo git, o comportamento antigo
# (Get-ChildItem no disco) continua valendo.
# UTF-8 sem BOM.

param(
  [Parameter(Mandatory)][string]$Dir,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
  Write-Host ("[ERRO] pasta nao encontrada: " + $Dir)
  exit 1
}

$dirFull = (Get-Item -LiteralPath $Dir).FullName
$manifestPath = Join-Path $dirFull "MANIFEST.sha256"

function WriteAsciiFile([string]$path, [string]$content) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

. (Join-Path $PSScriptRoot "_manifest-exclude.ps1")

$isGitRepo = $false
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
& git -C $dirFull rev-parse --is-inside-work-tree 1>$null 2>$null
if ($LASTEXITCODE -eq 0) { $isGitRepo = $true }
$ErrorActionPreference = $prevEap

$entries = @()

if ($isGitRepo) {
  $relPaths = & git -C $dirFull ls-files |
    Where-Object { -not (Test-ManifestExcluded $_) }
  foreach ($rel in $relPaths) {
    $full = Join-Path $dirFull ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    $hash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLower()
    $entries += [PSCustomObject]@{ path = $rel; sha256 = $hash }
  }
} else {
  $files = Get-ChildItem -LiteralPath $dirFull -Recurse -File -Force |
    Where-Object {
      $rel = $_.FullName.Substring($dirFull.Length).TrimStart('\', '/')
      -not (Test-ManifestExcluded $rel)
    }
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($dirFull.Length).TrimStart('\', '/') -replace '\\', '/'
    $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
    $entries += [PSCustomObject]@{ path = $rel; sha256 = $hash }
  }
}

$entries = $entries | Sort-Object -Property path

$lines = foreach ($e in $entries) { $e.sha256 + "  " + $e.path }
WriteAsciiFile $manifestPath (($lines -join "`n") + "`n")

if ($Json) {
  $result = [PSCustomObject]@{
    dir      = $dirFull
    manifest = $manifestPath
    total    = $entries.Count
  }
  $result | ConvertTo-Json -Depth 3
} else {
  Write-Host "=== Alia Flow Make Manifest ==="
  Write-Host ("  pasta:     " + $dirFull)
  Write-Host ("  manifesto: " + $manifestPath)
  Write-Host ("  arquivos:  " + $entries.Count)
  Write-Host ""
  Write-Host ("[OK] manifesto gerado: " + $entries.Count + " arquivos")
}

exit 0
