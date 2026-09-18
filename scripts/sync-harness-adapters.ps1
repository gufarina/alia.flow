# Alia Flow - sync-harness-adapters.ps1
#
# Uma fonte, tres hosts. O corpo da skill "alia" (o gatilho de presenca + a deteccao de harness)
# vive UMA vez em skills\alia\ALIA.md. Cada coding agent le esse mesmo texto num caminho diferente,
# com um frontmatter diferente - entao este script GERA as copias:
#
#   .claude\skills\alia\SKILL.md   - Claude Code (skill; vence command de mesmo nome)
#   .agents\skills\alia\SKILL.md   - Codex ($alia) e OpenCode (que tambem le .agents\skills)
#   .opencode\commands\alia.md     - OpenCode (/alia)
#
# As duas SKILL.md sao BYTE-IDENTICAS entre si (mesmo frontmatter name+description). A copia do
# OpenCode e um command: frontmatter so com description. Por isso o contrato que o smoke cobra e
# sobre o CORPO: o hash SHA256 do corpo (tudo depois do frontmatter) tem que ser o mesmo nos tres.
#
# NUNCA edite uma copia a mao - a proxima geracao sobrescreve. Mexer no texto = editar
# skills\alia\ALIA.md e rodar este script.
#
# -Check nao escreve nada: so compara e sai 1 se algo divergir (uso em CI/smoke).
# -DryRun mostra o que faria.
# UTF-8 sem BOM.

[CmdletBinding()]
param([switch]$Check, [switch]$DryRun)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'skills\alia\ALIA.md'

if (-not (Test-Path -LiteralPath $sourcePath)) {
    Write-Error "fonte nao encontrada: $sourcePath"
    exit 1
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$raw = [System.IO.File]::ReadAllText($sourcePath, $utf8NoBom)
$raw = $raw -replace "`r`n", "`n"

# A primeira linha da fonte e "DESCRIPTION: ..." - vira o campo description do frontmatter de cada
# host. O corpo comeca depois dela.
$lines = $raw -split "`n"
if ($lines[0] -notmatch '^DESCRIPTION:\s*(.+)$') {
    Write-Error "a primeira linha de $sourcePath tem que ser 'DESCRIPTION: <texto>'"
    exit 1
}
$description = $Matches[1].Trim()
$body = (($lines | Select-Object -Skip 1) -join "`n").Trim() + "`n"

$skillFrontmatter = @(
    '---',
    'name: alia',
    "description: $description",
    '---',
    ''
) -join "`n"

$commandFrontmatter = @(
    '---',
    "description: $description",
    '---',
    ''
) -join "`n"

$targets = @(
    @{ Path = (Join-Path $root '.claude\skills\alia\SKILL.md'); Content = $skillFrontmatter + $body },
    @{ Path = (Join-Path $root '.agents\skills\alia\SKILL.md'); Content = $skillFrontmatter + $body },
    @{ Path = (Join-Path $root '.opencode\commands\alia.md');   Content = $commandFrontmatter + $body }
)

$divergent = @()
$written = 0

foreach ($t in $targets) {
    $exists = Test-Path -LiteralPath $t.Path
    $same = $false
    if ($exists) {
        $current = [System.IO.File]::ReadAllText($t.Path, $utf8NoBom) -replace "`r`n", "`n"
        $same = ($current -eq $t.Content)
    }

    if ($same) {
        Write-Host ("[OK]   " + $t.Path.Substring($root.Length + 1))
        continue
    }

    $divergent += $t.Path.Substring($root.Length + 1)

    if ($Check) {
        Write-Host ("[DIFF] " + $t.Path.Substring($root.Length + 1) + $(if ($exists) { " (conteudo divergente)" } else { " (ausente)" }))
        continue
    }
    if ($DryRun) {
        Write-Host ("[DRYRUN] escreveria: " + $t.Path.Substring($root.Length + 1))
        continue
    }

    $dir = Split-Path -Parent $t.Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($t.Path, $t.Content, $utf8NoBom)
    Write-Host ("[GRAVADO] " + $t.Path.Substring($root.Length + 1))
    $written++
}

Write-Host ''
if ($Check) {
    if ($divergent.Count -gt 0) {
        Write-Host ("DIVERGENTE: " + ($divergent -join ', ') + " - rode sync-harness-adapters.ps1 sem -Check")
        exit 1
    }
    Write-Host 'OK: as tres copias batem com skills\alia\ALIA.md'
    exit 0
}

Write-Host ("sync-harness-adapters: " + $written + " arquivo(s) gravado(s), " + ($targets.Count - $written) + " ja em dia")
exit 0
