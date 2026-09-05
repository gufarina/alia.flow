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
| **Codex** | Parcial | Le o `AGENTS.md` nativo e assume a persona; entende o protocolo de 5 passos como prosa. Desde a v1.65.0 tem tambem: a palavra de acordar `$alia` (skill em `.agents/skills/alia/SKILL.md`, o caminho de skill que o Codex le no repo) e o passo DELEGA portavel escrito (`skills/delegate/SKILL.md`), que trocam o travamento por **context-load**. | O Codex nao tem sub-agente nativo nem hook de usuario - a delegacao ali e SEMPRE context-load (a Alia veste o papel no proprio turno), onde escopo de tools e tier sao contrato lido, sem enforcement do host. Comando customizado do Codex so existe em `~/.codex/prompts/` (a home do usuario), fora do repo: o Alia Flow NAO escreve la sozinho. Execucao de PowerShell depende da configuracao do agente. |
| **OpenCode** | Parcial | Le o `AGENTS.md` nativo (`opencode.json` declara isso explicitamente), assume a persona, entende o protocolo como prosa. Desde a v1.65.0 tem tambem: `/alia` (`.opencode/commands/alia.md`) e **delegacao por sub-agente NATIVO** - `scripts/squad-bridge.ps1 -Mode opencode` gera `.opencode/agent/{client}-{id}.md` com o frontmatter que o OpenCode le (`description`, `mode: subagent`, `permission` traduzido da allow-list da persona), invocavel por `@{client}-{id}`. Isso promove o OpenCode de context-load para **spawn**. | Nada disso foi exercitado AO VIVO ainda - ver "O que e disco e o que e ao vivo". Hooks de ciclo de vida existem no OpenCode como plugins JS (`.opencode/plugins/`), mas o Alia Flow ainda nao publica um: o readout de host nao chega sozinho ali, a Alia roda `scripts/detect-harness.ps1` quando acorda. |
| **Outros agentes que leem AGENTS.md** | Basico | Se o agente le arquivos de prosa aberta (`.md`) no boot, ele consegue assumir a persona da Alia e seguir o protocolo como texto - o arquivo nao exige nenhuma extensao proprietaria pra ser lido. | Tudo que depende de o agente saber rodar comando (`.ps1`), gerenciar sub-agentes com contexto isolado, ou observar hooks de lifecycle nao tem garantia nenhuma - depende inteiramente das capacidades desse agente especifico, nao testadas pelo Alia Flow. |

## A Alia descobre sozinha onde esta (v1.65.0)

Antes de trabalhar, a Alia roda `scripts/detect-harness.ps1`. Ele responde seis campos - `harness`,
`spawn`, `hooks`, `skills_dir`, `delegation_mode` e `signal` (a evidencia que decidiu) - e o passo
DELEGA obedece o `delegation_mode`. Sinal forte primeiro: `CLAUDECODE=1` para Claude Code,
`CODEX_SANDBOX*` para Codex; depois marcador de pasta; nada reconhecido cai em `context-load`, o
modo que funciona em qualquer host. Ele nunca falha (exit 0 sempre): deteccao errada nao pode
travar trabalho.

Ressalva medida e assumida: como toda instalacao passou a ter `.claude/`, `.opencode/` e `.agents/`
ao mesmo tempo, marcador de pasta dentro do repo deixou de distinguir host. Quando os marcadores
sao ambiguos, o script diz `unknown` e cai em `context-load` em vez de chutar. O OpenCode nao
publica variavel de ambiente propria em doc oficial - por isso ele so e detectado por marcador
unico. Quem quiser cravar: a Alia aceita ser corrigida na conversa.

## Palavra de acordar, por host

| Host | Como chamar a Alia | O que ela le |
|---|---|---|
| Claude Code | `alia...` ou `/alia` | `.claude/skills/alia/SKILL.md` (a skill vence o command de mesmo nome; o command continua existindo) |
| OpenCode | `alia...` ou `/alia` | `.opencode/commands/alia.md` (e tambem `.agents/skills/alia/` por compatibilidade) |
| Codex | `alia...` ou `$alia` | `.agents/skills/alia/SKILL.md` |

Os tres textos saem de UMA fonte, `skills/alia/ALIA.md`, e as copias sao geradas por
`scripts/sync-harness-adapters.ps1`. O smoke reprova se o corpo das tres divergir (hash SHA256) -
tres textos com o mesmo nome seria a Alia se comportando diferente por host sem ninguem perceber.

## O que e disco e o que e ao vivo (honestidade)

| Host | Adapter em disco | Rodado ao vivo |
|---|---|---|
| Claude Code | Sim | **Sim** - e o host de referencia, validado ponta a ponta |
| OpenCode | Sim (`opencode.json`, `/alia`, 6 Specialists em `.opencode/agent/`) | **Nao** - tentado em 05/09/2026 e o proprio OpenCode quebrou antes de ler qualquer arquivo nosso (erro interno de banco: `no such column: replacement_seq`). Log literal em `docs/provas/harness-opencode-2026-09-05.txt` |
| Codex | Sim (`$alia` em `.agents/skills/`, `skills/delegate`) | **Nao** - tentado em 05/09/2026; o Codex subiu apontando para a pasta certa e morreu por falta de modelo (provider local do usuario fora do ar). Log literal em `docs/provas/harness-codex-2026-09-05.txt` |

Nenhuma das duas falhas foi causada pelo Alia Flow, e nenhuma foi consertada: consertar exigiria
mexer na configuracao do usuario (`~/.config/opencode`, `~/.codex/config.toml`), o que nao se faz
sem ordem. Ate um desses rodar de verdade, "funciona no OpenCode/Codex" continua sendo promessa
nao verificada - e por isso nao vira claim publico.

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
