# Compatibilidade por coding agent

O Alia Flow e vendor-neutral por construcao: a identidade e o protocolo
vivem em `AGENTS.md`, um arquivo de prosa aberta que qualquer CLI de agente
pode ler (nao ha plugin nem config travada a um unico fornecedor). Mas
vendor-neutral na construcao nao quer dizer identico na experiencia nem no
MECANISMO de boot. No Claude Code, a porta de entrada e um `CLAUDE.md` que
importa (`@AGENTS.md`) esse arquivo - a documentacao oficial confirma que o
Claude Code le `CLAUDE.md`, nao `AGENTS.md` direto; existe tambem o comando
`/alia` como rede de seguranca, caso o boot automatico nao pegue. Nos
demais agentes (Codex, OpenCode, Aider, outros que leem `AGENTS.md`), o
boot continua sendo o proprio `AGENTS.md`, lido direto - sem `CLAUDE.md` e
sem `/alia`. Esta pagina existe pra dizer a verdade sobre essa variacao -
sem prometer paridade que ainda nao existe.

## Tabela de compatibilidade

| Coding agent | Status | O que funciona | O que degrada |
|---|---|---|---|
| **Claude Code** | Pleno | Boot via `CLAUDE.md` (que importa `AGENTS.md`) + comando `/alia` como rede de seguranca, os 5 passos de orquestracao, delegacao a Specialists, Quality Gate, memoria nativa, scripts PowerShell chamados pelo agente, smoke/doctor. E o unico onde o fluxo completo esta validado ponta a ponta. | Nada declarado como faltante especificamente aqui - e a referencia. |
| **Codex** | Parcial | Le o `AGENTS.md` e assume a persona da Alia; entende o protocolo de 5 passos como prosa. | Delegacao portavel (isolamento de contexto entre coordenador e Specialist) ainda nao esta validada neste agente - esta no roadmap (OPP-42), nao garantido hoje. Execucao de scripts PowerShell pode exigir confirmacao manual dependendo da configuracao do agente. |
| **OpenCode** | Parcial | Mesma base: le `AGENTS.md`, assume a persona, entende o protocolo como prosa. | Mesma ressalva do Codex - delegacao portavel nao validada; comportamento de sub-agentes/isolamento de contexto pode diferir do testado no Claude Code. |
| **Outros agentes que leem AGENTS.md** | Basico | Se o agente le arquivos de prosa aberta (`.md`) no boot, ele consegue assumir a persona da Alia e seguir o protocolo como texto - o arquivo nao exige nenhuma extensao proprietaria pra ser lido. | Tudo que depende de o agente saber rodar comando (`.ps1`), gerenciar sub-agentes com contexto isolado, ou observar hooks de lifecycle nao tem garantia nenhuma - depende inteiramente das capacidades desse agente especifico, nao testadas pelo Alia Flow. |

Nota: "Parcial" e "Basico" aqui descrevem o que o Alia Flow HOJE tem
evidencia de rodar - nao um teto tecnico do agente. Um agente pode evoluir e
subir de categoria; a tabela reflete o estado testado, nao uma opiniao sobre
o produto de terceiros.

## O que voce perde sem X, e como compensar

- **Sem execucao de script (o agente nao roda `.ps1` sozinho ou pede
  confirmacao a cada chamada):** o smoke test e o doctor nao rodam
  automaticamente durante a sessao - abra um terminal e rode
  `scripts/smoke-test.ps1` e `scripts/doctor.ps1` a mao, fora do agente,
  sempre que quiser validar o estado do motor.

- **Sem hooks de lifecycle (o agente nao dispara automacao em boot/eventos):**
  a governanca (loops, checagem de tasks paradas, gates agendados) nao
  dispara sozinha - ela roda quando a Alia e explicitamente chamada dentro da
  sessao. Mitigacao: peca a Alia pra rodar a varredura (`stale-tasks.ps1`,
  Quality Gate) no inicio de cada sessao de trabalho, como um passo manual.

- **Sem isolamento de contexto entre coordenador e Specialist (sub-agentes
  reais com contexto proprio):** a delegacao vira mais prosa-guiada do que
  mecanica - o mesmo agente/contexto representa varios papeis em sequencia,
  em vez de um sub-agente separado executando e devolvendo so o resumo.
  Mitigacao: siga o protocolo de 5 passos manualmente na conversa (IDENTIFICA
  -> REGISTRA -> DELEGA -> MONITORA -> FECHA), tratando cada papel como uma
  troca de chapeu explicita, e cobre o Artifact antes de considerar a task
  fechada.

- **Sem allow-list de tools aplicada (enforcement em runtime):** isso nao e
  perda exclusiva de outros agentes - nem no Claude Code o enforcement duro
  existe ainda (ver nota de honestidade do README). Em qualquer agente, a
  lista de ferramentas por persona e contrato lido, nao trava mecanica.
  Mitigacao: revisao humana do que cada Specialist tocou, via o Artifact e o
  registro em `state.json`.

- **Sem memoria nativa automatica (o agente nao mantem/le notas entre
  sessoes por conta propria):** o segundo cerebro do cliente nao carrega
  sozinho - a Alia precisa ser instruida a ler `squad/knowledge/` no inicio
  da sessao. Mitigacao: comece cada sessao nova pedindo explicitamente "carrega
  a memoria do cliente X antes de comecar".

## Nota de honestidade: contrato lido vs codigo executado

O Alia Flow separa duas coisas que e facil confundir:

- **Contrato lido** - prosa em arquivos abertos (`AGENTS.md`, `engine/*.md`)
  que o agente LE no boot e DEVE seguir por interpretacao, nao por trava
  fisica. Roteamento por capacidade, o protocolo de 5 passos e a allow-list
  de tools sao, hoje, contrato lido - valem porque o agente os entende e os
  segue, nao porque um mecanismo impede o desvio.
- **Codigo executado** - scripts que rodam de fato e produzem evidencia em
  disco (o smoke test, o doctor, `apply-safe-output`). Esses sao garantidos
  no sentido de que, se rodarem, o resultado e verificavel - nao dependem de
  o agente "entender" nada.

Essa distincao e a mesma que o README ja faz para o motor como um todo (ver
"Nota de honestidade para quem le o codigo"). Ela vale tambem entre agentes:
quanto menos o agente tiver equivalentes de execucao mecanica (scripts,
sub-agentes isolados, hooks), mais o funcionamento correto depende de ele
seguir bem o contrato lido - e isso varia de agente para agente, nao e uma
propriedade do Alia Flow.

## Em resumo

O pre-requisito e um coding agent (README) - Claude Code, Codex ou OpenCode
hoje; qualquer agente que leia `AGENTS.md` amanha. Mas o caminho mais
completo, testado e validado ponta a ponta e o **Claude Code**. Se voce esta
comecando agora e quer a experiencia inteira sem surpresa, comece por ele.
