# targets/claude.ps1 - saida Claude Code: .claude\agents\<client>-<id>.md (frontmatter + persona + operacional).
# Contrato: devolve @{ Name; Render = {param($a,$ctx)}; Clean = {param($ctx,$clientIds)} }. Sem estado.
return @{
    Name   = 'claude'
    Render = {
        param($a, $ctx)
        $s = @('---', "name: $($a.Name)", "description: $($a.Description)", "tools: $($a.Tools -join ', ')", "model: $($a.TierModel)", '---', '',
            $a.Persona, '', $a.Operating, '', "<!-- source_hash: $($a.SourceHash) -->")
        return @(@{ path = (Join-Path $ctx.Out['claude'] "$($a.Name).md"); content = (($s -join "`n").TrimEnd() + "`n") })
    }
    # o .brief.md por agente saiu do desenho (9 secoes em branco, sem leitor): apaga os velhos.
    Clean  = {
        param($ctx, $clientIds)
        $dir = $ctx.Out['claude']
        if (-not (Test-Path $dir)) { return }
        foreach ($c in $clientIds) {
            foreach ($f in (Get-ChildItem -Path $dir -Filter "$($c.ToLower())-*.brief.md" -File -ErrorAction SilentlyContinue)) {
                if ($ctx.DryRun) { Write-Host "[DRYRUN] removeria: $($f.FullName)" } else { Remove-Item -LiteralPath $f.FullName -Force; Write-Host "[REMOVIDO] $($f.Name)" }
            }
        }
    }
}
