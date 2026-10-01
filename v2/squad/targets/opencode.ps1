# targets/opencode.ps1 - saida OpenCode: .opencode\agent\<client>-<id>.md (description, mode: subagent,
# permission traduzida da allow-list). model so quando a persona declara provider/modelo de verdade.
return @{
    Name   = 'opencode'
    Render = {
        param($a, $ctx)
        $edit = if (($a.Tools -contains 'Edit') -or ($a.Tools -contains 'Write')) { 'allow' } else { 'deny' }
        $bash = if ($a.Tools -contains 'Bash') { 'allow' } else { 'deny' }
        $web = if (($a.Tools -contains 'WebFetch') -or ($a.Tools -contains 'WebSearch')) { 'allow' } else { 'deny' }
        $s = New-Object System.Collections.ArrayList
        foreach ($l in @('---', "description: $($a.Description)", 'mode: subagent')) { [void]$s.Add($l) }
        if ($a.DeclaredModel -match '^[\w.-]+/[\w.:-]+$') { [void]$s.Add("model: $($a.DeclaredModel)") }
        foreach ($l in @('permission:', "  edit: $edit", "  bash: $bash", "  webfetch: $web", '---', '', $a.Persona, '',
                '## Escopo de ferramentas declarado', '', ($a.Tools -join ', '), '', $a.Operating, '', "<!-- source_hash: $($a.SourceHash) -->")) { [void]$s.Add($l) }
        return @(@{ path = (Join-Path $ctx.Out['opencode'] "$($a.Name).md"); content = (($s -join "`n").TrimEnd() + "`n") })
    }
}
