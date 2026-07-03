<#
  memory-curator.ps1 - Mecanismo do loop agendado memory-curator (cadence: weekly, owner: alia).
  Spec: engine/governance/loops.catalog.yaml (scheduled_loops: memory-curator).
  Pergunta que responde: a memoria/regras do Client tem redundancia ou notas stale acumuladas?
  Curador semanal do loop de aprendizado: consolida memorias/regras e arquiva o que envelheceu.
  Espelha evolution-scan/debt-scan (semanais, dono alia). Le studio/clients/{Client}.
  Provenance (engine/governance/provenance.md): so toca agent-authored em studio/. NUNCA toca
  nucleo (arquivo com "provenance: nucleo"), NUNCA toca engine/, e NUNCA deleta. Para stale,
  ARQUIVA movendo para studio/clients/{Client}/_retired/ com motivo+data (caminho irma _retired/).
  Em -DryRun so LISTA - nada e movido. Frugal: so le mtime/git log e compara titulos.
  TTL (engine/governance/memory-types.md): alem do stale-por-data, honra o campo opcional
  `expires: YYYY-MM-DD`. Memoria tipo Estado com expires no passado expirou e e proposta para
  arquivamento; memoria critica (type: Decisoes|Preferencias) NUNCA expira por TTL (ignora expires).
  Escrita .NET UTF-8 sem BOM. Sem acentos, sem emojis. RSI propoe, Gate aprova.
#>
param(
  [Parameter(Mandatory = $true)][string]$Client,
  [int]$StaleDays = 90,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "_studio.ps1")
$studioRoot = Get-StudioRoot $root

# Aceita ambos os layouts: studio real OU studio.example (briefing). O real vence se existir.
$clientDir = Join-Path $studioRoot ("clients\" + $Client)
if (-not (Test-Path -LiteralPath $clientDir)) {
  $alt = Join-Path $root ("studio.example\clients\" + $Client)
  if (Test-Path -LiteralPath $alt) { $clientDir = $alt }
}
$knowDir = Join-Path $clientDir "squad\knowledge"

$utf8  = New-Object System.Text.UTF8Encoding($false)
$today = (Get-Date).ToString("yyyy-MM-dd")
$now   = Get-Date

Write-Host "=== Memory Curator Loop ==="
Write-Host ("client: " + $Client + " | data: " + $today + " | limiar stale: " + $StaleDays + " dia(s)")
Write-Host ("modo: " + $(if ($DryRun) { "DRY-RUN (so analisa, nada e movido)" } else { "RUN (arquiva stale em _retired/)" }))
Write-Host ""

if (-not (Test-Path -LiteralPath $clientDir)) {
  Write-Host ("[ERRO] diretorio do Client ausente: " + $clientDir)
  exit 1
}

# Ultima atividade por arquivo: git log -1 (data do ultimo commit), fallback mtime.
function Get-LastActivity {
  param([string]$path)
  try {
    $iso = & git -C $root log -1 --format=%cI -- "$path" 2>$null
    if ($LASTEXITCODE -eq 0 -and $iso) {
      $d = ([string]$iso).Trim() -as [datetime]
      if ($null -ne $d) { return @{ when = $d; via = "git" } }
    }
  } catch { }
  $fi = Get-Item -LiteralPath $path
  return @{ when = $fi.LastWriteTime; via = "mtime" }
}

# Normaliza um titulo/nome para comparar similaridade (heuristica simples de duplicata).
function Normalize-Title {
  param([string]$s)
  $t = ([string]$s).ToLowerInvariant()
  $t = ($t -replace '[^a-z0-9 ]', ' ')
  $t = ($t -replace '\s+', ' ').Trim()
  return $t
}

# (1) Coleta de candidatos: .md agent-authored em memory/ e squad/knowledge/.
# Exclui loop-reports/ (saida do proprio loop) e _retired/ (ja arquivado).
$scanRoots = @()
$memRoot = Join-Path $clientDir "memory"
if (Test-Path -LiteralPath $memRoot) { $scanRoots += $memRoot }
if (Test-Path -LiteralPath $knowDir) { $scanRoots += $knowDir }

$candidates = New-Object System.Collections.Generic.List[object]
$skippedNucleo = 0

foreach ($sr in $scanRoots) {
  $mds = @(Get-ChildItem -LiteralPath $sr -Filter "*.md" -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\loop-reports\\' -and $_.FullName -notmatch '\\_retired\\' })
  foreach ($f in $mds) {
    $text = [System.IO.File]::ReadAllText($f.FullName)
    # Provenance: pula qualquer arquivo marcado como nucleo (so o operador toca).
    if ($text -match '(?im)^\s*provenance\s*:\s*nucleo\b') {
      $skippedNucleo++
      continue
    }
    # Titulo = primeiro cabecalho "# ..."; fallback = nome base sem extensao.
    $title = ""
    $m = [regex]::Match($text, '(?m)^\s*#\s+(.+?)\s*$')
    if ($m.Success) { $title = $m.Groups[1].Value } else { $title = $f.BaseName }
    # Tipagem de memoria (engine/governance/memory-types.md): tipo opcional e TTL opcional.
    # type: Preferencias|Decisoes|Estado | expires: YYYY-MM-DD (so Estado expira).
    $memType = ""
    $mt = [regex]::Match($text, '(?im)^\s*type\s*:\s*(\S+)')
    if ($mt.Success) { $memType = $mt.Groups[1].Value }
    # Critica = Decisoes/Preferencias: nunca expira por TTL (so revogacao do operador).
    $isCritical = ($memType -ieq 'Decisoes' -or $memType -ieq 'Preferencias')
    $expiresOn = $null
    $me = [regex]::Match($text, '(?im)^\s*expires\s*:\s*(\d{4}-\d{2}-\d{2})\b')
    if ($me.Success) {
      $parsed = $me.Groups[1].Value -as [datetime]
      if ($null -ne $parsed) { $expiresOn = $parsed }
    }
    $act = Get-LastActivity $f.FullName
    $candidates.Add([pscustomobject]@{
      file       = $f.FullName
      rel        = $f.FullName.Substring($clientDir.Length).TrimStart('\')
      title      = $title
      norm       = (Normalize-Title $title)
      lastWhen   = $act.when
      via        = $act.via
      ageDays    = [math]::Round(($now - $act.when).TotalDays, 1)
      memType    = $memType
      isCritical = $isCritical
      expiresOn  = $expiresOn
    })
  }
}

Write-Host ("[OK] candidatos agent-authored: " + $candidates.Count + " (nucleo ignorado: " + $skippedNucleo + ")")
foreach ($c in $candidates) {
  Write-Host ("    - " + $c.rel + " | atividade ha " + $c.ageDays + " dia(s) [" + $c.via + "]")
}

# (2) Duplicatas/orfas: titulos normalizados iguais (heuristica simples e frugal).
$dups = New-Object System.Collections.Generic.List[object]
$byNorm = $candidates | Group-Object -Property norm | Where-Object { $_.Count -gt 1 }
foreach ($g in $byNorm) {
  $names = ($g.Group | ForEach-Object { $_.rel }) -join " ; "
  $dups.Add([pscustomobject]@{ norm = $g.Name; count = $g.Count; files = $names })
}

Write-Host ""
if ($dups.Count -eq 0) {
  Write-Host "[OK] nenhuma duplicata por titulo detectada."
} else {
  foreach ($d in $dups) {
    Write-Host ("[DUP] " + $d.count + " arquivos com titulo similar: " + $d.files)
  }
}

# (3) Stale por data: atividade mais antiga que StaleDays.
$stale = @($candidates | Where-Object { $_.ageDays -gt $StaleDays })

Write-Host ""
if ($stale.Count -eq 0) {
  Write-Host ("[OK] nenhum arquivo stale (> " + $StaleDays + " dia(s)).")
} else {
  foreach ($s in $stale) {
    Write-Host ("[STALE] " + $s.rel + " | atividade ha " + $s.ageDays + " dia(s) [" + $s.via + "]")
  }
}

# (3b) Expirou por declaracao (TTL): memoria Estado com `expires:` no passado.
# Memory tipada (engine/governance/memory-types.md): so Estado expira; Decisoes/Preferencias
# (critica) nunca expiram por prazo - sao ignoradas aqui mesmo que tragam `expires`.
$expired = @($candidates | Where-Object {
  $null -ne $_.expiresOn -and -not $_.isCritical -and $_.expiresOn -lt $now
})

Write-Host ""
if ($expired.Count -eq 0) {
  Write-Host "[OK] nenhuma memoria expirada por TTL (campo expires no passado)."
} else {
  foreach ($e in $expired) {
    Write-Host ("[EXPIRED] " + $e.rel + " | type: " + $(if ($e.memType) { $e.memType } else { "(sem type)" }) +
      " | expires: " + $e.expiresOn.ToString("yyyy-MM-dd"))
  }
}
# Aviso de tipagem: memoria critica que traz `expires` (ignorado) - sinal, nao acao.
$criticalWithExpires = @($candidates | Where-Object { $null -ne $_.expiresOn -and $_.isCritical })
foreach ($cw in $criticalWithExpires) {
  Write-Host ("[AVISO] " + $cw.rel + " e " + $cw.memType + " (critica): campo expires ignorado (nao expira por TTL).")
}

# (4) Acao de arquivamento (NUNCA deleta). Em DryRun so propoe; senao move para _retired/.
# Une stale + expirou-por-TTL sem arquivar o mesmo arquivo duas vezes (chave = caminho).
$archived = New-Object System.Collections.Generic.List[object]
$retiredDir = Join-Path $clientDir "_retired"

$toArchive = New-Object System.Collections.Generic.List[object]
$seen = New-Object System.Collections.Generic.HashSet[string]
foreach ($s in $stale) {
  if ($seen.Add($s.file)) {
    $reason = "stale: sem atividade ha " + $s.ageDays + " dia(s) (limiar " + $StaleDays + ")"
    $toArchive.Add([pscustomobject]@{ item = $s; reason = $reason })
  }
}
foreach ($e in $expired) {
  if ($seen.Add($e.file)) {
    $reason = "expirou (TTL): expires " + $e.expiresOn.ToString("yyyy-MM-dd") + " ja passou (tipo Estado)"
    $toArchive.Add([pscustomobject]@{ item = $e; reason = $reason })
  }
}

foreach ($a in $toArchive) {
  $s = $a.item
  $reason = $a.reason
  if ($DryRun) {
    Write-Host ("    -> PROPOR arquivar: " + $s.rel + " (" + $reason + ")")
    $archived.Add([pscustomobject]@{ rel = $s.rel; action = "proposto"; reason = $reason })
  } else {
    New-Item -ItemType Directory -Force -Path $retiredDir | Out-Null
    $destName = (Split-Path $s.file -Leaf)
    $dest = Join-Path $retiredDir $destName
    if (Test-Path -LiteralPath $dest) {
      $dest = Join-Path $retiredDir ((Split-Path $s.file -LeafBase) + "-" + $today + ".md")
    }
    # Preserva o arquivo: prefixa cabecalho de arquivamento com motivo+data, sem perder conteudo.
    $orig = [System.IO.File]::ReadAllText($s.file)
    $header = "<!-- retired_on: " + $today + " | retired_reason: " + $reason + " -->" + "`r`n`r`n"
    [System.IO.File]::WriteAllText($dest, $header + $orig, $utf8)
    Remove-Item -LiteralPath $s.file -Force
    Write-Host ("    -> ARQUIVADO: " + $s.rel + " -> _retired\" + (Split-Path $dest -Leaf))
    $archived.Add([pscustomobject]@{ rel = $s.rel; action = "arquivado"; reason = $reason })
  }
}

# (5) Resumo estruturado.
Write-Host ""
Write-Host ("Resumo: " + $candidates.Count + " candidato(s) | " + $dups.Count + " grupo(s) duplicado(s) | " +
  $stale.Count + " stale | " + $expired.Count + " expirado(s) por TTL | " +
  $archived.Count + " " + $(if ($DryRun) { "proposto(s)" } else { "arquivado(s)" }))

# (6) Relatorio datado em loop-reports/ (igual aos outros scans: so grava fora do DryRun).
if (-not $DryRun) {
$outDir = Join-Path $knowDir "loop-reports"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outFile = Join-Path $outDir ($today + "-memory-curator.md")
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Memory Curator - " + $Client + " (" + $today + ")")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("> Mecanismo: scripts/memory-curator.ps1. Curador semanal de memoria e regras.")
[void]$sb.AppendLine("> So agent-authored; nunca nucleo; nunca deleta (arquiva em _retired/).")
[void]$sb.AppendLine("> Modo: " + $(if ($DryRun) { "DRY-RUN (nada movido)" } else { "RUN" }) +
  " | limiar stale: " + $StaleDays + " dia(s)")
[void]$sb.AppendLine("> Candidatos: " + $candidates.Count + " | nucleo ignorado: " + $skippedNucleo)
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Consolidacoes propostas (titulos similares)")
[void]$sb.AppendLine("")
if ($dups.Count -eq 0) {
  [void]$sb.AppendLine("Nenhuma duplicata por titulo detectada.")
} else {
  [void]$sb.AppendLine("| Titulo normalizado | Qtd | Arquivos |")
  [void]$sb.AppendLine("|--------------------|-----|----------|")
  foreach ($d in $dups) {
    $files = ($d.files -replace '\|', '\')
    [void]$sb.AppendLine("| " + $d.norm + " | " + $d.count + " | " + $files + " |")
  }
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Memoria expirada por TTL (campo expires)")
[void]$sb.AppendLine("")
if ($expired.Count -eq 0) {
  [void]$sb.AppendLine("Nenhuma memoria Estado com expires no passado.")
} else {
  [void]$sb.AppendLine("| Arquivo | Tipo | Expires |")
  [void]$sb.AppendLine("|---------|------|---------|")
  foreach ($e in $expired) {
    $tp = $(if ($e.memType) { $e.memType } else { "(sem type)" })
    [void]$sb.AppendLine("| " + $e.rel + " | " + $tp + " | " + $e.expiresOn.ToString("yyyy-MM-dd") + " |")
  }
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Arquivamentos (" + $(if ($DryRun) { "propostos" } else { "realizados" }) + ")")
[void]$sb.AppendLine("")
if ($archived.Count -eq 0) {
  [void]$sb.AppendLine("Nenhum arquivo stale para arquivar.")
} else {
  [void]$sb.AppendLine("| Arquivo | Acao | Motivo |")
  [void]$sb.AppendLine("|---------|------|--------|")
  foreach ($a in $archived) {
    [void]$sb.AppendLine("| " + $a.rel + " | " + $a.action + " | " + $a.reason + " |")
  }
}
[System.IO.File]::WriteAllText($outFile, $sb.ToString(), $utf8)
Write-Host ("[OK] relatorio: " + $outFile)
} else {
  Write-Host "[OK] DRY-RUN: relatorio nao gravado (so listagem acima)."
}

# Achar debito de curadoria e sinal, nao erro: exit 0 quando rodou bem.
exit 0
