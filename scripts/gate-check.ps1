<#
  gate-check.ps1 - a PORTA DE SAIDA do Gate (checks de maquina, sem LLM, sem rede).

  Por que existe (TASK-782): auditoria sobre 466 Tasks com veredito PASS e artifact preenchido
  achou 226 caminho unico existente, 152 varios arquivos numa string so, 60 caminho unico que NAO
  existe em disco, 21 URL, 4 prosa - e, dos 100 HTML aprovados que existem, 20 tinham travessao
  (regra dura da casa) e 5 tinham emoji. O Gate em prosa (quality-gate.md, 6 criterios julgados por
  humano/LLM) aprovava peca com defeito detectavel por maquina porque nada MEDIA antes do
  julgamento. A PORTA DE ENTRADA (5 perguntas antes de delegar) foi tentada e reprovou na prova
  cega (pega 50%, alarme falso 37%) - so a porta de SAIDA, binaria e determinista, entra aqui.

  O que confere, 6 checks binarios (PASS/FAIL/SKIP, nunca "meio termo"):
    1. existe   - cada caminho declarado existe em disco e tem tamanho > 0. Caminho que nao e
                  arquivo (URL, prosa, string com varios arquivos sem separador ';') -> SKIP, NUNCA PASS.
    2. travessao - zero em dash (U+2014) e en dash (U+2013) no conteudo (html/md). Regra dura da casa.
    3. emoji    - zero PICTOGRAMA de verdade (astral U+1F300+, simbolos de emocao U+2600-U+26FF)
                  no conteudo (html/md) -> FAIL. Dingbat tipografico (visto/cruz/seta/estrela,
                  U+2700-U+27BF e U+2B00-U+2BFF) NUNCA e emoji -> vira SKIP/CONCERN, nunca FAIL.
    4. marca    - DIRIGIDO POR DADO (TASK-782), nunca por codigo: o motor e produto PUBLICO que
                  qualquer operador instala, entao nenhuma cor/Client/termo de UMA operacao
                  especifica pode morar no script (uma heuristica por tonalidade sem lista/fonte ja
                  foi removida daqui por dar alarme falso). As regras vem de um arquivo OPCIONAL do
                  operador, -BrandRulesFile (default: <StudioDir-ou-cwd>/studio/brand-rules.json),
                  formato {"surfaces":[{"pathPattern":<regex do caminho>,"forbidden":[<cores/termos>],
                  "level":"fail"|"concern","motivo":<opcional>}, ...]} - a PRIMEIRA superficie cujo
                  pathPattern bate no caminho (normalizado, minusculo, barras) vence. Exemplo
                  FICTICIO (nao e a regra de ninguem de verdade): pathPattern "/marketing/" proibe
                  "#123456" nivel "fail"; pathPattern "/rascunhos/" proibe "#123456" nivel "concern"
                  com motivo "confirmar com o time". Sem `brand-rules.json` (ou arquivo invalido),
                  ou caminho que nao bate com nenhuma superficie -> SKIP, NUNCA FAIL - ausencia de
                  regra nao e ausencia de defeito, mas tambem nao e um defeito inventado.
    5. minimo   - so reprova quando o ARQUIVO inteiro e pequeno (menos de 2.000 bytes) E o texto
                  visivel tambem e pequeno (HTML: menos de 800 bytes visiveis; MD: menos de 200
                  bytes de conteudo). Arquivo grande com pouco texto visivel (slide, post com
                  imagem embutida) nunca e stub.
    6. encoding - PASS sempre que o arquivo decodifica como UTF-8 valido, ponto - nao julga o
                  CONTEUDO decodificado (documento que fala sobre mojibake contem "Ã" legitimamente).
                  FAIL so quando a decodificacao falha de verdade (bytes invalidos).
  Verdito: qualquer FAIL -> FAIL. Sem FAIL mas com algum SKIP -> CONCERN (prova nao verificavel
  nunca vira PASS por omissao). Todos PASS -> PASS.

  CLI: -Artifact <caminho ou lista separada por ';'> [-Kind auto|html|md|code] [-Client <id>]
       [-Json] [-StudioDir <dir>] [-NoLog]
  -Kind auto detecta pela extensao do primeiro arquivo real da lista (html/htm->html, md->md,
  qualquer outra extensao->code). -StudioDir e a raiz da instancia (onde moram state.json/clients/
  studio/); default = a pasta que contem scripts/ (mesma convencao de register-task.ps1). Caminho
  relativo em -Artifact resolve contra -StudioDir.
  Saida sem -Json: uma linha [PASS]/[FAIL]/[SKIP] por check + veredito final. Com -Json: UMA linha
  JSON {verdict, checks:[{nome,estado,motivo}], artifact, ts} - o formato que register-task.ps1 le.
  Ledger: sem -NoLog, appenda a MESMA linha JSON (+ client) em <StudioDir>\studio\gate-check-log.jsonl
  (padrao de persistencia de studio/graph-usage-log.jsonl, engine/governance/persistence-catalog.md).

  FAIL-SOFT: qualquer excecao interna vira verdict CONCERN com o motivo do erro, ledger tentado em
  best-effort, e o script sempre sai com exit 0 nesse caminho - o Gate nunca trava quem chamou.
  Exit code no caminho normal: 1 quando o veredito e FAIL (uso como gate de CLI/CI), 0 caso
  contrario (PASS ou CONCERN) - quem so quer o JSON (register-task.ps1) ignora o exit code e le o
  veredito no proprio JSON. UTF-8 sem BOM.
#>
param(
  [Parameter(Mandatory=$true)][string]$Artifact,
  [ValidateSet("auto","html","md","code")][string]$Kind = "auto",
  [string]$Client = "",
  [switch]$Json,
  [string]$StudioDir = "",
  [string]$BrandRulesFile = "",
  [switch]$NoLog
)

$utf8 = New-Object System.Text.UTF8Encoding($false)
$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

function New-CheckResult([string]$Nome, [string]$Estado, [string]$Motivo) {
  return [ordered]@{ nome = $Nome; estado = $Estado; motivo = $Motivo }
}

function Get-VisibleHtmlText([string]$html) {
  $t = [regex]::Replace($html, '(?is)<script.*?</script>', ' ')
  $t = [regex]::Replace($t, '(?is)<style.*?</style>', ' ')
  $t = [regex]::Replace($t, '(?is)<!--.*?-->', ' ')
  $t = [regex]::Replace($t, '(?is)<[^>]+>', ' ')
  $t = $t -replace '&nbsp;', ' ' -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"' -replace '&#39;', "'"
  $t = [regex]::Replace($t, '\s+', ' ').Trim()
  return $t
}

function Resolve-ArtifactPath([string]$p, [string]$baseDir) {
  if ([System.IO.Path]::IsPathRooted($p)) { return $p }
  return (Join-Path $baseDir $p)
}

# Deteccao por codigo numerico ([char]0xNNNN), nunca por caractere literal no fonte deste script -
# um em/en dash ou emoji LITERAL aqui dentro contaminaria o proprio gate-check.ps1 (o script que
# prova que ninguem mais faz isso).
function Test-HasDash([string]$s) {
  return ($s.IndexOf([char]0x2013) -ge 0) -or ($s.IndexOf([char]0x2014) -ge 0)
}
# Achado da coordenadora (TASK-782, auditoria a mao de 7 disparos): U+2700-U+27BF (Dingbats) e
# onde mora visto/cruz/seta/estrela TIPOGRAFICA (ex. checkmark de lista), nao emoji - 5 dos 7
# alarmes eram esse engano. Emoji DE VERDADE: astral (surrogate pair, U+1F300+, pictograma/mao) +
# U+2600-U+26FF (simbolos de emocao/tempo, ex. sol/chuva/carinha) + selecionadores estruturais
# (FE0F/200D). Dingbat (2700-27BF) e "misc symbols and arrows" (2B00-2BFF, estrela/seta
# tipografica) viram AVISO (CONCERN), nunca FAIL - fonte: a propria coordenadora.
function Test-HasRealEmoji([string]$s) {
  for ($i = 0; $i -lt $s.Length; $i++) {
    $c = [int][char]$s[$i]
    if ($c -ge 0xD800 -and $c -le 0xDFFF) { return $true }
    if ($c -ge 0x2600 -and $c -le 0x26FF) { return $true }
    if ($c -eq 0xFE0F -or $c -eq 0x200D) { return $true }
  }
  return $false
}
function Test-HasDingbat([string]$s) {
  for ($i = 0; $i -lt $s.Length; $i++) {
    $c = [int][char]$s[$i]
    if ($c -ge 0x2700 -and $c -le 0x27BF) { return $true }
    if ($c -ge 0x2B00 -and $c -le 0x2BFF) { return $true }
  }
  return $false
}
$verdict = "CONCERN"
$checks = New-Object System.Collections.Generic.List[object]

try {
  $root = Split-Path -Parent $PSScriptRoot
  # BUG 1 (achado pela Alia rodando o retroativo, TASK-782): caminho relativo em -Artifact NUNCA
  # resolve contra $PSScriptRoot/$root (a pasta do PROPRIO SCRIPT, a oficina) - isso transformava
  # todo -Artifact relativo chamado de fora da oficina em FAIL falso de "existe". A base de
  # resolucao de caminho RELATIVO e -StudioDir quando informado, senao o diretorio de trabalho
  # ATUAL (Get-Location) - $root so continua servindo de default para o LEDGER (linha do -NoLog
  # abaixo), nunca para o artifact.
  $artifactBaseDir = if (-not [string]::IsNullOrWhiteSpace($StudioDir)) { $StudioDir } else { (Get-Location).Path }
  # -BrandRulesFile > <StudioDir-ou-cwd>/studio/brand-rules.json (dado do OPERADOR, nunca do
  # motor - ver a doc do check "marca" abaixo).
  $brandRulesPath = if (-not [string]::IsNullOrWhiteSpace($BrandRulesFile)) { $BrandRulesFile } else { Join-Path $artifactBaseDir "studio\brand-rules.json" }

  $rawParts = @($Artifact -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
  $urlParts = @($rawParts | Where-Object { $_ -match '^(?i)https?://' })
  $pathParts = @($rawParts | Where-Object { $_ -notmatch '^(?i)https?://' })
  $resolved = @($pathParts | ForEach-Object { Resolve-ArtifactPath $_ $artifactBaseDir })

  # (1) existe
  if ($pathParts.Count -eq 0) {
    $checks.Add((New-CheckResult "existe" "SKIP" "prova nao verificavel por caminho (URL ou prosa, nada de arquivo declarado)"))
  } else {
    $missing = @(); $empty = @()
    foreach ($p in $resolved) {
      if (-not (Test-Path -LiteralPath $p)) { $missing += $p }
      elseif ((Get-Item -LiteralPath $p).Length -le 0) { $empty += $p }
    }
    if ($missing.Count -gt 0) {
      $checks.Add((New-CheckResult "existe" "FAIL" ("nao existe em disco: " + ($missing -join "; "))))
    } elseif ($empty.Count -gt 0) {
      $checks.Add((New-CheckResult "existe" "FAIL" ("tamanho zero: " + ($empty -join "; "))))
    } else {
      $checks.Add((New-CheckResult "existe" "PASS" ($resolved.Count.ToString() + " caminho(s) existem e tem conteudo")))
    }
  }

  $contentFiles = @($resolved | Where-Object { (Test-Path -LiteralPath $_) -and ((Get-Item -LiteralPath $_).Length -gt 0) })

  $resolvedKind = $Kind
  if ($resolvedKind -eq "auto") {
    if ($contentFiles.Count -gt 0) {
      $ext = [System.IO.Path]::GetExtension($contentFiles[0]).ToLowerInvariant()
    } elseif ($resolved.Count -gt 0) {
      $ext = [System.IO.Path]::GetExtension($resolved[0]).ToLowerInvariant()
    } else { $ext = "" }
    if ($ext -eq ".html" -or $ext -eq ".htm") { $resolvedKind = "html" }
    elseif ($ext -eq ".md" -or $ext -eq ".markdown") { $resolvedKind = "md" }
    else { $resolvedKind = "code" }
  }
  $isTextKind = ($resolvedKind -eq "html" -or $resolvedKind -eq "md")

  if ($contentFiles.Count -eq 0) {
    foreach ($n in @("travessao","emoji","marca","minimo","encoding")) {
      $checks.Add((New-CheckResult $n "SKIP" "sem arquivo legivel em disco para checar conteudo"))
    }
  } else {
    # (2) travessao
    if (-not $isTextKind) {
      $checks.Add((New-CheckResult "travessao" "SKIP" ("check de prosa nao se aplica a kind=" + $resolvedKind)))
    } else {
      $hits = @()
      foreach ($f in $contentFiles) {
        $txt = [System.IO.File]::ReadAllText($f)
        if (Test-HasDash $txt) { $hits += (Split-Path -Leaf $f) }
      }
      if ($hits.Count -gt 0) { $checks.Add((New-CheckResult "travessao" "FAIL" ("em/en dash em: " + ($hits -join ", ")))) }
      else { $checks.Add((New-CheckResult "travessao" "PASS" "zero travessao")) }
    }

    # (3) emoji
    if (-not $isTextKind) {
      $checks.Add((New-CheckResult "emoji" "SKIP" ("check de prosa nao se aplica a kind=" + $resolvedKind)))
    } else {
      $hits = @()
      $dingbatHits = @()
      foreach ($f in $contentFiles) {
        $txt = [System.IO.File]::ReadAllText($f)
        if (Test-HasRealEmoji $txt) { $hits += (Split-Path -Leaf $f) }
        elseif (Test-HasDingbat $txt) { $dingbatHits += (Split-Path -Leaf $f) }
      }
      if ($hits.Count -gt 0) { $checks.Add((New-CheckResult "emoji" "FAIL" ("emoji em: " + ($hits -join ", ")))) }
      elseif ($dingbatHits.Count -gt 0) { $checks.Add((New-CheckResult "emoji" "SKIP" ("elemento tipografico (dingbat/seta/estrela, ex. visto de lista), nao emoji - CONCERN, nao FAIL: " + ($dingbatHits -join ", ")))) }
      else { $checks.Add((New-CheckResult "emoji" "PASS" "zero emoji")) }
    }

    # (4) marca
    if ($resolvedKind -ne "html") {
      $checks.Add((New-CheckResult "marca" "SKIP" "check so se aplica a HTML"))
    } else {
      # DIRIGIDO POR DADO, nunca por codigo (TASK-782, mandato da coordenadora): o motor e produto
      # PUBLICO que qualquer operador instala - nenhuma cor, id de Client ou termo de marca de UMA
      # operacao especifica pode morar aqui. As regras (quais pastas sao "superficie de marca",
      # quais cores/termos cada uma proibe, e se isso e FAIL ou CONCERN) vem de um arquivo de
      # configuracao OPCIONAL do proprio operador (ver -BrandRulesFile acima). Sem o arquivo, o
      # check nunca inventa regra - SKIP sempre, nunca FAIL.
      if (-not (Test-Path -LiteralPath $brandRulesPath)) {
        $checks.Add((New-CheckResult "marca" "SKIP" "sem regra de marca configurada"))
      } else {
        $surfaces = $null
        try { $surfaces = @((Get-Content -LiteralPath $brandRulesPath -Raw | ConvertFrom-Json).surfaces) }
        catch { $checks.Add((New-CheckResult "marca" "SKIP" ("brand-rules.json invalido/ilegivel: " + $_.Exception.Message))) }
        if ($null -ne $surfaces) {
          $bad = @()
          $ambiguous = @()
          $noMatch = 0
          foreach ($f in $contentFiles) {
            $norm = $f.Replace('\','/').ToLowerInvariant()
            $surface = $null
            foreach ($s in $surfaces) { if ($norm -match $s.pathPattern) { $surface = $s; break } }
            if ($null -eq $surface) { $noMatch++; continue }
            $txt = [System.IO.File]::ReadAllText($f)
            $reasons = @()
            foreach ($term in @($surface.forbidden)) { if ($txt -match [regex]::Escape($term)) { $reasons += $term } }
            if ($reasons.Count -eq 0) { continue }
            $prefixo = if ($surface.motivo) { $surface.motivo + " - " } else { "" }
            $linha = (Split-Path -Leaf $f) + ": " + $prefixo + "proibido: " + ($reasons -join ", ")
            if ($surface.level -eq "concern") { $ambiguous += $linha } else { $bad += $linha }
          }
          if ($bad.Count -gt 0) { $checks.Add((New-CheckResult "marca" "FAIL" ($bad -join "; "))) }
          elseif ($ambiguous.Count -gt 0) { $checks.Add((New-CheckResult "marca" "SKIP" ($ambiguous -join "; "))) }
          elseif ($noMatch -eq $contentFiles.Count) { $checks.Add((New-CheckResult "marca" "SKIP" "nenhuma superficie do brand-rules.json bate com este caminho")) }
          else { $checks.Add((New-CheckResult "marca" "PASS" (($contentFiles.Count - $noMatch).ToString() + " arquivo(s) avaliados contra brand-rules.json, sem termo proibido"))) }
        }
      }
    }

    # (5) minimo - achado real da coordenadora (TASK-782): pouco texto VISIVEL nao e stub quando o
    # ARQUIVO e grande (slide/post com bastante CSS/markup/imagem embutida em volta de pouco
    # texto e peca pronta, nao vazia). So reprova quando os DOIS sao minusculos: arquivo inteiro
    # abaixo de 2.000 bytes E texto visivel abaixo de 800. Arquivo grande nunca e stub.
    if ($resolvedKind -eq "html") {
      $stubs = @()
      foreach ($f in $contentFiles) {
        $fileBytes = (Get-Item -LiteralPath $f).Length
        $txt = [System.IO.File]::ReadAllText($f)
        $visible = Get-VisibleHtmlText $txt
        $visibleBytes = $utf8.GetByteCount($visible)
        if ($fileBytes -lt 2000 -and $visibleBytes -lt 800) { $stubs += ((Split-Path -Leaf $f) + " (arquivo " + $fileBytes + " bytes, " + $visibleBytes + " bytes visiveis)") }
      }
      if ($stubs.Count -gt 0) { $checks.Add((New-CheckResult "minimo" "FAIL" ("peca vazia ou stub: " + ($stubs -join ", ")))) }
      else { $checks.Add((New-CheckResult "minimo" "PASS" "arquivo grande ou texto visivel acima do minimo (2.000 bytes de arquivo / 800 de texto visivel)")) }
    } elseif ($resolvedKind -eq "md") {
      $stubs = @()
      foreach ($f in $contentFiles) {
        $bytes = (Get-Item -LiteralPath $f).Length
        if ($bytes -lt 200) { $stubs += ((Split-Path -Leaf $f) + " (" + $bytes + " bytes)") }
      }
      if ($stubs.Count -gt 0) { $checks.Add((New-CheckResult "minimo" "FAIL" ("peca vazia ou stub: " + ($stubs -join ", ")))) }
      else { $checks.Add((New-CheckResult "minimo" "PASS" "conteudo acima do minimo (200 bytes)")) }
    } else {
      $checks.Add((New-CheckResult "minimo" "SKIP" "check so se aplica a HTML/MD"))
    }

    # (6) encoding - so se aplica a arquivo de TEXTO. Binario (pdf/gif/png/jpg/zip/...) nao e UTF-8
    # por natureza e nao e defeito nenhum - medido no retroativo (TASK-782): .pdf/.gif reprovando
    # "nao e UTF-8 valido" era falso-positivo, nao achado real.
    $binExt = @(".pdf",".gif",".png",".jpg",".jpeg",".webp",".ico",".zip",".exe",".dll",".docx",".xlsx",".pptx",".ttf",".woff",".woff2",".mp4",".mp3",".psd",".ai")
    $textFiles = @($contentFiles | Where-Object { $binExt -notcontains [System.IO.Path]::GetExtension($_).ToLowerInvariant() })
    $skippedBin = @($contentFiles | Where-Object { $binExt -contains [System.IO.Path]::GetExtension($_).ToLowerInvariant() })
    if ($textFiles.Count -eq 0) {
      $checks.Add((New-CheckResult "encoding" "SKIP" "todos os arquivos sao binarios (extensao nao-texto), UTF-8 nao se aplica"))
    } else {
      # Achado real da coordenadora (TASK-782): decodificar como UTF-8 valido e a prova. Texto que
      # FALA sobre mojibake (documentacao, titulo de tarefa citando o assunto) contem a sequencia
      # "Ã" legitimamente - so decodificacao que FALHA de verdade e defeito de encoding.
      $bad = @()
      foreach ($f in $textFiles) {
        $bytes = [System.IO.File]::ReadAllBytes($f)
        $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
        try { [void]$strictUtf8.GetString($bytes) } catch { $bad += ((Split-Path -Leaf $f) + ": nao e UTF-8 valido") }
      }
      if ($bad.Count -gt 0) { $checks.Add((New-CheckResult "encoding" "FAIL" ($bad -join "; "))) }
      else { $checks.Add((New-CheckResult "encoding" "PASS" ("UTF-8 valido" + $(if ($skippedBin.Count -gt 0) { " (" + $skippedBin.Count + " arquivo(s) binario(s) fora da checagem)" } else { "" })))) }
    }
  }

  if (@($checks | Where-Object { $_.estado -eq "FAIL" }).Count -gt 0) { $verdict = "FAIL" }
  elseif (@($checks | Where-Object { $_.estado -eq "SKIP" }).Count -gt 0) { $verdict = "CONCERN" }
  else { $verdict = "PASS" }

} catch {
  $verdict = "CONCERN"
  $checks = New-Object System.Collections.Generic.List[object]
  $checks.Add((New-CheckResult "erro-interno" "SKIP" ("gate-check falhou por dentro, fail-soft: " + $_.Exception.Message)))
}

$result = [ordered]@{
  verdict  = $verdict
  checks   = $checks.ToArray()
  artifact = $Artifact
  ts       = $ts
}
$line = ($result | ConvertTo-Json -Depth 6 -Compress)

if (-not $NoLog) {
  try {
    $studioRootForLog = if (-not [string]::IsNullOrWhiteSpace($StudioDir)) { $StudioDir } else { (Split-Path -Parent $PSScriptRoot) }
    $ledgerDir = Join-Path $studioRootForLog "studio"
    if (-not (Test-Path -LiteralPath $ledgerDir)) { New-Item -ItemType Directory -Force -Path $ledgerDir -ErrorAction SilentlyContinue | Out-Null }
    $ledgerPath = Join-Path $ledgerDir "gate-check-log.jsonl"
    $logEntry = [ordered]@{ verdict = $verdict; checks = $checks.ToArray(); artifact = $Artifact; client = $Client; ts = $ts }
    $logLine = ($logEntry | ConvertTo-Json -Depth 6 -Compress)
    $sw = New-Object System.IO.StreamWriter($ledgerPath, $true, $utf8)
    try { $sw.Write($logLine + "`n") } finally { $sw.Close() }
  } catch { }
}

if ($Json) {
  Write-Output $line
} else {
  foreach ($c in $checks) {
    Write-Host ("[" + $c.estado + "] " + $c.nome + $(if ($c.motivo) { " -> " + $c.motivo } else { "" }))
  }
  Write-Host ("Gate-check: " + $verdict)
}

if ($verdict -eq "FAIL") { exit 1 } else { exit 0 }
