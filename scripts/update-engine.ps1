<#
  update-engine.ps1 - Atualiza o MOTOR desta instancia a partir do laboratorio (a fonte da verdade).

  Atualiza SO o produto (engine, scripts, skills, onboarding, optional-mcps, docs + arquivos de
  produto do topo). NUNCA toca a sua camada: clients/, state.json, studio.yaml, _inbox/,
  alia.config.json, AGENTS.md, .gitignore. O script lista explicitamente o que E motor; tudo que
  nao esta nessa lista (os seus dados) nunca entra na copia, logo nunca e tocado.

  Seguranca em duas pontas:
    - ANTES de copiar: roda a prova do laboratorio. Lab vermelho => aborta sem tocar em nada.
    - DEPOIS de copiar: roda a prova desta instancia, pra confirmar que continua saudavel.

  Uso (rode da raiz da instancia):
    powershell -ExecutionPolicy Bypass -File scripts/update-engine.ps1            # aplica (diff-only)
    powershell -ExecutionPolicy Bypass -File scripts/update-engine.ps1 -Check     # so relata o que mudaria
    -From "<caminho>"   usa outra fonte (default: clients/alia-flow-lab)

  Modo de aplicacao: DIFF-ONLY. Compara lab -> instancia por hash SHA256 e copia SO os
  arquivos NOVOS/ALTERADOS; remove SO os que sumiram do lab (nas pastas de espelho).
  Antes de sobrescrever ou remover, o arquivo antigo ganha copia dentro do backup datado
  em _backups\ (o mesmo backup que ja guarda state/config - um backup so).

  -Check imprime o relatorio (NOVO / ALTERADO / REMOVIDO por pasta) sem tocar em nada.
  -DryRun e sinonimo de -Check (mantido por compatibilidade).

  Sem acentos, sem emojis. UTF-8 sem BOM.
#>
param(
  [string]$From = "",
  [switch]$DryRun,
  [switch]$Check
)
if ($DryRun) { $Check = $true }

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$lab  = if ($From -ne "") { $From } else { Join-Path $root "clients\alia-flow-lab" }

Write-Host "=== Atualizar o motor (laboratorio -> esta instancia) ==="
Write-Host ("  fonte:   " + $lab)
Write-Host ("  destino: " + $root)

if (-not (Test-Path -LiteralPath $lab)) {
  # Instalacao SEM laboratorio local (o caso normal de quem recebeu o pacote pronto - beta).
  # Nao e erro da pessoa: explica em linguagem simples como atualizar e sai limpo.
  Write-Host ""
  Write-Host "Esta instalacao nao tem uma oficina de atualizacao local - e o normal do pacote publico."
  Write-Host ""
  $online = Join-Path $root "scripts\update-online.ps1"
  if (Test-Path -LiteralPath $online) {
    Write-Host "Atualizacao automatica: rode  scripts\update-online.ps1  (ou o atalho atualizar-alia.bat)."
    Write-Host "Ele baixa a versao nova do GitHub, faz backup e troca SO o motor - seus dados"
    Write-Host "(studio/, clientes, estado, memoria) nunca sao tocados; se algo falhar, ele reverte."
    Write-Host "Prever antes de aplicar:  scripts\update-online.ps1 -Check"
  } else {
    Write-Host "Como atualizar: quando houver versao nova, voce recebe um novo pacote (zip)."
    Write-Host "Descompacte ele POR CIMA desta mesma pasta. Seus dados (studio/, clientes,"
    Write-Host "memoria) nao sao tocados: a atualizacao troca so o motor."
  }
  Write-Host ""
  Write-Host "Guia completo: PRIMEIROS-PASSOS.md (nesta pasta)."
  exit 0
}
if (-not (Test-Path -LiteralPath (Join-Path $lab "engine\constitution.md"))) {
  Write-Host ("[ERRO] nao parece um laboratorio Alia Flow valido (faltou engine\constitution.md): " + $lab)
  Write-Host "       Abortei sem tocar em nada."
  exit 1
}

$verLab  = ((Get-Content (Join-Path $lab  "VERSION") -ErrorAction SilentlyContinue) -join "").Trim()
$verInst = ((Get-Content (Join-Path $root "VERSION") -ErrorAction SilentlyContinue) -join "").Trim()
Write-Host ("  versao no lab:       " + $verLab)
Write-Host ("  versao na instancia: " + $verInst)
Write-Host ("  modo: " + $(if ($Check) { "CHECK (so relata o que mudaria, nada muda)" } else { "APLICAR (diff-only)" }))
Write-Host ""

# --- Portao: so propaga o que esta verde (no -Check nao ha propagacao, entao pula o portao) ---
$labSmoke = Join-Path $lab "scripts\smoke-test.ps1"
if ($Check) {
  Write-Host "1/3 (modo CHECK - portao de smoke do lab pulado, nada sera propagado)"
} elseif (Test-Path -LiteralPath $labSmoke) {
  Write-Host "1/3 Validando o laboratorio (so propaga motor que passa no smoke)..."
  & $labSmoke | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERRO] o laboratorio NAO esta verde. Abortei sem tocar em nada."
    Write-Host "       Rode  clients\alia-flow-lab\scripts\smoke-test.ps1  para ver o que falta."
    exit 1
  }
  Write-Host "    laboratorio OK (ALL GREEN)."
} else {
  Write-Host "1/3 (laboratorio sem smoke-test.ps1 - pulando o portao)"
}
Write-Host ""

# --- O que e PRODUTO (atualiza) vs o que e SEU (nunca aparece aqui, logo nunca e tocado) ---
$engineDirs   = @("engine","scripts","skills","onboarding","optional-mcps")          # 100% produto: espelha
$mergeDirs    = @(".claude","docs")                                                   # soma (preserva local: docs do produto atualizam, mas planos/docs locais do operador nao sao apagados)
$productFiles = @("README.md","PRIMEIROS-PASSOS.md","VERSION","CHANGELOG.md","LICENSE","CREDITS.md","iniciar-alia.bat","atualizar-alia.bat",".gitattributes")
# Camada do operador, intocada: clients/  state.json  studio.yaml  _inbox/  alia.config.json  AGENTS.md  .gitignore

# --- GUARDA DE SEGURANCA DOS DADOS (nunca estragar info do usuario: clientes, estado, config) ---
# (1) A camada de dados do operador NUNCA pode entrar no conjunto de copia. Se um dia alguem editar as
#     listas acima e incluir 'clients', 'state.json' etc. por engano, ABORTA antes de tocar em nada.
$protected = @("clients","state.json","studio.yaml","_inbox","alia.config.json","AGENTS.md",".gitignore",".git")
$copySet = @($engineDirs + $mergeDirs + $productFiles)
$overlap = @($copySet | Where-Object { $protected -contains $_ })
if ($overlap.Count -gt 0) {
  Write-Host ("[ABORTADO] guarda de seguranca: o update tentaria tocar a sua camada de dados (" + ($overlap -join ", ") + "). Nada foi alterado.")
  exit 1
}
# (2) Backup automatico do registro/config ANTES de tocar no motor (recuperavel). clients/ (grande)
#     nunca e copiado nem tocado - so estes arquivos-chave pequenos ganham copia de seguranca datada.
$bkp = $null
if (-not $Check) {
  $stampB = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $bkp = Join-Path $root ("_backups\pre-update-" + $verInst + "-para-" + $verLab + "-" + $stampB)
  New-Item -ItemType Directory -Force -Path $bkp | Out-Null
  foreach ($cf in @("state.json","studio.yaml","alia.config.json")) {
    $cp = Join-Path $root $cf
    if (Test-Path -LiteralPath $cp) { Copy-Item -LiteralPath $cp -Destination (Join-Path $bkp $cf) -Force }
  }
  Write-Host ("    [backup]  registro + config salvos (recuperavel) em _backups\" + (Split-Path $bkp -Leaf))
}

# --- Diff-only: compara lab -> instancia por hash e age SO no que mudou ---
function Get-Sha256([string]$path) {
  return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
# Devolve o diff de uma pasta espelhada: listas de caminhos RELATIVOS New/Changed/Removed.
function Get-MirrorDiff([string]$srcDir, [string]$dstDir) {
  $new = @(); $changed = @(); $removed = @()
  $srcFiles = @{}
  if (Test-Path -LiteralPath $srcDir) {
    foreach ($f in (Get-ChildItem -LiteralPath $srcDir -Recurse -File)) {
      $rel = $f.FullName.Substring($srcDir.Length).TrimStart('\')
      $srcFiles[$rel] = $f.FullName
    }
  }
  $dstFiles = @{}
  if (Test-Path -LiteralPath $dstDir) {
    foreach ($f in (Get-ChildItem -LiteralPath $dstDir -Recurse -File)) {
      $rel = $f.FullName.Substring($dstDir.Length).TrimStart('\')
      $dstFiles[$rel] = $f.FullName
    }
  }
  foreach ($rel in $srcFiles.Keys) {
    if (-not $dstFiles.ContainsKey($rel)) { $new += $rel }
    elseif ((Get-Sha256 $srcFiles[$rel]) -ne (Get-Sha256 $dstFiles[$rel])) { $changed += $rel }
  }
  foreach ($rel in $dstFiles.Keys) {
    if (-not $srcFiles.ContainsKey($rel)) { $removed += $rel }
  }
  return @{ New = @($new | Sort-Object); Changed = @($changed | Sort-Object); Removed = @($removed | Sort-Object) }
}
# Salva a versao ATUAL do arquivo da instancia dentro do backup datado, preservando o caminho.
function Backup-InstanceFile([string]$bkpRoot, [string]$topDir, [string]$rel, [string]$fullPath) {
  $dest = Join-Path (Join-Path $bkpRoot $topDir) $rel
  $destDir = Split-Path -Parent $dest
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  Copy-Item -LiteralPath $fullPath -Destination $dest -Force
}

$totNew = 0; $totChanged = 0; $totRemoved = 0

if ($Check) { Write-Host "2/3 Comparando o motor (lab -> instancia)..." }
else        { Write-Host "2/3 Atualizando o motor (diff-only)..." }

foreach ($d in $engineDirs) {
  $src = Join-Path $lab $d
  if (-not (Test-Path -LiteralPath $src)) { continue }
  $dst = Join-Path $root $d
  $diff = Get-MirrorDiff $src $dst
  $n = $diff.New.Count; $c = $diff.Changed.Count; $r = $diff.Removed.Count
  Write-Host ("    [motor]   " + $d + "\ (espelho diff-only): " + $n + " NOVO, " + $c + " ALTERADO, " + $r + " REMOVIDO")
  foreach ($rel in $diff.New)     { Write-Host ("        NOVO      " + $d + "\" + $rel) }
  foreach ($rel in $diff.Changed) { Write-Host ("        ALTERADO  " + $d + "\" + $rel) }
  foreach ($rel in $diff.Removed) { Write-Host ("        REMOVIDO  " + $d + "\" + $rel) }
  $totNew += $n; $totChanged += $c; $totRemoved += $r
  if ($Check) { continue }
  foreach ($rel in $diff.New) {
    $to = Join-Path $dst $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    Copy-Item -LiteralPath (Join-Path $src $rel) -Destination $to -Force
  }
  foreach ($rel in $diff.Changed) {
    $to = Join-Path $dst $rel
    Backup-InstanceFile $bkp $d $rel $to
    Copy-Item -LiteralPath (Join-Path $src $rel) -Destination $to -Force
  }
  foreach ($rel in $diff.Removed) {
    $to = Join-Path $dst $rel
    Backup-InstanceFile $bkp $d $rel $to
    Remove-Item -LiteralPath $to -Force
  }
  # limpa pastas que ficaram vazias depois das remocoes (o /MIR fazia isso; aqui e cirurgico)
  if (Test-Path -LiteralPath $dst) {
    $empties = @(Get-ChildItem -LiteralPath $dst -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($dir in $empties) {
      if (@(Get-ChildItem -LiteralPath $dir.FullName -Force).Count -eq 0) { Remove-Item -LiteralPath $dir.FullName -Force }
    }
  }
}
foreach ($d in $mergeDirs) {
  $src = Join-Path $lab $d
  if (Test-Path -LiteralPath $src) {
    Write-Host ("    [merge]   " + $d + "\ (soma - preserva ajustes locais)")
    if ($Check) { robocopy $src (Join-Path $root $d) /E /L /NFL /NDL /NP /NS /NC /NJH /NJS | Out-Null }
    else        { robocopy $src (Join-Path $root $d) /E    /NFL /NDL /NP /NS /NC /NJH /NJS | Out-Null }
  }
}
foreach ($f in $productFiles) {
  $src = Join-Path $lab $f
  if (-not (Test-Path -LiteralPath $src)) { continue }
  $dstF = Join-Path $root $f
  if (-not (Test-Path -LiteralPath $dstF)) {
    Write-Host ("    [arquivo] " + $f + " (NOVO)")
    $totNew += 1
    if (-not $Check) { Copy-Item -LiteralPath $src -Destination $dstF -Force }
  } elseif ((Get-Sha256 $src) -ne (Get-Sha256 $dstF)) {
    Write-Host ("    [arquivo] " + $f + " (ALTERADO)")
    $totChanged += 1
    if (-not $Check) {
      Backup-InstanceFile $bkp "_arquivos-topo" $f $dstF
      Copy-Item -LiteralPath $src -Destination $dstF -Force
    }
  }
}
Write-Host ""
Write-Host ("    Total: " + $totNew + " NOVO, " + $totChanged + " ALTERADO, " + $totRemoved + " REMOVIDO" + $(if ($Check) { " (nada aplicado)" } else { " aplicados" }))
Write-Host ""

if ($Check) {
  Write-Host "CHECK: nada foi alterado. Rode sem -Check para aplicar exatamente o relatorio acima."
  Write-Host "Sua camada (clients/, state.json, studio.yaml, alia.config.json, AGENTS.md) nunca e tocada."
  exit 0
}

Write-Host "3/3 Validando esta instancia depois do update..."
Write-Host ""
& (Join-Path $root "scripts\smoke-test-studio.ps1")
$rc = $LASTEXITCODE
Write-Host ""
if ($rc -eq 0) {
  Write-Host "=== MOTOR ATUALIZADO (instancia ALL GREEN). Seus clientes e dados intactos. ==="
} else {
  Write-Host "=== ATENCAO: update aplicado, mas a prova da instancia acusou falha acima. Verifique. ==="
}
exit $rc
