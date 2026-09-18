# Alia Flow - Frugal Skill: sanitize-input
# Borda que neutraliza texto perigoso ANTES de virar comando. Subset BARATO por regex (sem LLM,
# sem tabela de homoglifo Unicode - cortada por peso). Roda SOB DEMANDA quando entra payload de
# dominio (briefing, email, texto de cliente, retorno da escada de pesquisa) - NAO no boot/AGENTS.md
# (nao adicionar peso ao caminho sempre-carregado: MAP.md / biblioteca-sob-demanda).
#
# O que faz (5 passos deterministicos):
#   1. Limite de tamanho      -> trunca em -MaxChars (default 20000), marca o corte.
#   2. Control chars / ANSI   -> remove ESC[...m e os C0/C1 invisiveis (tab/nl/cr preservados).
#   3. Tag                     -> <x> vira (x) (inerta HTML/pseudo-tag de injecao).
#   4. @mention / bot-trigger  -> @nome vira (at:nome); /comando no inicio de linha vira (cmd:comando).
#   5. URI nao-HTTPS          -> http://, ftp://, file://, data:, javascript: viram (redacted).
#
# Saida:
#   - escreve o texto neutralizado (stdout, util pra pipe) OU em -OutPath se dado.
#   - imprime um relatorio [sanitize-input] com a contagem por categoria.
#   - exit 0 sempre (e sanitizador, nao gate; nunca bloqueia - so desarma).
# Português correto, com acentos. Arquivo salvo em UTF-8 sem BOM; o único erro é caractere corrompido. Emoji continua fora de peça pública.

param(
  [string]$Path = "",
  [string]$Text = "",
  [string]$OutPath = "",
  [int]$MaxChars = 20000
)

$ErrorActionPreference = "Stop"

function ReadText([string]$p) {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($p, $utf8)
}
function WriteText([string]$p, [string]$content) {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($p, $content, $utf8)
}

# Origem do payload: -Text vence -Path; se nenhum, le stdin.
if ($Text -ne "") {
  $raw = $Text
} elseif ($Path -ne "") {
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "=== sanitize-input ==="
    Write-Host ("[FAIL] payload ausente: " + $Path)
    exit 1
  }
  $raw = ReadText $Path
} else {
  $raw = ($input | Out-String)
}

$counts = [ordered]@{
  truncated      = 0
  control_ansi   = 0
  tags           = 0
  mentions       = 0
  bot_triggers   = 0
  uris_redacted  = 0
}

$out = $raw

# 1. Limite de tamanho (antes do resto: corta payload-bomba cedo).
if ($out.Length -gt $MaxChars) {
  $out = $out.Substring(0, $MaxChars) + "`n(truncated: limite de " + $MaxChars + " chars)"
  $counts.truncated = 1
}

# 2. Control chars / ANSI. Primeiro a sequencia ANSI (ESC [ ... letra), depois os C0/C1
#    invisiveis preservando tab(09) newline(0A) cr(0D).
$ansiRx = [char]0x1B + '\[[0-9;?]*[ -/]*[@-~]'
$m = [regex]::Matches($out, $ansiRx); $counts.control_ansi += $m.Count
$out = [regex]::Replace($out, $ansiRx, "")
$ctrlRx = '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]'
$m = [regex]::Matches($out, $ctrlRx); $counts.control_ansi += $m.Count
$out = [regex]::Replace($out, $ctrlRx, "")

# 3. Tag: <qualquer-coisa-sem-newline> -> (qualquer-coisa). Inerta HTML/pseudo-tag.
$tagRx = '<([^<>\r\n]*)>'
$m = [regex]::Matches($out, $tagRx); $counts.tags = $m.Count
$out = [regex]::Replace($out, $tagRx, '($1)')

# 4a. @mention -> (at:nome). Desarma ping/handle que viraria acao.
$mentionRx = '(?<![\w/])@([A-Za-z0-9_.\-]+)'
$m = [regex]::Matches($out, $mentionRx); $counts.mentions = $m.Count
$out = [regex]::Replace($out, $mentionRx, '(at:$1)')

# 4b. bot-trigger: /comando no inicio de linha (slash-command) -> (cmd:comando).
$botRx = '(?m)^\s*/([A-Za-z][A-Za-z0-9_\-]*)'
$m = [regex]::Matches($out, $botRx); $counts.bot_triggers = $m.Count
$out = [regex]::Replace($out, $botRx, '(cmd:$1)')

# 5. URI nao-HTTPS -> (redacted). https:// e mailto: passam; o resto e marcado.
$uriRx = '(?i)\b(?:http|ftp|file|ws|gopher)://\S+|(?i)\b(?:javascript|data|vbscript):\S+'
$m = [regex]::Matches($out, $uriRx); $counts.uris_redacted = $m.Count
$out = [regex]::Replace($out, $uriRx, '(redacted)')

# Entrega.
if ($OutPath -ne "") {
  WriteText $OutPath $out
}

Write-Host "=== sanitize-input ==="
Write-Host ("Origem:    " + $(if ($Text -ne "") { "(text)" } elseif ($Path -ne "") { $Path } else { "(stdin)" }))
Write-Host ("[sanitize-input] truncated=" + $counts.truncated + " control_ansi=" + $counts.control_ansi + " tags=" + $counts.tags + " mentions=" + $counts.mentions + " bot_triggers=" + $counts.bot_triggers + " uris_redacted=" + $counts.uris_redacted)
$total = 0; foreach ($k in $counts.Keys) { $total += $counts[$k] }
if ($total -gt 0) { Write-Host "[PASS] payload neutralizado" } else { Write-Host "[PASS] payload limpo (nada a neutralizar)" }
Write-Host "----- payload neutralizado -----"
Write-Output $out
exit 0
