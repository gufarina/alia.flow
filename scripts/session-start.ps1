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

 # Linha curta da lei de delegacao (reaproveitada de delegation-guard.ps1:20 - reuse-first,
 # nao duplica o texto como fonte, so cita o mesmo conteudo). UserPromptSubmit parou de injetar
 # isto a cada turno; o boot injeta uma vez por sessao/resume/compact.
 Write-Output "[ALIA - lei de operacao] DELEGA: dominio e do especialista do squad - a Alia coordena, registra a Task e aciona a mao mais capaz; nunca executa dominio com a propria mao (engine/orchestration.md, passo DELEGA). FONTE ANTES DE VARRER: se o cliente tem graphify-out/, mapas ou docs curados, leia-os antes de qualquer varredura de codigo. Excecao unica: ordem explicita do operador para a Alia executar ela mesma."

 exit 0
} catch {
 exit 0
}
