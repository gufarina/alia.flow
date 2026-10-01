# lib.ps1 - helpers do nucleo da bridge (v2/squad/bridge.ps1). Dot-sourced; sem efeito colateral.
# Nao conhece formato de host nenhum. Espera $RepoRootFull definido pelo chamador.

function ConvertTo-PortablePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = $Path
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { }
    $prefix = $RepoRootFull + [System.IO.Path]::DirectorySeparatorChar
    if ($full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($full.Substring($prefix.Length) -replace '\\', '/')
    }
    return $full
}

# mcp__servidor__ferramenta validada contra .mcp.json: servidor real mantem; correspondencia
# obvia corrige o namespace com aviso; sem correspondencia retorna $null (descartada).
function Resolve-McpTool {
    param([string]$Token, [string[]]$Servers, $Warnings, [string]$Context)
    $parts = $Token -split '__', 3
    if ($parts.Count -lt 3 -or $parts[0] -ne 'mcp') {
        [void]$Warnings.Add("$Context : tool '$Token' fora do formato mcp__servidor__ferramenta - descartada")
        return $null
    }
    $server = $parts[1]; $rest = $parts[2]
    if ($Servers -contains $server) { return $Token }
    $match = @($Servers | Where-Object { $_ -like "$server*" }) | Select-Object -First 1
    if ($match) {
        [void]$Warnings.Add("$Context : tool '$Token' - namespace corrigido para 'mcp__${match}__$rest'")
        return "mcp__${match}__$rest"
    }
    [void]$Warnings.Add("$Context : tool '$Token' - servidor '$server' nao existe em .mcp.json - descartada")
    return $null
}

# parser YAML minimo (chave: valor / [lista] / lista indentada / mapa de UM nivel achatado).
function Read-SimpleYaml {
    param([Parameter(Mandatory = $true)][string]$Path)
    $data = @{}; $currentKey = $null; $nestedKey = $null
    foreach ($line in (Get-Content -Path $Path -Encoding UTF8)) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^(\w[\w-]*):\s*(.*)$') {
            $key = $Matches[1]; $val = ($Matches[2] -replace '\s+#.*$', '').TrimEnd()
            if ($val -eq '' -or $val -eq '[]') {
                $data[$key] = New-Object System.Collections.ArrayList; $currentKey = $key; $nestedKey = $key
            }
            elseif ($val -match '^\[(.*)\]$') {
                $list = New-Object System.Collections.ArrayList
                if ($Matches[1].Trim() -ne '') {
                    foreach ($it in ($Matches[1] -split ',')) { $t = $it.Trim().Trim('"').Trim("'"); if ($t) { [void]$list.Add($t) } }
                }
                $data[$key] = $list; $currentKey = $null; $nestedKey = $null
            }
            else { $data[$key] = $val.Trim(); $currentKey = $null; $nestedKey = $null }
            continue
        }
        if ($line -match '^\s+-\s*(.+)$') {
            $item = ($Matches[1] -replace '\s+#.*$', '').Trim().Trim('"').Trim("'")
            if ($currentKey -and $data[$currentKey] -is [System.Collections.ArrayList]) { [void]$data[$currentKey].Add($item) }
            $nestedKey = $null; continue
        }
        if ($nestedKey -and $line -match '^\s+(\w[\w-]*):\s*(.*)$') {
            $subKey = $Matches[1]; $subVal = ($Matches[2] -replace '\s+#.*$', '').TrimEnd().Trim('"').Trim("'")
            if (-not $data.ContainsKey($subKey) -or ($data[$subKey] -is [System.Collections.ArrayList] -and $data[$subKey].Count -eq 0)) { $data[$subKey] = $subVal }
            continue
        }
    }
    if ($nestedKey -and $data[$nestedKey] -is [System.Collections.ArrayList] -and $data[$nestedKey].Count -eq 0) { $data.Remove($nestedKey) | Out-Null }
    return $data
}

function Get-ListValue {
    param($Data, [string]$Key)
    if ($Data.ContainsKey($Key) -and $Data[$Key] -is [System.Collections.ArrayList]) { return @($Data[$Key]) }
    return @()
}

function Get-ScalarValue {
    param($Data, [string]$Key, [string]$Default = '')
    if ($Data.ContainsKey($Key) -and -not ($Data[$Key] -is [System.Collections.ArrayList])) { return [string]$Data[$Key] }
    return $Default
}

# squad.yaml: camada por id (override) + quem e o Gateway (gateway: id | gateway: true | squad.owner).
function Read-SquadYamlInfo {
    param([Parameter(Mandatory = $true)][string]$Path)
    $map = @{}; $curId = $null; $topGateway = $null; $memberGateway = $null; $owner = $null; $inSquad = $false
    foreach ($line in (Get-Content -Path $Path -Encoding UTF8)) {
        if ($line -match '^squad:\s*$') { $inSquad = $true; continue }
        if ($inSquad) {
            if ($line -match '^\S') { $inSquad = $false }
            elseif ($line -match '^\s+owner:\s*([^\s#]+)') { $owner = $Matches[1].Trim() }
        }
        if ($line -match '^gateway:\s*([^\s#]+)') { $topGateway = $Matches[1].Trim(); continue }
        if ($line -match '^\s*-\s*id:\s*([^\s#]+)') { $curId = $Matches[1].Trim(); continue }
        if ($curId) {
            if ($line -match '^\s*(?:camada|layer):\s*([^\s#]+)') { $map[$curId] = $Matches[1].Trim().ToUpper() }
            elseif ($line -match '^\s*gateway:\s*true\s*$') { $memberGateway = $curId }
        }
    }
    $gw = if ($topGateway) { $topGateway } elseif ($memberGateway) { $memberGateway } elseif ($owner) { $owner } else { $null }
    return [pscustomobject]@{ Camadas = $map; GatewayId = $gw }
}

# ---- PERSONA SEM FANTASIA. Uma regra no nucleo, vale para todo squad. ----
# Sai a secao inteira (do titulo ate o proximo titulo) cujo titulo comeca por: Voz, Como pensa,
# Alma, Afeto, owner_soul, Tracos, Personalidade, Tom de voz. Fica o Faz, o Nao faz, o
# conhecimento, o checklist, as tools e o aceite. Evidencia: A/B tests/token-budget/dados/ab-especialista*.jsonl.
function Test-FantasyHeading {
    param([string]$Heading)
    $n = $Heading.Normalize([System.Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    $n = $n.ToLowerInvariant().Trim()
    return [bool]($n -match '^(voz|como pensa|alma|afeto|owner[_ -]?soul|tracos|personalidade|tom de voz)(\s|$|:|\()')
}

function Remove-FantasySections {
    param([string]$Text)
    $out = New-Object System.Collections.ArrayList
    $skip = $false
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^#{1,6}\s+(.*)$') { $skip = Test-FantasyHeading $Matches[1] }
        if (-not $skip) { [void]$out.Add($line) }
    }
    return ((($out -join "`n") -replace "(\n){3,}", "`n`n").Trim())
}

# hash da FONTE (persona .md + .yaml + squad.yaml), 16 hex. frescor.py compara com o do bundle.
function Get-SourceHash {
    param([string[]]$Paths)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $all = New-Object System.Collections.Generic.List[byte]
    foreach ($p in $Paths) {
        if ($p -and (Test-Path -LiteralPath $p)) { $all.AddRange([System.IO.File]::ReadAllBytes($p)) }
    }
    $h = $sha.ComputeHash($all.ToArray())
    return (($h | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 16)
}
