<#
  docs-check.ps1 - portao de calibracao da documentacao do Client (LEI 5 de client-truth.md).

  Por que existe (07/09/2026, mandato do CEO): num Client real, o que tinha portao automatico
  (CHANGELOG, catalogo de dados, DESIGN.md) estava em dia e o que NAO tinha ficou pra tras -
  PRD e README de 5 semanas antes, sem saber de 4 features lancadas; ficha do Client (client.md)
  ainda dizia a versao de 2 releases atras. Doc atrasada com cara de fonte curada e PIOR que doc
  nenhuma: a proxima peca nasce errada por causa dela. Isto e falta de CALIBRACAO, nao de
  disciplina - e se calibra com maquina, nao com lembrete.

  O que confere, por Client com `**codePath:**` no clients/<id>/client.md:
    (a) FICHA: a versao publicada do codigo (package.json "version" ou arquivo VERSION do
        codePath) aparece literalmente em client.md. Nao aparece -> [FICHA] (reprova).
    (b) DOCS: cada doc curada (README.md e todo PRD*.md/prd*.md do codePath, mais o que o
        client.md listar em `**docsGate:**`, separado por virgula, relativo ao codePath) foi
        tocada DEPOIS do ultimo release MINOR (x.y.0) registrado no CHANGELOG.md do codePath.
        Data do doc = ultimo commit que o tocou (git) ou mtime (sem git). Doc mais velha que o
        MINOR -> [STALE] (reprova). PATCH nao cobra doc (correcao nao muda produto).
  Client sem codePath, ou codePath sem CHANGELOG -> [N/A], nunca reprova (nao da pra exigir o que
  nao existe). Saida: uma linha por Client + resumo "OK n | FICHA n | STALE n | N/A n".
  exit 0 = nada reprovado; exit 1 = FICHA ou STALE. -Path aponta a raiz da instancia (default: cwd).
  -ClientsDir troca o nome da pasta de Clients (default: "clients"); a fixture usa "fixture-clients"
  pra nao vazar como material de cliente real no check-public-surface.ps1 (07/09/2026).
  Sem acentos, sem emojis. UTF-8 sem BOM.
#>
param(
  [string]$Path = ".",
  [string]$Client = "",
  [string]$ClientsDir = "clients"
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $Path).Path
$clientsDir = Join-Path $root $ClientsDir
if (-not (Test-Path -LiteralPath $clientsDir)) { Write-Host ("[N/A] sem clients/ em " + $root); exit 0 }

function ReadText([string]$p) { return [System.IO.File]::ReadAllText($p) }

function Get-DocDate([string]$file, [string]$repo, [bool]$hasGit) {
  if ($hasGit) {
    $rel = $file.Substring($repo.Length).TrimStart('\','/')
    $d = (& git -C $repo log -1 --format=%cs -- $rel 2>$null)
    if ($d) { return [datetime]::ParseExact(($d -join "").Trim(), "yyyy-MM-dd", $null) }
  }
  return (Get-Item -LiteralPath $file).LastWriteTime.Date
}

$counts = @{ OK = 0; FICHA = 0; STALE = 0; NA = 0 }
$fail = 0
foreach ($dir in (Get-ChildItem -LiteralPath $clientsDir -Directory | Sort-Object Name)) {
  $id = $dir.Name
  if ($Client -and $id -ne $Client) { continue }
  $cm = Join-Path $dir.FullName "client.md"
  if (-not (Test-Path -LiteralPath $cm)) { continue }
  $txt = ReadText $cm
  $m = [regex]::Match($txt, '(?m)^\s*-?\s*\*\*codePath:\*\*\s*(.+?)\s*$')
  if (-not $m.Success) { $counts.NA++; Write-Host ("[N/A]   " + $id + " - sem codePath"); continue }
  # client.md pode anotar o caminho com um parentese depois ("... (criado em ...)"): so o caminho vale.
  $code = ($m.Groups[1].Value -split '\s\(')[0].Trim().TrimEnd('/','\')
  if (-not [System.IO.Path]::IsPathRooted($code)) { $code = Join-Path $dir.FullName $code }   # relativo = a partir da pasta do Client (fixtures)
  if (-not (Test-Path -LiteralPath $code)) { $counts.NA++; Write-Host ("[N/A]   " + $id + " - codePath nao existe: " + $code); continue }
  $code = (Resolve-Path -LiteralPath $code).Path

  # versao publicada do codigo
  $ver = ""
  $pkg = Join-Path $code "package.json"
  $verFile = Join-Path $code "VERSION"
  if (Test-Path -LiteralPath $pkg) {
    $pv = [regex]::Match((ReadText $pkg), '"version"\s*:\s*"([^"]+)"'); if ($pv.Success) { $ver = $pv.Groups[1].Value }
  } elseif (Test-Path -LiteralPath $verFile) { $ver = (ReadText $verFile).Trim() }

  # ultimo MINOR no CHANGELOG do codigo
  $chg = Join-Path $code "CHANGELOG.md"
  if (-not (Test-Path -LiteralPath $chg)) { $counts.NA++; Write-Host ("[N/A]   " + $id + " - codePath sem CHANGELOG.md"); continue }
  $minor = $null; $minorVer = ""
  foreach ($e in [regex]::Matches((ReadText $chg), '(?m)^##\s+\[?v?(\d+)\.(\d+)\.(\d+)\]?\s*-\s*(\d{4}-\d{2}-\d{2})')) {
    if ($e.Groups[3].Value -eq "0") {
      $minor = [datetime]::ParseExact($e.Groups[4].Value, "yyyy-MM-dd", $null)
      $minorVer = $e.Groups[1].Value + "." + $e.Groups[2].Value + ".0"; break
    }
  }
  if ($null -eq $minor) { $counts.NA++; Write-Host ("[N/A]   " + $id + " - CHANGELOG sem release MINOR datado"); continue }

  $problems = @()
  # (a) ficha
  if ($ver -and -not [regex]::IsMatch($txt, '(?<!\d)' + [regex]::Escape($ver) + '(?!\d)')) { $problems += ("FICHA: client.md nao cita a versao publicada " + $ver) }

  # (b) docs
  $hasGit = Test-Path -LiteralPath (Join-Path $code ".git")
  $docs = @()
  $rd = Join-Path $code "README.md"; if (Test-Path -LiteralPath $rd) { $docs += $rd }
  # PRD so na raiz e em docs/ (nunca varre node_modules - medido: varredura recursiva do codePath
  # inteiro passava de 2 minutos num Client real).
  foreach ($base in @($code, (Join-Path $code "docs"))) {
    if (Test-Path -LiteralPath $base) {
      $docs += @(Get-ChildItem -LiteralPath $base -File -Filter "*.md" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(?i)prd' } | ForEach-Object { $_.FullName })
    }
  }
  $dg = [regex]::Match($txt, '(?m)^\s*-?\s*\*\*docsGate:\*\*\s*(.+?)\s*$')
  if ($dg.Success) {
    foreach ($rel in ($dg.Groups[1].Value -split ',')) {
      $p = Join-Path $code $rel.Trim(); if (Test-Path -LiteralPath $p) { $docs += (Resolve-Path -LiteralPath $p).Path } else { $problems += ("STALE: docsGate aponta arquivo inexistente " + $rel.Trim()) }
    }
  }
  $stale = @()
  foreach ($d in ($docs | Sort-Object -Unique)) {
    $dd = Get-DocDate $d $code $hasGit
    if ($dd -lt $minor) { $stale += ($d.Substring($code.Length).TrimStart('\','/') + " (" + $dd.ToString("yyyy-MM-dd") + ")") }
  }
  if ($stale.Count -gt 0) { $problems += ("STALE: " + $stale.Count + " doc(s) mais velha(s) que o release " + $minorVer + " de " + $minor.ToString("yyyy-MM-dd") + ": " + ($stale -join ", ")) }

  if ($problems.Count -eq 0) {
    $counts.OK++; Write-Host ("[OK]    " + $id + " - v" + $ver + ", " + $docs.Count + " doc(s) em dia desde " + $minorVer)
  } else {
    $fail++
    $tag = if ($problems[0].StartsWith("FICHA")) { "FICHA" } else { "STALE" }
    $counts[$tag]++
    Write-Host ("[" + $tag + "] " + $id + " - " + ($problems -join " | "))
  }
}
Write-Host ("Docs-gate: OK " + $counts.OK + " | FICHA " + $counts.FICHA + " | STALE " + $counts.STALE + " | N/A " + $counts.NA)
if ($fail -gt 0) { exit 1 } else { exit 0 }
