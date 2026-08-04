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

# benchmarks/ entra no pacote (TASK-015): sao 5 scripts Python + README, deterministicos, sem
# rede e sem dado de operador. Sem eles, "rode os benchmarks na sua maquina" seria promessa falsa
# - o smoke ia, os benchmarks nao.
# NOTA: "docs" NAO esta em $shipDirs de proposito - a pasta docs/ da oficina mistura doc de
# usuario com doc interno (CLAIMS.md, BRAND.md, DESIGN.md, RELEASE-STATUS.md, product/, brand/).
# Copiar a pasta inteira vaza "doc do arquivo de edicao" pro publico (mandato do CEO). docs/ e
# tratada abaixo por ALLOWLIST explicita, nunca por denylist.
# .claude/ ship de proposito (v1.42.2): settings.json liga os hooks de enforcement do proprio
# produto (delegation-guard.ps1, response-guard.ps1 etc, todos ja em scripts/) - e mecanismo do
# motor, nao doc de trabalho. Sem isso o produto instalado nunca ativa a propria governanca.
# Traz junto .claude/commands/alia.md (comando /alia), copiado pelo mesmo robocopy /E abaixo.
# CLAUDE.md ship de proposito (v1.42.3): Claude Code le CLAUDE.md, NAO AGENTS.md (confirmado na
# doc oficial code.claude.com/docs/en/memory). Sem este arquivo no pacote, quem abre a pasta no
# Claude Code recebe um agente generico - a Alia nunca aparece (bloqueador de release medido
# 03/ago). CLAUDE.md so importa AGENTS.md (@AGENTS.md); a fonte da identidade continua unica.
$shipDirs  = @("engine","scripts","skills","onboarding","optional-mcps","studio.example","benchmarks",".github",".claude")
$shipFiles = @("AGENTS.md","CLAUDE.md","README.md","PRIMEIROS-PASSOS.md","CONTRIBUTING.md","CHANGELOG.md","VERSION","LICENSE","CREDITS.md","alia.config.json","iniciar-alia.bat","atualizar-alia.bat",".gitattributes",".gitignore")
# Excluido de proposito (dado de operador/interno): studio, opportunities, rsi-backlog, memory, release, _retired, state.json, studio.yaml

foreach ($d in $shipDirs) {
  $src = Join-Path $root $d
  if (Test-Path $src) {
    # /XD cobre as pastas de trabalho interno que podem aparecer dentro de qualquer shipDir.
    robocopy $src (Join-Path $out $d) /E /XD _retired _dev _drafts release /NFL /NDL /NP /NS /NC /NJH /NJS | Out-Null
    Write-Host ("    [dir]  " + $d + "\ (sem _retired/_dev/_drafts)")
  }
}
foreach ($f in $shipFiles) {
  $src = Join-Path $root $f
  if (Test-Path $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $out $f) -Force; Write-Host ("    [file] " + $f) }
}

# docs/ e ALLOWLIST, nao denylist: allowlist falha fechado (doc novo de amanha nasce de FORA do
# pacote ate alguem decidir explicitamente publica-lo); denylist esquece o arquivo novo. Criterio
# de inclusao, arquivo por arquivo: "isto serve a quem INSTALA o produto?". Hoje SO 3 servem:
#   - README.md         : indice/porta de entrada da documentacao do produto.
#   - COMPATIBILIDADE.md: degradacao honesta por IDE (o usuario precisa saber o que funciona onde).
#   - INTEGRIDADE.md    : como verificar o MANIFEST.sha256 (o usuario que baixou precisa disto).
# Fora de proposito (doc do arquivo de edicao, nunca vai pro publico - engine/governance/public-surface.md):
#   - CLAIMS.md         : registro de claims/vetos, uso interno do motor.
#   - RELEASE-STATUS.md : relatorio de drift oficina/staging/publico, cita caminho da maquina do dono.
#   - BRAND.md / DESIGN.md: IP de marca/sistema visual do dono (produto funciona sem eles).
#   - product/          : PRD, ARQUITETURA, alia-launcher-plan (planejamento interno).
#   - brand/            : BrandScript, LP-copy, direcao de arte, PRFAQ (material de marca em desenvolvimento).
$docsAllow = @("README.md","COMPATIBILIDADE.md","INTEGRIDADE.md")
$docsSrc = Join-Path $root "docs"
if (Test-Path $docsSrc) {
  New-Item -ItemType Directory -Force -Path (Join-Path $out "docs") | Out-Null
  foreach ($df in $docsAllow) {
    $dsrc = Join-Path $docsSrc $df
    if (Test-Path -LiteralPath $dsrc) {
      Copy-Item -LiteralPath $dsrc -Destination (Join-Path $out ("docs\" + $df)) -Force
      Write-Host ("    [file] docs\" + $df)
    }
  }
}

# Material interno do dono do produto que NAO sobe (mesmo morando em pasta que ship parcialmente):
# - scripts/migrate-to-studio.ps1 / scripts/extract-secrets.ps1 : migracao UNICA do sistema legado
#   do dono (caminhos da maquina dele); inutil numa instalacao limpa.
$internalFiles = @("scripts\migrate-to-studio.ps1","scripts\extract-secrets.ps1")
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
# Material interno do dono (scripts de migracao unica) tambem nao pode estar no pacote.
foreach ($rel in $internalFiles) {
  if (Test-Path -LiteralPath (Join-Path $out $rel)) { $leak += $rel }
}
# Defesa em profundidade da allowlist de docs/: nenhum destes pode existir no pacote, mesmo que
# um shipDir futuro volte a copiar docs/ por inteiro por engano.
foreach ($bad in @("docs\product","docs\brand","docs\CLAIMS.md","docs\BRAND.md","docs\DESIGN.md","docs\RELEASE-STATUS.md")) {
  if (Test-Path -LiteralPath (Join-Path $out $bad)) { $leak += $bad }
}
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

# Manifesto de integridade (supply-chain leve): SHA256 de todo arquivo do pacote, para o
# usuario poder verificar depois que baixou que o conteudo nao foi alterado. Isto prova
# integridade (hash), nao autenticidade de origem por PKI. Ver docs/INTEGRIDADE.md.
& (Join-Path $PSScriptRoot "make-manifest.ps1") -Dir $out | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "[ERRO] falha ao gerar o manifesto de integridade."; exit 1 }
Write-Host "manifesto de integridade gerado (MANIFEST.sha256)."

Write-Host ""
Write-Host ("=== PACOTE PRONTO: " + $out + " (v" + $ver + ", CLEAN, smoke verde). ===")
Write-Host "Proximo passo (DevOps): publicar este conteudo no repo publico alia-flow."
exit 0
