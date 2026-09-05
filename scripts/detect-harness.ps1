# Alia Flow - detect-harness.ps1 (onde eu estou?)
#
# Responde UMA pergunta: em qual coding agent (harness) a Alia esta rodando agora, e o que aquele
# host sabe fazer. Fecha o Delta 3 de OPP-42 ("Deteccao de host no boot") e o incidente de origem
# daquela OPP: no Codex a Alia seguiu ate DELEGA e TRAVOU tentando spawnar sub-agente que aquele
# host nao tem. Com a deteccao na entrada, ela ESCOLHE o modo antes de tentar.
#
# Saida (ASCII, uma chave por linha, chave=valor - facil de ler por humano e por script):
#   harness=claude-code|opencode|codex|unknown
#   spawn=yes|no                 (o host tem sub-agente nativo?)
#   hooks=yes|no                 (o host dispara automacao de ciclo de vida?)
#   skills_dir=<caminho relativo que AQUELE host le>
#   delegation_mode=spawn|context-load
#   signal=<a evidencia que decidiu>
#
# -Json imprime o mesmo conteudo como objeto JSON.
#
# NUNCA falha: exit 0 sempre, qualquer erro vira harness=unknown (fail-soft). Deteccao errada
# nunca pode travar o trabalho - e por isso que o desconhecido cai em context-load, o modo que
# funciona em QUALQUER host (nao depende de ferramenta de spawn).
#
# ORDEM DOS SINAIS (do mais forte pro mais fraco):
#   1. CLAUDECODE=1                       -> claude-code   (env documentado do Claude Code)
#   2. CODEX_SANDBOX / CODEX_SANDBOX_NETWORK_DISABLED -> codex (env que a shell tool do Codex seta)
#   3. marcador de pasta                  -> heuristica (fraca, ver ressalva abaixo)
#   4. nada                               -> unknown + context-load
#
# RESSALVA MEDIDA (honestidade): a partir da v1.65.0 TODA instalacao do Alia Flow tem ao mesmo
# tempo .claude/ E .opencode/ E .agents/ (e o que torna a Alia portavel). Logo, marcador de pasta
# DENTRO do repo deixou de distinguir host. Quando mais de um marcador aparece, este script NAO
# escolhe no chute: cai para unknown + context-load, dizendo isso no campo signal. So marcador
# UNICO ainda vale como pista. OpenCode nao publica variavel de ambiente propria em doc oficial -
# por isso ele so e detectado por marcador unico ou pela pasta de config do usuario.

[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = 'Continue'

function Get-HarnessProfile {
    param([string]$Harness, [string]$Signal)

    switch ($Harness) {
        'claude-code' {
            return [ordered]@{
                harness = 'claude-code'; spawn = 'yes'; hooks = 'yes'
                skills_dir = '.claude/skills'; delegation_mode = 'spawn'; signal = $Signal
            }
        }
        'opencode' {
            return [ordered]@{
                harness = 'opencode'; spawn = 'yes'; hooks = 'yes'
                skills_dir = '.opencode/skills'; delegation_mode = 'spawn'; signal = $Signal
            }
        }
        'codex' {
            return [ordered]@{
                harness = 'codex'; spawn = 'no'; hooks = 'no'
                skills_dir = '.agents/skills'; delegation_mode = 'context-load'; signal = $Signal
            }
        }
        default {
            return [ordered]@{
                harness = 'unknown'; spawn = 'no'; hooks = 'no'
                skills_dir = '.agents/skills'; delegation_mode = 'context-load'; signal = $Signal
            }
        }
    }
}

$harness = 'unknown'
$signal = 'nenhum sinal reconhecido - assumindo o modo que funciona em qualquer host'

try {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $home1 = $env:USERPROFILE
    if (-not $home1) { $home1 = $env:HOME }

    # --- 1. env do Claude Code (documentado: code.claude.com/docs/en/env-vars) ---
    if ($env:CLAUDECODE -eq '1') {
        $harness = 'claude-code'
        $signal = 'env CLAUDECODE=1'
    }
    # --- 2. env do Codex (a shell tool do Codex seta CODEX_SANDBOX_NETWORK_DISABLED sempre) ---
    elseif ($env:CODEX_SANDBOX -or $env:CODEX_SANDBOX_NETWORK_DISABLED) {
        $harness = 'codex'
        $found = @()
        if ($env:CODEX_SANDBOX) { $found += 'CODEX_SANDBOX' }
        if ($env:CODEX_SANDBOX_NETWORK_DISABLED) { $found += 'CODEX_SANDBOX_NETWORK_DISABLED' }
        $signal = 'env ' + ($found -join '+')
    }
    else {
        # --- 3. heuristica por marcador de pasta (fraca - so vale marcador UNICO) ---
        $marks = @()
        if (Test-Path -LiteralPath (Join-Path $repoRoot '.opencode')) { $marks += 'opencode:repo/.opencode' }
        if ($home1 -and (Test-Path -LiteralPath (Join-Path $home1 '.config\opencode'))) { $marks += 'opencode:~/.config/opencode' }
        if ($home1 -and (Test-Path -LiteralPath (Join-Path $home1 '.codex'))) { $marks += 'codex:~/.codex' }
        if (Test-Path -LiteralPath (Join-Path $repoRoot '.claude')) { $marks += 'claude-code:repo/.claude' }

        $hosts = @($marks | ForEach-Object { ($_ -split ':')[0] } | Select-Object -Unique)

        if ($hosts.Count -eq 1) {
            $harness = $hosts[0]
            $signal = 'marcador de pasta (unico): ' + ($marks -join ', ')
        }
        elseif ($hosts.Count -gt 1) {
            $harness = 'unknown'
            $signal = 'marcadores de pasta ambiguos (' + ($marks -join ', ') + ') - toda instalacao do Alia Flow tem os tres; sem env do host nao da pra decidir'
        }
    }
}
catch {
    $harness = 'unknown'
    $signal = 'erro na deteccao (fail-soft): ' + $_.Exception.Message
}

$result = Get-HarnessProfile -Harness $harness -Signal $signal

if ($Json) {
    ($result | ConvertTo-Json -Compress) | Write-Output
}
else {
    foreach ($k in $result.Keys) { Write-Output ("$k=" + $result[$k]) }
}

exit 0
