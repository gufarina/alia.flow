<#
  ddd-drift.ps1 - Mecanismo do loop agendado ddd-drift-scan (cadence: daily, owner: squad-owner).
  Spec: engine/governance/loops.catalog.yaml (scheduled_loops: ddd-drift-scan).
  Pergunta que responde: ha drift acumulado vs a linguagem ubiqua do Client?
  Le os termos canonicos do glossario (knowledge/ubiquitous-language.md, coluna 1 das linhas de
  tabela) e varre os entregaveis recentes (knowledge/*.md, exceto o proprio glossario e relatorios
  de loop) procurando por Termos Capitalizados de Negocio que NAO estao no glossario - candidatos a
  drift semantico. Frugal: heuristica leve, so o que mudou recentemente. Reporta, nao corrige.
  Escrita .NET UTF-8 sem BOM. Sem acentos, sem emojis. O RSI propoe, o Quality Gate aprova.
#>
param(
  [Parameter(Mandatory = $true)][string]$Client,
  [int]$RecentDays = 30,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "_studio.ps1")
$studioRoot = Get-StudioRoot $root

$knowDir = Join-Path $studioRoot ("clients\" + $Client + "\squad\knowledge")
$glossary = Join-Path $knowDir "ubiquitous-language.md"

$utf8  = New-Object System.Text.UTF8Encoding($false)
$today = (Get-Date).ToString("yyyy-MM-dd")

Write-Host "=== DDD Drift Scan Loop ==="
Write-Host ("client: " + $Client + " | data: " + $today + " | janela: " + $RecentDays + " dia(s)")
Write-Host ("glossario: " + $glossary)
Write-Host ("modo: " + $(if ($DryRun) { "DRY-RUN (so analisa, nao grava relatorio)" } else { "RUN" }))
Write-Host ""

if (-not (Test-Path -LiteralPath $glossary)) {
  Write-Host "[ERRO] ubiquitous-language.md ausente - sem glossario nao ha como medir drift."
  exit 1
}

# Termos canonicos: coluna 1 das linhas de tabela "| Termo | ... |".
$canon = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($ln in ([System.IO.File]::ReadAllText($glossary) -split "`r?`n")) {
  if ($ln -match '^\s*\|\s*([^|]+?)\s*\|') {
    $term = $matches[1].Trim()
    if ($term -and $term -ne "Termo" -and $term -notmatch '^-+$') {
      [void]$canon.Add($term)
      # palavras individuais do termo composto (ex: "Squad Owner" -> Squad, Owner)
      foreach ($w in ($term -split '\s+')) { if ($w.Length -gt 2) { [void]$canon.Add($w) } }
    }
  }
}
Write-Host ("[OK] termos canonicos carregados: " + $canon.Count)

# Stopwords: termos capitalizados comuns que nao sao jargao de negocio.
$stop = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($w in @("A","O","As","Os","E","Em","De","Do","Da","No","Na","Para","Por","Com","Sem",
  "Que","Se","Um","Uma","Ao","Aos","Toda","Todo","Cada","Nao","Sim","Ha","Ja","So","Pra",
  "DDD","RSI","RTF","QA","YAML","JSON","CLI","URL","CEO","UTF","BOM","MIT","PR","CI","Tier","L1","L4",
  "Studio","Alia","Flow","Client","Task","Loop","Gate","Memory","Squad","Engine","Operator")) {
  [void]$stop.Add($w)
}

# Entregaveis recentes (exclui glossario e relatorios de loop).
$cutoff = (Get-Date).AddDays(-$RecentDays)
$deliverables = @(Get-ChildItem -LiteralPath $knowDir -Filter "*.md" -File -Recurse -ErrorAction SilentlyContinue |
  Where-Object {
    $_.FullName -ne $glossary -and
    $_.FullName -notmatch '\\loop-reports\\' -and
    $_.LastWriteTime -ge $cutoff
  })

Write-Host ("[OK] entregaveis recentes na janela: " + $deliverables.Count)
Write-Host ""

# Coleta termos candidatos. Para reduzir falso-positivo (palavra Capitalizada por inicio de frase
# ou jargao em ingles de docs de referencia), so flagamos TERMOS COMPOSTOS: 2+ palavras
# Capitalizadas consecutivas (assinatura de termo de negocio cunhado, ex: "Domain Pack"), quando o
# termo inteiro NAO esta no glossario e nenhuma das palavras e stopword/inicio-de-frase obvio.
$drift = @{}   # termo -> lista de arquivos
foreach ($f in $deliverables) {
  $content = [System.IO.File]::ReadAllText($f.FullName)
  # remove blocos de codigo para reduzir ruido
  $content = [regex]::Replace($content, '(?s)```.*?```', ' ')
  $rel = $f.FullName.Substring($knowDir.Length).TrimStart('\')
  # frase de 2+ palavras Capitalizadas consecutivas
  $mset = [regex]::Matches($content, '\b([A-Z][a-zA-Z]{2,}(?:[ \t]+[A-Z][a-zA-Z]{2,})+)\b')
  foreach ($m in $mset) {
    $term = $m.Groups[1].Value.Trim()
    if ($canon.Contains($term)) { continue }
    # se TODAS as palavras do termo composto sao canonicas ou stopwords, nao e drift novo
    $words = $term -split '[ \t]+'
    $allKnown = $true
    foreach ($w in $words) { if (-not ($canon.Contains($w) -or $stop.Contains($w))) { $allKnown = $false; break } }
    if ($allKnown) { continue }
    if (-not $drift.ContainsKey($term)) { $drift[$term] = New-Object System.Collections.Generic.HashSet[string] }
    [void]$drift[$term].Add($rel)
  }
}

$driftTerms = @($drift.Keys | Sort-Object)
if ($driftTerms.Count -eq 0) {
  Write-Host "[OK] nenhum termo fora do glossario detectado - sem drift aparente."
} else {
  Write-Host ("[ERRO] termos fora do glossario (candidatos a drift): " + $driftTerms.Count)
  foreach ($t in $driftTerms) {
    Write-Host ("    - " + $t + " (em: " + (@($drift[$t]) -join ", ") + ")")
  }
}

Write-Host ""
Write-Host ("Resumo: " + $driftTerms.Count + " termo(s) candidato(s) a drift em " + $deliverables.Count + " entregavel(is).")

if (-not $DryRun) {
  $outDir = Join-Path $knowDir "loop-reports"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $outFile = Join-Path $outDir ($today + "-ddd-drift.md")
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("# DDD Drift Scan - " + $Client + " (" + $today + ")")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("> Mecanismo: scripts/ddd-drift.ps1. Heuristica leve - candidatos, nao veredito.")
  [void]$sb.AppendLine("> Termos canonicos: " + $canon.Count + " | entregaveis na janela: " + $deliverables.Count + " | drift: " + $driftTerms.Count)
  [void]$sb.AppendLine("")
  if ($driftTerms.Count -eq 0) {
    [void]$sb.AppendLine("Nenhum termo fora do glossario detectado.")
  } else {
    [void]$sb.AppendLine("| Termo candidato | Aparece em |")
    [void]$sb.AppendLine("|-----------------|------------|")
    foreach ($t in $driftTerms) {
      [void]$sb.AppendLine("| " + $t + " | " + (@($drift[$t]) -join ", ") + " |")
    }
  }
  [System.IO.File]::WriteAllText($outFile, $sb.ToString(), $utf8)
  Write-Host ("[OK] relatorio: " + $outFile)
}

# Drift e sinal, nao falha de execucao: exit 0 sempre que rodou bem.
exit 0
