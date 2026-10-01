<#
  capability-check.ps1 - a maquina do Capability Ledger (LEI L57, engine/governance/capability-ledger.md).

  POR QUE EXISTE (TASK-511, 09/09/2026): docs/CAPACIDADE-REAL.md foi medido em 10/08/2026 na
  v1.46.0. O motor andou 43 versoes ate a v1.71.1 e NADA avisou que a medicao tinha vencido. A
  coordenadora leu os selos velhos e os afirmou ao Operator como estado de hoje. A casa tinha
  catraca para grafo, acervo, linhagem, leis e harness - nenhuma para a propria PROMESSA.

  O QUE FAZ
    (a) le as linhas maquinais `CAP:` de docs/CAPACIDADE-REAL.md;
    (b) confere VALIDADE: idade acima do teto (-MaxAgeDays, default 14) ou versao medida diferente
        da VERSION atual do motor -> registro VENCIDO;
    (c) confere INTEGRIDADE: capacidade sem comando de prova, selo fora do vocabulario, id repetido;
    (d) com -Run, EXECUTA o comando de prova de cada capacidade FUNCIONA e reprova quem nao passa.

  VOCABULARIO DE SELO (fechado, ver capability-ledger.md): FUNCIONA | FUNCIONA PARCIAL |
  SO CONTRATO | NAO EXISTE. "existe mas nao provado" NAO e selo - foi essa ambiguidade que deixou
  a divida dormir um mes; o script REPROVA se ela voltar.

  FORMATO DA LINHA (uma por capacidade, dentro de docs/CAPACIDADE-REAL.md):
    CAP: <id> | <selo> | <versao> | <AAAA-MM-DD> | <comando de prova ou "-"> | <lacuna em 1 frase>

  Exit 0 = registro integro e no prazo. Exit 1 = vencido, incoerente, ou prova falhou com -Run.
  BLINDAGEM: erro de leitura vira FAIL explicito, nunca silencio.
#>
param(
  [string]$Root = "",
  [int]$MaxAgeDays = 14,
  [switch]$Run,
  [switch]$Quiet,
  [switch]$Restamp,
  [int]$TimeoutSec = 300
)

$ErrorActionPreference = "Continue"
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }

# PROVA FALHANDO (achado da coordenadora, TASK-787): status de MEDICAO, nao de capacidade -
# quando a prova falha, o -Restamp carimba versao+data de HOJE (mediu, so que deu errado) com este
# status, guardando o selo ANTERIOR no campo de lacuna pra poder devolver quando a prova passar de
# novo. Substitui o efeito colateral antigo (selo antigo parado numa versao velha, bloqueando o
# release por "vencido" quando na verdade so a PROVA falhou hoje).
$SELOS_VALIDOS = @("FUNCIONA", "FUNCIONA PARCIAL", "SO CONTRATO", "NAO EXISTE", "PROVA FALHANDO")
$fails = New-Object System.Collections.Generic.List[string]
$warns = New-Object System.Collections.Generic.List[string]

function Say($t) { if (-not $Quiet) { Write-Host $t } }

$ledgerPath = Join-Path $Root "docs\CAPACIDADE-REAL.md"
if (-not (Test-Path -LiteralPath $ledgerPath)) {
  Write-Host "[FAIL] registro ausente: docs/CAPACIDADE-REAL.md - sem ele nao ha o que afirmar sobre capacidade."
  exit 1
}

$versionPath = Join-Path $Root "VERSION"
$versaoMotor = ""
if (Test-Path -LiteralPath $versionPath) { $versaoMotor = ([System.IO.File]::ReadAllText($versionPath)).Trim() }

$linhas = @()
try {
  $raw = [System.IO.File]::ReadAllText($ledgerPath)
  $linhas = @($raw -split "`r?`n" | Where-Object { $_ -match '^\s*CAP:\s' })
} catch {
  Write-Host ("[FAIL] nao consegui ler o registro: " + $_.Exception.Message)
  exit 1
}

Say ""
Say "=== Capability Ledger (LEI L57) ==="
Say ("registro: " + $ledgerPath)
Say ("motor:    " + $versaoMotor + " | teto de validade: " + $MaxAgeDays + " dias ou mudanca de MINOR")
Say ""

if ($linhas.Count -eq 0) {
  Write-Host "[FAIL] o registro nao tem nenhuma linha CAP: - capacidade sem forma maquinal nao e conferivel."
  exit 1
}

# -Restamp (TASK-787, achado da coordenadora - causa raiz do "selo vencido carimbado a mao, sem
# medir"): carimbar e medir eram gestos SEPARADOS - alguem trocava a versao/data na mao sem rodar
# nada. Aqui os dois viram UM gesto so: re-roda o comando de prova que a PROPRIA linha ja declara;
# so carimba (versao atual + data de HOJE) quem passou de verdade; quem falhou ou estourou o teto
# de tempo fica com versao/data ANTIGAS (nunca muda data sem ter rodado) e entra na lista de
# pendentes com o motivo. Comandos IDENTICOS (varias linhas citam o mesmo "rode o smoke inteiro")
# rodam UMA vez so, nunca N vezes - o resultado se aplica a todas as linhas que citam esse comando.
# Extrai comando real + exit code ESPERADO do campo de prova. Marca "[exit N]" no FIM do campo
# declara a saida esperada (prova NEGATIVA - o esperado e falhar); sem marca, espera 0. CONSERTO
# (achado da coordenadora, defeito 2 de 3): antes -Restamp tratava QUALQUER exit != 0 como falha,
# inclusive quando a propria linha ja documentava que o comando existe pra DAR ERRO de proposito
# (ex.: rsi-apply.ps1 -Candidate inexistente-proposital).
function Get-ProvaComExitEsperado([string]$Prova) {
  $m = [regex]::Match($Prova, '^(.*?)\s*\[exit\s+(-?\d+)\]\s*$')
  if ($m.Success) { return @{ cmd = $m.Groups[1].Value.Trim(); exitEsperado = [int]$m.Groups[2].Value } }
  return @{ cmd = $Prova; exitEsperado = 0 }
}

# PROVA FALHANDO (achado da coordenadora): a lacuna guarda o SELO ANTERIOR + a LACUNA ANTERIOR
# codificados, pra devolver os dois quando a prova voltar a passar - sem isso, recuperar exigiria
# adivinhar. Formato: "[selo-anterior:<SELO>] <motivo curto de hoje> (lacuna original: <texto>)".
function New-LacunaFalha([string]$SeloAnterior, [string]$LacunaAnterior, [string]$MotivoAtual) {
  return ("[selo-anterior:" + $SeloAnterior + "] " + $MotivoAtual + " (lacuna original: " + $LacunaAnterior + ")")
}
function Get-LacunaFalhaInfo([string]$Lacuna) {
  $m = [regex]::Match($Lacuna, '^\[selo-anterior:([^\]]+)\]\s*(.*?)\s*\(lacuna original: (.*)\)$')
  if ($m.Success) { return @{ seloAnterior = $m.Groups[1].Value.Trim(); motivoAtual = $m.Groups[2].Value; lacunaAnterior = $m.Groups[3].Value } }
  return $null
}

if ($Restamp) {
  $hoje = (Get-Date).Date
  Say ""
  Say "=== capability-check -Restamp: re-medindo antes de carimbar ==="
  $restampGroups = @{}
  foreach ($ln in $linhas) {
    $corpo = ($ln -replace '^\s*CAP:\s*', '')
    $p = @($corpo -split '\s*\|\s*')
    if ($p.Count -lt 5) { continue }
    $prova = $p[4].Trim()
    if ($prova -eq "-" -or [string]::IsNullOrWhiteSpace($prova)) { continue }
    if (-not $restampGroups.ContainsKey($prova)) { $restampGroups[$prova] = $true }
  }
  $resultadoPorComando = @{}
  # CONSERTO (achado da coordenadora, defeito 1 de 3): quando a bateria (scripts/smoke-test.ps1) e
  # usada como PROVA de uma capacidade AQUI (-Restamp, nao -Run), o registro ainda esta parcialmente
  # velho no meio do proprio recarimbo - o check de "selo vencido" da bateria reprovava por
  # CONSTRUCAO (prova circular), nunca por defeito real. ALIA_CAPABILITY_RESTAMP=1 faz ESSE check
  # especifico virar SKIP "em recarimbo" so nesta execucao (ver scripts/smoke-test.ps1); fora do
  # -Restamp essa variavel nunca existe, o check continua cobrado normal.
  $env:ALIA_SKIP_L57_SELFCHECK = "1"
  $env:ALIA_CAPABILITY_RESTAMP = "1"
  foreach ($cmd in @($restampGroups.Keys)) {
    $parsed = Get-ProvaComExitEsperado $cmd
    $comandoReal = $parsed.cmd
    $exitEsperado = $parsed.exitEsperado
    Say ("  rodando (teto " + $TimeoutSec + "s, espera exit " + $exitEsperado + "): " + $comandoReal)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $job = Start-Job -ScriptBlock {
      param($c, $wd)
      Set-Location -LiteralPath $wd
      & powershell -ExecutionPolicy Bypass -NoProfile -Command $c *> $null
      $LASTEXITCODE
    } -ArgumentList $comandoReal, $Root
    $finished = Wait-Job -Job $job -Timeout $TimeoutSec
    if ($null -eq $finished) {
      Stop-Job -Job $job -ErrorAction SilentlyContinue
      Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
      $resultadoPorComando[$cmd] = @{ ok = $false; motivo = "estourou o teto de tempo (" + $TimeoutSec + "s) - nao carimbado" }
    } else {
      $exitReal = Receive-Job -Job $job
      Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
      $ok = ("$exitReal" -eq "$exitEsperado")
      $resultadoPorComando[$cmd] = @{ ok = $ok; motivo = $(if ($ok) { "" } else { "comando saiu com exit " + $exitReal + " (esperado " + $exitEsperado + ")" }) }
    }
    $sw.Stop()
    $veredito = if ($resultadoPorComando[$cmd].ok) { "PASSOU" } else { "FALHOU: " + $resultadoPorComando[$cmd].motivo }
    Say ("    -> " + $veredito + " (" + [math]::Round($sw.Elapsed.TotalSeconds, 1) + "s)")
  }
  Remove-Item Env:\ALIA_SKIP_L57_SELFCHECK -ErrorAction SilentlyContinue
  Remove-Item Env:\ALIA_CAPABILITY_RESTAMP -ErrorAction SilentlyContinue

  $rawFull = [System.IO.File]::ReadAllText($ledgerPath)
  $linhasRaw = @($rawFull -split "`r?`n")
  $novasLinhas = New-Object System.Collections.Generic.List[string]
  $restampCount = 0
  $recuperados = New-Object System.Collections.Generic.List[string]
  $provaFalhandoCount = 0
  $falhando = New-Object System.Collections.Generic.List[string]
  $semComandoAcompanha = 0
  $hojeStr = $hoje.ToString("yyyy-MM-dd")
  foreach ($L in $linhasRaw) {
    if ($L -notmatch '^\s*CAP:\s') { $novasLinhas.Add($L); continue }
    $corpo = ($L -replace '^\s*CAP:\s*', '')
    $p = @($corpo -split '\s*\|\s*')
    if ($p.Count -lt 5) { $novasLinhas.Add($L); continue }
    $id = $p[0].Trim(); $selo = $p[1].Trim().ToUpperInvariant(); $prova = $p[4].Trim()
    $lacunaAtual = if ($p.Count -ge 6) { $p[5].Trim() } else { "" }
    $falhaInfo = if ($selo -eq "PROVA FALHANDO") { Get-LacunaFalhaInfo $lacunaAtual } else { $null }

    if ($prova -eq "-" -or [string]::IsNullOrWhiteSpace($prova)) {
      # CONSERTO (achado da coordenadora, defeito 3 de 3): SEM comando de prova declarado, o
      # tratamento depende do que a linha AFIRMA. SO CONTRATO / NAO EXISTE nao afirmam que a
      # capacidade FUNCIONA - nao ha o que medir, entao acompanhar a versao do motor e honesto (a
      # DATA fica a antiga, porque nao houve medicao nova hoje). FUNCIONA / FUNCIONA PARCIAL sem
      # comando E uma afirmacao de funcionamento sem prova: vira PROVA FALHANDO (nunca fica
      # afirmando funcionamento sem prova parada numa versao velha).
      if ($selo -eq "SO CONTRATO" -or $selo -eq "NAO EXISTE") {
        $p[2] = $versaoMotor
        $novasLinhas.Add("CAP: " + ($p -join " | "))
        $semComandoAcompanha++
      } elseif ($selo -eq "PROVA FALHANDO" -and $null -ne $falhaInfo -and ($falhaInfo.seloAnterior -eq "SO CONTRATO" -or $falhaInfo.seloAnterior -eq "NAO EXISTE")) {
        # linha ja convertida cujo selo de origem nao afirma funcionamento - nao devia ter entrado
        # aqui, mas se entrou, so acompanha a versao tambem (mesma regra do ramo acima).
        $p[2] = $versaoMotor
        $novasLinhas.Add("CAP: " + ($p -join " | "))
        $semComandoAcompanha++
      } else {
        $seloParaGuardar = if ($null -ne $falhaInfo) { $falhaInfo.seloAnterior } else { $selo }
        $lacunaParaGuardar = if ($null -ne $falhaInfo) { $falhaInfo.lacunaAnterior } else { $lacunaAtual }
        $p[1] = "PROVA FALHANDO"
        $p[2] = $versaoMotor
        $p[3] = $hojeStr
        if ($p.Count -ge 6) { $p[5] = New-LacunaFalha $seloParaGuardar $lacunaParaGuardar "sem comando de prova" } else { $p += (New-LacunaFalha $seloParaGuardar $lacunaParaGuardar "sem comando de prova") }
        $novasLinhas.Add("CAP: " + ($p -join " | "))
        $falhando.Add($id + " (era " + $seloParaGuardar + "): sem comando de prova declarado")
        $provaFalhandoCount++
      }
      continue
    }

    $res = $resultadoPorComando[$prova]
    if ($null -ne $res -and $res.ok) {
      $p[2] = $versaoMotor
      $p[3] = $hojeStr
      if ($selo -eq "PROVA FALHANDO" -and $null -ne $falhaInfo) {
        # RECUPERACAO: a prova voltou a passar - devolve o selo e a lacuna que a linha afirmava
        # antes de comecar a falhar, nunca adivinhado.
        $p[1] = $falhaInfo.seloAnterior
        if ($p.Count -ge 6) { $p[5] = $falhaInfo.lacunaAnterior } else { $p += $falhaInfo.lacunaAnterior }
        $novasLinhas.Add("CAP: " + ($p -join " | "))
        $recuperados.Add($id + " (volta a " + $falhaInfo.seloAnterior + ")")
      } else {
        $novasLinhas.Add("CAP: " + ($p -join " | "))
      }
      $restampCount++
    } else {
      # CONSERTO (achado da coordenadora): prova falhou - o selo GANHA versao+data de HOJE (foi
      # medido, so que deu errado) com status PROVA FALHANDO, nunca mais parado numa versao velha
      # bloqueando o release. Guarda o selo/lacuna ANTERIOR (so na PRIMEIRA vez que comeca a
      # falhar - se ja estava falhando, mantem o ANTERIOR original, so atualiza o motivo de hoje).
      $motivoFalha = if ($null -ne $res) { $res.motivo } else { "comando nao executado" }
      $seloParaGuardar = if ($null -ne $falhaInfo) { $falhaInfo.seloAnterior } else { $selo }
      $lacunaParaGuardar = if ($null -ne $falhaInfo) { $falhaInfo.lacunaAnterior } else { $lacunaAtual }
      $p[1] = "PROVA FALHANDO"
      $p[2] = $versaoMotor
      $p[3] = $hojeStr
      if ($p.Count -ge 6) { $p[5] = New-LacunaFalha $seloParaGuardar $lacunaParaGuardar $motivoFalha } else { $p += (New-LacunaFalha $seloParaGuardar $lacunaParaGuardar $motivoFalha) }
      $novasLinhas.Add("CAP: " + ($p -join " | "))
      $falhando.Add($id + " (era " + $seloParaGuardar + "): " + $motivoFalha)
      $provaFalhandoCount++
    }
  }
  [System.IO.File]::WriteAllText($ledgerPath, ($novasLinhas -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
  Say ""
  Say ("-Restamp: " + $restampCount + " capacidade(s) carimbada(s) para " + $versaoMotor + "/" + $hojeStr + " (" + $recuperados.Count + " recuperada(s) de PROVA FALHANDO) | " + $provaFalhandoCount + " viraram/continuam PROVA FALHANDO (versao+data de HOJE, selo anterior guardado) | " + $semComandoAcompanha + " (SO CONTRATO/NAO EXISTE) so acompanharam a versao")
  foreach ($rc in $recuperados) { Say ("  [recuperado] " + $rc) }
  foreach ($fl in $falhando) { Say ("  [prova falhando] " + $fl) }
  exit 0
}

$hoje = (Get-Date).Date
$vistos = @{}
$porSelo = @{}
foreach ($s in $SELOS_VALIDOS) { $porSelo[$s] = 0 }
$maisVelha = $null
$versoesDivergentes = New-Object System.Collections.Generic.List[string]
$provas = @()

foreach ($ln in $linhas) {
  $corpo = ($ln -replace '^\s*CAP:\s*', '')
  $p = @($corpo -split '\s*\|\s*')
  if ($p.Count -lt 5) { $fails.Add("linha CAP incompleta (precisa de id|selo|versao|data|prova): " + $corpo.Substring(0, [Math]::Min(70, $corpo.Length))); continue }

  $id = $p[0].Trim(); $selo = $p[1].Trim().ToUpperInvariant(); $ver = $p[2].Trim(); $data = $p[3].Trim(); $prova = $p[4].Trim()
  $lacuna = if ($p.Count -ge 6) { $p[5].Trim() } else { "" }

  if ($vistos.ContainsKey($id)) { $fails.Add("id repetido no registro: " + $id) } else { $vistos[$id] = $true }
  if ($SELOS_VALIDOS -notcontains $selo) { $fails.Add(("selo fora do vocabulario em " + $id + ": '" + $selo + "' (use FUNCIONA / FUNCIONA PARCIAL / SO CONTRATO / NAO EXISTE)")); continue }
  $porSelo[$selo] = $porSelo[$selo] + 1

  # CONSERTO (achado da coordenadora, defeito 3 de 3 do -Restamp): FUNCIONA PARCIAL sem comando e a
  # MESMA afirmacao sem prova que FUNCIONA sem comando - so o grau da promessa muda, a ausencia de
  # maquina e identica. Antes so FUNCIONA entrava aqui; FUNCIONA PARCIAL sem comando passava batido.
  if (($selo -eq "FUNCIONA" -or $selo -eq "FUNCIONA PARCIAL") -and ($prova -eq "-" -or [string]::IsNullOrWhiteSpace($prova))) {
    $fails.Add("capacidade " + $id + " esta " + $selo + " sem comando de prova - selo sem maquina e prosa")
  }
  if ($selo -ne "FUNCIONA" -and [string]::IsNullOrWhiteSpace($lacuna)) {
    $warns.Add("capacidade " + $id + " (" + $selo + ") sem a lacuna escrita - quem le nao sabe o que falta")
  }

  $d = $null
  try { $d = [datetime]::ParseExact($data, "yyyy-MM-dd", $null) } catch { }
  if ($null -eq $d) { $fails.Add("data invalida em " + $id + ": '" + $data + "' (use AAAA-MM-DD)") }
  else { if ($null -eq $maisVelha -or $d -lt $maisVelha) { $maisVelha = $d } }

  if (-not [string]::IsNullOrWhiteSpace($versaoMotor) -and $ver -ne $versaoMotor) { $versoesDivergentes.Add($id + " (medido em " + $ver + ")") }

  if ($Run -and $selo -eq "FUNCIONA" -and $prova -ne "-") { $provas += [PSCustomObject]@{ id = $id; cmd = $prova } }
}

Say ("capacidades no registro: " + $vistos.Count)
foreach ($s in $SELOS_VALIDOS) { Say ("  " + $s.PadRight(18) + $porSelo[$s]) }
Say ""

$idade = if ($null -ne $maisVelha) { [math]::Floor(($hoje - $maisVelha).TotalDays) } else { -1 }
if ($idade -ge 0) {
  Say ("medicao mais antiga: " + $maisVelha.ToString("yyyy-MM-dd") + " (" + $idade + " dias)")
  if ($idade -gt $MaxAgeDays) {
    $fails.Add("registro VENCIDO: a medicao mais antiga tem " + $idade + " dias (teto " + $MaxAgeDays + "). Selo vencido e historico, nao fonte - re-meça antes de afirmar capacidade.")
  }
}

if ($versoesDivergentes.Count -gt 0) {
  $amostra = ($versoesDivergentes | Select-Object -First 6) -join ", "
  $fails.Add("registro VENCIDO por versao: " + $versoesDivergentes.Count + " capacidade(s) medidas em versao diferente de " + $versaoMotor + " -> " + $amostra)
}

if ($Run -and $provas.Count -gt 0) {
  Say ""
  Say ("-- rodando " + $provas.Count + " prova(s) de capacidade FUNCIONA --")
  # TASK-580: varias provas sao literalmente "rode o smoke inteiro". O proprio smoke-test.ps1
  # embute o check do L57 (linha ~2444) - o mesmo cadeado que ESTE script ja confere acima
  # (idade/versao, linhas 113-124). Sem supressao, todo bump derruba o smoke por essa auto-
  # referencia e reprova a prova por construcao, nao por defeito real do motor. A variavel so
  # vale ao redor da execucao da prova (propaga ao processo filho, nunca ao ambiente do chamador).
  $env:ALIA_SKIP_L57_SELFCHECK = "1"
  foreach ($pr in $provas) {
    $ok = $false
    $saida = ""
    try {
      $saida = (& powershell -ExecutionPolicy Bypass -NoProfile -Command $pr.cmd 2>&1 | Out-String)
      $ok = ($LASTEXITCODE -eq 0)
    } catch { $ok = $false; $saida = $_.Exception.Message }
    if ($ok) { Say ("  [ok]   " + $pr.id) }
    else {
      $corte = if ($saida.Length -gt 120) { $saida.Substring(0, 120) } else { $saida }
      $fails.Add("prova de " + $pr.id + " FALHOU (selo diz FUNCIONA): " + ($corte -replace "`r?`n", " "))
    }
  }
  Remove-Item Env:\ALIA_SKIP_L57_SELFCHECK -ErrorAction SilentlyContinue
}

Say ""
foreach ($w in $warns) { Say ("[AVISO] " + $w) }
if ($fails.Count -eq 0) {
  Say "REGISTRO DE CAPACIDADE INTEGRO E NO PRAZO"
  exit 0
}
foreach ($f in $fails) { Write-Host ("[FAIL] " + $f) }
Write-Host ""
Write-Host ("REPROVADO: " + $fails.Count + " problema(s) no registro de capacidade. Re-meça com os comandos de prova e atualize docs/CAPACIDADE-REAL.md.")
exit 1
