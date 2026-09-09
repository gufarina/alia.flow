# Alia Flow - Make Manifest (integridade do pacote, supply-chain leve)
# Gera MANIFEST.sha256 na raiz de uma pasta: uma linha por arquivo, no formato
# "<sha256>  <caminho relativo>" (padrao sha256sum), ordenado por caminho.
# Exclui o proprio MANIFEST.sha256 e qualquer coisa dentro de .git.
# Isto e um manifesto de INTEGRIDADE (hash), nao de autenticidade de origem (PKI).
# Ver docs/INTEGRIDADE.md.
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

$files = Get-ChildItem -LiteralPath $dirFull -Recurse -File -Force |
  Where-Object {
    $rel = $_.FullName.Substring($dirFull.Length).TrimStart('\', '/')
    ($rel -ne "MANIFEST.sha256") -and ($rel -notmatch '(^|[\\/])\.git([\\/]|$)')
  }

$entries = @()
foreach ($f in $files) {
  $rel = $f.FullName.Substring($dirFull.Length).TrimStart('\', '/') -replace '\\', '/'
  $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
  $entries += [PSCustomObject]@{ path = $rel; sha256 = $hash }
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
