# targets/pi.ps1 - saida Pi (0.99.0). O Pi nao tem pasta de agentes nem sub-agente nativo; o host que o
# comanda (app hospedeiro) passa: --append-system-prompt <conteudo do .system.md> e --tools <tools_arg do .json>.
# Gera o PAR em <PiOut>\<client>-<id>.{system.md,json}. Nunca toca o ~/.pi da pessoa.
# Nomes de ferramenta do Pi: read, grep, find, ls, bash, edit, write (executor Pi do host,
# lista de ferramentas; flag --tools confirmada).
# Sem equivalente no Pi (vao para "dropped"): Task (sem sub-agente), WebFetch, WebSearch, NotebookEdit, mcp__*
# (MCP no Pi e por `pi mcp`/registerMcpServer, nao por nome de ferramenta).
return @{
    Name   = 'pi'
    Render = {
        param($a, $ctx)
        $map = @{ 'Read' = @('read'); 'Grep' = @('grep'); 'Glob' = @('find', 'ls'); 'Edit' = @('edit'); 'Write' = @('write'); 'Bash' = @('bash') }
        $piTools = New-Object System.Collections.ArrayList
        $dropped = New-Object System.Collections.ArrayList
        foreach ($t in $a.Tools) {
            if ($map.ContainsKey($t)) { foreach ($p in $map[$t]) { if ($piTools -notcontains $p) { [void]$piTools.Add($p) } } }
            else { [void]$dropped.Add($t) }
        }
        $system = (@($a.Persona, '', $a.OperatingNoTask, '', "<!-- source_hash: $($a.SourceHash) -->") -join "`n").TrimEnd() + "`n"
        $meta = [ordered]@{
            name = $a.Name; client = $a.Client; source_hash = $a.SourceHash; model_hint = $a.TierModel
            tools = @($piTools); tools_arg = ($piTools -join ','); dropped = @($dropped)
            system_file = "$($a.Name).system.md"
        }
        $json = (($meta | ConvertTo-Json -Depth 4) -replace "`r`n", "`n").TrimEnd() + "`n"
        return @(
            @{ path = (Join-Path $ctx.Out['pi'] "$($a.Name).system.md"); content = $system },
            @{ path = (Join-Path $ctx.Out['pi'] "$($a.Name).json"); content = $json }
        )
    }
}
