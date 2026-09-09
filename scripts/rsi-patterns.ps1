<#
  rsi-patterns.ps1 - PECA 3 do motor de RSI: o detector de recorrencia.

  Varre memory/_proposals/ (staging vivo) E memory/_proposals/_archive/ (digests/atritos ja
  julgados) e procura o MESMO TIPO de item aparecendo em 3+ SESSOES DISTINTAS. So relata -
  NUNCA aplica nada, nunca escreve proposta pronta, nunca decide. Vira insumo de uma proposta
  de PECA 1 (rsi-apply.ps1) por decisao HUMANA.

  Duas fontes, dois classificadores:
    1. friction-*.md (PECA 2) - JA estruturado: cada item tem "tipo:" no proprio texto. So agrupa.
    2. reflection-inbox-*.md (digest) - texto livre. Aplica um classificador por palavra-chave,
       pequeno e deterministico, calibrado no historico REAL desta casa (nao inventado): os dois
       padroes que o operador ja registrou como recorrentes na memoria - delegacao furada
       (a Alia executa dominio sozinha em vez de delegar) e numero publico fossil (numero antigo
       repetido numa peca depois de ja ter mudado na fonte).

  Uso: scripts/rsi-patterns.ps1 [-ProposalsDir <caminho>] [-MinSessions 3] [-Write]
  -Write grava o relatorio (se achou algo) em memory/_proposals/patterns-<data>.md - sem isso,
  so imprime (nenhum efeito colateral por padrao). exit 0 sempre (detector nunca falha o hook). UTF-8 sem BOM.
#>
param(
  [string]$ProposalsDir = "",
  [int]$MinSessions = 3,
  [switch]$Write
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProposalsDir)) { $ProposalsDir = Join-Path $root "memory\_proposals" }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$today = (Get-Date).ToString("yyyy-MM-dd")

Write-Host "=== RSI Patterns (detector de recorrencia) ==="
Write-Host ("propostas: " + $ProposalsDir)
Write-Host ("minimo de sessoes distintas para virar candidato: " + $MinSessions)
Write-Host ""

if (-not (Test-Path -LiteralPath $ProposalsDir)) {
  Write-Host "[OK] sem pasta de propostas - nada para varrer."
  exit 0
}

$archiveDir = Join-Path $ProposalsDir "_archive"
$frictionFiles = @(Get-ChildItem -LiteralPath $ProposalsDir -Filter "friction-*.md" -File -ErrorAction SilentlyContinue)
$inboxFiles    = @(Get-ChildItem -LiteralPath $ProposalsDir -Filter "reflection-inbox-*.md" -File -ErrorAction SilentlyContinue)
if (Test-Path -LiteralPath $archiveDir) {
  $frictionFiles += @(Get-ChildItem -LiteralPath $archiveDir -Filter "friction-*.md" -File -ErrorAction SilentlyContinue)
  $inboxFiles    += @(Get-ChildItem -LiteralPath $archiveDir -Filter "reflection-inbox-*.md" -File -ErrorAction SilentlyContinue)
}

# JULGADO NAO SE RECONTA (TASK-289, WARDEN): arquivo de _archive/ que ja carrega uma secao
# "## Julgamento ... DESCARTADO" foi decidido a mao por um humano (protocolo "descartar com nota",
# nunca deletar) - este script nao sabia disso e recontava o item pra sempre em todo bucket, ja
# que a fonte nunca sai do disco. Caso real: memory/_proposals/_archive/friction-2026-08-14-agenta01.md
# (Julgamento 2026-08-17: falso positivo do regex, sub-agente confundido com operador) continuava
# entrando no bucket atrito:correcao-repetida a cada corrida. Pula o arquivo inteiro (o julgamento
# vale para TODOS os itens dele, nao so o citado na nota).
function Test-JulgadoDescartado {
  param([string]$path)
  $txt = [System.IO.File]::ReadAllText($path)
  return ($txt -match '(?m)^##\s*Julgamento.*DESCARTADO')
}
$julgados = New-Object System.Collections.Generic.List[string]
$frictionFiles = @($frictionFiles | Where-Object {
  if (Test-JulgadoDescartado $_.FullName) { $julgados.Add($_.Name); return $false }
  return $true
})
$inboxFiles = @($inboxFiles | Where-Object {
  if (Test-JulgadoDescartado $_.FullName) { $julgados.Add($_.Name); return $false }
  return $true
})
if ($julgados.Count -gt 0) {
  Write-Host ("[OK] " + $julgados.Count + " arquivo(s) JA JULGADO(S) (secao 'Julgamento ... DESCARTADO') pulado(s): " + ($julgados -join ", "))
}
Write-Host ("friction-*.md encontrados:        " + $frictionFiles.Count)
Write-Host ("reflection-inbox-*.md encontrados: " + $inboxFiles.Count)
Write-Host ""

# hits: lista de {Bucket, Session, Snippet, Fonte}
$hits = New-Object System.Collections.Generic.List[object]

# --- 1) friction-*.md: ja estruturado, so agrupa por "tipo:" ---
foreach ($f in $frictionFiles) {
  $txt = [System.IO.File]::ReadAllText($f.FullName)
  foreach ($m in [regex]::Matches($txt, '(?m)^-\s*severidade\s*(\d+)\s*\|\s*tipo:\s*(.+)$')) {
    $types = $m.Groups[2].Value.Split(',') | ForEach-Object { $_.Trim() }
    foreach ($t in $types) {
      if ([string]::IsNullOrWhiteSpace($t)) { continue }
      $hits.Add([PSCustomObject]@{ Bucket = "atrito:" + $t; Session = $f.BaseName; Snippet = $f.Name; Fonte = $f.Name })
    }
  }
}

# --- 2) reflection-inbox-*.md: classificador por palavra-chave, calibrado no historico real ---
# (ver memory/delegacao-furada-*.md e memory/mos-19-telas-auditadas.md, licao "3 numeros
# contraditorios"; e o README com numero fossil citado em reflection-inbox-2026-07-03-c5e36aa2.md)
$inboxRules = @(
  @{ Bucket = "digest:delegacao-furada"; Words = @(
      "sem delegar", "sem chamar um especialista", "sem acionar", "voce que fez isso",
      "vc que fez isso", "violou sua regra", "voce nao delegou", "vc nao delegou",
      "havia delegado", "ou vc estava fazendo isso", "duas leis furadas"
    ) }
  @{ Bucket = "digest:numero-publico-fossil"; Words = @(
      "numero fossil", "numero antigo", "numero desatualizado", "numeros contraditorios",
      "numero errado", "numero que nao bate"
    ) }
)
foreach ($f in $inboxFiles) {
  $txt = [System.IO.File]::ReadAllText($f.FullName).ToLowerInvariant()
  foreach ($rule in $inboxRules) {
    foreach ($w in $rule.Words) {
      if ($txt.Contains($w)) {
        $idx = $txt.IndexOf($w)
        $start = [Math]::Max(0, $idx - 40)
        $len = [Math]::Min(160, $txt.Length - $start)
        $snippet = $txt.Substring($start, $len).Trim()
        $hits.Add([PSCustomObject]@{ Bucket = $rule.Bucket; Session = $f.BaseName; Snippet = $snippet; Fonte = $f.Name })
        break   # 1 hit por regra por arquivo - a distinta e a SESSAO, nao a contagem de palavras
      }
    }
  }
}

# --- Agrupa por Bucket, conta SESSOES DISTINTAS ---
$byBucket = $hits | Group-Object Bucket
$candidates = New-Object System.Collections.Generic.List[object]
foreach ($g in $byBucket) {
  $sessions = @($g.Group | Select-Object -ExpandProperty Session -Unique)
  if ($sessions.Count -ge $MinSessions) {
    $candidates.Add([PSCustomObject]@{
      Bucket   = $g.Name
      Sessions = $sessions
      Items    = $g.Group
    })
  }
}

Write-Host ("--- Candidatos a padrao (>= " + $MinSessions + " sessoes distintas) ---")
if ($candidates.Count -eq 0) {
  Write-Host "[OK] nenhum padrao recorrente encontrado no volume atual."
} else {
  foreach ($c in $candidates) {
    Write-Host ""
    Write-Host ("[PADRAO] " + $c.Bucket + " - " + $c.Sessions.Count + " sessao(oes) distinta(s)")
    foreach ($it in $c.Items) {
      Write-Host ("    - sessao " + $it.Session + " (" + $it.Fonte + "): " + $it.Snippet)
    }
  }
}
Write-Host ""

# Buckets vistos mas ABAIXO do minimo - visivel, para nao dar a impressao de detector cego.
$below = $byBucket | Where-Object { $_.Name -notin @($candidates.Bucket) -and $_.Count -gt 0 }
if ($below) {
  Write-Host "--- Vistos, mas abaixo do minimo (nao viram candidato ainda) ---"
  foreach ($g in $below) {
    $sessions = @($g.Group | Select-Object -ExpandProperty Session -Unique)
    Write-Host ("  - " + $g.Name + ": " + $sessions.Count + " sessao(oes) distinta(s)")
  }
  Write-Host ""
}

if ($candidates.Count -gt 0 -and $Write) {
  $reportName = "patterns-" + $today
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("---")
  [void]$sb.AppendLine("name: " + $reportName)
  [void]$sb.AppendLine("description: Candidatos a padrao recorrente (scripts/rsi-patterns.ps1).")
  [void]$sb.AppendLine("metadata:")
  [void]$sb.AppendLine("  node_type: memory")
  [void]$sb.AppendLine("  type: pattern-report")
  [void]$sb.AppendLine("  status: proposed")
  [void]$sb.AppendLine("---")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("# Candidatos a padrao - " + $today)
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("> Gerado por scripts/rsi-patterns.ps1. NUNCA aplica nada - vira proposta de")
  [void]$sb.AppendLine("> PECA 1 (rsi-apply.ps1) so por decisao humana.")
  [void]$sb.AppendLine("")
  foreach ($c in $candidates) {
    [void]$sb.AppendLine("## " + $c.Bucket + " - " + $c.Sessions.Count + " sessao(oes) distinta(s)")
    [void]$sb.AppendLine("")
    foreach ($it in $c.Items) {
      [void]$sb.AppendLine("- sessao " + $it.Session + " (" + $it.Fonte + "): " + $it.Snippet)
    }
    [void]$sb.AppendLine("")
  }
  $reportFile = Join-Path $ProposalsDir ($reportName + ".md")
  New-Item -ItemType Directory -Force -Path $ProposalsDir | Out-Null
  [System.IO.File]::WriteAllText($reportFile, $sb.ToString(), $utf8)
  Write-Host ("[OK] relatorio gravado: " + $reportFile)
}

Write-Host ("Resumo: " + $candidates.Count + " padrao(oes) candidato(s) | " + $hits.Count + " ocorrencia(s) brutas | " + $byBucket.Count + " bucket(s) tocado(s)")
exit 0
