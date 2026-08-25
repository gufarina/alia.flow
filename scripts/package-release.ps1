<#
  package-release.ps1 - empacota o Alia Flow CLEAN para release open source.
  Da raiz do lab (a fonte da verdade), produz release/alia-flow/ com SO o produto:
  engine, scripts, skills, onboarding, optional-mcps, docs, studio.example + os arquivos de topo
  (AGENTS, README, CHANGELOG, VERSION, LICENSE, alia.config.json, launchers, .git*).
  NUNCA inclui dado de operador/interno: studio/, opportunities/, rsi-backlog/, memory/, state.json,
  studio.yaml, _retired/. Portao: so empacota se o smoke estiver verde E se existir revisao de
  release aprovada para a versao atual (release-reviews/<VERSION>.md, veredito PASS - ver
  engine/governance/public-surface.md). Valida o pacote no fim. Sem acentos, sem emojis. UTF-8 sem BOM.
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

# 0/3 Portao: nenhuma versao sai sem revisao de release aprovada (lei do law-ledger.md, mecanismo
# = este passo). release-reviews/<VERSION>.md precisa existir, ter `veredito: PASS` e ter
# `versao: <VERSION>` batendo com a versao atual - qualquer um dos 3 faltando ABORTA, nao so avisa.
# Isto e a mesma logica da recusa de varredura cega do graphify: nao e lembrete, e porta estrutural.
Write-Host "0/3 Conferindo revisao de release aprovada..."
$reviewPath = Join-Path $root ("release-reviews\" + $ver + ".md")
if (-not (Test-Path -LiteralPath $reviewPath)) {
  Write-Host ("[ERRO] versao " + $ver + " sem revisao de release aprovada - acione o squad. Esperado: " + $reviewPath)
  exit 1
}
$reviewTxt = [System.IO.File]::ReadAllText($reviewPath)
$reviewVerMatch = [regex]::Match($reviewTxt, '(?m)^versao:\s*(\S+)\s*$')
$reviewVerdMatch = [regex]::Match($reviewTxt, '(?m)^veredito:\s*(\S+)\s*$')
$reviewVer = if ($reviewVerMatch.Success) { $reviewVerMatch.Groups[1].Value } else { "" }
$reviewVerd = if ($reviewVerdMatch.Success) { $reviewVerdMatch.Groups[1].Value } else { "" }
if ($reviewVerd -ne "PASS") {
  Write-Host ("[ERRO] versao " + $ver + " sem revisao de release aprovada - acione o squad. " + $reviewPath + " tem veredito '" + $reviewVerd + "' (precisa ser PASS).")
  exit 1
}
if ($reviewVer -ne $ver) {
  Write-Host ("[ERRO] versao " + $ver + " sem revisao de release aprovada - acione o squad. " + $reviewPath + " declara versao '" + $reviewVer + "', divergente da versao atual (" + $ver + ").")
  exit 1
}
Write-Host ("    revisao aprovada: " + $reviewPath + " (veredito PASS, versao confere).")
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
$shipDirs  = @("engine","skills","onboarding","optional-mcps","studio.example","benchmarks",".github",".claude")
$shipFiles = @("AGENTS.md","CLAUDE.md","README.md","PRIMEIROS-PASSOS.md","CONTRIBUTING.md","CHANGELOG.md","VERSION","LICENSE","CREDITS.md","alia.config.json","iniciar-alia.bat","atualizar-alia.bat",".gitattributes",".gitignore")
# Excluido de proposito (dado de operador/interno): studio, opportunities, rsi-backlog, memory, release, _retired, state.json, studio.yaml
# "scripts" saiu de $shipDirs de proposito (auditoria de superficie, 10/08/2026): a pasta inteira
# nao entra mais por robocopy /E cego. Tem tratamento proprio logo abaixo, por ALLOWLIST - ver o
# bloco "scripts/ e ALLOWLIST".

foreach ($d in $shipDirs) {
  $src = Join-Path $root $d
  if (Test-Path $src) {
    # /XD cobre as pastas de trabalho interno que podem aparecer dentro de qualquer shipDir.
    # Quando $d = ".claude", exclui TAMBEM ".claude\agents" por caminho completo (nao so o nome
    # "agents" - isso vazaria engine\agents\, que e legitimo): e onde squad-bridge gera
    # especialista de CLIENTE (acme-saas-*, cliente-*, etc); o produto publico nunca pode carregar
    # isso, mesmo que a oficina algum dia acumule a pasta por engano (defesa em profundidade - a
    # lei de verdade e nunca gerar isso na oficina, mas o empacotador tambem nao confia cegamente).
    $xd = @("_retired","_dev","_drafts","release")
    if ($d -eq ".claude") { $xd += (Join-Path $src "agents") }
    robocopy $src (Join-Path $out $d) /E /XD $xd /NFL /NDL /NP /NS /NC /NJH /NJS | Out-Null
    Write-Host ("    [dir]  " + $d + "\ (sem _retired/_dev/_drafts)")
  }
}

# scripts/ e ALLOWLIST, nao denylist (auditoria de superficie, 10/08/2026, dado confirmado: o
# robocopy /E cego que existia aqui antes vazava scripts/smoke-test-studio.ps1 - o smoke DA
# INSTANCIA Studio Farina, nao do motor - para todo pacote publico). Allowlist falha fechado:
# script novo nasce de FORA do pacote ate alguem decidir explicitamente ship-lo (mesmo criterio
# de docs/ mais abaixo). Criterio de inclusao, arquivo por arquivo: "isto e mecanismo do MOTOR
# (hook, loop/gate agendado, CLI de Client/Task, integridade, empacotamento) que faz sentido rodar
# em QUALQUER instalacao limpa"? Se sim, entra. Se e amarrado A ESTA INSTANCIA/OFICINA, fica fora.
# Fora de proposito, com o motivo:
#   - smoke-test-studio.ps1  : smoke DA INSTANCIA Studio Farina (le clientes/squads do operador em
#                               state.json do studio) - nao existe "Studio Farina" numa instalacao
#                               limpa; o smoke do MOTOR (o que ship) e scripts/smoke-test.ps1.
#   - migrate-to-studio.ps1  : migracao UNICA do sistema legado do dono (caminhos da maquina dele).
#   - extract-secrets.ps1    : idem - opera em studio/state.json especifico da migracao do dono.
$scriptsAllow = @(
  "_studio.ps1","budget-check.ps1","check-public-surface.ps1","client-state.ps1","cost-per-artifact.ps1","cost-sensor.ps1","ddd-drift.ps1",
  "debt-scan.ps1","delegation-guard.ps1","doctor.ps1","evolution-scan.ps1","git-sync.ps1",
  "graph-check.ps1","graph-usage-sensor.ps1","graph-usage.ps1","guard-core.ps1","health-check.ps1",
  "import-project.ps1","install.ps1","kb-index.ps1","law-ledger-check.ps1",
  "lineage-graph.ps1","make-manifest.ps1","memory-curator.ps1","mission-control.ps1",
  "package-release.ps1","promote-memory.ps1","reflect-check.ps1","register-task.ps1",
  "response-guard.ps1","semantic-lint.ps1","session-reflection.ps1",
  "session-search.py","smoke-test.ps1","squad-bridge.ps1","squad-report.ps1","stale-tasks.ps1",
  "task-context.ps1","update-engine.ps1","update-online.ps1","validate-workflow.ps1","verify-manifest.ps1"
)
$scriptsSrc = Join-Path $root "scripts"
if (Test-Path $scriptsSrc) {
  New-Item -ItemType Directory -Force -Path (Join-Path $out "scripts") | Out-Null
  foreach ($sf in $scriptsAllow) {
    $ssrc = Join-Path $scriptsSrc $sf
    if (Test-Path -LiteralPath $ssrc) { Copy-Item -LiteralPath $ssrc -Destination (Join-Path $out ("scripts\" + $sf)) -Force }
  }
  Write-Host ("    [dir]  scripts\ (" + $scriptsAllow.Count + " arquivo(s), allowlist)")
  # scripts/fixtures/ ship a parte (nao denylist aqui): sao fixtures deterministicas, sem segredo,
  # que o proprio scripts/smoke-test.ps1 do PACOTE (shipado acima) le para se auto-validar no passo
  # 3/3 abaixo (guard de superficie, budget, lineage, stale-tasks) - sem elas o smoke do pacote quebra.
  $fixturesSrc = Join-Path $scriptsSrc "fixtures"
  if (Test-Path $fixturesSrc) {
    robocopy $fixturesSrc (Join-Path $out "scripts\fixtures") /E /NFL /NDL /NP /NS /NC /NJH /NJS | Out-Null
    Write-Host "    [dir]  scripts\fixtures\ (fixtures do smoke, sem segredo)"
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
#   - product/          : PRD, ARQUITETURA, planos de produto internos (planejamento interno).
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

# Nota: scripts/migrate-to-studio.ps1, scripts/extract-secrets.ps1 e scripts/smoke-test-studio.ps1
# ja NAO sao copiados (scripts/ virou allowlist acima) - nao ha mais nada a remover aqui depois do
# fato. O que sobra e so defesa em profundidade no leak-check do passo 3/3, para o caso de a
# allowlist ser alterada por engano no futuro.
$internalFiles = @("scripts\migrate-to-studio.ps1","scripts\extract-secrets.ps1","scripts\smoke-test-studio.ps1")
Write-Host ""

# 3/3 Validar o pacote: zero vazamento de operador + smoke verde no pacote.
Write-Host "3/3 Validando o pacote..."
$leak = @()
foreach ($bad in @("studio","opportunities","rsi-backlog","memory","state.json","studio.yaml")) {
  if (Test-Path (Join-Path $out $bad)) { $leak += $bad }
}
# Defesa em profundidade da allowlist de scripts/: nenhum destes pode existir no pacote, mesmo que
# a allowlist $scriptsAllow volte a incluir um deles por engano no futuro.
foreach ($rel in $internalFiles) {
  if (Test-Path -LiteralPath (Join-Path $out $rel)) { $leak += $rel }
}
# Defesa em profundidade da allowlist de docs/: nenhum destes pode existir no pacote, mesmo que
# um shipDir futuro volte a copiar docs/ por inteiro por engano.
foreach ($bad in @("docs\product","docs\brand","docs\CLAIMS.md","docs\BRAND.md","docs\DESIGN.md","docs\RELEASE-STATUS.md")) {
  if (Test-Path -LiteralPath (Join-Path $out $bad)) { $leak += $bad }
}
# .claude\agents nunca pode ir junto: e onde squad-bridge gera especialista de CLIENTE (task 5,
# conserto do pipeline 09/08/2026). O /XD acima ja evita isso na copia; este check confere que
# o /XD funcionou (defesa em profundidade, nao confia cego no proprio robocopy).
if (Test-Path -LiteralPath (Join-Path $out ".claude\agents")) { $leak += ".claude\agents" }
if ($leak.Count -gt 0) { Write-Host ("[ERRO] vazou dado de operador/interno no pacote: " + ($leak -join ", ")); exit 1 }

# Nenhum caminho absoluto de maquina pode sobrar (path de usuario Windows). Guard generico: nao
# crava nome privado neste script (que e publicado) - so detecta o padrao de pasta de usuario.
$pathLeaks = Get-ChildItem -Path $out -Recurse -File -Include *.ps1,*.py,*.md,*.html,*.json,*.bat,*.yaml,*.yml -ErrorAction SilentlyContinue |
  Where-Object { (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'C:\\Users\\[^\\]+\\' } |
  ForEach-Object { $_.FullName.Substring($out.Length).TrimStart('\') }
if ($pathLeaks.Count -gt 0) {
  Write-Host ("[ERRO] caminho absoluto de maquina vazou no pacote: " + ($pathLeaks -join ", ")); exit 1
}

# Gate final: o guarda da LEI da superficie publica (scripts/check-public-surface.ps1) tem que
# aprovar o PACOTE em si (nao so a raiz da oficina) - fecha o ciclo (task 4, auditoria de
# superficie 10/08/2026). ANTES disto o guarda nunca era chamado aqui: dava pra empacotar e
# publicar sem passar por ele. Reprovou, ABORTA o empacotamento (nao so avisa) - mesmo criterio
# de "reprovou, nao publica" de engine/governance/public-surface.md.
& (Join-Path $PSScriptRoot "check-public-surface.ps1") -Repo $out
if ($LASTEXITCODE -ne 0) { Write-Host "[ERRO] o pacote reprovou no guarda da superficie publica (check-public-surface.ps1). Empacotamento abortado."; exit 1 }
Write-Host "    guarda da superficie publica: pacote APROVADO."
Write-Host ""

# Sincroniza o numero publico do README ANTES do gate real (causa raiz do fossil "N na versao
# atual" repetir 3x: 161 -> 179 -> 185 - o numero era escrito a mao e o total muda toda vez que
# alguem adiciona um check). Roda o smoke do PACOTE com -UpdateReadme: ele reescreve so a linha
# "(N na versao atual" com o total real deste contexto, se estiver errada. Copia a correcao de
# volta pra raiz da oficina (a fonte) - senao a proxima edicao manual do README perderia o numero
# certo nesta mesma pasta, mas o proximo empacotamento a partir da raiz voltaria a vazar o antigo.
& (Join-Path $out "scripts\smoke-test.ps1") -UpdateReadme | Out-Null
Copy-Item -LiteralPath (Join-Path $out "README.md") -Destination (Join-Path $root "README.md") -Force
Write-Host "    numero publico do README.md sincronizado com o total real (gerado, nao mais escrito a mao)."

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
