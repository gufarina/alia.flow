<#
  package-release.ps1 - empacota o Alia Flow CLEAN para release open source.
  Da raiz do lab (a fonte da verdade), produz release/alia-flow/ com SO o produto:
  engine, scripts, skills, onboarding, optional-mcps, docs, studio.example + os arquivos de topo
  (AGENTS, README, CHANGELOG, VERSION, LICENSE, alia.config.json, launchers, .git*).
  NUNCA inclui dado de operador/interno: studio/, opportunities/, rsi-backlog/, memory/, state.json,
  studio.yaml, _retired/. Portao: so empacota se o smoke estiver verde. Valida o pacote no fim.
  Sem acentos, sem emojis. UTF-8 sem BOM.
#>
param([switch]$Force)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out  = Join-Path $root "release\alia-flow"
$ver  = ((Get-Content (Join-Path $root "VERSION") -ErrorAction SilentlyContinue) -join "").Trim()

Write-Host "=== Empacotar Alia Flow (release open source) ==="
Write-Host ("  versao: " + $ver)
Write-Host ("  saida:  " + $out)
Write-Host ""

# 1/3 Portao: so empacota o que esta verde.
Write-Host "1/3 Validando o produto (smoke)..."
& (Join-Path $PSScriptRoot "smoke-test.ps1") | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "[ERRO] smoke vermelho. Abortei sem empacotar."; exit 1 }
Write-Host "    produto OK (ALL GREEN)."
Write-Host ""

# 2/3 Montar o pacote CLEAN.
Write-Host "2/3 Montando o pacote CLEAN..."
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force -Path $out | Out-Null

$shipDirs  = @("engine","scripts","skills","onboarding","optional-mcps","docs","studio.example")
$shipFiles = @("AGENTS.md","README.md","PRIMEIROS-PASSOS.md","CHANGELOG.md","VERSION","LICENSE","CREDITS.md","alia.config.json","iniciar-alia.bat","atualizar-alia.bat",".gitattributes",".gitignore")
# Excluido de proposito (dado de operador/interno): studio, opportunities, rsi-backlog, memory, release, _retired, state.json, studio.yaml

foreach ($d in $shipDirs) {
  $src = Join-Path $root $d
  if (Test-Path $src) {
    # /XD cobre TODAS as pastas de trabalho interno: _retired/_dev/_drafts/release (.gitignore)
    # e "product" (docs\product = PRDs internos do dono; a validacao 3/3 reprova se vazar).
    robocopy $src (Join-Path $out $d) /E /XD _retired _dev _drafts release product /NFL /NDL /NP /NS /NC /NJH /NJS | Out-Null
    Write-Host ("    [dir]  " + $d + "\ (sem _retired/_dev/_drafts/product)")
  }
}
foreach ($f in $shipFiles) {
  $src = Join-Path $root $f
  if (Test-Path $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $out $f) -Force; Write-Host ("    [file] " + $f) }
}

# Material interno do dono do produto que NAO sobe (mesmo morando em pasta de produto):
# - docs/BRAND.md / docs/DESIGN.md : material de marca e sistema visual - IP do dono (o produto
#   funciona sem eles; o CSS da pagina de onboarding e inline).
# - scripts/migrate-to-studio.ps1 / scripts/extract-secrets.ps1 : migracao UNICA do sistema legado
#   do dono (caminhos da maquina dele); inutil numa instalacao limpa.
# Tudo isso fica no lab, nunca no pacote publico.
$internalFiles = @("docs\BRAND.md","docs\DESIGN.md","scripts\migrate-to-studio.ps1","scripts\extract-secrets.ps1")
foreach ($rel in $internalFiles) {
  $p = Join-Path $out $rel
  if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; Write-Host ("    [interno-removido] " + $rel) }
}
Write-Host ""

# 3/3 Validar o pacote: zero vazamento de operador + smoke verde no pacote.
Write-Host "3/3 Validando o pacote..."
$leak = @()
foreach ($bad in @("studio","opportunities","rsi-backlog","memory","state.json","studio.yaml")) {
  if (Test-Path (Join-Path $out $bad)) { $leak += $bad }
}
# Material interno do dono (marca/design) tambem nao pode estar no pacote.
foreach ($rel in $internalFiles) {
  if (Test-Path -LiteralPath (Join-Path $out $rel)) { $leak += $rel }
}
# docs/product (PRDs e docs de manutencao) NUNCA vao pro pacote publico.
if (Test-Path -LiteralPath (Join-Path $out "docs\product")) { $leak += "docs\product" }
if ($leak.Count -gt 0) { Write-Host ("[ERRO] vazou dado de operador/interno no pacote: " + ($leak -join ", ")); exit 1 }

# Nenhum caminho absoluto de maquina pode sobrar (path de usuario Windows). Guard generico: nao
# crava nome privado neste script (que e publicado) - so detecta o padrao de pasta de usuario.
$pathLeaks = Get-ChildItem -Path $out -Recurse -File -Include *.ps1,*.py,*.md,*.html,*.json,*.bat,*.yaml,*.yml -ErrorAction SilentlyContinue |
  Where-Object { (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'C:\\Users\\[^\\]+\\' } |
  ForEach-Object { $_.FullName.Substring($out.Length).TrimStart('\') }
if ($pathLeaks.Count -gt 0) {
  Write-Host ("[ERRO] caminho absoluto de maquina vazou no pacote: " + ($pathLeaks -join ", ")); exit 1
}

& (Join-Path $out "scripts\smoke-test.ps1") | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "[ERRO] o pacote nao passou no proprio smoke."; exit 1 }

Write-Host ""
Write-Host ("=== PACOTE PRONTO: " + $out + " (v" + $ver + ", CLEAN, smoke verde). ===")
Write-Host "Proximo passo (DevOps): publicar este conteudo no repo publico alia-flow."
exit 0
