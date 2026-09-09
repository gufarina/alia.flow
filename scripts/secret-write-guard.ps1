<#
  secret-write-guard.ps1 - Hook de PreToolUse. GUARDA NO ATO: bloqueia Write/Edit/NotebookEdit
  ANTES de gravar quando o CONTEUDO carrega o valor puro de um segredo conhecido pelo cofre
  (studio/.secrets/vault.json). Mesmo molde de scripts/delegation-gate.ps1 (reuse-first: matcher
  de PreToolUse, payload JSON no STDIN, contrato de recusa permissionDecision:deny).

  Por que existe (mandato do CEO, 08/09/2026, WARDEN): o incidente que criou secret.ps1 foi um
  VERCEL_TOKEN colado na CONVERSA - fora do escopo deste hook (conversa nao e Write/Edit). O que
  este hook fecha e o padrao IRMAO, medido como o furo real do motor (L42/memoria
  "varredura-de-identidade-nao-e-de-credencial"): segredo JA conhecido do cofre reaparecendo, por
  copy-paste ou script gerado, dentro de um arquivo que a casa esta prestes a gravar (state.json,
  artifact de cliente, memoria, doc versionado). check-public-surface.ps1 secao (1.7) prova a
  MESMA regra depois do fato (gate de empacotamento/smoke); este hook prova ANTES, no ATO.

  Contrato: JSON no STDIN (session_id, transcript_path, tool_name, tool_input). Para Write:
  tool_input.file_path + tool_input.content. Para Edit: tool_input.file_path + tool_input.new_string
  (so o texto NOVO importa - o texto antigo que esta saindo nao e o problema). Para NotebookEdit:
  tool_input.notebook_path + tool_input.new_source. Fora desses tres tool_name: exit 0 silencioso.

  Contrato de recusa (identico a delegation-gate.ps1):
    {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
     "permissionDecisionReason":"<texto, cita NOME e FINGERPRINT, nunca o valor>"}}

  EXCLUSOES: o proprio cofre (.secrets/) e o proprio ledger (secrets-ledger.jsonl) nunca bloqueiam
  (e la que o valor DEVE morar) - mesmo padrao de auto-exclusao de memory/ em delegation-gate.ps1.

  SEM VAULT (arquivo ausente ou vazio): nada a comparar, libera sempre - nao da pra exigir o que
  nao existe (mesma doutrina do graph-usage-sensor.ps1 pra Client sem mapa).

  Segredo com menos de 8 caracteres NUNCA entra na comparacao (ruido: string curta bate por acaso
  em qualquer arquivo grande - risco de FALSO POSITIVO alto pra ganho de seguranca baixo).

  Ao bloquear, grava uma linha "fail" no MESMO ledger que secret.ps1 usa (reuse-first: mesma
  funcao de append, mesmo schema) - o bloqueio em si vira evidencia auditavel.

  INTERRUPTOR DE EMERGENCIA (mesmo padrao dos outros guards): env ALIA_SECRET_GUARD_OFF=1 (ou
  "true") OU arquivo .claude/secret-guard.off desligam SO o bloqueio (a leitura do vault nem
  acontece), fail-soft.

  BLINDAGEM: tudo em try/catch. Qualquer erro -> exit 0 silencioso. Guarda quebrado nunca trava.

 Parametros de teste (WARDEN): -Root, -VaultPath, -LedgerPath - mesmo padrao dos outros hooks. Escrita .NET UTF-8 sem BOM.
#>
# WARDEN 09/09/2026: logica movida para funcao Invoke-SecretWriteGuard (aceita -RawInput) para
# permitir chamada em-processo por scripts/pre-tool-use.ps1 (1 spawn em vez de 2). Rodar este
# arquivo direto (powershell -File) continua identico.
param(
  [string]$Root = "",
  [string]$VaultPath = "",
 [string]$LedgerPath = "",
 [string]$RawInput = $null
)

function Invoke-SecretWriteGuard {
param(
 [string]$Root = "",
 [string]$VaultPath = "",
 [string]$LedgerPath = "",
 [string]$RawInput = $null
)

try {
  $offEnv = $env:ALIA_SECRET_GUARD_OFF
  $guardOff = ($offEnv -eq "1") -or ($offEnv -eq "true")

  $raw = ""
 if (-not [string]::IsNullOrWhiteSpace($RawInput)) {
 $raw = $RawInput
 } else {
 if (-not [Console]::IsInputRedirected) { return }

  try {
    $readTask = [Console]::In.ReadToEndAsync()
    if ($readTask.Wait(5000)) { $raw = $readTask.Result } else { $raw = "" }
  } catch { $raw = "" }
}

 if ([string]::IsNullOrWhiteSpace($raw)) { return }

  $h = $null
 try { $h = $raw | ConvertFrom-Json } catch { return }
 if ($null -eq $h) { return }

  $tool = ""
  try { $tool = [string]$h.tool_name } catch { }
 if ($tool -ne 'Write' -and $tool -ne 'Edit' -and $tool -ne 'NotebookEdit') { return }

  $root = if (-not [string]::IsNullOrWhiteSpace($Root)) { $Root } else { Split-Path -Parent $PSScriptRoot }
  $offFile = Join-Path $root ".claude\secret-guard.off"
  if (Test-Path -LiteralPath $offFile) { $guardOff = $true }
 if ($guardOff) { return }

  # _studio.ps1 e sempre o irmao REAL deste arquivo em disco (PSScriptRoot nunca muda com -Root).
  . (Join-Path $PSScriptRoot "_studio.ps1")
  $studioRoot = Get-StudioRoot -Root $root
  $vaultFile = if (-not [string]::IsNullOrWhiteSpace($VaultPath)) { $VaultPath } else { Join-Path $studioRoot ".secrets\vault.json" }
  $ledgerFile = if (-not [string]::IsNullOrWhiteSpace($LedgerPath)) { $LedgerPath } else { Join-Path $studioRoot "secrets-ledger.jsonl" }
 if (-not (Test-Path -LiteralPath $vaultFile)) { return }

  $fp = ""
  try { $fp = [string]$h.tool_input.file_path } catch { }
  if ([string]::IsNullOrWhiteSpace($fp)) { try { $fp = [string]$h.tool_input.notebook_path } catch { } }
 if ([string]::IsNullOrWhiteSpace($fp)) { return }
  $norm = $fp.Replace('\', '/').ToLowerInvariant()
 if ($norm.Contains('.secrets/') -or $norm.Contains('secrets-ledger.jsonl')) { return }

  $content = ""
  if ($tool -eq 'Write') { try { $content = [string]$h.tool_input.content } catch { } }
  elseif ($tool -eq 'Edit') { try { $content = [string]$h.tool_input.new_string } catch { } }
  elseif ($tool -eq 'NotebookEdit') { try { $content = [string]$h.tool_input.new_source } catch { } }
 if ([string]::IsNullOrEmpty($content)) { return }

  $vaultRaw = ""
 try { $vaultRaw = [System.IO.File]::ReadAllText($vaultFile) } catch { return }
 if ([string]::IsNullOrWhiteSpace($vaultRaw)) { return }
  $vaultObj = $null
 try { $vaultObj = $vaultRaw | ConvertFrom-Json } catch { return }
 if ($null -eq $vaultObj -or -not ($vaultObj.PSObject.Properties.Name -contains 'secrets')) { return }

  $hit = $null
  foreach ($p in $vaultObj.secrets.PSObject.Properties) {
    $sVal = "$($p.Value.value)"
    if ($sVal.Length -lt 8) { continue }
    if ($content.Contains($sVal)) { $hit = $p.Value; break }
  }

 if ($null -eq $hit) { return }

  $sessionId = ""
  try { $sessionId = [string]$h.session_id } catch { }

  try {
    $dir = Split-Path -Parent $ledgerFile
    if (-not [string]::IsNullOrWhiteSpace($dir)) { New-Item -ItemType Directory -Force -Path $dir -ErrorAction SilentlyContinue | Out-Null }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $entry = [ordered]@{
      ts = (Get-Date).ToUniversalTime().ToString("o")
      secret = "$($hit.name)"; scope = "$($hit.scope)"; action = "fail"
      who = "secret-write-guard.ps1 (session_id=" + $sessionId + ")"
      reason = "bloqueado no ATO: valor apareceu em " + $fp
      fingerprint = "$($hit.fingerprint)"
    }

    [System.IO.File]::AppendAllText($ledgerFile, (($entry | ConvertTo-Json -Compress) + "`n"), $utf8)
  } catch { }

  $reason = "[SEGREDO] valor de '" + $hit.name + "' (escopo " + $hit.scope + ", fingerprint " + $hit.fingerprint + ") detectado no conteudo de " + $fp + " - nunca cole valor de segredo em arquivo. Use scripts/secret.ps1 -Use para injetar via variavel de ambiente sem ver o valor."
  $out = [ordered]@{
    hookSpecificOutput = [ordered]@{
      hookEventName = "PreToolUse"
      permissionDecision = "deny"
      permissionDecisionReason = $reason
    }

  }

  Write-Output ($out | ConvertTo-Json -Depth 5 -Compress)
 return
} catch {
 return
}
}

if ($MyInvocation.InvocationName -ne '.') {
 Invoke-SecretWriteGuard -Root $Root -VaultPath $VaultPath -LedgerPath $LedgerPath -RawInput $RawInput
  exit 0
}
