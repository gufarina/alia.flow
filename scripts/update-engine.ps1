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
    powershell -ExecutionPolicy Bypass -File scripts/update-engine.ps1            # aplica
    powershell -ExecutionPolicy Bypass -File scripts/update-engine.ps1 -DryRun    # so mostra
    -From "<caminho>"   usa outra fonte (default: clients/alia-flow-lab)

  Sem acentos, sem emojis. UTF-8 sem BOM.
#>
param(
  [string]$From = "",
  [switch]$DryRun
)

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
  Write-Host "Esta instalacao nao tem uma oficina de atualizacao local - e o normal na fase beta."
  Write-Host ""
  Write-Host "Como atualizar: quando houver versao nova, voce recebe um novo pacote (zip)."
  Write-Host "Descompacte ele POR CIMA desta mesma pasta. Seus dados (studio/, clientes,"
  Write-Host "memoria) nao sao tocados: a atualizacao troca so o motor."
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
Write-Host ("  modo: " + $(if ($DryRun) { "DRY-RUN (so mostra, nada muda)" } else { "APLICAR" }))
Write-Host ""

# --- Portao: so propaga o que esta verde ---
$labSmoke = Join-Path $lab "scripts\smoke-test.ps1"
if (Test-Path -LiteralPath $labSmoke) {
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
if (-not $DryRun) {
  $stampB = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $bkp = Join-Path $root ("_backups\pre-update-" + $verInst + "-para-" + $verLab + "-" + $stampB)
  New-Item -ItemType Directory -Force -Path $bkp | Out-Null
  foreach ($cf in @("state.json","studio.yaml","alia.config.json")) {
    $cp = Join-Path $root $cf
    if (Test-Path -LiteralPath $cp) { Copy-Item -LiteralPath $cp -Destination (Join-Path $bkp $cf) -Force }
  }
  Write-Host ("    [backup]  registro + config salvos (recuperavel) em _backups\" + (Split-Path $bkp -Leaf))
}

Write-Host "2/3 Atualizando o motor..."
foreach ($d in $engineDirs) {
  $src = Join-Path $lab $d
  if (Test-Path -LiteralPath $src) {
    Write-Host ("    [motor]   " + $d + "\ (espelho - remove pecas de versoes antigas)")
    if ($DryRun) { robocopy $src (Join-Path $root $d) /MIR /L /NFL /NDL /NP /NS /NC /NJH /NJS | Out-Null }
    else         { robocopy $src (Join-Path $root $d) /MIR    /NFL /NDL /NP /NS /NC /NJH /NJS | Out-Null }
  }
}
foreach ($d in $mergeDirs) {
  $src = Join-Path $lab $d
  if (Test-Path -LiteralPath $src) {
    Write-Host ("    [merge]   " + $d + "\ (soma - preserva ajustes locais)")
    if ($DryRun) { robocopy $src (Join-Path $root $d) /E /L /NFL /NDL /NP /NS /NC /NJH /NJS | Out-Null }
    else         { robocopy $src (Join-Path $root $d) /E    /NFL /NDL /NP /NS /NC /NJH /NJS | Out-Null }
  }
}
foreach ($f in $productFiles) {
  $src = Join-Path $lab $f
  if (Test-Path -LiteralPath $src) {
    Write-Host ("    [arquivo] " + $f)
    if (-not $DryRun) { Copy-Item -LiteralPath $src -Destination (Join-Path $root $f) -Force }
  }
}
Write-Host ""

if ($DryRun) {
  Write-Host "DRY-RUN: nada foi alterado."
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
