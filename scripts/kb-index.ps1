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

  TASK-587/TASK-588 (Etapa 2, contrato do LATTICE, corrigido apos medicao): na MESMA chamada,
  tambem escreve edges.json - indice ESTRUTURAL de arestas doc->doc, nasce de parser (custo de
  modelo ZERO), nunca substitui o mapa semantico do graphify (nome/pasta graphify-out/ e graph.json
  sao reservados a ele). Cinco vias, cada aresta com proveniencia (from + from_line), sem
  peso/score gravado - grau de entrada e CALCULADO por quem le, nunca armazenado aqui. MEDIDO
  (TASK-588): contar "to" bruto (toda linha) infla doc que so repete a mesma mencao varias vezes;
  contar por PAR UNICO from->to (uma origem conta 1x por alvo, nao 1x por linha) bate muito mais
  perto do numero de referencia do LATTICE - e o jeito certo de calcular grau aqui:
    (a) mencao de caminho em texto de corpo, resolvida contra o disco - a de MAIOR SINAL.
    (b) link markdown [texto](alvo).
    (c) mencao de caminho dentro de uma linha de heading (mesmo regex da via a, so linha "# ...").
    (d) campo de frontmatter YAML (--- ... --- no topo do doc) cujo valor bate o regex de caminho.
    (e) wikilink [[alvo]] no corpo do doc (TASK-633, FURO B) - resolve SO contra a pasta do doc de
        origem (alvo ou alvo.md), nunca contra a raiz do lab: wikilink e convencao de nota curta
        entre vizinhos da mesma pasta, nao caminho de projeto.
  Via (a)/(c)/(d) casam o token `[\w./-]+\.(md|ps1|yaml|json|yml)` e resolvem, nesta ordem, contra
  (i) a pasta do doc de origem e (ii) a raiz do lab (`Split-Path -Parent $PSScriptRoot`) - primeiro
  que existir em disco vence. Via (e) casa `\[\[([^\]]+)\]\]` e resolve so contra a pasta do doc de
  origem (sem fallback de raiz). Mencao que NAO resolve nao vira aresta (e nao gera aviso). Array
  final ordenado por GRAU de entrada (PageRank fora de escopo, proibido); corte de topo e politica
  de quem consome, nao deste artefato.

  Duas formas de apontar a pasta (MESMO parametro generalizado, sem script novo):
    -KnowledgePath <dir>  legado, 1 pasta so, caminho como foi passado (relativo ao cwd ou
                          absoluto) - inalterado, mesmo comportamento de sempre (compat com
                          squad-bridge.ps1). MAP.md e -Validate SO existem neste modo (indice de
                          1 Client). edges.json sai DENTRO da propria pasta (como hoje).
    -Roots <lista>        1+ pastas, SEMPRE resolvidas relativas a raiz do lab. Generalizacao para
                          escopo cruzado (o motor inteiro = varias pastas). Exige -EdgesOnly (nao
                          ha "MAP.md" de multiplas pastas). edges.json sai em engine/governance/
                          (decisao do LATTICE: raiz limpa reprova arquivo solto na raiz do lab, e
                          governance/ ja abriga o persistence-catalog, que por precedente cataloga
                          artefato que vive FORA de engine/) - arquivo UNICO mesmo com N roots,
                          porque aresta CRUZADA entre pastas (ex. engine/orchestration.md citando
                          skills/delegate/SKILL.md) e o sinal que a via (a) existe pra capturar; um
                          edges.json por pasta faria essa aresta nao aparecer em lugar nenhum. NAO
                          propaga no pacote (package-release.ps1 exclui explicitamente) - cada
                          instancia regenera o seu proprio ao rodar o smoke, nunca uma foto
                          congelada do lab.

  Flags:
    -Recurse   varre .md recursivamente a partir de cada pasta (default: so top-level).
    -EdgesOnly so escreve edges.json, NUNCA encosta em MAP.md (prosa curada a mao - regenerar a
               lista automatica destruiria o doc). Invocacao do motor inteiro:
               kb-index.ps1 -Roots engine,docs,skills -Recurse -EdgesOnly -> engine/governance/edges.json

  Uso:  powershell -ExecutionPolicy Bypass -File scripts/kb-index.ps1 (-KnowledgePath <dir> | -Roots <p1>,<p2>...) [-Validate] [-BudgetLines 80] [-Recurse] [-EdgesOnly]
  Escrita .NET UTF-8 sem BOM.
#>
param(
  [string]$KnowledgePath,
  [string[]]$Roots,
  [switch]$Validate,
  [int]$BudgetLines = 80,
  [switch]$Recurse,
  [switch]$EdgesOnly
)
$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$root = Split-Path -Parent $PSScriptRoot

if ((-not $KnowledgePath) -and (-not $Roots -or $Roots.Count -eq 0)) {
  Write-Host "[ERRO] informe -KnowledgePath <dir> ou -Roots <p1>,<p2>,..."
  exit 1
}
if ($Roots -and $Roots.Count -gt 0 -and -not $EdgesOnly) {
  Write-Host "[ERRO] -Roots exige -EdgesOnly (nao ha MAP.md de multiplas pastas - use -KnowledgePath para gerar MAP.md de 1 Client)"
  exit 1
}
if ($Roots -and $Roots.Count -gt 0 -and $Validate) {
  Write-Host "[ERRO] -Roots nao tem modo -Validate (validacao de MAP.md e por Client, 1 pasta - use -KnowledgePath)"
  exit 1
}

# Normaliza para uma lista de pastas resolvidas em disco. -Roots e sempre relativo a raiz do lab;
# -KnowledgePath mantem o comportamento legado (relativo ao cwd ou absoluto, como sempre foi).
$rootFolders = @()
if ($Roots -and $Roots.Count -gt 0) {
  foreach ($r in $Roots) {
    $p = if ([System.IO.Path]::IsPathRooted($r)) { $r } else { Join-Path $root $r }
    $rootFolders += $p
  }
} else {
  $rootFolders += $KnowledgePath
}
foreach ($p in $rootFolders) {
  if (-not (Test-Path -LiteralPath $p)) {
    Write-Host ("[ERRO] knowledge nao encontrado: " + $p)
    exit 1
  }
}

function ReadText([string]$p) { return [System.IO.File]::ReadAllText($p, $utf8) }

$excludeSubpathRe = '[\\/](expert-minds|graphify-out|examples)[\\/]'
$allMd = @()
foreach ($p in $rootFolders) {
  if ($Recurse) {
    $allMd += Get-ChildItem -Path $p -Filter *.md -File -Recurse -ErrorAction SilentlyContinue
  } else {
    $allMd += Get-ChildItem -Path $p -Filter *.md -File -ErrorAction SilentlyContinue
  }
}
$docs = $allMd |
  Where-Object { $_.Name -ne "MAP.md" -and ($_.FullName -notmatch $excludeSubpathRe) } |
  Sort-Object FullName -Unique

# ---------- TASK-587 (Etapa 2): arestas estruturais (edges.json) ----------
# So roda fora de -Validate: -Validate e modo de CONFERENCIA (nunca escreve nada, contrato
# pre-existente) - gerar edges.json ali seria efeito colateral que ninguem pediu.
if (-not $Validate) {
function ToRootRel([string]$absPath) {
  $full = (Resolve-Path -LiteralPath $absPath).ProviderPath
  $rootFull = (Resolve-Path -LiteralPath $root).ProviderPath
  $rel = $full
  if ($full.Length -gt $rootFull.Length -and $full.Substring(0, $rootFull.Length).ToLowerInvariant() -eq $rootFull.ToLowerInvariant()) {
    $rel = $full.Substring($rootFull.Length).TrimStart('\', '/')
  }
  return $rel.Replace('\', '/')
}

function Resolve-Token([string]$token, [string]$docDir) {
  try {
    $c1 = Join-Path $docDir $token
    if (Test-Path -LiteralPath $c1 -PathType Leaf) { return (ToRootRel $c1) }
  } catch { }
  try {
    $c2 = Join-Path $root $token
    if (Test-Path -LiteralPath $c2 -PathType Leaf) { return (ToRootRel $c2) }
  } catch { }
  return $null
}

$rePath = '[\w./-]+\.(?:md|ps1|yaml|json|yml)'
$reLink = '\[[^\]]*\]\(([^)]+)\)'
$reHeading = '^#{1,6}\s'
$reWiki = '\[\[([^\]]+)\]\]'

$edges = New-Object System.Collections.Generic.List[object]
foreach ($d in $docs) {
  $txt = ReadText $d.FullName
  $relFrom = ToRootRel $d.FullName
  $docDir = Split-Path -Parent $d.FullName
  $lines = $txt -split "`r?`n"

  for ($i = 0; $i -lt $lines.Count; $i++) {
    $ln = $lines[$i]
    $lineNo = $i + 1
    $isHeading = $ln -match $reHeading

    # vias (a)/(c): mencao de caminho - corpo vira 'a', dentro de heading vira 'c'.
    foreach ($mm in [regex]::Matches($ln, $rePath)) {
      $token = $mm.Value
      $resolved = Resolve-Token $token $docDir
      if ($null -ne $resolved -and $resolved -ne $relFrom) {
        $via = if ($isHeading) { 'c' } else { 'a' }
        $edges.Add([pscustomobject]@{ via = $via; from = $relFrom; from_line = $lineNo; to = $resolved; raw = $token })
      }
    }

    # via (b): link markdown - ignora URL externa (esquema://), ignora fragmento (#heading) na resolucao.
    foreach ($mm in [regex]::Matches($ln, $reLink)) {
      $target = $mm.Groups[1].Value.Trim()
      if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') { continue }
      $targetNoFrag = ($target -split '#')[0].Trim()
      if ($targetNoFrag -eq '') { continue }
      $resolved = Resolve-Token $targetNoFrag $docDir
      if ($null -ne $resolved -and $resolved -ne $relFrom) {
        $edges.Add([pscustomobject]@{ via = 'b'; from = $relFrom; from_line = $lineNo; to = $resolved; raw = $target })
      }
    }

    # via (e): wikilink [[alvo]] - resolve SO contra a pasta do doc de origem (alvo ou alvo.md),
    # nunca contra a raiz do lab (wikilink e convencao de nota curta entre vizinhos, nao caminho).
    foreach ($mm in [regex]::Matches($ln, $reWiki)) {
      $wTarget = $mm.Groups[1].Value.Trim()
      if ($wTarget -eq '') { continue }
      $wResolved = $null
      foreach ($wCandidate in @($wTarget, ($wTarget + '.md'))) {
        $wPath = Join-Path $docDir $wCandidate
        if (Test-Path -LiteralPath $wPath -PathType Leaf) { $wResolved = ToRootRel $wPath; break }
      }
      if ($null -ne $wResolved -and $wResolved -ne $relFrom) {
        $edges.Add([pscustomobject]@{ via = 'e'; from = $relFrom; from_line = $lineNo; to = $wResolved; raw = $mm.Value })
      }
    }
  }

  # via (d): campo de frontmatter YAML (--- ... --- no topo do arquivo).
  if ($lines.Count -gt 0 -and $lines[0].Trim() -eq '---') {
    $endIdx = -1
    for ($j = 1; $j -lt $lines.Count; $j++) { if ($lines[$j].Trim() -eq '---') { $endIdx = $j; break } }
    if ($endIdx -gt 0) {
      for ($j = 1; $j -lt $endIdx; $j++) {
        $mKV = [regex]::Match($lines[$j], '^\s*[\w-]+:\s*(.+)$')
        if ($mKV.Success) {
          foreach ($mm in [regex]::Matches($mKV.Groups[1].Value, $rePath)) {
            $token = $mm.Value
            $resolved = Resolve-Token $token $docDir
            if ($null -ne $resolved -and $resolved -ne $relFrom) {
              $edges.Add([pscustomobject]@{ via = 'd'; from = $relFrom; from_line = ($j + 1); to = $resolved; raw = $token })
            }
          }
        }
      }
    }
  }
}

# Ordenacao por GRAU de entrada (contagem de "to" repetido) - nunca PageRank, nunca gravado como
# campo (quem le calcula). Desempate deterministico: to, from, from_line.
$degree = @{}
foreach ($e in $edges) {
  if (-not $degree.ContainsKey($e.to)) { $degree[$e.to] = 0 }
  $degree[$e.to] = $degree[$e.to] + 1
}
$edgesSorted = $edges | Sort-Object -Property @{Expression = { $degree[$_.to] }; Descending = $true }, `
  @{Expression = 'to'; Descending = $false }, @{Expression = 'from'; Descending = $false }, @{Expression = 'from_line'; Descending = $false }

function JEsc([string]$s) {
  if ($null -eq $s) { return '' }
  return $s.Replace('\', '\\').Replace('"', '\"')
}
$edgeLines = foreach ($e in $edgesSorted) {
  '  {"via":"' + $e.via + '","from":"' + (JEsc $e.from) + '","from_line":' + $e.from_line + ',"to":"' + (JEsc $e.to) + '","raw":"' + (JEsc $e.raw) + '"}'
}
$edgesJson = if ($edgeLines.Count -eq 0) { "[]" } else { "[`r`n" + ($edgeLines -join ",`r`n") + "`r`n]" }
# -Roots (N pastas, escopo motor) sempre escreve na RAIZ do lab - arquivo UNICO, nunca um por
# pasta (a aresta cruzada entre pastas so aparece se todo mundo cair no mesmo arquivo). Legado
# -KnowledgePath (1 pasta, escopo Client) mantem o destino de sempre: dentro da propria pasta.
$edgesOutDir = if ($Roots -and $Roots.Count -gt 0) { Join-Path $root "engine/governance" } else { $KnowledgePath }
$edgesOutFile = Join-Path $edgesOutDir "edges.json"
[System.IO.File]::WriteAllText($edgesOutFile, $edgesJson + "`r`n", $utf8)

$uniqueEdgeCount = (@($edges | ForEach-Object { $_.from + "->" + $_.to }) | Sort-Object -Unique).Count
$docsComEdge = (@($edges | Select-Object -ExpandProperty from -Unique)).Count
$mencoesAC = (@($edges | Where-Object { $_.via -eq 'a' -or $_.via -eq 'c' })).Count
Write-Host ("=== edges.json gerado === arestas resolvidas: " + $edges.Count + " (vias a+c: " + $mencoesAC + ") | unicas (from->to): " + $uniqueEdgeCount + " | docs com aresta: " + $docsComEdge + "/" + $docs.Count + " | saida: " + $edgesOutFile)

if ($EdgesOnly) { exit 0 }
}
# ---------- fim TASK-587 ----------

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
