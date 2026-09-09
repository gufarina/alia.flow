<#
 pre-tool-use.ps1 - Hook UNICO de PreToolUse para o matcher Edit|Write|NotebookEdit|Task.
 WARDEN 09/09/2026: antes existiam 2 hooks separados (delegation-gate.ps1 + secret-write-guard.ps1)
 no settings.json, cada um disparando um spawn de powershell.exe por evento (2 spawns). Este
 arquivo le o STDIN UMA VEZ e chama os dois guards EM-PROCESSO (dot-source, sem novo processo) -
 1 spawn por evento em vez de 2. Medido: spawn puro de powershell ~293ms; cada spawn evitado e
 ~293ms a menos por Edit/Write/Task.

 Semantica preservada: os dois guards continuam independentes (mesma logica interna, mesmo
 contrato de deny). Se delegation-gate negar, o deny dele sai e o secret guard nem roda (mesmo
 efeito pratico de antes - um deny ja bloqueia a ferramenta). Se delegation-gate liberar, o
 secret guard roda em seguida com o MESMO raw JSON.

 Contrato: identico aos guards originais (JSON no STDIN, deny no formato hookSpecificOutput).
 BLINDAGEM: tudo em try/catch, exit 0 sempre. Guarda quebrado nunca trava o operador.
#>
try {
 $raw = ""
 if ([Console]::IsInputRedirected) {
 try {
 $readTask = [Console]::In.ReadToEndAsync()
 if ($readTask.Wait(5000)) { $raw = $readTask.Result } else { $raw = "" }
 } catch { $raw = "" }
 }

 $root = Split-Path -Parent $PSScriptRoot

 . (Join-Path $PSScriptRoot "delegation-gate.ps1") -RawInput $raw
 $delegationOut = Invoke-DelegationGate -RawInput $raw
 if (-not [string]::IsNullOrWhiteSpace($delegationOut)) {
 Write-Output $delegationOut
 exit 0
 }

 . (Join-Path $PSScriptRoot "secret-write-guard.ps1") -RawInput $raw
 $secretOut = Invoke-SecretWriteGuard -RawInput $raw
 if (-not [string]::IsNullOrWhiteSpace($secretOut)) {
 Write-Output $secretOut
 exit 0
 }

 exit 0
} catch {
 exit 0
}
