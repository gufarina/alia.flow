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
  [switch]$Quiet
)

$ErrorActionPreference = "Continue"
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }

$SELOS_VALIDOS = @("FUNCIONA", "FUNCIONA PARCIAL", "SO CONTRATO", "NAO EXISTE")
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

  if ($selo -eq "FUNCIONA" -and ($prova -eq "-" -or [string]::IsNullOrWhiteSpace($prova))) {
    $fails.Add("capacidade " + $id + " esta FUNCIONA sem comando de prova - selo sem maquina e prosa")
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
