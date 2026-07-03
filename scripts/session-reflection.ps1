<#
  session-reflection.ps1 - Helper deterministico (sem LLM) da OPP-02 (Reflexao pos-sessao).
  Spec: skills/session-reflection/SKILL.md. Governanca: engine/rsi/rsi.md,
  engine/governance/provenance.md.

  O que faz (passo mecanico, custo zero de token de modelo):
   - alvo: le o payload JSON que o hook entrega no STDIN (session_id + transcript_path) e mira
     a sessao que acabou - caminho direto, sem varredura. Fallback 1: -SessionId. Fallback 2:
     o .jsonl mais recente DO PROJETO ATUAL (nunca do PC inteiro - evita digerir sessao de
     outro projeto na memoria deste).
   - extrai um DIGEST enxuto: mensagens do usuario (texto) + pontos de decisao (texto do
     assistente), descartando ruido (tool_result, blocos sem texto).
   - aplica a LISTA ANTI-CAPTURA por palavra-chave (erro de ambiente / negacao de ferramenta /
     erro transitorio): essas linhas vao para a secao DESCARTADO, fora do digest util.
   - grava "reflection-inbox-{data}-{id8}.md" em -ProposalsDir (default memory/_proposals/),
     criada se nao existir; o sufixo {id8} (inicio do id da sessao) impede que duas sessoes no
     mesmo dia sobrescrevam o digest uma da outra. NUNCA escreve na memoria real, NUNCA deleta
     nada, NUNCA toca nucleo/engine.
   - GUARD anti-loop: marcador .last em -ProposalsDir guarda nome+mtime do ultimo transcript
     processado; se o mais recente nao mudou, nao faz nada (evita reprocessar).
   - -DryRun: so imprime o que faria, nao grava nada.

  Escrita .NET UTF-8 sem BOM. Sem acentos, sem emojis. RSI propoe, Gate aprova. exit 0.
#>
param(
  [string]$TranscriptDir = (Join-Path $env:USERPROFILE ".claude\projects"),
  [string]$ProposalsDir = "",
  [string]$SessionId = "",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

# (0) Payload do hook: o Claude Code entrega JSON no stdin do hook (session_id, transcript_path).
#     Ler daqui mira a sessao CERTA sem varredura nenhuma. Leitura ASSINCRONA com timeout de 2s:
#     no hook o payload chega na hora e o stdin fecha; num shell nao-interativo com stdin
#     redirecionado-mas-aberto, um ReadToEnd sincrono travaria o script pra sempre.
$hookTranscript = ""
try {
  # So le stdin em contexto de hook de verdade: o Claude Code define CLAUDE_PROJECT_DIR nos
  # hooks e fecha o stdin depois do payload. Fora de hook (uso manual/CI), nem toca no stdin.
  if ($env:CLAUDE_PROJECT_DIR -and [Console]::IsInputRedirected) {
    $readTask = [Console]::In.ReadToEndAsync()
    $stdinRaw = if ($readTask.Wait(2000)) { $readTask.Result } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($stdinRaw)) {
      $hookObj = $stdinRaw | ConvertFrom-Json
      $tp = $null; try { $tp = [string]$hookObj.transcript_path } catch { }
      if (-not [string]::IsNullOrWhiteSpace($tp)) { $hookTranscript = $tp }
      if ([string]::IsNullOrWhiteSpace($SessionId)) {
        $sid = $null; try { $sid = [string]$hookObj.session_id } catch { }
        if (-not [string]::IsNullOrWhiteSpace($sid)) { $SessionId = $sid }
      }
    }
  }
} catch { }

if ([string]::IsNullOrWhiteSpace($ProposalsDir)) {
  $ProposalsDir = Join-Path $root "memory\_proposals"
}

$utf8  = New-Object System.Text.UTF8Encoding($false)
$today = (Get-Date).ToString("yyyy-MM-dd")

Write-Host "=== Session Reflection (digest deterministico) ==="
Write-Host ("transcripts: " + $TranscriptDir)
Write-Host ("propostas:   " + $ProposalsDir)
Write-Host ("modo:        " + $(if ($DryRun) { "DRY-RUN (nada e gravado)" } else { "RUN (grava inbox em _proposals/)" }))
Write-Host ""

if (-not (Test-Path -LiteralPath $TranscriptDir)) {
  Write-Host ("[ERRO] diretorio de transcripts ausente: " + $TranscriptDir)
  exit 1
}

# (1) Alvo, em 3 degraus (do direto pro fallback):
#     a) transcript_path do stdin do hook -> caminho direto, zero varredura (o caso normal).
#     b) -SessionId -> procura o id DENTRO da pasta de transcripts deste projeto.
#     c) mais recente por mtime, TAMBEM so deste projeto (a pasta e o cwd codificado pelo
#        Claude Code). Nunca varre o PC inteiro: sessao de outro projeto nao entra aqui.
$latest = $null
if (-not [string]::IsNullOrWhiteSpace($hookTranscript) -and (Test-Path -LiteralPath $hookTranscript)) {
  $latest = Get-Item -LiteralPath $hookTranscript
  Write-Host ("[OK] transcript vindo do hook (stdin): " + $latest.Name)
}
if ($null -eq $latest) {
  # Pasta de transcripts DESTE projeto: o Claude Code codifica o cwd trocando nao-alfanumerico por '-'.
  $projFolder = ($root -replace '[^A-Za-z0-9]', '-')
  $scanDir = Join-Path $TranscriptDir $projFolder
  if (-not (Test-Path -LiteralPath $scanDir)) { $scanDir = $TranscriptDir }
  $allJsonl = Get-ChildItem -LiteralPath $scanDir -Filter "*.jsonl" -File -Recurse -ErrorAction SilentlyContinue
  if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
    $latest = $allJsonl | Where-Object { $_.BaseName -eq $SessionId } | Select-Object -First 1
    if ($null -eq $latest) { Write-Host ("[AVISO] SessionId '" + $SessionId + "' nao encontrado; usando o mais recente do projeto.") }
  }
  if ($null -eq $latest) {
    $latest = $allJsonl | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  }
}

if ($null -eq $latest) {
  Write-Host "[OK] nenhum transcript .jsonl encontrado - nada a refletir."
  exit 0
}

Write-Host ("[OK] transcript mais recente: " + $latest.Name)
Write-Host ("     modificado em: " + $latest.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))

# (2) GUARD anti-loop: comparar com o marcador .last.
$marker = Join-Path $ProposalsDir ".last"
$sig = $latest.Name + "|" + $latest.LastWriteTime.ToString("o")
if (Test-Path -LiteralPath $marker) {
  $prev = ([System.IO.File]::ReadAllText($marker)).Trim()
  if ($prev -eq $sig) {
    Write-Host ""
    Write-Host "[OK] transcript mais recente nao mudou desde a ultima execucao (guard anti-loop). Nada a fazer."
    exit 0
  }
}

# (3) Lista anti-captura: palavras-chave simples (ASCII). Linha que casa = descartada do digest util.
$antiCapture = @(
  'no such file', 'not found', 'cannot find', 'nao encontrado', 'path nao existe',
  'permission denied', 'permissao negada', 'access denied', 'disco cheio', 'disk full',
  'nao funciona', 'does not work', 'doesn t work', 'esta fora', 'is down', 'unavailable',
  'timeout', 'timed out', 'flaky', 'tente novamente', 'try again', 'retry',
  'connection refused', 'rede caiu', 'network error', 'econnrefused', 'command not found'
)

function Test-AntiCapture {
  param([string]$line)
  $l = $line.ToLowerInvariant()
  foreach ($kw in $antiCapture) {
    if ($l.Contains($kw)) { return $true }
  }
  return $false
}

# (4) Parse do JSONL: uma linha JSON por evento. Extrai texto de usuario e pontos de decisao.
function Get-TextFromContent {
  param($content)
  # content pode ser string (mensagem real) ou lista de blocos (texto/tool_result/etc).
  if ($null -eq $content) { return @() }
  if ($content -is [string]) { return @($content) }
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($block in @($content)) {
    if ($block -is [string]) { $out.Add($block); continue }
    $bt = $null
    try { $bt = $block.type } catch { }
    if ($bt -eq 'text') {
      try { if ($block.text) { $out.Add([string]$block.text) } } catch { }
    }
  }
  return $out.ToArray()
}

# Fold para ASCII puro: o transcript pode conter acentos/aspas curvas/em-dash/middle-dot
# (texto do CEO ou citado). A regra do CEO exige saida 100% ASCII, entao normalizamos aqui.
function To-Ascii {
  param([string]$s)
  if ([string]::IsNullOrEmpty($s)) { return "" }
  $map = @{
    [char]0x00E1='a';[char]0x00E0='a';[char]0x00E2='a';[char]0x00E3='a';[char]0x00E4='a'
    [char]0x00E9='e';[char]0x00E8='e';[char]0x00EA='e';[char]0x00EB='e'
    [char]0x00ED='i';[char]0x00EC='i';[char]0x00EE='i';[char]0x00EF='i'
    [char]0x00F3='o';[char]0x00F2='o';[char]0x00F4='o';[char]0x00F5='o';[char]0x00F6='o'
    [char]0x00FA='u';[char]0x00F9='u';[char]0x00FB='u';[char]0x00FC='u'
    [char]0x00E7='c';[char]0x00F1='n'
    [char]0x00C1='A';[char]0x00C0='A';[char]0x00C2='A';[char]0x00C3='A';[char]0x00C4='A'
    [char]0x00C9='E';[char]0x00C8='E';[char]0x00CA='E';[char]0x00CB='E'
    [char]0x00CD='I';[char]0x00CC='I';[char]0x00CE='I';[char]0x00CF='I'
    [char]0x00D3='O';[char]0x00D2='O';[char]0x00D4='O';[char]0x00D5='O';[char]0x00D6='O'
    [char]0x00DA='U';[char]0x00D9='U';[char]0x00DB='U';[char]0x00DC='U'
    [char]0x00C7='C';[char]0x00D1='N'
    [char]0x2018="'";[char]0x2019="'";[char]0x201C='"';[char]0x201D='"'
    [char]0x2013='-';[char]0x2014='-';[char]0x2212='-';[char]0x00B7='-';[char]0x2022='-'
    [char]0x2026='...';[char]0x00A0=' ';[char]0x2192='->'
  }
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $s.ToCharArray()) {
    $code = [int]$ch
    if ($code -lt 128) { [void]$sb.Append($ch); continue }
    if ($map.ContainsKey($ch)) { [void]$sb.Append($map[$ch]); continue }
    # Qualquer outro non-ASCII vira espaco (nunca escapa byte>127 para a saida).
    [void]$sb.Append(' ')
  }
  return $sb.ToString()
}

function Clean-Line {
  param([string]$s)
  $t = To-Ascii $s
  $t = ($t -replace '\s+', ' ').Trim()
  return $t
}

$userMsgs   = New-Object System.Collections.Generic.List[string]
$decisions  = New-Object System.Collections.Generic.List[string]
$discarded  = New-Object System.Collections.Generic.List[string]

$lines = [System.IO.File]::ReadAllLines($latest.FullName)
foreach ($raw in $lines) {
  if ([string]::IsNullOrWhiteSpace($raw)) { continue }
  $o = $null
  try { $o = $raw | ConvertFrom-Json } catch { continue }
  $etype = $null
  try { $etype = $o.type } catch { }
  if ($etype -ne 'user' -and $etype -ne 'assistant') { continue }

  $msg = $null
  try { $msg = $o.message } catch { }
  if ($null -eq $msg) { continue }
  $content = $null
  try { $content = $msg.content } catch { }

  $texts = Get-TextFromContent $content
  foreach ($txt in $texts) {
    $clean = Clean-Line $txt
    if ($clean.Length -lt 8) { continue }

    if ($etype -eq 'user') {
      # Descartar o prompt-sistema gigante de boot e ruido obvio.
      if ($clean.Length -gt 1500) { continue }
      if (Test-AntiCapture $clean) { $discarded.Add("[user] " + $clean); continue }
      $userMsgs.Add($clean)
    }
    else {
      # Pontos de decisao: texto do assistente. So o primeiro corte enxuto por mensagem.
      $snippet = if ($clean.Length -gt 280) { $clean.Substring(0, 280) + " ..." } else { $clean }
      if (Test-AntiCapture $snippet) { $discarded.Add("[assist] " + $snippet); continue }
      $decisions.Add($snippet)
    }
  }
}

# Enxugar: limitar volume para um digest legivel.
$userOut = @($userMsgs | Select-Object -Unique)
$decOut  = @($decisions | Select-Object -Last 20)

# (4.5) DEDUP POR CONTEUDO (conserta P1: digests byte-a-byte iguais entupindo a caixa).
# Assina o MIOLO (msgs + decisoes); se ja foi visto, nao grava outro inbox - so atualiza o .last.
$meat = ($userOut -join "`n") + "||" + ($decOut -join "`n")
$sha = [System.Security.Cryptography.SHA256]::Create()
$meatHash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($meat))).Replace("-","").Substring(0,16)
$seenFile = Join-Path $ProposalsDir ".seen"
$seen = @()
if (Test-Path -LiteralPath $seenFile) { $seen = @([System.IO.File]::ReadAllLines($seenFile)) }
if ($seen -contains $meatHash) {
  Write-Host ""
  Write-Host ("[OK] conteudo identico a um digest ja visto (hash " + $meatHash + ") - NAO gravo duplicata.")
  if (-not $DryRun) {
    $sigDup = $latest.Name + "|" + $latest.LastWriteTime.ToString("o")
    [System.IO.File]::WriteAllText((Join-Path $ProposalsDir ".last"), $sigDup, $utf8)
  }
  exit 0
}

Write-Host ""
Write-Host ("[OK] mensagens de usuario (texto): " + $userOut.Count)
foreach ($u in $userOut) {
  $show = if ($u.Length -gt 140) { $u.Substring(0, 140) + " ..." } else { $u }
  Write-Host ("    - " + $show)
}
Write-Host ""
Write-Host ("[OK] pontos de decisao (ultimos " + $decOut.Count + "):")
foreach ($d in $decOut) {
  $show = if ($d.Length -gt 140) { $d.Substring(0, 140) + " ..." } else { $d }
  Write-Host ("    - " + $show)
}
Write-Host ""
Write-Host ("[OK] descartado pela lista anti-captura: " + $discarded.Count + " linha(s).")

# (5) Montar o conteudo do inbox. Sufixo {id8} da sessao no nome: duas sessoes no mesmo
# dia nao sobrescrevem o digest uma da outra (os consumidores usam o wildcard reflection-inbox-*).
$id8 = $latest.BaseName -replace '[^A-Za-z0-9]', ''
if ($id8.Length -gt 8) { $id8 = $id8.Substring(0, 8) }
$inboxName = "reflection-inbox-" + $today + "-" + $id8
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("name: " + $inboxName)
[void]$sb.AppendLine("description: Digest deterministico da sessao " + $latest.BaseName + " - entrada para a reflexao do agente.")
[void]$sb.AppendLine("metadata:")
[void]$sb.AppendLine("  node_type: memory")
[void]$sb.AppendLine("  type: reference")
[void]$sb.AppendLine("  originSessionId: " + $latest.BaseName)
[void]$sb.AppendLine("  status: proposed")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("# Reflection Inbox - " + $today)
[void]$sb.AppendLine("")
[void]$sb.AppendLine("> Gerado por scripts/session-reflection.ps1 (passo mecanico, sem LLM).")
[void]$sb.AppendLine("> AREA DE PROPOSTAS - NUNCA e memoria real. So propoe; nunca aplica; nunca deleta.")
[void]$sb.AppendLine("> Proximo passo: o agente segue skills/session-reflection/SKILL.md (heuristicas Hermes)")
[void]$sb.AppendLine("> e escreve as notas propostas como .md tipados nesta mesma pasta.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Transcript de origem: " + $latest.Name)
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Mensagens do usuario")
[void]$sb.AppendLine("")
if ($userOut.Count -eq 0) {
  [void]$sb.AppendLine("Nenhuma mensagem de usuario em texto.")
} else {
  foreach ($u in $userOut) { [void]$sb.AppendLine("- " + $u) }
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Pontos de decisao (texto do assistente, ultimos " + $decOut.Count + ")")
[void]$sb.AppendLine("")
if ($decOut.Count -eq 0) {
  [void]$sb.AppendLine("Nenhum ponto de decisao capturado.")
} else {
  foreach ($d in $decOut) { [void]$sb.AppendLine("- " + $d) }
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Descartado pela lista anti-captura (" + $discarded.Count + ")")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("> Regra: capturar o conserto, nao a reclamacao. Erro de ambiente / negacao de")
[void]$sb.AppendLine("> ferramenta / erro transitorio nao viram nota.")
[void]$sb.AppendLine("")
if ($discarded.Count -eq 0) {
  [void]$sb.AppendLine("Nada descartado.")
} else {
  foreach ($x in $discarded) { [void]$sb.AppendLine("- " + $x) }
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Resumo do que foi proposto")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Este inbox e o digest deterministico. As notas tipadas (user|feedback|project|")
[void]$sb.AppendLine("reference) sao propostas pelo agente no passo de julgamento, como .md irmaos aqui.")

$inboxFile = Join-Path $ProposalsDir ($inboxName + ".md")

# (6) Gravar (ou simular em DryRun). NUNCA fora de _proposals/. NUNCA deleta.
Write-Host ""
if ($DryRun) {
  Write-Host ("[OK] DRY-RUN: NAO gravou. Gravaria o inbox em: " + $inboxFile)
  Write-Host ("[OK] DRY-RUN: NAO atualizou o marcador anti-loop (.last).")
} else {
  New-Item -ItemType Directory -Force -Path $ProposalsDir | Out-Null
  [System.IO.File]::WriteAllText($inboxFile, $sb.ToString(), $utf8)
  Write-Host ("[OK] inbox gravado: " + $inboxFile)
  [System.IO.File]::WriteAllText($marker, $sig, $utf8)
  Write-Host ("[OK] marcador anti-loop atualizado: " + $marker)
  [System.IO.File]::AppendAllText($seenFile, $meatHash + [Environment]::NewLine, $utf8)
  Write-Host ("[OK] hash de conteudo registrado (anti-duplicata): " + $meatHash)
}

Write-Host ""
Write-Host ("Resumo: " + $userOut.Count + " msg(s) de usuario | " + $decOut.Count +
  " ponto(s) de decisao | " + $discarded.Count + " descartado(s) | inbox " +
  $(if ($DryRun) { "proposto (nao gravado)" } else { "gravado em _proposals/" }))

exit 0
