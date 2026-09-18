<#
  rsi-promote-pattern.ps1 - o elo que faltava entre PECA 3 (deteccao, rsi-patterns.ps1) e PECA 1
  (portao, rsi-apply.ps1). Depois do SIM do operador sobre um bucket de um relatorio de padrao
  (memory/_proposals/patterns-<data>.md), monta o ESQUELETO do candidato em
  engine/rsi/_candidates/<slug>/manifest.md - so o manifesto (o que muda, por que, como reverter,
  qual padrao originou). NUNCA escreve proposed/test.ps1 (isso exige decidir a mudanca de verdade,
  trabalho de quem escreve a proposta), NUNCA promove, NUNCA aplica - e o rsi-apply.ps1 (portao de
  6 passos) que aplica depois, sem alteracao nenhuma neste script.

  Uso:
    scripts/rsi-promote-pattern.ps1 -ReportPath <memory/_proposals/patterns-*.md> -Bucket "<nome do ## bucket>" -Slug <slug-do-candidato> [-What <texto>] [-Why <texto>] [-Target <caminho>]

  -Slug so [a-z0-9-]. Pasta ja existente = erro (nao sobrescreve). "como reverter" pra este estagio
  e sempre o mesmo (apagar a pasta do candidato - nada foi promovido ainda), gravado no manifesto.
  UTF-8 sem BOM. exit 0 = candidato criado; exit 1 = erro (bucket nao achado, slug invalido, pasta
  ja existe).
#>
param(
  [Parameter(Mandatory=$true)][string]$ReportPath,
  [Parameter(Mandatory=$true)][string]$Bucket,
  [Parameter(Mandatory=$true)][string]$Slug,
  [string]$What = "",
  [string]$Why = "",
  [string]$Target = "",
  [string]$Root = ""
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$utf8 = New-Object System.Text.UTF8Encoding($false)

if ($Slug -notmatch '^[a-z0-9][a-z0-9-]*$') {
  Write-Host "[ERRO] -Slug so aceita [a-z0-9-], comecando por letra/numero."
  exit 1
}
if (-not (Test-Path -LiteralPath $ReportPath)) {
  Write-Host ("[ERRO] relatorio de padrao nao encontrado: " + $ReportPath)
  exit 1
}
# TASK-511: o manifesto NUNCA grava caminho absoluto de maquina. Medido: o candidato gerado hoje
# citava o caminho completo da pasta do operador e o guarda da superficie publica REPROVOU o pacote
# inteiro no passo 3/3 - candidato de RSI viaja para o produto. Aqui o caminho vira relativo a raiz
# do repo (ou so o nome do arquivo, se estiver fora dela).
$repoRootLocal = Split-Path -Parent $PSScriptRoot
$reportRel = $ReportPath
try {
  $full = (Resolve-Path -LiteralPath $ReportPath -ErrorAction Stop).Path
  $rootFull = (Resolve-Path -LiteralPath $repoRootLocal -ErrorAction Stop).Path
  if ($full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    $reportRel = $full.Substring($rootFull.Length).TrimStart('\\', '/').Replace('\\', '/')
  } else {
    $reportRel = Split-Path -Leaf $full
  }
} catch { $reportRel = Split-Path -Leaf $ReportPath }

$reportLines = [System.IO.File]::ReadAllLines($ReportPath)
$bucketLine = $null
foreach ($ln in $reportLines) {
  if ($ln -match "^##\s*(.+)$") {
    $sectionTitle = $matches[1].Trim()
    if ($sectionTitle.StartsWith($Bucket)) { $bucketLine = $sectionTitle; break }
  }
}
if ($null -eq $bucketLine) {
  Write-Host ("[ERRO] bucket '" + $Bucket + "' nao encontrado em " + $ReportPath + " - confira o titulo exato da secao '## ...' no relatorio.")
  exit 1
}

$candidateDir = Join-Path $Root ("engine/rsi/_candidates/" + $Slug)
if (Test-Path -LiteralPath $candidateDir) {
  Write-Host ("[ERRO] candidato ja existe: " + $candidateDir + " - escolha outro -Slug ou apague a pasta antes.")
  exit 1
}

$whatOut = if ([string]::IsNullOrWhiteSpace($What)) { "A DEFINIR - preencher antes de rodar rsi-apply.ps1 (o que exatamente muda no arquivo alvo)." } else { $What }
$whyOut  = if ([string]::IsNullOrWhiteSpace($Why))  { "A DEFINIR - preencher antes de rodar rsi-apply.ps1 (por que este padrao justifica a mudanca)." } else { $Why }
$targetOut = if ([string]::IsNullOrWhiteSpace($Target)) { "A DEFINIR" } else { $Target }
$today = (Get-Date).ToString("yyyy-MM-dd")

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("target: " + $targetOut)
[void]$sb.AppendLine("what: " + $whatOut)
[void]$sb.AppendLine("why: " + $whyOut)
[void]$sb.AppendLine("motivated_by: " + $reportRel + " | " + $bucketLine)
[void]$sb.AppendLine("promoted_on: " + $today)
[void]$sb.AppendLine("status: staged")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("# Candidato " + $Slug + " - staged em " + $today)
[void]$sb.AppendLine("")
[void]$sb.AppendLine("> Criado por scripts/rsi-promote-pattern.ps1 apos SIM do operador sobre o padrao abaixo.")
[void]$sb.AppendLine("> Faltam proposed/ e test.ps1 (quem escreve a mudanca de verdade preenche) antes de")
[void]$sb.AppendLine("> este candidato poder rodar por scripts/rsi-apply.ps1 -Candidate " + $Slug + ".")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Padrao que originou")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("- relatorio: " + $reportRel)
[void]$sb.AppendLine("- bucket: " + $bucketLine)
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Como reverter")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Nada foi promovido ainda (status: staged) - reverter e so apagar esta pasta:")
[void]$sb.AppendLine("engine/rsi/_candidates/" + $Slug)
[void]$sb.AppendLine("Se um dia isto for promovido por rsi-apply.ps1, o rollback vira -Rollback " + $Slug + " (registrado em engine/rsi/_archive/LINEAGE.md).")

New-Item -ItemType Directory -Force -Path $candidateDir | Out-Null
$manifestPath = Join-Path $candidateDir "manifest.md"
[System.IO.File]::WriteAllText($manifestPath, $sb.ToString(), $utf8)
Write-Host ("[OK] candidato staged: " + $manifestPath)
Write-Host ("     bucket: " + $bucketLine)
Write-Host "[OK] NADA foi promovido/aplicado - preencha proposed/+test.ps1 e so entao rode rsi-apply.ps1."
exit 0
