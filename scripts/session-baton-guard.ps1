<#
 session-baton-guard.ps1 - Hook de PreCompact e SessionEnd. Chama scripts/session-baton.ps1
 (dono: ARCHIVE) SE ele existir; se ainda nao existir, ignora e sai (exit 0) em silencio - nao
 bloqueia o evento nem quebra a cadeia (session-reflection.ps1 continua como segundo hook do
 mesmo evento em settings.json, roda de qualquer jeito).
 BLINDAGEM: tudo em try/catch. exit 0 sempre.
#>
try {
 $root = Split-Path -Parent $PSScriptRoot
 $batonPath = Join-Path $root "scripts\session-baton.ps1"
 if (-not (Test-Path -LiteralPath $batonPath)) { exit 0 }

 $raw = ""
 if ([Console]::IsInputRedirected) {
 try {
 $readTask = [Console]::In.ReadToEndAsync()
 if ($readTask.Wait(5000)) { $raw = $readTask.Result } else { $raw = "" }
 } catch { $raw = "" }
 }
 if ([string]::IsNullOrWhiteSpace($raw)) {
 & $batonPath
 } else {
 $raw | & $batonPath
 }
 exit 0
} catch {
 exit 0
}
