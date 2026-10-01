# targets/context-load.ps1 - host SEM sub-agente (ex: Codex): briefing portavel, sem frontmatter.
# Movido do bridge antigo (OPP-42) sem decisao nova do CEO: mantido como estava.
return @{
    Name   = 'context-load'
    Render = {
        param($a, $ctx)
        $s = @("# CONTEXT-LOAD BUNDLE - $($a.Name)", '# Modo: context-load (OPP-42) - para host sem sub-agente nativo',
            "# Gerado de: clients\$($a.Client)\squad\agents\$($a.Id).{md,yaml}", '',
            '## Identidade', '', "Specialist: $($a.Role) ($($a.Client)/$($a.Id))", "Camada: $($a.Camada)", '',
            '## Escopo de ferramentas declarado', '', ($a.Tools -join ', '), '',
            'Vestir este chapeu NAO amplia acesso alem desta lista.', '',
            '## Persona (vista este chapeu)', '', $a.Persona, '', $a.OperatingNoTask, '',
            '## Regra de folha (context-load)', '',
            'Nao invoque outro Specialist dentro deste contexto. Produza a entrega com o Artifact esperado,',
            'DESCARREGUE este bloco e retome a coordenacao - o Quality Gate roda depois, fora do chapeu.', '',
            "<!-- source_hash: $($a.SourceHash) -->")
        return @(@{ path = (Join-Path $ctx.Out['context-load'] "$($a.Name).context-load.md"); content = (($s -join "`n").TrimEnd() + "`n") })
    }
}
