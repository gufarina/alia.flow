---
name: file-organization
description: Senso de design organizacional do Alia Flow. Toda pasta tem um tema e um indice; nada de arquivo solto; revisar na hora. Casa arrumada e escalabilidade. Use sempre que for criar, mover ou nomear arquivos no seu estudio ou no engine do Alia Flow, ou quando notar arquivos soltos acumulando.
trigger: criar/mover/nomear arquivo, organizar pasta, indice, casa arrumada, arquivo solto
provenance: nucleo
---

# File Organization - Senso de Design (lei do bibliotecario do Alia Flow)

> O estudio nasce organizado. Casa arrumada e escalabilidade de Clients, Projects e
> Squads. Acumular arquivo solto e falha minha, nao do operador. Esta skill existe para que a
> bagunca nunca comece.

## Principio

Toda pasta tem **um tema** e **um indice**. A estrutura e revisada **sempre** - na hora em que o
problema aparece, nao quando o operador reclama.

## Regras

1. **Subpastas tematicas.** Agrupar por tema (engine, studio, skills, scripts, docs, clients...),
   nunca despejar tudo solto na raiz.
2. **Indice/README.** Toda pasta com 5+ arquivos ganha um `README.md` que e a porta de entrada -
   explica o tema da pasta e aponta para cada arquivo.
3. **Pensar antes de criar.** Antes de escrever um arquivo: "onde isso mora? ja existe pasta-tema?".
4. **Revisar na hora.** Ao notar 5+ arquivos soltos ou nomes confusos, organizar imediatamente,
   sem esperar pedido.
5. **Nomes claros.** O nome do arquivo diz o que ele e. Sem `final`, `novo`, `temp`, `v2`.
6. **Indice sempre atualizado.** Ao adicionar/remover/renomear um arquivo, atualizar o README da
   pasta no mesmo passo. Indice desatualizado = indice errado.

## Auto-check (antes de CADA novo arquivo)

> "Esse arquivo tem uma pasta-tema certa? Existe um indice? Vou deixar a casa mais organizada ou
> mais baguncada?" - se a resposta piora a casa, paro e organizo primeiro.

## Regras do Studio (invariantes)

- **Sem acentos e sem emojis** em qualquer arquivo (regra do operador).
- **UTF-8 sem BOM.** Nunca corromper texto (0xFFFD). No Windows, usar Edit/Write ou
  `[System.IO.File]::WriteAllText` em UTF-8 - nunca Set-Content sem encoding.
- **Linguagem ubiqua do Alia Flow.** Os termos sao Studio, Client, Project, Task, Artifact,
  Squad, Squad Owner, Specialist, Gate, Memory, Loop, RSI. Inventar sinonimo = anti-pattern.
- **Caminhos com espaco sempre entre aspas.**

## Layout canonico de uma instalacao Alia Flow (a arquitetura aprovada)

Toda instalacao - o produto (lab) e a instancia do operador - segue ESTE layout. A raiz tem pastas
tematicas + uma allowlist pequena de arquivos essenciais. Qualquer arquivo na raiz fora da allowlist
e VAZAMENTO; o smoke (raiz limpa) reprova.

### Pastas tematicas (na raiz)

- `engine/` - o motor (specs, agents, governance, features, workflows). Produto.
- `scripts/` - automacao (.ps1). Produto.
- `skills/` - skills. Produto.
- `docs/` - documentacao e guias do produto. Produto.
- `onboarding/` - a pagina de boas-vindas. Produto.
- `optional-mcps/` - catalogo curado de MCP. Produto.
- `clients/` - os Clients do operador (os dados). Operador. No produto, os dados vivem em
  `studio/` (+ `studio.example/` como demo CLEAN).
- `_inbox/` - entrada/staging de itens a triar. Operador.
- `.claude/` - config do Claude. Preserva ajuste local.
- `_retired/` - arquivado (nunca deletar; provenance). Pode existir dentro de qualquer pasta-tema.

### Arquivos permitidos na raiz (allowlist - SO estes)

- `README.md`, `PRIMEIROS-PASSOS.md`, `AGENTS.md`, `CHANGELOG.md`, `LICENSE`, `CREDITS.md` - docs convencionais (AGENTS.md = boot loader; PRIMEIROS-PASSOS.md = guia de quem recebe o pacote).
- `VERSION`, `alia.config.json` - versao + config que o motor le.
- `iniciar-alia.bat`, `atualizar-alia.bat` - os botoes que o operador clica.
- `CLAUDE.md` - boot do harness Claude Code quando a instancia roda nele (par do AGENTS.md).
- `mission-control.html` - o painel da operacao (gerado por scripts/mission-control.ps1 a partir do state.json; regeneravel, nunca editado na mao).
- `.gitignore`, `.gitattributes` - convencao git (dotfiles, nao policiados).
- `state.json`, `studio.yaml` - SO quando `studio_dir="."` (dados na raiz). Senao vivem em `studio/`.

Qualquer outro arquivo solto na raiz e bagunca - ele tem uma pasta-tema certa: script -> `scripts/`,
doc -> `docs/`, dado de cliente -> `clients/{id}/`, MCP -> `optional-mcps/`. Pensar antes de criar
(auto-check acima); o smoke reprova o vazamento.

## Aplica a

Engine (o motor), studio (os dados do operador), skills, scripts e docs - **toda** a estrutura
de arquivos do Alia Flow. E principio do produto, nao so desta operacao.
