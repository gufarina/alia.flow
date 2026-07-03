# _studio.ps1 - resolve a pasta de dados (o "studio") a partir do alia.config.json.
# O engine nunca crava "studio/": le o caminho do campo studio_dir na config.
#   studio_dir = "."       => os dados ficam na RAIZ da instalacao (ao lado do engine).
#   studio_dir = "studio"  => os dados ficam numa subpasta (padrao do produto / lab).
# Default "studio" quando a config nao existe ou nao traz o campo. Sem acentos, sem emojis.
function Get-StudioRoot {
  param([Parameter(Mandatory = $true)][string]$Root)
  $studioDir = "studio"
  $cfgPath = Join-Path $Root "alia.config.json"
  if (Test-Path -LiteralPath $cfgPath) {
    try {
      $cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
      $val = "$($cfg.studio_dir)".Trim()
      if ($val -ne "") { $studioDir = $val }
    } catch {}
  }
  if ($studioDir -eq "." -or $studioDir -eq "./" -or $studioDir -eq ".\") { return $Root }
  return (Join-Path $Root $studioDir)
}
