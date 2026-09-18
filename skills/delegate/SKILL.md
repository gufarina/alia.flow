---
name: delegate
description: O passo DELEGA portavel - executa a delegacao no modo que o host suporta. Use sempre que for delegar uma Task a um Specialist, e OBRIGATORIAMENTE quando scripts/detect-harness.ps1 responder delegation_mode=context-load (Codex, host desconhecido, ou meio de sessao no Claude Code). Impede o fallback proibido de "executo eu mesma sem papel".
trigger: delegar, DELEGA, context-load, host sem sub-agente, Codex, OpenCode, "nao consigo spawnar"
provenance: OPP-42 (delegacao portavel), Delta 2
---

# DELEGA portavel - o mesmo contrato em qualquer coding agent

> Origem (OPP-42, linhas 6-9): o CEO testou a Alia no Codex. Ela seguiu o protocolo ate DELEGA e
> TRAVOU - tentou spawnar sub-agente tres vezes num host que nao tem essa ferramenta, ficou presa
> entre "a coordenadora NUNCA executa" (Principio I) e "nao da pra acionar o Specialist", e caiu no
> pior fallback: executar ela mesma, sem papel. Esta skill existe para que isso nao volte a
> acontecer.
>

## A LEI nao muda, o mecanismo sim

O Principio I proibe a coordenadora de "se virar" SEM a especialidade - output generico, sem o
Domain Pack nem o Expert Mind. Ele NAO exige um processo separado. Delegar = a entrega sair COM a
capacidade do Specialist. O modo e detalhe do host.

## Passo 0 - descubra o modo (nunca tente e trave)

```
scripts/detect-harness.ps1
```

Leia `delegation_mode`. No Claude Code o readout ja chega pelo hook de `SessionStart`. Host que nao
deixa rodar script, ou script que falhou: assuma `context-load` (funciona em qualquer lugar).

## Modo spawn (host com sub-agente nativo)

| Host | Onde o agente mora | Como acionar |
|---|---|---|
| Claude Code | `.claude/agents/{client}-{id}.md` | ferramenta de sub-agente (Agent/Task) |
| OpenCode | `.opencode/agent/{client}-{id}.md` | `@{client}-{id}` ou acionamento automatico |

O agente nao existe ainda? Gere da fonte unica (`clients/{client}/squad/`):

```
scripts/squad-bridge.ps1 -Client {client} -Mode spawn      # Claude Code
scripts/squad-bridge.ps1 -Client {client} -Mode opencode   # OpenCode
```

LIMITE CONHECIDO: agente recem-gerado so fica acionavel em SESSAO NOVA (o host le a lista de
sub-agentes na abertura). Precisa do Specialist AGORA, no meio da sessao? Use context-load abaixo -
nao e degradacao, e o mesmo contrato por outro mecanismo.

## Modo context-load (host sem sub-agente nativo, ou meio de sessao)

1. **Resolva o Specialist mais capaz.** Fonte deterministica: `clients/{client}/squad/squad.yaml`
   (o time, o Gateway, as camadas) + `agents/{id}.yaml` (dominio, gatilhos, tools, knowledge).
   Nenhum LLM decide isso no chute: case a lente da Task contra `domain` e `triggers`. Empate ou
   duvida sobe ao Gateway (Squad Owner), que re-roteia.
2. **Carregue o briefing portavel:** `.claude/agents/{client}-{id}.context-load.md`. Nao existe?
   Gere: `scripts/squad-bridge.ps1 -Client {client} -Mode context-load`. Esse arquivo ja traz
   identidade, camada, escopo de ferramentas em prosa, a persona integral e os caminhos de
   knowledge validados contra o disco.
3. **VISTA o papel** no proprio turno: produza a entrega COMO aquele Specialist, dentro do escopo
   de ferramentas declarado. Vestir o chapeu NAO amplia acesso.
4. **Devolva o Artifact** (arquivo, path ou URL) e um resumo objetivo.
5. **DESCARREGUE o bloco** e volte a coordenar. O isolamento aqui e limpar o contexto entre os
   chapeus, nao um processo separado.
6. **Registre o modo na Task.** No `state.json` do studio, a Task que rodou assim leva a nota
   `delegation_mode: context-load` (e o host, quando conhecido). Sem esse registro, a auditoria nao
   consegue distinguir delegacao portavel de violacao do Principio I - e as duas ficam parecidas
   depois do fato.
7. **Rode o Gate** (`engine/governance/quality-gate.md`) FORA do chapeu, como coordenadora.

## O fallback proibido

"Nao consegui acionar o Specialist, entao fiz eu mesma" nao existe mais. Se o host nao spawna, o
caminho e context-load. Se o briefing nao existe, gere. Se o Client nao tem squad, isso e uma
escalacao ao Operator, nao licenca para produzir output generico. Entrega sem a capacidade do
Specialist e **Fail no Gate**, em qualquer host.

## Honestidade sobre enforcement

No modo spawn, o host aplica a allow-list de tools e o modelo do frontmatter - enforcement real.
No modo context-load nao ha frontmatter que host nenhum leia: escopo e tier viram **contrato lido**
pela coordenadora. Mesma entrega, garantia diferente - e isso se declara, nao se esconde
(`engine/orchestration.md`, "Delegacao = isolamento de contexto", itens 3 e 4).
