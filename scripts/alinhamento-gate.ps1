<#
  alinhamento-gate.ps1 - Hook de UserPromptSubmit. O GATILHO que faltava para
  skills/alinhamento/SKILL.md (TASK-684): a regua ja existia completa (4 fatores, piso 5,
  gatilho duro DESFAZ=2, teto de 4 perguntas/2 rodadas) mas nada disparava a leitura dela -
  a capacidade "projetada com rigor, ligada por lembrete" que a auditoria de 04/08/2026 mediu
  como o padrao que mais se repete no motor. Este hook mede o PROPRIO texto do prompt contra
  sinais MEDIVEIS de superficie (nao substitui o julgamento da Alia - so garante que a regua
  seja LEMBRADA no momento certo, antes do trabalho comecar).

  PONTUACAO (espelha os 4 fatores da propria skill, 0 a 2 cada, total 0 a 8):
    DESFAZ     - sinal de peca publica/envio/exclusao/gasto/rumo de produto no texto
    REFAZ      - sinal de escopo grande/reescrita completa
    LEITURAS   - verbo vago sem objeto claro ("resolve", "ve isso", "da um jeito")
    DISTANCIA  - mais de uma superficie/publico citados no mesmo pedido

  DECISAO: total >= 5 (o piso da propria skill) OU DESFAZ = 2 (gatilho duro, igual a skill)
  -> imprime a obrigacao curta no stdout (o host injeta no contexto). Abaixo disso -> stdout
  vazio, SILENCIO TOTAL - requisito de custo, nao detalhe: a casa ja tirou delegation-guard.ps1
  de UserPromptSubmit em 09/09/2026 porque injetar em TODO prompt saia caro
  (.claude/rules/graphify-integration.md). Um portao que fala sempre repete esse erro.

  LEDGER: studio/alinhamento-log.jsonl - uma linha por prompt avaliado (inclusive silencioso):
  {ts, session, nota, sinais, decisao}. Substrato para medir desperdicio depois (nao construido
  aqui - fora de escopo desta Task).

  INTERRUPTOR DE EMERGENCIA (mesmo padrao de publish-gate.ps1/leitor-gate.ps1): env
  ALIA_ALINHAMENTO_GATE_OFF=1 (ou "true") OU arquivo .claude/alinhamento-gate.off (qualquer
  conteudo) desligam SO a fala - a medida no ledger continua.

  BLINDAGEM: tudo em try/catch. Qualquer erro -> retorno vazio (fail-open, mesma doutrina dos
  vizinhos - guarda quebrado nunca trava o operador).

  PARAMETROS DE TESTE (WARDEN): -Root, -LedgerPath, -RawInput sao overrides SO para fixture de
  smoke test (mesmo padrao de leitor-gate.ps1/publish-gate.ps1). O hook de producao nunca passa
  esses params - le stdin. UTF-8 sem BOM.
#>
param(
  [string]$Root = "",
  [string]$LedgerPath = "",
  [string]$RawInput = $null
)

function Get-AlinhamentoAsciiFold {
  # mesmo proposito de Get-LeitorAsciiFold em leitor-gate.ps1: casamento robusto a acento,
  # independente do encoding com que o host le este .ps1 em runtime.
  param([string]$Text)
  if ([string]::IsNullOrEmpty($Text)) { return "" }
  $norm = $Text.Normalize([System.Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $norm.ToCharArray()) {
    $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
    if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
  }
  return $sb.ToString().ToLowerInvariant()
}

function Get-AlinhamentoScore {
  param([string]$Prompt)

  $result = [ordered]@{
    desfaz     = 0
    refaz      = 0
    leituras   = 0
    distancia  = 0
    total      = 0
  }
  if ([string]::IsNullOrWhiteSpace($Prompt)) { return $result }

  $f = Get-AlinhamentoAsciiFold -Text $Prompt

  # DESFAZ = 2 (gatilho duro): peca publica, envio, exclusao, gasto, rumo de produto.
  $desfazPatterns = @(
    'publica', 'publicar', 'publicacao', 'deploy', 'sobe pro ar', 'coloca no ar',
    'manda pro cliente', 'envia', 'enviar', 'apaga', 'deleta', 'excluir', 'exclusao',
    'descarta', '\bpaga\b', 'pagar', 'gasta', 'gasto', 'compra', 'assina', 'git push',
    'propagad', 'sobe pro github', 'atualiza.{0,3}o github', 'muda o preco',
    'muda o posicionamento', 'rumo do produto', 'decide sozinho'
  )
  foreach ($p in $desfazPatterns) { if ($f -match $p) { $result.desfaz = 2; break } }

  # REFAZ: escopo grande / reescrita completa (2), ou pedido longo/reescreve (1).
  $refazAltoPatterns = @('projeto inteiro', 'site inteiro', 'tudo de novo', 'do zero',
    'refaz tudo', 'landing inteira', 'app inteiro', 'motor inteiro', 'plano inteiro')
  $refazAlto = $false
  foreach ($p in $refazAltoPatterns) { if ($f -match $p) { $refazAlto = $true; break } }
  if ($refazAlto) {
    $result.refaz = 2
  } elseif (($f -match 'refaz') -or ($f -match 'reescreve') -or ($f -match 'redesenha') -or (($f -split '\s+').Count -gt 25)) {
    $result.refaz = 1
  }

  # LEITURAS: verbo vago sem objeto claro sobrevive a mais de uma leitura.
  $leiturasAltoPatterns = @('\bresolve\b(?! o| a| isto que| que)', 've isso', '\bda um jeito\b',
    '\bconserta\b(?! o| a)', 'melhora isso', 'arruma isso', 'cuida disso',
    'faz o que achar melhor', '\bresolva\b')
  $leiturasAlto = $false
  foreach ($p in $leiturasAltoPatterns) { if ($f -match $p) { $leiturasAlto = $true; break } }
  if ($leiturasAlto) {
    $result.leituras = 2
  } elseif ($f -match '\bou\b') {
    $result.leituras = 1
  }

  # DISTANCIA: mais de uma superficie/publico citados no mesmo pedido.
  $superficies = @('landing', 'pagina', 'lp\b', 'copy', 'design', 'app', 'produto', 'cliente',
    'publico', 'github', 'deploy', 'marca', 'brand')
  $hits = 0
  foreach ($s in $superficies) { if ($f -match $s) { $hits++ } }
  if ($hits -ge 2) { $result.distancia = 2 } elseif ($hits -eq 1) { $result.distancia = 1 }

  $result.total = $result.desfaz + $result.refaz + $result.leituras + $result.distancia
  return $result
}

function Write-AlinhamentoLedgerLine {
  param([string]$LedgerFile, $Entry)
  try {
    $dir = Split-Path -Parent $LedgerFile
    if (-not [string]::IsNullOrWhiteSpace($dir)) { New-Item -ItemType Directory -Force -Path $dir -ErrorAction SilentlyContinue | Out-Null }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($LedgerFile, (($Entry | ConvertTo-Json -Compress) + "`n"), $utf8)
  } catch { }
}

function Invoke-AlinhamentoGate {
  param(
    [string]$RawInput = $null,
    [string]$Root = "",
    [string]$LedgerPath = ""
  )

  $rootResolved = if (-not [string]::IsNullOrWhiteSpace($Root)) { $Root } else { Split-Path -Parent $PSScriptRoot }
  $ledgerFile = if (-not [string]::IsNullOrWhiteSpace($LedgerPath)) { $LedgerPath } else { Join-Path (Join-Path $rootResolved "studio") "alinhamento-log.jsonl" }
  $sessionId = ""

  try {
    if ([string]::IsNullOrWhiteSpace($RawInput)) { return "" }
    $h = $null
    try { $h = $RawInput | ConvertFrom-Json } catch { return "" }
    if ($null -eq $h) { return "" }

    try { $sessionId = [string]$h.session_id } catch { }
    $prompt = ""
    try { $prompt = [string]$h.prompt } catch { }
    if ([string]::IsNullOrWhiteSpace($prompt)) { return "" }

    $score = Get-AlinhamentoScore -Prompt $prompt
    $dispara = ($score.total -ge 5) -or ($score.desfaz -eq 2)

    # interruptor de emergencia (so desliga a fala; a medida no ledger continua).
    $offEnv = $env:ALIA_ALINHAMENTO_GATE_OFF
    $gateOff = ($offEnv -eq "1") -or ($offEnv -eq "true")
    $offFile = Join-Path $rootResolved ".claude\alinhamento-gate.off"
    if (Test-Path -LiteralPath $offFile) { $gateOff = $true }

    $decisao = if (-not $dispara) { "silencio" } elseif ($gateOff) { "silencio-off" } else { "dispara" }
    $sinaisTxt = ("desfaz={0},refaz={1},leituras={2},distancia={3}" -f $score.desfaz, $score.refaz, $score.leituras, $score.distancia)
    Write-AlinhamentoLedgerLine -LedgerFile $ledgerFile -Entry ([ordered]@{
      ts      = (Get-Date).ToUniversalTime().ToString("o")
      session = $sessionId
      nota    = $score.total
      sinais  = $sinaisTxt
      decisao = $decisao
    })

    if (-not $dispara) { return "" }
    if ($gateOff) { return "" }

    return "[ALINHAMENTO] Este pedido pode ter mais de uma leitura ou mexer em algo caro de desfazer (peca publica, envio, exclusao, gasto ou rumo de produto). Antes de produzir: rode a regua de skills/alinhamento/SKILL.md, devolva o entendimento em uma frase e, se a nota der 5 ou mais, faca a rodada de ate 4 perguntas com recomendacao (Passo 3 da skill)."
  } catch {
    try {
      Write-AlinhamentoLedgerLine -LedgerFile $ledgerFile -Entry ([ordered]@{ ts = (Get-Date).ToUniversalTime().ToString("o"); session = $sessionId; erro = $_.Exception.Message; fase = "Invoke-AlinhamentoGate" })
    } catch { }
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
        if ($readTask.Wait(2000)) { $rawIn = $readTask.Result }
      } catch { }
    }
    $result = Invoke-AlinhamentoGate -RawInput $rawIn -Root $Root -LedgerPath $LedgerPath
    if (-not [string]::IsNullOrWhiteSpace($result)) { Write-Output $result }
  } catch { }
  exit 0
}
