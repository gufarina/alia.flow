<#
  gate-check.ps1 - a PORTA DE SAIDA do Gate (checks de maquina, sem LLM, sem rede).

  Por que existe: o Gate em prosa (quality-gate.md, 6 criterios julgados por humano/LLM) aprovava
  peca com defeito detectavel por maquina porque nada MEDIA antes do julgamento (auditoria TASK-782
  sobre Tasks com veredito PASS e artifact preenchido achou travessao, emoji e caminho inexistente
  em peca ja aprovada).

  6 checks, cada um sai PASS, FAIL, SKIP ou NA:
    - PASS = checou e esta certo.
    - FAIL = checou e achou defeito real. Qualquer FAIL derruba o veredito inteiro.
    - SKIP = devia ter checado e nao deu (URL/prosa sem arquivo, arquivo ilegivel, config de marca
             corrompida, marca ambigua que so humano resolve) - prova nao verificavel, nunca vira
             PASS por omissao. Sem FAIL mas com algum SKIP -> veredito CONCERN.
    - NA   = o check nao se aplica a este arquivo (kind errado, sem regra de marca configurada,
             binario). NA nao e duvida, entao NUNCA conta para CONCERN - so PASS/FAIL/SKIP contam.

  Os 6:
    1. existe   - cada caminho declarado existe em disco e tem tamanho > 0. Trecho sem extensao de
                  arquivo e prosa (nao arquivo) -> SKIP. URL -> SKIP. Separador aceito: ';' ou ','.
    2. travessao - zero em dash (U+2014) e en dash (U+2013) no conteudo (html/md). Regra dura da
                  casa. Kind que nao e prosa (html/md) -> NA.
    3. emoji    - zero pictograma com apresentacao de emoji por padrao -> FAIL. Simbolo tipografico
                  (estrela de texto, letra matematica, checkmark de lista) nunca e emoji -> PASS.
                  Kind que nao e prosa -> NA.
    4. marca    - DIRIGIDO POR DADO, nunca por codigo: o motor e produto PUBLICO que qualquer
                  operador instala, entao nenhuma cor/termo de UMA operacao especifica pode morar
                  no script. As regras vem de um arquivo OPCIONAL do operador, -BrandRulesFile
                  implicito em <StudioDir-ou-cwd>/studio/brand-rules.json, formato
                  {"surfaces":[{"pathPattern":<regex>,"forbidden":[<termos>],"level":"fail"|
                  "concern","motivo":<opcional>}]} - a PRIMEIRA superficie cujo pathPattern bate no
                  caminho (normalizado, minusculo, barras) vence. Sem o arquivo, arquivo invalido,
                  ou caminho sem superficie que bata -> NA (nao ha regra pra aplicar). Termo proibido
                  em superficie "concern" -> SKIP (ambiguo, humano decide); em "fail" -> FAIL.
                  Kind que nao e html -> NA.
    5. minimo   - reprova so quando o ARQUIVO inteiro e pequeno (menos de 2.000 bytes) E o texto
                  visivel tambem e pequeno (html: menos de 800 bytes visiveis; md: menos de 200
                  bytes). Arquivo grande com pouco texto visivel (slide, post com imagem embutida)
                  nunca e stub. Kind que nao e html/md -> NA.
    6. encoding - binario decidido pelo CONTEUDO (byte zero nos primeiros 8 KB), nunca por lista de
                  extensao - so precisa ler o inicio do arquivo, nunca carrega video/imagem inteiro
                  na memoria. Binario -> NA. Texto que decodifica como UTF-8 valido -> PASS (nao
                  julga o CONTEUDO decodificado: documento que fala sobre mojibake contem "A-til"
                  legitimamente). Decodificacao que falha de verdade -> FAIL.
  Veredito: qualquer FAIL -> FAIL. Sem FAIL mas com algum SKIP -> CONCERN. Resto (PASS/NA) -> PASS.

  CLI: -Artifact <caminho ou lista separada por ';' ou ','> [-Kind auto|html|md|code] [-Client <id>]
       [-Json] [-StudioDir <dir>] [-NoLog]
  -Kind auto detecta pela extensao do primeiro arquivo real da lista (html/htm->html, md->md,
  qualquer outra extensao->code). -StudioDir e a raiz da instancia (onde moram state.json/clients/
  studio/); default = a pasta que contem scripts/ (mesma convencao de register-task.ps1). Caminho
  relativo em -Artifact resolve contra -StudioDir quando informado, senao contra o diretorio de
  trabalho atual.
  Saida sem -Json: uma linha [PASS]/[FAIL]/[SKIP]/[NA] por check + veredito final. Com -Json: UMA
  linha JSON {verdict, checks:[{nome,estado,motivo}], artifact, client, ts} - o formato que
  register-task.ps1 le.
  Ledger: sem -NoLog, appenda a MESMA linha JSON em <StudioDir>\studio\gate-check-log.jsonl (padrao
  de persistencia de studio/graph-usage-log.jsonl, engine/governance/persistence-catalog.md).

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
  [switch]$NoLog
)

$utf8 = New-Object System.Text.UTF8Encoding($false)
$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
# Resolucao de caminho vem de UMA fonte so (Resolve-ArtifactItems, _studio.ps1) - TASK-787
# remediacao: register-task.ps1 e este script tinham logica propria e divergiam em prova de
# repositorio irmao. Nenhum dos dois reimplementa resolucao de caminho depois desta linha.
. (Join-Path $PSScriptRoot "_studio.ps1")

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

# Deteccao por codigo numerico ([char]0xNNNN), nunca por caractere literal no fonte deste script -
# um em/en dash ou emoji LITERAL aqui dentro contaminaria o proprio gate-check.ps1.
function Test-HasDash([string]$s) {
  return ($s.IndexOf([char]0x2013) -ge 0) -or ($s.IndexOf([char]0x2014) -ge 0)
}

# Emoji_Presentation=Yes no plano basico (fonte: emoji-data.txt do Unicode) - lista curada, nao um
# intervalo generico. 0x2600-0x26FF genero (a versao anterior deste check) pegava simbolo
# tipografico sem apresentacao de emoji (zodiaco, clima) como se fosse pictograma; e tratar
# QUALQUER par substituto (surrogate pair) como emoji reprovava letra matematica astral
# (U+1D400+) que nunca foi emoji. Corrigido: lista explicita no plano basico + faixa astral
# estreita (0x1F000-0x1FAFF, onde moram os pictogramas de verdade) + o seletor de apresentacao.
$script:EmojiPresentationBmpRanges = @(
  @(0x231A,0x231B), @(0x23E9,0x23EC), @(0x23F0,0x23F0), @(0x23F3,0x23F3),
  @(0x25FD,0x25FE), @(0x2614,0x2615), @(0x2648,0x2653), @(0x267F,0x267F),
  @(0x2693,0x2693), @(0x26A1,0x26A1), @(0x26AA,0x26AB), @(0x26BD,0x26BE),
  @(0x26C4,0x26C5), @(0x26CE,0x26CE), @(0x26D4,0x26D4), @(0x26EA,0x26EA),
  @(0x26F2,0x26F3), @(0x26F5,0x26F5), @(0x26FA,0x26FA), @(0x26FD,0x26FD),
  @(0x2705,0x2705), @(0x270A,0x270B), @(0x2728,0x2728), @(0x274C,0x274C),
  @(0x274E,0x274E), @(0x2753,0x2755), @(0x2757,0x2757), @(0x2795,0x2797),
  @(0x27B0,0x27B0), @(0x27BF,0x27BF), @(0x2B1B,0x2B1C), @(0x2B50,0x2B50),
  @(0x2B55,0x2B55)
)
function Test-HasRealEmoji([string]$s) {
  for ($i = 0; $i -lt $s.Length; $i++) {
    $c = [int][char]$s[$i]
    if ($c -eq 0xFE0F) { return $true }
    if ($c -ge 0xD800 -and $c -le 0xDBFF -and ($i + 1) -lt $s.Length) {
      $cp = [char]::ConvertToUtf32($s[$i], $s[$i + 1])
      if ($cp -ge 0x1F000 -and $cp -le 0x1FAFF) { return $true }
      $i++
      continue
    }
    foreach ($r in $script:EmojiPresentationBmpRanges) { if ($c -ge $r[0] -and $c -le $r[1]) { return $true } }
  }
  return $false
}

$verdict = "CONCERN"
$checks = New-Object System.Collections.Generic.List[object]

try {
  # Base de resolucao de caminho RELATIVO: -StudioDir quando informado, senao o diretorio de
  # trabalho ATUAL - nunca a pasta do proprio script (isso fazia todo -Artifact relativo chamado
  # de fora da oficina virar FAIL falso de "existe").
  $artifactBaseDir = if (-not [string]::IsNullOrWhiteSpace($StudioDir)) { $StudioDir } else { (Get-Location).Path }
  $brandRulesPath = Join-Path $artifactBaseDir "studio\brand-rules.json"

  # Caminho com aspas/</>/| (ou controle) lanca "Illegal characters in path" em IsPathRooted,
  # GetExtension e Test-Path - isolar ANTES de tocar qualquer API de Path evita que isso derrube o
  # script inteiro pro catch geral (virava erro-interno em vez de SKIP com motivo claro).
  $invalidPathChars = [System.IO.Path]::GetInvalidPathChars()
  # Formato canonico agora e SO ";" (TASK-787 remediacao - unificado com register-task.ps1, que
  # nunca aceitou "," como separador; "," virava adivinhacao dupla que os dois scripts tratavam
  # diferente).
  $rawParts = @($Artifact -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
  $urlParts = @($rawParts | Where-Object { $_ -match '^(?i)https?://' })
  $candidateParts = @($rawParts | Where-Object { $_ -notmatch '^(?i)https?://' })
  $invalidParts = @($candidateParts | Where-Object { $_.IndexOfAny($invalidPathChars) -ge 0 })
  $textCandidates = @($candidateParts | Where-Object { $_.IndexOfAny($invalidPathChars) -lt 0 })
  # CONSERTO (achado da coordenadora): "sem extensao = prosa" excluia PASTA de verdade (pasta nao
  # tem extensao por natureza) - toda pasta virava SKIP falso. A funcao unica agora MODELA o tipo
  # (arquivo/pasta/url) e decide existencia por tipo; aqui so passamos os candidatos (ja filtrados
  # de URL e caractere invalido) pra ela resolver - nenhum julgamento de "e caminho ou prosa" por
  # sintaxe/extensao continua deste lado.
  $pathParts = $textCandidates
  # RESOLUCAO: fonte unica (Resolve-ArtifactItems, scripts/_studio.ps1) - a MESMA que
  # register-task.ps1 usa. Resolve absoluto, relativo a -StudioDir e relativo a pasta que CONTEM
  # o studio (repositorios irmaos), MODELANDO arquivo/pasta/url - nenhuma logica de resolucao ou
  # de tipo propria aqui depois desta linha.
  $resolvedInfo = @()
  if ($pathParts.Count -gt 0) { $resolvedInfo = @(Resolve-ArtifactItems ($pathParts -join ';') $artifactBaseDir) }
  $resolved = @($resolvedInfo | ForEach-Object { $_.resolvedPath })

  # (1) existe
  if ($pathParts.Count -eq 0) {
    $motivo = "prova nao verificavel por caminho (URL ou prosa, nada de arquivo/pasta declarado)"
    if ($invalidParts.Count -gt 0) { $motivo = "caminho com caractere invalido (aspas/</>/|): " + ($invalidParts -join "; ") }
    $checks.Add((New-CheckResult "existe" "SKIP" $motivo))
  } else {
    $missing = @($resolvedInfo | Where-Object { -not $_.found } | ForEach-Object { $_.resolvedPath })
    $empty = @($resolvedInfo | Where-Object { $_.found -and -not $_.exists } | ForEach-Object { $_.resolvedPath })
    if ($missing.Count -gt 0) {
      # CONSERTO (achado da coordenadora, raiz do numero falso da 1.83.0): o portao so SABE que o
      # item nao RESOLVEU para nada em disco - nunca teve certeza de que "nao existe" (texto livre
      # sem trava de escrita, que nao e caminho nenhum, tambem nao resolve). Afirmar "nao existe em
      # disco" era prometer uma certeza que o mecanismo nao tem - a mesma confusao (texto que nao e
      # caminho lido como prova ausente) que gerou o numero publicado errado.
      $checks.Add((New-CheckResult "existe" "FAIL" ("nao resolve para arquivo, pasta ou link: " + ($missing -join "; "))))
    } elseif ($empty.Count -gt 0) {
      $checks.Add((New-CheckResult "existe" "FAIL" ("vazio (arquivo de 0 bytes ou pasta sem conteudo): " + ($empty -join "; "))))
    } else {
      $checks.Add((New-CheckResult "existe" "PASS" ($resolved.Count.ToString() + " caminho(s) existem e tem conteudo")))
    }
  }

  # CONSERTO (achado da coordenadora): pasta agora pode chegar aqui como item valido (tipo=pasta).
  # DirectoryInfo.Length no PowerShell 5.1 NAO e $null/erro (e algum valor > 0 por adaptacao do
  # proprio host) - dependia so de .Length deixava pasta entrar em $contentFiles e quebrava mais
  # abaixo tentando ReadAllBytes numa pasta. Checks de CONTEUDO de texto (emoji/dash/marca/minimo)
  # so fazem sentido em ARQUIVO - filtra por PSIsContainer explicitamente, nunca por Length.
  $contentFiles = @($resolved | Where-Object { (Test-Path -LiteralPath $_) -and (-not (Get-Item -LiteralPath $_ -Force).PSIsContainer) -and ((Get-Item -LiteralPath $_).Length -gt 0) })

  $resolvedKind = $Kind
  if ($resolvedKind -eq "auto") {
    $ext = if ($contentFiles.Count -gt 0) { [System.IO.Path]::GetExtension($contentFiles[0]).ToLowerInvariant() } else { "" }
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
    # Le cada arquivo do disco UMA VEZ SO (a versao anterior lia ate 4 vezes: travessao, emoji,
    # marca e minimo cada um com seu proprio ReadAllText). Bytes crus servem pro binario/encoding;
    # o decoder estrito roda uma vez fora do loop, texto decodificado fica em cache pros outros 4.
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $fileText = @{}
    $fileIsBinary = @{}
    $fileDecodeOk = @{}
    foreach ($f in $contentFiles) {
      $bytes = [System.IO.File]::ReadAllBytes($f)
      $probeLen = [Math]::Min(8192, $bytes.Length)
      $isBinary = $false
      for ($bi = 0; $bi -lt $probeLen; $bi++) { if ($bytes[$bi] -eq 0) { $isBinary = $true; break } }
      $fileIsBinary[$f] = $isBinary
      try { $fileText[$f] = $strictUtf8.GetString($bytes); $fileDecodeOk[$f] = $true }
      catch { $fileText[$f] = ""; $fileDecodeOk[$f] = $false }
    }

    # (2) travessao
    if (-not $isTextKind) {
      $checks.Add((New-CheckResult "travessao" "NA" ("check de prosa nao se aplica a kind=" + $resolvedKind)))
    } else {
      $hits = @($contentFiles | Where-Object { Test-HasDash $fileText[$_] } | ForEach-Object { Split-Path -Leaf $_ })
      if ($hits.Count -gt 0) { $checks.Add((New-CheckResult "travessao" "FAIL" ("em/en dash em: " + ($hits -join ", ")))) }
      else { $checks.Add((New-CheckResult "travessao" "PASS" "zero travessao")) }
    }

    # (3) emoji
    if (-not $isTextKind) {
      $checks.Add((New-CheckResult "emoji" "NA" ("check de prosa nao se aplica a kind=" + $resolvedKind)))
    } else {
      $hits = @($contentFiles | Where-Object { Test-HasRealEmoji $fileText[$_] } | ForEach-Object { Split-Path -Leaf $_ })
      if ($hits.Count -gt 0) { $checks.Add((New-CheckResult "emoji" "FAIL" ("emoji em: " + ($hits -join ", ")))) }
      else { $checks.Add((New-CheckResult "emoji" "PASS" "zero emoji")) }
    }

    # (4) marca - regra vem do arquivo do operador (ver doc do check 4 no topo); sem regra, sem
    # superficie que bata, ou arquivo de regra corrompido -> nao ha o que aplicar.
    if ($resolvedKind -ne "html") {
      $checks.Add((New-CheckResult "marca" "NA" "check so se aplica a HTML"))
    } elseif (-not (Test-Path -LiteralPath $brandRulesPath)) {
      $checks.Add((New-CheckResult "marca" "NA" "sem regra de marca configurada"))
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
          $txt = $fileText[$f]
          $reasons = @()
          foreach ($term in @($surface.forbidden)) { if ($txt -match [regex]::Escape($term)) { $reasons += $term } }
          if ($reasons.Count -eq 0) { continue }
          $prefixo = if ($surface.motivo) { $surface.motivo + " - " } else { "" }
          $linha = (Split-Path -Leaf $f) + ": " + $prefixo + "proibido: " + ($reasons -join ", ")
          if ($surface.level -eq "concern") { $ambiguous += $linha } else { $bad += $linha }
        }
        if ($bad.Count -gt 0) { $checks.Add((New-CheckResult "marca" "FAIL" ($bad -join "; "))) }
        elseif ($ambiguous.Count -gt 0) { $checks.Add((New-CheckResult "marca" "SKIP" ($ambiguous -join "; "))) }
        elseif ($noMatch -eq $contentFiles.Count) { $checks.Add((New-CheckResult "marca" "NA" "nenhuma superficie do brand-rules.json bate com este caminho")) }
        else { $checks.Add((New-CheckResult "marca" "PASS" (($contentFiles.Count - $noMatch).ToString() + " arquivo(s) avaliados contra brand-rules.json, sem termo proibido"))) }
      }
    }

    # (5) minimo - so reprova quando ARQUIVO e TEXTO VISIVEL sao os dois minusculos (arquivo grande
    # com pouco texto visivel e slide/post com imagem embutida, nunca stub).
    if ($resolvedKind -eq "html") {
      $stubs = @()
      foreach ($f in $contentFiles) {
        $fileBytes = (Get-Item -LiteralPath $f).Length
        $visible = Get-VisibleHtmlText $fileText[$f]
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
      $checks.Add((New-CheckResult "minimo" "NA" "check so se aplica a HTML/MD"))
    }

    # (6) encoding - binario decidido pelo CONTEUDO (byte zero nos primeiros 8 KB), nunca por lista
    # de extensao (a lista antiga reprovava .mov/.wav/.webm/.avif/.otf como "nao UTF-8" e exigia
    # ler o arquivo inteiro pra decodificar).
    $textFiles = @($contentFiles | Where-Object { -not $fileIsBinary[$_] })
    $binCount = @($contentFiles | Where-Object { $fileIsBinary[$_] }).Count
    if ($textFiles.Count -eq 0) {
      $checks.Add((New-CheckResult "encoding" "NA" "todos os arquivos tem byte zero nos primeiros 8 KB (binario), UTF-8 nao se aplica"))
    } else {
      $bad = @($textFiles | Where-Object { -not $fileDecodeOk[$_] } | ForEach-Object { (Split-Path -Leaf $_) + ": nao e UTF-8 valido" })
      if ($bad.Count -gt 0) { $checks.Add((New-CheckResult "encoding" "FAIL" ($bad -join "; "))) }
      else { $checks.Add((New-CheckResult "encoding" "PASS" ("UTF-8 valido" + $(if ($binCount -gt 0) { " (" + $binCount + " arquivo(s) binario(s) fora da checagem)" } else { "" })))) }
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
  client   = $Client
  ts       = $ts
}
$line = ($result | ConvertTo-Json -Depth 6 -Compress)

if (-not $NoLog) {
  try {
    $studioRootForLog = if (-not [string]::IsNullOrWhiteSpace($StudioDir)) { $StudioDir } else { (Split-Path -Parent $PSScriptRoot) }
    $ledgerDir = Join-Path $studioRootForLog "studio"
    New-Item -ItemType Directory -Force -Path $ledgerDir -ErrorAction SilentlyContinue | Out-Null
    $ledgerPath = Join-Path $ledgerDir "gate-check-log.jsonl"
    $sw = New-Object System.IO.StreamWriter($ledgerPath, $true, $utf8)
    try { $sw.Write($line + "`n") } finally { $sw.Close() }
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
