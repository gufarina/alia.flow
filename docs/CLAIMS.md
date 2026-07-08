# Alia Flow - Registro de Claims Publicos

> A fonte unica dos FATOS que podem aparecer em peca publica (LP, site, social, deck, README
> publico). Regra (engine/governance/client-truth.md, LEI 2): peca publica so afirma o que esta
> aqui, com a fonte anexada. Numero NUNCA se fabrica somando fontes distintas. Feature so entra
> com status LANCADO. Alimentado a cada decisao do CEO ou release. Sem acentos, sem emojis.

Ultima revisao: 2026-07-07 (auditoria growth TASK-064 + PRD v1.6 + BRAND).

## Identidade e taglines (vigentes)

| Claim | Status | Fonte |
|---|---|---|
| Tagline-mae: "Voce lidera. Ela opera." | VIGENTE (travada pelo CEO 02/jul) | PRD.md L8, L229 |
| Identidade: "o braco direito que voce sempre quis" | VIGENTE | PRD.md L9 |
| Assinatura/CTA: "Delegue. Nao opere." | VIGENTE | PRD.md L230, persona.md L240 |
| Selo de prova: "NADA CHEGA SEM CONFERIR" | VIGENTE | PRD.md L231 |
| Apoio: "O gargalo deixa de ser voce" | APOIO (nao e headline-mae) | BRAND.md L116-117 |

## VETOS (proibido ressuscitar)

| Veto | Decisao | Fonte |
|---|---|---|
| "Sua COO de IA" e qualquer cargo corporativo em ingles | DERRUBADO pelo CEO 02/jul | PRD.md L234 |
| Lema "A forca da IA, sem o manual" | APOSENTADO | PRD.md nota de marca |
| "Loop" e vocabulario de bastidor | nunca em peca publica | persona.md L105-111, PRD.md L154 |
| Metafora restaurante/chef/brigada/cozinha | NUNCA EXISTIU nas fontes (invencao de 07/jul, reprovada) | auditoria growth TASK-064 |
| Headline "Voce contrata um funcionario. Ganha uma empresa." | invencao de 07/jul, reprovada | auditoria growth TASK-064 |

## Guard do smoke - termos PROIBIDOS no motor (engine/)

> O smoke le esta lista e REPROVA se qualquer regex abaixo aparecer em engine/ (persona,
> orquestracao, agentes). Transforma "confie que o veto foi cumprido" em "o teste prova".
> Formato: uma linha por termo, comecando com `GUARD:` seguido do regex (case-sensitive).
> So entram aqui vetos que NUNCA devem viver no motor - jargao de bastidor de peca publica
> (ex: "Loop") NAO entra, porque no motor o termo e legitimo.

GUARD: \bCOO\b
GUARD: sua COO de IA
GUARD: A forca da IA, sem o manual

## Numeros publicos

| Numero | Valor | Fonte |
|---|---|---|
| Verificacoes deterministicas do produto | **99** ("na versao atual"; o exato sai no fim do smoke) | README.md L95 |
| Prova de ablacao (memoria) | **0/5 sem cerebro vs 5/5 com; ganho 5, limiar 3; scorer Python** | PRD.md L796-801 |
| Instalacao | **1 linha** de PowerShell, sem git/Python; abre pagina de boas-vindas | install.ps1 L5, README |
| Comando real | `iwr -useb https://raw.githubusercontent.com/gufarina/alia.flow/main/scripts/install.ps1 \| iex` | install.ps1 L5 |
| Licenca | MIT | LICENSE, README |
| Protocolo | 5 passos (IDENTIFICA REGISTRA DELEGA MONITORA FECHA) | PRD.md L351 |

PROIBIDO: "144 verificacoes" (soma fabricada de 99 do produto + 45 da operacao interna - fontes
distintas, numero interno sem fonte publica). Reprovado em 07/jul.

## Features anunciaveis (status)

| Feature | Status publico | Pode anunciar? |
|---|---|---|
| Orquestracao com conferencia (Quality Gate) | LANCADO | SIM |
| Memoria/segundo cerebro com prova de ablacao | LANCADO | SIM |
| Squads de especialistas + Expert Minds | LANCADO | SIM |
| Smoke test deterministico (99) | LANCADO | SIM |
| Instalador 1 linha | LANCADO (beta) | SIM |
| "O Conselheiro" / Advisor Pattern | INTERNO (engine 1.18.0; publico so no roadmap 7.2 DESENHADO) | NAO - ate release publico |
| Pre-requisito: mora dentro de coding agent (Claude Code/Codex/OpenCode) | FATO (sempre declarar junto da instalacao) | SIM (obrigatorio declarar) |
