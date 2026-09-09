<#
 session-baton.ps1 - Escreve o bastao da sessao (engine/features/bastao.md) no fecho/compactacao.
 Chamado pelos hooks PreCompact e SessionEnd (fiacao do WARDEN, fora do escopo deste script).

 Le o payload do hook via stdin (JSON: session_id, cwd, transcript_path quando vier), acha no
 state.json do studio a(s) Task(s) com status doing/review cujo campo "session" bate o
 session_id do payload, e escreve studio/baton/<session_id>.md com os campos do CONTRATO
 (engine/features/bastao.md): de/para/task_id/decisoes/arquivos_tocados/bloqueios/proximo_passo.
 Sem Task da sessao: bastao minimo (data, cwd, "sem Task ativa") - nao e erro, e informacao.

 Teto DURO de 1800 bytes (~500 tokens, cabeca de linha do contrato) - corta o corpo, nunca a
 saudacao/rodape. ASCII, .NET UTF-8 sem BOM. exit 0 sempre (hook nunca pode travar a sessao).

 Uso (producao, via hook): payload JSON no stdin, sem parametros.
 Uso (teste): echo '{"session_id":"abc","cwd":"C:\..."}' | powershell -File scripts/session-baton.ps1 -Root <studio-root>
#>
param([string]$Root = "", [string]$StateFile = "", [string]$OutDir = "")

$ErrorActionPreference = "Continue"
$MAX_BYTES = 1800

function Cut([string]$s, [int]$max) {
 $bytes = [System.Text.Encoding]::UTF8.GetByteCount($s)
 if ($bytes -le $max) { return $s }
 # corte duro por caractere (aproxima char->byte 1:1 em ASCII, o padrao deste motor)
 if ($s.Length -gt $max) { return $s.Substring(0, $max) }
 return $s
}

try {
 $root = if (-not [string]::IsNullOrWhiteSpace($Root)) { $Root } else { Split-Path -Parent $PSScriptRoot }
 $utf8 = New-Object System.Text.UTF8Encoding($false)

 # (0) Payload do hook - so le stdin quando redirecionado (hook real ou teste por pipe).
 $raw = ""
 if ([Console]::IsInputRedirected) {
 $readTask = [Console]::In.ReadToEndAsync()
 $raw = if ($readTask.Wait(2000)) { $readTask.Result } else { "" }
 }
 $sessionId = ""
 $cwd = ""
 if (-not [string]::IsNullOrWhiteSpace($raw)) {
 try {
 $h = $raw | ConvertFrom-Json
 try { $sessionId = [string]$h.session_id } catch { }
 try { $cwd = [string]$h.cwd } catch { }
 } catch { }
 }
 if ([string]::IsNullOrWhiteSpace($sessionId)) { $sessionId = "sem-sessao-" + (Get-Date).ToString("yyyyMMddHHmmss") }

 if ([string]::IsNullOrWhiteSpace($StateFile)) {
 $candA = Join-Path $root "studio\state.json"
 $StateFile = if (Test-Path -LiteralPath $candA) { $candA } else { Join-Path $root "state.json" }
 }
 if ([string]::IsNullOrWhiteSpace($OutDir)) {
 # TASK-509: so grava quando existe um STUDIO de verdade (studio/state.json). Sem studio nao ha
 # sessao real para registrar - e sair criando baton/ na raiz suja o pacote. Medido: o smoke que
 # roda contra release/alia-flow criava uma pasta baton/ na raiz do pacote, que viajou pro produto.
 $studioDir = Split-Path -Parent $StateFile
 if (-not (Test-Path -LiteralPath (Join-Path $studioDir "state.json"))) { return }
 if ((Split-Path -Leaf $studioDir) -ne "studio") { return }
 $OutDir = Join-Path $studioDir "baton"
 }
 if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
 $outFile = Join-Path $OutDir ($sessionId + ".md")
 $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

 $tasks = @()
 if (Test-Path -LiteralPath $StateFile) {
 try {
 $st = [System.IO.File]::ReadAllText($StateFile) | ConvertFrom-Json
 if ($st.tasks) { $tasks = @($st.tasks) }
 } catch { }
 }
 function Field($t, $name) {
 $v = $null; try { $v = $t.PSObject.Properties[$name].Value } catch { }
 if ($null -eq $v) { return "" } else { return "$v" }
 }
 $mine = @($tasks | Where-Object {
 (Field $_ 'session') -eq $sessionId -and
 ((Field $_ 'status') -eq 'doing' -or (Field $_ 'status') -eq 'review' -or (Field $_ 'status') -eq 'in_review')
 })

 $lines = New-Object System.Collections.Generic.List[string]
 $lines.Add("# Bastao de sessao")
 $lines.Add("data: " + $now)
 $lines.Add("cwd: " + $cwd)
 $lines.Add("session_id: " + $sessionId)
 $lines.Add("")

 if ($mine.Count -eq 0) {
 $lines.Add("sem Task ativa (nenhuma Task doing/review desta sessao no state.json)")
 } else {
 foreach ($t in $mine) {
 $lines.Add("task_id: " + (Field $t 'id'))
 $lines.Add("de: " + $(if ((Field $t 'agent_id') -ne '') { Field $t 'agent_id' } else { Field $t 'specialist' }))
 $lines.Add("para: (a definir por quem recebe)")
 $lines.Add("decisoes:")
 $lines.Add(" - status registrado: " + (Field $t 'status') + " | gate: " + $(if ((Field $t 'gate_verdict') -eq '') { "(sem veredito)" } else { Field $t 'gate_verdict' }))
 $lines.Add("arquivos_tocados:")
 $art = Field $t 'artifact'
 if ($art -ne '') { $lines.Add(" - " + $art) } else { $lines.Add(" - (nao registrado)") }
 $lines.Add("bloqueios: []")
 $lines.Add("proximo_passo: retomar " + (Field $t 'id') + " (" + (Field $t 'title') + ") a partir do artifact acima.")
 $lines.Add("consumed: false")
 $lines.Add("")
 }
 }

 $body = ($lines -join "`n")
 $body = Cut $body $MAX_BYTES
 [System.IO.File]::WriteAllText($outFile, $body, $utf8)
 Write-Host ("[OK] bastao escrito: " + $outFile)
 exit 0
} catch {
 Write-Host ("[AVISO] session-baton falhou sem travar a sessao: " + $_.Exception.Message)
 exit 0
}
