<#
  desperdicio.ps1 - o painel de desperdicio (GAUGE, TASK-685, etapa do plano TASK-680).

  Roda sobre os transcripts REAIS que o proprio Claude Code ja grava em disco (mesma fonte que
  cost-sensor.ps1 e response-guard.ps1 ja usam - $ProjectsDir\<slug>\*.jsonl) - SEM LLM, custo
  zero de modelo, deterministico. Responde 3 numeros por sessao, em CATRACA (o retrabalho so
  encolhe):
    1. perguntas feitas ANTES de executar (por sessao)
    2. reaberturas por tarefa (ver LIMITACAO MEDIDA abaixo - so parcialmente mensuravel)
    3. proporcao de mensagens do operador com marca de retrabalho (SEMPRE em par BRUTO/LIMPO)

  MOTIVO (TASK-685, 18/09/2026): o plano TASK-680 cravou 16,9% de retrabalho como base para uma
  pagina de diagnostico. Medido ao vivo contra os 137 transcripts reais desta instancia: 51,9% do
  que a pagina chamou de "mensagem do operador" (3.163 linhas role=user com texto, SEM FILTRO) na
  verdade e texto que o HARNESS injeta (<task-notification>, "Stop hook feedback:", etc.) e nao o
  Operador nunca digitou - restam 1.520 mensagens LIMPAS. O denominador sujo inflava tambem o
  numerador (82,4% do "retrabalho" contado no bruto vinha do proprio texto injetado, que contem a
  palavra "corrige"/"errado" na propria mecanica do Stop hook). A pagina estava errada, nao a
  medida - por isso o veredito abaixo SEMPRE mostra os dois numeros lado a lado, nunca um sozinho.

  NUNCA REINVENTA o filtro de texto injetado - a lista de marcadores abaixo (funcao
  Test-IsHarnessInjectedText) e uma COPIA LITERAL da mesma funcao em scripts/response-guard.ps1
  (mesmos 6 marcadores, mesmo comentario de origem). NAO e dot-source do arquivo original porque
  response-guard.ps1 tem corpo de execucao a NIVEL DE ARQUIVO (le STDIN e escreve log fora de
  qualquer funcao, contrato de hook de Stop) - dot-source dispararia esse corpo inteiro fora de
  contexto. Copiar a funcao pura (sem efeito colateral) foi o jeito seguro de reusar o MESMO
  criterio sem executar o hook. Se um dia response-guard.ps1 mudar a lista, esta copia tem que
  mudar junto (comentario deixado nos dois lados).

  CRITERIO DE CADA NUMERO (para quem quiser discordar, olhando so este arquivo):

  (1) PERGUNTA ANTES DE EXECUTAR: mensagem assistant cujos blocos de texto (type='text', nunca
      'thinking') concatenados terminam, na ULTIMA LINHA NAO VAZIA, com '?' (depois de Trim) E que
      NAO carrega nenhum bloco type='tool_use' NA MESMA MENSAGEM - "antes de executar" e o proprio
      turno ser so pergunta, nunca acao (medido primeiro contra o filtro mais estrito, "antes do
      1o tool_use de toda a sessao": deu 2 casos em 137 sessoes porque quase toda sessao chama uma
      tool nos primeiros turnos, o que TRANSFORMARIA o numero em "sessao nunca fez pergunta antes
      de tocar em ferramenta nenhuma" - proxy fraco demais pra ser util; o criterio por TURNO acima
      e o que fica). Sessao sem pergunta nenhuma conta 0, nunca fica de fora do denominador.

  (2) RETRABALHO: mensagem do OPERADOR (role=user, com texto, isSidechain != true) cujo texto
      (todos os blocos type='text' concatenados, minuscula, diacriticos removidos) bate qualquer
      um destes
      padroes - a lista e a MEDIDA, mudar a lista muda o numero, documentado aqui de proposito:
        "ta errado", "esta errado", "ta errada", "esta errada", "de novo", "refaz", "refazer",
        "corrige", "corrigir", "nao funciona", "faltou", "esqueceu", "esqueci", "nao era isso"
      BRUTO = sobre toda mensagem role=user com texto (o jeito que a pagina TASK-680 mediu).
      LIMPO = sobre a mesma populacao DEPOIS de remover Test-IsHarnessInjectedText (o jeito
      correto - ver MOTIVO acima). O veredito e catraca SEMPRE sobre o LIMPO.

  (3) REABERTURAS: LIMITACAO MEDIDA (D3, TASK-685) - nao existe no transcript nenhum campo que
      ligue duas invocacoes de um especialista a MESMA Task (agent-*.meta.json so grava
      {agentType, description, toolUseId, spawnDepth} - conferido ao vivo em disco, TASK-685;
      nenhum taskId). "Reaberturas por tarefa" portanto NAO E MENSURAVEL hoje sem inventar dado.
      O que ESTE script mede de fato, honesto sobre o que e: reaberturas por ESPECIALISTA POR
      SESSAO - quantas vezes o MESMO agentType foi spawnado mais de uma vez dentro da MESMA sessao
      (proxy adjacente, nao o numero pedido). Campo que faltaria para fechar a conta certa: um
      "taskId" gravado em agent-*.meta.json no ato do spawn (scripts/squad-bridge.ps1 ou o
      wrapper de Task/Agent), cruzando com o id que register-task.ps1 ja atribui em state.json.

  Uso:
    desperdicio.ps1 [-Dias 30] [-ProjectsDir <path>] [-Slug <slug>] [-Json]
  Sem -Slug: deriva do $PWD subindo ate achar "studio-farina" no caminho (a oficina fica dentro
  dele); mesmo padrao de derivacao de cost-sensor.ps1 ($PWD.Path -replace '[^a-zA-Z0-9]','-').
  So leitura: este script NUNCA escreve em disco (nem log, nem ledger).
  Escrita .NET UTF-8 sem BOM (so no -Json, via stdout).
#>
param(
  [int]$Dias = 30,
  [string]$ProjectsDir = "",
  [string]$Slug = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

# --- copia literal de Test-IsHarnessInjectedText (scripts/response-guard.ps1) - ver cabecalho ---
function Test-IsHarnessInjectedText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $t = $Text.TrimStart()
  if ($t.StartsWith('<task-notification')) { return $true }
  if ($t.StartsWith('Stop hook feedback:')) { return $true }
  if ($t.StartsWith('Another Claude session sent a message:')) { return $true }
  if ($t.Contains('<cross-session-message')) { return $true }
  if ($t.StartsWith('[Request interrupted by user for tool use]')) { return $true }
  if ($t.StartsWith('<system-reminder>')) { return $true }
  return $false
}

function Get-TextBlocks {
  # Mesmo contrato de Get-TextFromContent (response-guard.ps1): so blocos type='text', nunca
  # 'thinking' nem 'tool_use'/'tool_result'/'image'.
  param($content)
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

function Has-ToolUse {
  param($content)
  if ($null -eq $content -or ($content -is [string])) { return $false }
  foreach ($block in @($content)) {
    $bt = $null
    try { $bt = $block.type } catch { }
    if ($bt -eq 'tool_use') { return $true }
  }
  return $false
}

function Remove-Diacritics {
  param([string]$s)
  if ([string]::IsNullOrEmpty($s)) { return $s }
  $norm = $s.Normalize([System.Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $norm.ToCharArray()) {
    $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
    if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
  }
  return $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC)
}

# a MEDIDA (mudar esta lista muda o numero - ver criterio (2) no cabecalho).
$RETRABALHO_PATTERNS = @(
  "ta errado", "esta errado", "ta errada", "esta errada", "de novo", "refaz", "refazer",
  "corrige", "corrigir", "nao funciona", "faltou", "esqueceu", "esqueci", "nao era isso"
)

function Test-Retrabalho {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $flat = (Remove-Diacritics $Text).ToLowerInvariant()
  foreach ($p in $RETRABALHO_PATTERNS) {
    if ($flat.Contains($p)) { return $true }
  }
  return $false
}

function Get-LastNonEmptyLine {
  param([string]$Text)
  if ([string]::IsNullOrEmpty($Text)) { return "" }
  $lines = $Text -split "`n"
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $ln = $lines[$i].Trim()
    if ($ln -ne "") { return $ln }
  }
  return ""
}

$root = Split-Path -Parent $PSScriptRoot

if ($ProjectsDir -eq "") { $ProjectsDir = Join-Path $env:USERPROFILE ".claude/projects" }
if ($Slug -eq "") {
  $p = $PWD.Path
  if ($p -match '^(.*studio-farina)') { $p = $Matches[1] }
  $Slug = ($p -replace '[^a-zA-Z0-9]', '-')
}
$sessDir = Join-Path $ProjectsDir $Slug

Write-Host "=== Painel de Desperdicio (perguntas / reaberturas / retrabalho) ==="
Write-Host ("fonte: " + $sessDir)
Write-Host ("janela: ultimos " + $Dias + " dia(s) + agregado (todo o historico)")
Write-Host ""

function New-Vazio {
  [pscustomobject]@{
    sessoes = 0
    mensagensUserBruto = 0
    mensagensUserLimpo = 0
    retrabalhoBruto = 0
    retrabalhoLimpo = 0
    retrabalhoBrutoPct = $null
    retrabalhoLimpoPct = $null
    perguntasAntes = 0
    perguntasPorSessao = $null
    reaberturasEspecialista = 0
    reaberturasPorSessao = $null
    especialistasInvocados = 0
  }
}

if (-not (Test-Path -LiteralPath $sessDir)) {
  Write-Host ("[INFO] sem transcript para este slug (pasta nao existe: " + $sessDir + ") - nada a medir")
  if ($Json) {
    $out = [pscustomobject]@{
      ts = (Get-Date).ToString("o"); slug = $Slug; sessDir = $sessDir
      dias = $Dias; janela = (New-Vazio); agregado = (New-Vazio)
      reaberturasPorTarefa = $null
      falta = "sem transcript no ProjectsDir/Slug informado"
    }
    $out | ConvertTo-Json -Depth 6 -Compress
  }
  exit 0
}

$cutoff = (Get-Date).ToUniversalTime().AddDays(-$Dias)
$inv = [System.Globalization.CultureInfo]::InvariantCulture
$styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal

$jsonlFiles = Get-ChildItem -LiteralPath $sessDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue

# acumuladores: agregado (todo o historico) e janela (ultimos $Dias dias)
$agg = @{ sessoesSet = New-Object 'System.Collections.Generic.HashSet[string]'; userBruto = 0; userLimpo = 0; retrBruto = 0; retrLimpo = 0; perguntas = 0; reaberturas = 0; especialistas = 0; sessoesComEspecialista = New-Object 'System.Collections.Generic.HashSet[string]' }
$jan = @{ sessoesSet = New-Object 'System.Collections.Generic.HashSet[string]'; userBruto = 0; userLimpo = 0; retrBruto = 0; retrLimpo = 0; perguntas = 0; reaberturas = 0; especialistas = 0; sessoesComEspecialista = New-Object 'System.Collections.Generic.HashSet[string]' }

foreach ($f in $jsonlFiles) {
  $sid = $f.BaseName
  $lines = [System.IO.File]::ReadAllLines($f.FullName)
  $questoes = New-Object System.Collections.Generic.List[object]   # {naJanela}
  $sessaoTemFala = $false
  $sessaoTemMsgNaJanela = $false

  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $o = $null
    try { $o = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
    if ($null -eq $o) { continue }
    $isSidechain = $false
    try { $isSidechain = [bool]$o.isSidechain } catch { }
    if ($isSidechain) { continue }
    $ts = [datetime]::MinValue
    try { $ts = [datetime]::Parse([string]$o.timestamp, $inv, $styles) } catch { }
    $naJanela = ($ts -ge $cutoff)
    if ($naJanela) { $sessaoTemMsgNaJanela = $true }

    $ttype = $null
    try { $ttype = [string]$o.type } catch { }
    $content = $null
    try { $content = $o.message.content } catch { }

    if ($ttype -eq 'assistant') {
      $textos = Get-TextBlocks $content
      if (@($textos).Count -gt 0) {
        $sessaoTemFala = $true
        $joined = ($textos -join "`n")
        $lastLine = Get-LastNonEmptyLine $joined
        if ($lastLine.EndsWith('?') -and -not (Has-ToolUse $content)) {
          $questoes.Add([pscustomobject]@{ naJanela = $naJanela })
        }
      }
      continue
    }

    if ($ttype -eq 'user') {
      $role = $null
      try { $role = [string]$o.message.role } catch { }
      if ($role -ne 'user') { continue }
      $textos = Get-TextBlocks $content
      if (@($textos).Count -eq 0) { continue }
      $joined = ($textos -join "`n")
      $isInjected = Test-IsHarnessInjectedText $joined
      $isRetr = Test-Retrabalho $joined

      $agg.userBruto++
      if ($isRetr) { $agg.retrBruto++ }
      if (-not $isInjected) {
        $agg.userLimpo++
        if ($isRetr) { $agg.retrLimpo++ }
      }
      if ($naJanela) {
        $jan.userBruto++
        if ($isRetr) { $jan.retrBruto++ }
        if (-not $isInjected) {
          $jan.userLimpo++
          if ($isRetr) { $jan.retrLimpo++ }
        }
      }
    }
  }

  # perguntas "antes de executar": turno so-pergunta, sem tool_use na mesma mensagem (ver criterio
  # (1) no cabecalho).
  foreach ($q in $questoes) {
    $agg.perguntas++
    if ($q.naJanela) { $jan.perguntas++ }
  }

  if ($sessaoTemFala) {
    [void]$agg.sessoesSet.Add($sid)
    if ($sessaoTemMsgNaJanela) { [void]$jan.sessoesSet.Add($sid) }
  }

  # reaberturas: mesmo agentType spawnado >1x na MESMA sessao (proxy - ver LIMITACAO no cabecalho)
  $subDir = Join-Path $sessDir (Join-Path $sid "subagents")
  if (Test-Path -LiteralPath $subDir) {
    $metaFiles = Get-ChildItem -LiteralPath $subDir -Filter "*.meta.json" -File -ErrorAction SilentlyContinue
    if (@($metaFiles).Count -gt 0) {
      $porTipo = @{}
      foreach ($mf in $metaFiles) {
        $mo = $null
        try { $mo = (Get-Content -LiteralPath $mf.FullName -Raw -Encoding UTF8) | ConvertFrom-Json } catch { continue }
        $at = $null
        try { $at = [string]$mo.agentType } catch { }
        if ([string]::IsNullOrWhiteSpace($at)) { $at = "(desconhecido)" }
        if (-not $porTipo.ContainsKey($at)) { $porTipo[$at] = 0 }
        $porTipo[$at]++
      }
      $reab = 0
      foreach ($k in $porTipo.Keys) { if ($porTipo[$k] -gt 1) { $reab += ($porTipo[$k] - 1) } }
      $totalEsp = ($porTipo.Values | Measure-Object -Sum).Sum
      $agg.especialistas += $totalEsp
      $agg.reaberturas += $reab
      if ($reab -gt 0) { [void]$agg.sessoesComEspecialista.Add($sid) }
      if ($sessaoTemMsgNaJanela) {
        $jan.especialistas += $totalEsp
        $jan.reaberturas += $reab
        if ($reab -gt 0) { [void]$jan.sessoesComEspecialista.Add($sid) }
      }
    }
  }
}

function Build-Resultado {
  param($acc)
  $sessoes = $acc.sessoesSet.Count
  $r = New-Vazio
  $r.sessoes = $sessoes
  $r.mensagensUserBruto = $acc.userBruto
  $r.mensagensUserLimpo = $acc.userLimpo
  $r.retrabalhoBruto = $acc.retrBruto
  $r.retrabalhoLimpo = $acc.retrLimpo
  if ($acc.userBruto -gt 0) { $r.retrabalhoBrutoPct = [math]::Round(100.0 * $acc.retrBruto / $acc.userBruto, 1) }
  if ($acc.userLimpo -gt 0) { $r.retrabalhoLimpoPct = [math]::Round(100.0 * $acc.retrLimpo / $acc.userLimpo, 1) }
  $r.perguntasAntes = $acc.perguntas
  if ($sessoes -gt 0) { $r.perguntasPorSessao = [math]::Round(1.0 * $acc.perguntas / $sessoes, 2) }
  $r.reaberturasEspecialista = $acc.reaberturas
  if ($sessoes -gt 0) { $r.reaberturasPorSessao = [math]::Round(1.0 * $acc.reaberturas / $sessoes, 2) }
  $r.especialistasInvocados = $acc.especialistas
  return $r
}

$rAgg = Build-Resultado $agg
$rJan = Build-Resultado $jan

Write-Host ("-- JANELA (ultimos " + $Dias + " dia(s), desde " + $cutoff.ToString("yyyy-MM-dd") + ") --")
Write-Host ("sessoes: " + $rJan.sessoes)
Write-Host ("(1) perguntas antes de executar: " + $rJan.perguntasAntes + " | por sessao: " + $rJan.perguntasPorSessao)
Write-Host ("(2) retrabalho BRUTO: " + $rJan.retrabalhoBruto + "/" + $rJan.mensagensUserBruto + " = " + $rJan.retrabalhoBrutoPct + "%")
Write-Host ("(2) retrabalho LIMPO: " + $rJan.retrabalhoLimpo + "/" + $rJan.mensagensUserLimpo + " = " + $rJan.retrabalhoLimpoPct + "% (veredito)")
Write-Host ("(3) reaberturas de especialista por sessao (proxy, NAO 'por tarefa' - ver LIMITACAO no cabecalho): " + $rJan.reaberturasEspecialista + " | por sessao: " + $rJan.reaberturasPorSessao)
Write-Host ""
Write-Host "-- AGREGADO (todo o historico) --"
Write-Host ("sessoes: " + $rAgg.sessoes)
Write-Host ("(1) perguntas antes de executar: " + $rAgg.perguntasAntes + " | por sessao: " + $rAgg.perguntasPorSessao)
Write-Host ("(2) retrabalho BRUTO: " + $rAgg.retrabalhoBruto + "/" + $rAgg.mensagensUserBruto + " = " + $rAgg.retrabalhoBrutoPct + "%")
Write-Host ("(2) retrabalho LIMPO: " + $rAgg.retrabalhoLimpo + "/" + $rAgg.mensagensUserLimpo + " = " + $rAgg.retrabalhoLimpoPct + "% (veredito)")
Write-Host ("(3) reaberturas de especialista por sessao (proxy): " + $rAgg.reaberturasEspecialista + " | por sessao: " + $rAgg.reaberturasPorSessao)
Write-Host ""
Write-Host "[FALTA] reaberturas POR TAREFA (numero pedido no plano) nao e mensuravel: agent-*.meta.json"
Write-Host "        nao grava taskId nenhum (so agentType/description/toolUseId/spawnDepth, conferido em"
Write-Host "        disco). O numero (3) acima e o proxy mais proximo que o transcript sustenta."
Write-Host ""
Write-Host ("VEREDITO: retrabalho LIMPO agregado = " + $rAgg.retrabalhoLimpoPct + "% (compare com studio/desperdicio-baseline.txt - so pode ENCOLHER)")

if ($Json) {
  $out = [pscustomobject]@{
    ts = (Get-Date).ToString("o"); slug = $Slug; sessDir = $sessDir; dias = $Dias
    janela = $rJan; agregado = $rAgg
    reaberturasPorTarefa = $null
    falta = "reaberturas por tarefa nao mensuravel (sem taskId em agent-*.meta.json)"
  }
  $out | ConvertTo-Json -Depth 6 -Compress
}

exit 0
