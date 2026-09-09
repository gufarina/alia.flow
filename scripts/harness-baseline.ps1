<#
 harness-baseline.ps1 - WARDEN, 09/09/2026. Mede e grava (ou confere, -Check) a catraca de
 performance do motor: janela fria (bytes/tokens), latencia de hook (p50/p95), violacoes por
 100 turnos (response-guard-log.jsonl) e custo medio por Task delegada. Grava em
 studio/harness-baseline.txt (studio da instancia - resolvido via alia.config.json/studio_dir,
 ou -StudioDir).

 MODO NORMAL: mede e GRAVA (sobrescreve) o arquivo, com cabecalho de data.
 MODO -Check: mede de novo, compara com o arquivo gravado, sai 1 se QUALQUER metrica numerica
 piorar mais de 10% (catraca - nunca deixa regredir em silencio). Metrica ausente no baseline
 (primeira vez) -> AVISO, exit 0 (nao ha o que comparar ainda).

 Tokens estimados por ~4 caracteres/token (heuristica padrao, sem chamar modelo - fail-soft e
 sem custo). BLINDAGEM: tudo em try/catch por secao; erro numa secao vira "n/a" naquela linha,
 nunca derruba o script inteiro.
#>
param(
 [string]$StudioDir = "",
 [switch]$Check
)

function Get-StudioDirLocal {
 param([string]$Root)
 $cfgPath = Join-Path $Root "alia.config.json"
 $dir = "studio"
 if (Test-Path -LiteralPath $cfgPath) {
 try {
 $cfg = (Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8) | ConvertFrom-Json
 if ($cfg.studio_dir) { $dir = [string]$cfg.studio_dir }
 } catch { }
 }
 return (Join-Path $Root $dir)
}

function Get-TokenEstimate([string]$Text) {
 if ([string]::IsNullOrEmpty($Text)) { return 0 }
 return [math]::Ceiling($Text.Length / 4.0)
}

$root = Split-Path -Parent $PSScriptRoot
$studioDir = if (-not [string]::IsNullOrWhiteSpace($StudioDir)) { $StudioDir } else { Get-StudioDirLocal -Root $root }
$baselineFile = Join-Path $studioDir "harness-baseline.txt"

$metrics = [ordered]@{}

# (a) Janela fria: produto (descriptions de .claude/agents/*.md do Client ativo + AGENTS.md/CLAUDE.md
# do motor) e instancia (CLAUDE.md do studio + .claude/rules + MEMORY.md do host, se existir).
try {
 $prodBytes = 0
 $agentsDir = Join-Path $root ".claude\agents"
 if (Test-Path -LiteralPath $agentsDir) {
 foreach ($f in Get-ChildItem -LiteralPath $agentsDir -Filter "*.md" -File -ErrorAction SilentlyContinue) {
 $txt = [System.IO.File]::ReadAllText($f.FullName)
 $m = [regex]::Match($txt, '(?im)^description:\s*(.+)$')
 if ($m.Success) { $prodBytes += $m.Groups[1].Value.Length } else { $prodBytes += [math]::Min($txt.Length, 500) }
 }
 }
 foreach ($rel in @("AGENTS.md", "CLAUDE.md")) {
 $p = Join-Path $root $rel
 if (Test-Path -LiteralPath $p) { $prodBytes += (Get-Item -LiteralPath $p).Length }
 }
 $metrics["janela_fria_produto_bytes"] = $prodBytes
 $metrics["janela_fria_produto_tokens_est"] = Get-TokenEstimate ("x" * $prodBytes)
} catch {
 $metrics["janela_fria_produto_bytes"] = "n/a"
 $metrics["janela_fria_produto_tokens_est"] = "n/a"
}

try {
 $instBytes = 0
 $instCandidates = @()
 $studioClaudeMd = Split-Path -Parent $root
 foreach ($rel in @("CLAUDE.md")) {
 $p = Join-Path $studioClaudeMd $rel
 if (Test-Path -LiteralPath $p) { $instCandidates += $p }
 }
 $rulesDir = Join-Path $studioClaudeMd ".claude\rules"
 if (Test-Path -LiteralPath $rulesDir) {
 $instCandidates += (Get-ChildItem -LiteralPath $rulesDir -Filter "*.md" -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
 }
 $hostMemory = Join-Path $env:USERPROFILE ".claude\projects"
 if (Test-Path -LiteralPath $hostMemory) {
 $memMd = Get-ChildItem -LiteralPath $hostMemory -Filter "MEMORY.md" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
 if ($memMd) { $instCandidates += $memMd.FullName }
 }
 foreach ($p in $instCandidates) { $instBytes += (Get-Item -LiteralPath $p).Length }
 $metrics["janela_fria_instancia_bytes"] = $instBytes
 $metrics["janela_fria_instancia_tokens_est"] = Get-TokenEstimate ("x" * $instBytes)
} catch {
 $metrics["janela_fria_instancia_bytes"] = "n/a"
 $metrics["janela_fria_instancia_tokens_est"] = "n/a"
}

# (b) p50/p95 de latencia de hook: pre-tool-use.ps1 e graph-usage-sensor.ps1, 5x, payload de teste.
function Measure-HookLatency([string]$ScriptPath, [string]$Payload) {
 $samples = @()
 for ($i = 0; $i -lt 5; $i++) {
 $ms = (Measure-Command {
 $Payload | powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath | Out-Null
 }).TotalMilliseconds
 $samples += $ms
 }
 $sorted = $samples | Sort-Object
 $p50 = $sorted[2]
 $p95 = $sorted[4]
 return [pscustomobject]@{ p50 = [math]::Round($p50, 1); p95 = [math]::Round($p95, 1) }
}

try {
 $payload1 = '{"session_id":"baseline","tool_name":"Edit","tool_input":{"file_path":"memory/x.md","new_string":"x"}}'
 $r1 = Measure-HookLatency -ScriptPath (Join-Path $PSScriptRoot "pre-tool-use.ps1") -Payload $payload1
 $metrics["latencia_pretooluse_p50_ms"] = $r1.p50
 $metrics["latencia_pretooluse_p95_ms"] = $r1.p95
} catch {
 $metrics["latencia_pretooluse_p50_ms"] = "n/a"
 $metrics["latencia_pretooluse_p95_ms"] = "n/a"
}

try {
 $payload2 = '{"session_id":"baseline","tool_name":"Bash","tool_input":{"command":"echo x"}}'
 $r2 = Measure-HookLatency -ScriptPath (Join-Path $PSScriptRoot "graph-usage-sensor.ps1") -Payload $payload2
 $metrics["latencia_graphsensor_p50_ms"] = $r2.p50
 $metrics["latencia_graphsensor_p95_ms"] = $r2.p95
} catch {
 $metrics["latencia_graphsensor_p50_ms"] = "n/a"
 $metrics["latencia_graphsensor_p95_ms"] = "n/a"
}

# (c) violacoes por 100 turnos (response-guard-log.jsonl, ultimos 500).
try {
 $rgPath = Join-Path $studioDir "response-guard-log.jsonl"
 if (Test-Path -LiteralPath $rgPath) {
 $lines = @(Get-Content -LiteralPath $rgPath -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -Last 500)
 $viol = 0
 foreach ($l in $lines) {
 if ([string]::IsNullOrWhiteSpace($l)) { continue }
 try { $o = $l | ConvertFrom-Json } catch { continue }
 $action = ""
 try { $action = [string]$o.action } catch { }
 if ($action -eq 'fail' -or $action -eq 'violation' -or $action -eq 'deny') { $viol++ }
 }
 $total = [math]::Max($lines.Count, 1)
 $metrics["violacoes_por_100_turnos"] = [math]::Round((100.0 * $viol / $total), 2)
 } else {
 $metrics["violacoes_por_100_turnos"] = "n/a"
 }
} catch {
 $metrics["violacoes_por_100_turnos"] = "n/a"
}

# (d) custo medio por Task delegada (state.json tasks com campo tokens, se houver).
try {
 $stateFile = Join-Path $root "state.json"
 if (Test-Path -LiteralPath $stateFile) {
 $st = (Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8) | ConvertFrom-Json
 $tasksComTokens = @($st.tasks | Where-Object { $_.PSObject.Properties.Name -contains 'tokens' -and $_.tokens })
 if ($tasksComTokens.Count -gt 0) {
 $soma = ($tasksComTokens | ForEach-Object { [double]$_.tokens } | Measure-Object -Sum).Sum
 $metrics["custo_medio_por_task_tokens"] = [math]::Round($soma / $tasksComTokens.Count, 1)
 } else {
 $metrics["custo_medio_por_task_tokens"] = "n/a"
 }
 } else {
 $metrics["custo_medio_por_task_tokens"] = "n/a"
 }
} catch {
 $metrics["custo_medio_por_task_tokens"] = "n/a"
}

function Format-Baseline([hashtable]$M) {
 $lines = New-Object System.Collections.Generic.List[string]
 $lines.Add("# harness-baseline.txt - WARDEN - gravado em " + (Get-Date).ToUniversalTime().ToString("o"))
 foreach ($k in $M.Keys) { $lines.Add($k + "=" + $M[$k]) }
 return ($lines -join "`n") + "`n"
}

if ($Check) {
 if (-not (Test-Path -LiteralPath $baselineFile)) {
 Write-Host "[AVISO] baseline ausente em $baselineFile - rode sem -Check primeiro para gravar."
 exit 0
 }
 $old = @{}
 foreach ($l in (Get-Content -LiteralPath $baselineFile -Encoding UTF8)) {
 if ($l -match '^([a-z0-9_]+)=(.+)$') { $old[$matches[1]] = $matches[2] }
 }
 $piorou = @()
 foreach ($k in $metrics.Keys) {
 if (-not $old.ContainsKey($k)) { continue }
 $novo = $metrics[$k]
 $antigo = $old[$k]
 $novoNum = 0.0; $antigoNum = 0.0
 if (-not [double]::TryParse([string]$novo, [ref]$novoNum)) { continue }
 if (-not [double]::TryParse([string]$antigo, [ref]$antigoNum)) { continue }
 if ($antigoNum -le 0) { continue }
 $delta = ($novoNum - $antigoNum) / $antigoNum
 # Para "bytes/tokens/latencia/violacoes/custo": maior = pior (tudo aqui e "menor e melhor").
 if ($delta -gt 0.10) { $piorou += ($k + ": " + $antigo + " -> " + $novo + " (+" + [math]::Round($delta * 100, 1) + "%)") }
 }
 if ($piorou.Count -gt 0) {
 Write-Host "[FAIL] catraca de performance regrediu:"
 foreach ($p in $piorou) { Write-Host (" - " + $p) }
 exit 1
 }
 Write-Host "[PASS] catraca de performance: nada regrediu mais de 10%."
 exit 0
} else {
 try {
 if (-not (Test-Path -LiteralPath $studioDir)) { New-Item -ItemType Directory -Force -Path $studioDir -ErrorAction SilentlyContinue | Out-Null }
 $utf8 = New-Object System.Text.UTF8Encoding($false)
 [System.IO.File]::WriteAllText($baselineFile, (Format-Baseline $metrics), $utf8)
 Write-Host ("[OK] baseline gravado em " + $baselineFile)
 } catch {
 Write-Host ("[FALHA] nao consegui gravar baseline: " + $_.Exception.Message)
 }
 exit 0
}
