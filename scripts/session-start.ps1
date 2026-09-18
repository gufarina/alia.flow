<#
 session-start.ps1 - Hook UNICO de SessionStart (matcher startup|resume|compact).
 WARDEN 09/09/2026: antes eram 2 hooks separados (reflect-check.ps1 + detect-harness.ps1),
 2 spawns de powershell.exe por evento de boot/resume/compact. Este arquivo chama os dois EM-
 PROCESSO (dot-source, sem novo processo) e ainda injeta o NUCLEO (engine/agents/nucleo.md) +
 a linha curta da lei de delegacao (reaproveitada de delegation-guard.ps1) - 1 spawn no lugar de
 2 (antes o nucleo nao era injetado por hook nenhum; UserPromptSubmit deixou de carregar
 delegation-guard.ps1 neste OPP, ver settings.json).

 Matcher "resume": [INFERIDO] - nao foi possivel confirmar na doc oficial do Claude Code hooks
 neste turno se "resume" e um matcher valido de SessionStart (a doc lista startup/resume/clear
 em versoes recentes, mas nao foi verificada aqui ao vivo). "compact" e evento PROPRIO
 (PreCompact), tratado por scripts/session-baton.ps1 se existir - nao por este hook.

 BLINDAGEM: tudo em try/catch. exit 0 sempre. Guarda quebrado nunca trava o boot.
#>
try {
 . (Join-Path $PSScriptRoot "reflect-check.ps1")
 Invoke-ReflectCheck

 . (Join-Path $PSScriptRoot "detect-harness.ps1")
 Invoke-DetectHarness

 $root = Split-Path -Parent $PSScriptRoot
 $nucleoPath = Join-Path $root "engine\agents\nucleo.md"
 if (Test-Path -LiteralPath $nucleoPath) {
 try {
 $nucleo = [System.IO.File]::ReadAllText($nucleoPath)
 Write-Output "---"
 Write-Output $nucleo
 Write-Output "---"
 } catch { }
 }

 # WARDEN 09/09/2026: a linha curta de lei que existia aqui (prefixo ALIA entre colchetes)
 # foi removida - duplicava DELEGA e valvula (secao "DELEGA e a valvula") e fonte-antes-de-
 # varrer (secao "Leitura por indice") do proprio engine/agents/nucleo.md, ja injetado em
 # texto INTEGRAL nas linhas acima, no MESMO boot.

 # WARDEN 09/09/2026: engine/MAP.md promete "nucleo + bastao mais recente + pendencias" no boot,
 # mas nenhum hook lia bastao ([MEDIDO] antes deste conserto). Injeta o bastao MAIS RECENTE de
 # studio/baton/ (contrato em engine/features/bastao.md, teto de 1800 bytes ja aplicado na
 # ESCRITA por session-baton.ps1 - aqui so relemos e recortamos de novo por seguranca). Sem
 # bastao nenhum: silencio, nunca inventa aviso. Fail-soft: qualquer erro aqui nunca trava o boot.
 try {
 . (Join-Path $PSScriptRoot "_studio.ps1")
 $studioRoot = Get-StudioRoot -Root $root
 $batonDir = Join-Path $studioRoot "baton"
 if (Test-Path -LiteralPath $batonDir) {
 $latest = Get-ChildItem -LiteralPath $batonDir -Filter "*.md" -ErrorAction SilentlyContinue |
 Sort-Object LastWriteTime -Descending | Select-Object -First 1
 if ($null -ne $latest) {
 $batonText = [System.IO.File]::ReadAllText($latest.FullName)
 if ([System.Text.Encoding]::UTF8.GetByteCount($batonText) -gt 1800) {
 $batonText = $batonText.Substring(0, 1800)
 }
 Write-Output "---"
 Write-Output $batonText
 Write-Output "---"
 }
 }
 } catch { }

 exit 0
} catch {
 exit 0
}
