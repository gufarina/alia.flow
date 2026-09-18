<#
  delegation-guard.ps1 - Hook de UserPromptSubmit. O ENFORCEMENT da lei de delegacao no
  PONTO DE DECISAO (OPP-74).

  Por que existe: a lei "a Alia delega dominio, nunca executa" morava so em prosa
  (persona.md, orchestration.md) carregada no boot. Em sessao longa ou pedido grande, o
  contexto dilui e a Alia volta a executar com a propria mao (incidentes de 02/ago: num Client -
  ia mapear codigo na mao com grafo pronto; ja tinha acontecido antes). Mesmo padrao do
  veto COO: a regra so parou de reincidir quando virou guard de maquina (smoke), nao prosa.
  Este hook aplica o mesmo principio ao DELEGA: a lei e re-injetada a CADA pedido do
  operador, no exato momento em que a Alia decide como atender.

  Mecanica: UserPromptSubmit roda so no loop principal (nunca nos especialistas
  delegados), entao o lembrete chega a coordenadora sem poluir o contexto de quem executa.
  O stdout e adicionado ao contexto pelo Claude Code. Curto de proposito: dispara em todo
  prompt, nao pode inchar o contexto. NUNCA bloqueia: exit 0 sempre, try/catch.
#>
try {
  Write-Host "[ALIA - lei de operacao, vale pra ESTE pedido] (1) DELEGA: dominio e do especialista do squad - a Alia coordena, registra a Task e aciona a mao mais capaz; nunca executa dominio com a propria mao (engine/orchestration.md, passo DELEGA). (2) FONTE ANTES DE VARRER: se o cliente tem graphify-out/, mapas ou docs curados, leia-os antes de qualquer varredura de codigo. Excecao unica: ordem explicita do operador para a Alia executar ela mesma."
  exit 0
} catch {
  exit 0
}
