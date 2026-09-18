<#
  read-shunt-guard.ps1 - Hook de PreToolUse. Nega leitura INTEIRA de arquivo grande no ato e
  aponta a rota (fatia com offset/limit, ou delega ao leitor em massa em modelo barato).

  ORIGEM (TASK-559, motor 1.75.0): engenharia do artigo "Portal by Spotify cut my Claude Code
  token usage by 90%" adaptada ao Alia Flow. MEDIDO (30 dias de transcricoes reais do studio,
  1.436 transcricoes, 82 mil turnos): Read = 16.751 chamadas, 92,9 MB (53% de todo byte devolvido
  por ferramenta); 909 Reads de arquivo > 350 linhas SEM offset/limit = 29,7 MB; mais 148
  cat/Get-Content grandes via Bash = 3,1 MB. Prova do mecanismo (4 cenarios reais, sub-agente
  Explore model=haiku devolvendo so bullets): arquivo de 53 KB virou 2,8 KB; 59 KB virou 3,0 KB;
  38 KB virou 1,9 KB; 255 KB virou 1,7 KB (media 96% a menos no contexto do modelo caro).
  `claude -p` aninhado NAO funciona aqui (o CLI recusa sessao dentro de sessao) - a "Portal" desta
  casa e o proprio sub-agente do host (Agent, subagent_type Explore, model haiku), nao um wrapper
  CLI externo.

  Contrato do hook: JSON no STDIN (session_id, tool_name, tool_input). Contrato de RECUSA
  identico ao de delegation-gate.ps1 / graph-usage-sensor.ps1 (reuse-first):
    {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
     "permissionDecisionReason":"<texto>"}}
  Sem violacao (ou fora de escopo): retorno vazio - "allow" e o default quando o hook nao
  imprime nada.

  REGRA: tool_name=Read com offset OU limit em tool_input -> sempre allow (leitura direcionada).
  Sem offset/limit, arquivo com mais linhas que o teto -> deny. tool_name=Bash/PowerShell: so o
  ULTIMO estagio de cada pipeline (separado por &&, ; , ||, depois por |) e considerado; casa
  cat/type/Get-Content/gc do arquivo inteiro -> deny; head/tail/sed/awk/grep/wc/Select-String
  nunca casam (leitura direcionada). Caminho relativo resolve contra um `cd <dir>` anterior no
  mesmo comando ou contra tool_input.cwd; nao resolvendo, allow (duvida de parse = allow).

  Teto: $env:ALIA_SHUNT_MIN_LINES (default 350, espelho do SHUNT_MIN_LINES do Spotify). Contagem
  de linhas para em teto+1 via StreamReader (nunca le o arquivo inteiro pra memoria) - por isso o
  N do aviso pode ficar em teto+1 em vez do total exato num arquivo muito maior que o teto; o que
  importa pro guard e "esta acima do teto", nao o total exato.

  INTERRUPTOR DE EMERGENCIA (mesmo padrao dos outros guards): env ALIA_READ_SHUNT_OFF=1 (ou
  "true") OU arquivo .claude/read-shunt.off (qualquer conteudo) desligam SO o bloqueio.

  Nunca nega: caminho contendo .claude/, memory/, _backups/, node_modules/, AppData/Local/Temp/
  (com ou sem barra invertida), nem extensao de imagem/binario (png, jpg, jpeg, gif, webp, svg,
  pdf, ico, woff, woff2). Arquivo inexistente = allow.

  LEDGER (a medida de adocao): a cada deny, 1 linha JSON em studio/read-shunt-log.jsonl sob
  $Root (ou -LedgerPath) - {ts, session, tool, path, lines, bytes, decision:"deny"}. Erro interno
  tambem grava 1 linha {ts, session, erro, fase} e segue liberando (fail-open).

  BLINDAGEM: tudo dentro de try/catch. Qualquer erro -> retorno vazio / exit 0. Guarda quebrado
  nunca trava o operador.

  PARAMETROS DE TESTE (WARDEN): -Root, -LedgerPath sao overrides SO para fixture de smoke test
  (mesmo padrao de -Root em graph-usage-sensor.ps1 e delegation-gate.ps1). O hook de producao
  nunca passa esses params. Escrita .NET UTF-8 sem BOM. Portugues correto, com acentos.
#>
param(
  [string]$Root = "",
  [string]$LedgerPath = "",
  [string]$RawInput = $null
)

function Test-ReadShuntExcluded {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
  $norm = '/' + $Path.Replace('\', '/').ToLowerInvariant().TrimStart('/')
  $excludeSubstrings = @('/.claude/', '/memory/', '/_backups/', '/node_modules/', '/appdata/local/temp/')
  foreach ($ex in $excludeSubstrings) { if ($norm.Contains($ex)) { return $true } }
  $binaryExt = @('png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'pdf', 'ico', 'woff', 'woff2')
  $ext = ""
  try { $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant().TrimStart('.') } catch { }
  if ($binaryExt -contains $ext) { return $true }
  return $false
}

function Get-ReadShuntLineCount {
  param([string]$Path, [int]$Cap)
  $n = 0
  $sr = $null
  try {
    $sr = New-Object System.IO.StreamReader($Path)
    while ($null -ne $sr.ReadLine()) {
      $n++
      if ($n -gt $Cap) { break }
    }
  } catch {
    return -1
  } finally {
    if ($sr) { $sr.Close() }
  }
  return $n
}

function New-ReadShuntDenyJson {
  param([string]$Path, [int]$Lines, [int]$Teto)
  $bytes = 0
  try { $bytes = (Get-Item -LiteralPath $Path).Length } catch { }
  $k = [math]::Round(($bytes / 4.0) / 1000.0)
  $reason = ('[LEITOR] {0} tem mais de {2} linhas (teto {2}). Ler inteiro põe ~{3}k tokens no contexto, e eles voltam a cada turno. Rotas, na ordem: 1) Vai EDITAR ou precisa do trecho exato: Read com offset/limit (fatia) ou Grep pelo header/símbolo; Read com limit é sempre liberado. 2) Precisa ENTENDER o arquivo: delegue ao leitor em massa (modelo barato, devolve resumo) - o próprio leitor lê com Read em fatias de 1000 linhas (offset/limit) até o fim do arquivo, nunca Read sem offset/limit (o hook nega igual dentro do sub-agente): Agent(subagent_type="Explore", model="haiku", prompt=<molde em skills/leitura-em-massa/SKILL.md: arquivo + pergunta + contrato só bullets, máx 30 linhas, cite L:>). 3) Sem a ferramenta Agent: fatie por header/símbolo; nunca cat/Get-Content inteiro. Desligar: ALIA_READ_SHUNT_OFF=1 ou .claude/read-shunt.off. Teto: ALIA_SHUNT_MIN_LINES.' -f $Path, $Lines, $Teto, $k)
  $out = [ordered]@{
    hookSpecificOutput = [ordered]@{
      hookEventName            = "PreToolUse"
      permissionDecision       = "deny"
      permissionDecisionReason = $reason
    }
  }
  return [ordered]@{ json = ($out | ConvertTo-Json -Depth 5 -Compress); bytes = $bytes }
}

function Write-ReadShuntLedgerLine {
  param([string]$LedgerFile, $Entry)
  try {
    $dir = Split-Path -Parent $LedgerFile
    if (-not [string]::IsNullOrWhiteSpace($dir)) { New-Item -ItemType Directory -Force -Path $dir -ErrorAction SilentlyContinue | Out-Null }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($LedgerFile, (($Entry | ConvertTo-Json -Compress) + "`n"), $utf8)
  } catch { }
}

function Invoke-ReadShuntGuard {
  param(
    [string]$RawInput = $null,
    [string]$Root = "",
    [string]$LedgerPath = ""
  )

  $rootResolved = if (-not [string]::IsNullOrWhiteSpace($Root)) { $Root } else { Split-Path -Parent $PSScriptRoot }
  $ledgerFile = if (-not [string]::IsNullOrWhiteSpace($LedgerPath)) { $LedgerPath } else { Join-Path (Join-Path $rootResolved "studio") "read-shunt-log.jsonl" }
  $sessionId = ""

  try {
    if ([string]::IsNullOrWhiteSpace($RawInput)) { return "" }
    $h = $null
    try { $h = $RawInput | ConvertFrom-Json } catch { return "" }
    if ($null -eq $h) { return "" }

    $tool = ""
    try { $tool = [string]$h.tool_name } catch { }
    if ([string]::IsNullOrWhiteSpace($tool)) { return "" }
    if ($tool -ne 'Read' -and $tool -ne 'Bash' -and $tool -ne 'PowerShell') { return "" }

    try { $sessionId = [string]$h.session_id } catch { }

    $teto = 350
    $tetoRaw = $env:ALIA_SHUNT_MIN_LINES
    if (-not [string]::IsNullOrWhiteSpace($tetoRaw)) {
      $parsedTeto = 0
      if ([int]::TryParse($tetoRaw, [ref]$parsedTeto)) { $teto = $parsedTeto }
    }

    $offEnv = $env:ALIA_READ_SHUNT_OFF
    $shuntOff = ($offEnv -eq "1") -or ($offEnv -eq "true")
    $offFile = Join-Path $rootResolved ".claude\read-shunt.off"
    if (Test-Path -LiteralPath $offFile) { $shuntOff = $true }
    if ($shuntOff) { return "" }

    if ($tool -eq 'Read') {
      $ti = $h.tool_input
      $hasOffset = $false
      $hasLimit = $false
      try { if ($ti -and ($ti.PSObject.Properties.Name -contains 'offset')) { $hasOffset = $true } } catch { }
      try { if ($ti -and ($ti.PSObject.Properties.Name -contains 'limit')) { $hasLimit = $true } } catch { }
      if ($hasOffset -or $hasLimit) { return "" }

      $fp = ""
      try { $fp = [string]$ti.file_path } catch { }
      if ([string]::IsNullOrWhiteSpace($fp)) { return "" }
      if (Test-ReadShuntExcluded $fp) { return "" }
      if (-not (Test-Path -LiteralPath $fp -PathType Leaf)) { return "" }

      $n = Get-ReadShuntLineCount -Path $fp -Cap $teto
      if ($n -le $teto) { return "" }

      $d = New-ReadShuntDenyJson -Path $fp -Lines $n -Teto $teto
      Write-ReadShuntLedgerLine -LedgerFile $ledgerFile -Entry ([ordered]@{ ts = (Get-Date).ToUniversalTime().ToString("o"); session = $sessionId; tool = $tool; path = $fp; lines = $n; bytes = $d.bytes; decision = "deny" })
      return $d.json
    }

    # Bash / PowerShell: divide por &&, ; , || (statements); dentro de cada statement, divide por
    # | e considera so o ULTIMO estagio.
    $cmd = ""
    try { $cmd = [string]$h.tool_input.command } catch { }
    if ([string]::IsNullOrWhiteSpace($cmd)) { return "" }
    $cwd = ""
    try { $cwd = [string]$h.tool_input.cwd } catch { }
    if ([string]::IsNullOrWhiteSpace($cwd)) { try { $cwd = [string]$h.cwd } catch { } }

    $statements = [regex]::Split($cmd, '&&|\|\||;')
    $lastCdDir = ""
    $catPattern = '^\s*(cat|type|Get-Content|gc)(\s+-{1,2}\S+)*\s+("[^"]+"|''[^'']+''|\S+)'

    foreach ($stmt in $statements) {
      $s = $stmt.Trim()
      if ([string]::IsNullOrWhiteSpace($s)) { continue }

      $cdM = [regex]::Match($s, '^cd\s+(.+)$', 'IgnoreCase')
      if ($cdM.Success) {
        $lastCdDir = $cdM.Groups[1].Value.Trim().Trim('"').Trim("'")
        continue
      }

      $stages = [regex]::Split($s, '\|')
      $last = $stages[$stages.Length - 1].Trim()
      # TASK-559 (item 2, gate do Nexus): -TotalCount/-Head/-Tail/-First/-Last sao leitura
      # DIRECIONADA (o equivalente de offset/limit do Get-Content) - o catPattern generico casava
      # so a flag "-Path" e perdia esses tokens depois dela, tratando "Get-Content -Path X
      # -TotalCount 20" como leitura inteira de X. Excluidos ANTES do match.
      if ($last -match '(?i)-(TotalCount|Head|Tail|First|Last)\b') { continue }
      $m = [regex]::Match($last, $catPattern, 'IgnoreCase')
      if (-not $m.Success) { continue }

      $rawPath = $m.Groups[3].Value.Trim().Trim('"').Trim("'")
      if ([string]::IsNullOrWhiteSpace($rawPath)) { continue }

      $resolved = $rawPath
      $isRooted = $false
      try { $isRooted = [System.IO.Path]::IsPathRooted($rawPath) } catch { }
      if (-not $isRooted) {
        if (-not [string]::IsNullOrWhiteSpace($lastCdDir)) { $resolved = Join-Path $lastCdDir $rawPath }
        elseif (-not [string]::IsNullOrWhiteSpace($cwd)) { $resolved = Join-Path $cwd $rawPath }
        else { continue }  # nao resolve -> allow (duvida de parse)
      }

      if (Test-ReadShuntExcluded $resolved) { continue }
      if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { continue }

      $n = Get-ReadShuntLineCount -Path $resolved -Cap $teto
      if ($n -le $teto) { continue }

      $d = New-ReadShuntDenyJson -Path $resolved -Lines $n -Teto $teto
      Write-ReadShuntLedgerLine -LedgerFile $ledgerFile -Entry ([ordered]@{ ts = (Get-Date).ToUniversalTime().ToString("o"); session = $sessionId; tool = $tool; path = $resolved; lines = $n; bytes = $d.bytes; decision = "deny" })
      return $d.json
    }

    return ""
  } catch {
    try {
      Write-ReadShuntLedgerLine -LedgerFile $ledgerFile -Entry ([ordered]@{ ts = (Get-Date).ToUniversalTime().ToString("o"); session = $sessionId; erro = $_.Exception.Message; fase = "Invoke-ReadShuntGuard" })
    } catch { }
    return ""
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  try {
    # CEO, TASK-559 (correcao pos-Gate): PowerShell escreve stdout na codepage do console, nao em
    # UTF-8 - acentos do texto do deny chegavam corrompidos ("pA?e", "sA-mbolo") no modelo. Forca
    # UTF-8 sem BOM ANTES de qualquer Write-Output.
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    $rawIn = $RawInput
    if ([string]::IsNullOrWhiteSpace($rawIn) -and [Console]::IsInputRedirected) {
      try {
        $readTask = [Console]::In.ReadToEndAsync()
        if ($readTask.Wait(2000)) { $rawIn = $readTask.Result }
      } catch { }
    }
    # TASK-569 (L64): teto de chamadas por especialista, checado ANTES do proprio shunt -
    # dot-source preserva/restaura $Root/$LedgerPath (budget-gate.ps1 declara os mesmos nomes).
    try {
      $bgPreservedRoot = $Root
      $bgPreservedLedgerPath = $LedgerPath
      . (Join-Path $PSScriptRoot "budget-gate.ps1")
      $Root = $bgPreservedRoot
      $LedgerPath = $bgPreservedLedgerPath
      $budgetOut = Invoke-BudgetGate -RawInput $rawIn -Root $Root
      if (-not [string]::IsNullOrWhiteSpace($budgetOut)) { Write-Output $budgetOut; exit 0 }
    } catch { }

    $result = Invoke-ReadShuntGuard -RawInput $rawIn -Root $Root -LedgerPath $LedgerPath
    if (-not [string]::IsNullOrWhiteSpace($result)) { Write-Output $result }
  } catch { }
  exit 0
}
