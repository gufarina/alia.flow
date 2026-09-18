<#
  publish-gate.ps1 - Hook de PreToolUse. Cerca de publicacao: um sub-agente (Specialist) nunca
  publica nem reescreve historico de git sozinho.

  INCIDENTE que motivou (TASK-603, aberto 16/09/2026): um Specialist rodou `git push` por Bash no
  meio da propria rodada e publicou no repositorio publico sem passar por ninguem. O portao de
  delegacao (delegation-gate.ps1) roda em PreToolUse para Edit/Write/Task, mas o matcher nunca
  cobriu comando de terminal - Bash e PowerShell passavam livre.

  DETECCAO DE CONTEXTO (reuse-first, MESMA forma que leitor-gate.ps1 ja usa e ja prova em producao
  para exatamente este formato de regra - sessao principal livre, sub-agente cercado):
  transcript_path (normalizado pra barra normal) contendo "/subagents/" = a chamada esta
  acontecendo DENTRO de um sub-agente. Sem essa substring = sessao principal (a Alia) - o gate
  NUNCA age, retorno vazio sempre. Esta e a MESMA leitura de payload que a REGRA (a) de
  leitor-gate.ps1 usa pro Task/Agent dentro de especialista (ver aquele arquivo, secao "ESCOPO");
  aqui so muda o tool_name vigiado (Bash/PowerShell, nao Task/Agent) e a lista de comandos negados.
  NAO reusa o marcador de sessao inteira de delegation-gate.ps1 (fallback "houve Task nesta
  sessao") de proposito: aquele fallback e mais fraco (janela = sessao inteira) e aqui a regra dura
  do Operator e o oposto - a sessao principal PRECISA continuar publicando old sem qualquer
  interferencia, mesmo depois de ja ter delegado a um Specialist na mesma sessao.

  NEGA (mesmo formato de recusa que delegation-gate.ps1 e leitor-gate.ps1 ja usam em producao -
  reuse-first, nao inventa segundo esquema):
    {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
     "permissionDecisionReason":"<texto>"}}
  Sem violacao (fora de sub-agente, comando nao listado, ou erro) -> retorno vazio ("" / sem
  stdout), que o host trata como "allow" (default).

  COMANDOS NEGADOS (dentro de sub-agente): git push, git commit, git tag, git remote, git init,
  git reset --hard, gh pr create, gh release. Casamento por regex \b (limite de palavra) contra
  tool_input.command inteiro - pega o comando em qualquer posicao de uma cadeia (&&, ;, |).

  INTERRUPTOR DE EMERGENCIA (mesmo padrao de delegation-gate.ps1/graph-usage-sensor.ps1): env
  ALIA_PUBLISH_GATE_OFF=1 (ou "true") OU arquivo .claude/publish-gate.off (qualquer conteudo)
  desligam SO o bloqueio - fail-soft, nunca trava o operador.

  BLINDAGEM: tudo em try/catch. Qualquer erro -> retorno vazio (fail-open, mesma doutrina dos
  vizinhos - guarda quebrado nunca trava o operador).

  LIMITACAO HONESTA (nao esconder): a mesma que leitor-gate.ps1 ja aceita - se o host algum dia
  parar de popular transcript_path com "/subagents/" pra chamada de dentro de um Task, este gate
  para de agir (fail-open, nunca fail-closed). Nao cobre segundo nivel de sub-agente com nome de
  ferramenta diferente de Bash/PowerShell (fora de escopo desta tarefa). Nao cobre `git push` via
  qualquer outro caminho que nao seja Bash/PowerShell (ex.: um MCP de git, se existir).

  PARAMETROS DE TESTE (WARDEN): -Root e -RawInput sao overrides SO para fixture de smoke test (
  mesmo padrao de -Root/-RawInput em delegation-gate.ps1 e leitor-gate.ps1). O hook de producao
  nunca passa esses params - le stdin. UTF-8 sem BOM.
#>
param(
  [string]$Root = "",
  [string]$RawInput = $null
)

function New-PublishDenyJson {
  param([string]$Reason)
  $out = [ordered]@{
    hookSpecificOutput = [ordered]@{
      hookEventName            = "PreToolUse"
      permissionDecision       = "deny"
      permissionDecisionReason = $Reason
    }
  }
  return ($out | ConvertTo-Json -Depth 5 -Compress)
}

function Invoke-PublishGate {
  param(
    [string]$RawInput = $null,
    [string]$Root = ""
  )

  try {
    if ([string]::IsNullOrWhiteSpace($RawInput)) { return "" }
    $h = $null
    try { $h = $RawInput | ConvertFrom-Json } catch { return "" }
    if ($null -eq $h) { return "" }

    $tool = ""
    try { $tool = [string]$h.tool_name } catch { }
    if ($tool -ne "Bash" -and $tool -ne "PowerShell") { return "" }

    # (1) escopo: so age dentro de sub-agente. Sessao principal segue livre sempre.
    $transcript = ""
    try { $transcript = [string]$h.transcript_path } catch { }
    if ([string]::IsNullOrWhiteSpace($transcript)) { return "" }
    if ($transcript.Replace('\', '/') -notmatch '/subagents/') { return "" }

    # (2) interruptor de emergencia.
    $offEnv = $env:ALIA_PUBLISH_GATE_OFF
    $gateOff = ($offEnv -eq "1") -or ($offEnv -eq "true")
    $rootResolved = if (-not [string]::IsNullOrWhiteSpace($Root)) { $Root } else { Split-Path -Parent $PSScriptRoot }
    $offFile = Join-Path $rootResolved ".claude\publish-gate.off"
    if (Test-Path -LiteralPath $offFile) { $gateOff = $true }
    if ($gateOff) { return "" }

    # (3) comando.
    $command = ""
    try { $command = [string]$h.tool_input.command } catch { }
    if ([string]::IsNullOrWhiteSpace($command)) { return "" }

    $patterns = @(
      'git\s+push',
      'git\s+commit',
      'git\s+tag',
      'git\s+remote',
      'git\s+init',
      'git\s+reset\s+--hard',
      'gh\s+pr\s+create',
      'gh\s+release'
    )
    foreach ($p in $patterns) {
      if ($command -match ('\b' + $p)) {
        $reason = "[PUBLICA] dentro de um sub-agente, comando que publica ou altera historico de git fica proibido: '" + $command.Trim() + "'. Specialist nunca publica - entregue o Artifact e deixe a sessao principal ou o COURIER publicar."
        return New-PublishDenyJson -Reason $reason
      }
    }

    return ""
  } catch {
    return ""
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  try {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    $rawIn = $RawInput
    if ([string]::IsNullOrWhiteSpace($rawIn) -and [Console]::IsInputRedirected) {
      try {
        $readTask = [Console]::In.ReadToEndAsync()
        if ($readTask.Wait(5000)) { $rawIn = $readTask.Result }
      } catch { }
    }
    $result = Invoke-PublishGate -RawInput $rawIn -Root $Root
    if (-not [string]::IsNullOrWhiteSpace($result)) { Write-Output $result }
  } catch { }
  exit 0
}
