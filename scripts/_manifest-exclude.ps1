# Alia Flow - regra de exclusao COMPARTILHADA do manifesto de integridade (TASK-567).
# make-manifest.ps1 (gera) e verify-manifest.ps1 (confere) chamam a MESMA funcao: se so um lado
# excluir um caminho, o outro lado acusa divergencia (EXTRA no verify, ou o arquivo some do
# manifesto no make) para o mesmo caso. Contrato unico, dot-sourced pelos dois scripts.
# Exclui:
#   - o proprio MANIFEST.sha256 (arquivo gerado, nao se hasheia a si mesmo);
#   - qualquer coisa dentro de .git;
#   - qualquer caminho sob studio/ na RAIZ (dado de operador/regeneravel em tempo de execucao -
#     NUNCA studio.example/ nem scripts/_studio.ps1 - engine/governance/public-surface.md,
#     mandato do CEO 01/08/2026). O empacotador ja nao copia studio/; esta regra existe para
#     quando make-manifest/verify-manifest rodam direto contra uma pasta que AINDA tem studio/
#     (ex.: a oficina, ou um repo publicado por engano com o script antigo).
# UTF-8 sem BOM.

function Test-ManifestExcluded {
  param([Parameter(Mandatory)][string]$RelPath)
  if ($RelPath -eq "MANIFEST.sha256") { return $true }
  if ($RelPath -match '(^|[\\/])\.git([\\/]|$)') { return $true }
  if ($RelPath -match '^studio[\\/]') { return $true }
  return $false
}
