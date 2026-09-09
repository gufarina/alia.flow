<#
  kb-index.ps1 - Indice mestre do segundo cerebro de um Client (OPP-69, estrategia de leitura).
  Monta o "repo-map de markdown": uma linha por doc do knowledge (titulo + assinatura de 1 linha),
  para a Alia decidir o que abrir SEM varrer os arquivos. Espelha o padrao do engine/MAP.md.

  Dois modos:
    (gerar, default) escreve knowledge/MAP.md com o indice.
    -Validate        so confere: exit 1 se o indice estourar o teto (-BudgetLines) ou se algum doc
                     top-level nao tiver assinatura (blockquote '> ...' logo abaixo do titulo).

  Assinatura = titulo '# ...' + primeira linha '> ...' (outline-first). Docs sem assinatura sao
  ilegiveis por indice - a regra reprova. Ignora o proprio MAP.md e subpastas (expert-minds/,
  graphify-out/, examples/): o indice e dos docs de contexto top-level.

  Uso:  powershell -ExecutionPolicy Bypass -File scripts/kb-index.ps1 -KnowledgePath <dir> [-Validate] [-BudgetLines 80]
  Escrita .NET UTF-8 sem BOM.
#>
param(
  [Parameter(Mandatory=$true)][string]$KnowledgePath,
  [switch]$Validate,
  [int]$BudgetLines = 80
)
$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath $KnowledgePath)) {
  Write-Host ("[ERRO] knowledge nao encontrado: " + $KnowledgePath)
  exit 1
}

function ReadText([string]$p) { return [System.IO.File]::ReadAllText($p, $utf8) }

$docs = Get-ChildItem -Path $KnowledgePath -Filter *.md -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -ne "MAP.md" } | Sort-Object Name

$rows = @()
$noSig = @()
foreach ($d in $docs) {
  $txt = ReadText $d.FullName
  $titleM = [regex]::Match($txt, '(?m)^\#\s+(.+?)\s*$')
  $sigM   = [regex]::Match($txt, '(?m)^\>\s+(.+?)\s*$')
  $title = if ($titleM.Success) { $titleM.Groups[1].Value } else { $d.BaseName }
  $sig   = if ($sigM.Success) { $sigM.Groups[1].Value } else { "" }
  if ($sig -eq "") { $noSig += $d.Name }
  # 1 linha por doc: nome do arquivo - titulo - assinatura curta.
  $sigShort = if ($sig.Length -gt 90) { $sig.Substring(0,88) + ".." } else { $sig }
  $rows += ("- [" + $d.Name + "](" + $d.Name + ") - " + $title + $(if ($sigShort -ne "") { " - " + $sigShort } else { "" }))
}

# Monta o conteudo do indice.
$header = @(
  "# MAP - indice do segundo cerebro",
  "",
  "> Indice mestre deste Client (kb-index.ps1). Uma linha por doc: leia AQUI para decidir o que abrir,",
  "> nao varra a pasta. Regeneravel - nunca editar na mao. Ver engine/reading-strategy.md.",
  ""
)
$content = ($header + $rows) -join "`r`n"
$lineCount = ($header.Count + $rows.Count)

if ($Validate) {
  $bad = @()
  if ($noSig.Count -gt 0) { $bad += ("docs sem assinatura: " + ($noSig -join ", ")) }
  if ($lineCount -gt $BudgetLines) { $bad += ("indice com " + $lineCount + " linhas > teto " + $BudgetLines) }
  if ($bad.Count -gt 0) {
    Write-Host ("[FAIL] indice invalido -> " + ($bad -join " | "))
    exit 1
  }
  Write-Host ("[PASS] indice valido: " + $rows.Count + " docs, " + $lineCount + " linhas (teto " + $BudgetLines + ").")
  exit 0
}

$outFile = Join-Path $KnowledgePath "MAP.md"
[System.IO.File]::WriteAllText($outFile, $content + "`r`n", $utf8)
Write-Host ("=== kb-index gerado ===")
Write-Host ("docs: " + $rows.Count + " | linhas: " + $lineCount + " | saida: " + $outFile)
exit 0
