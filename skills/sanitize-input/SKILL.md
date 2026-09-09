---
name: sanitize-input
description: Frugal Skill deterministica (script regex, sem LLM) que neutraliza texto perigoso na BORDA, antes de o payload virar comando. Subset BARATO - tag <x> vira (x), @mention e bot-trigger ficam inertes, URI nao-HTTPS vira (redacted), control chars/ANSI removidos, limite de tamanho. Roda SOB DEMANDA quando entra payload de dominio (briefing, email, texto de cliente, retorno da escada de pesquisa) - NUNCA no boot. E a borda que desarma instrucao escondida sem voce revisar cada paragrafo.
trigger: /sanitize-input
provenance: agent-authored
---

# Sanitize Input

Borda de entrada que desarma texto perigoso antes de ele virar comando. Confere e
neutraliza, sem chamar modelo, o payload de dominio que o operador cola ou que volta
da escada de pesquisa. E defesa de ENTRADA - complementa a LEI ASCII do smoke, que e
LEI de SAIDA.

Mecanismo: `skills/sanitize-input/sanitize-input.ps1`.

## Por que existe (e por que SOB DEMANDA)

Nada sanitizava o que o operador cola (briefing, email, texto de cliente) ou o que vem
da web pela escada de pesquisa. O ASCII do smoke e LEI de SAIDA, nao defesa de ENTRADA.
A LEI de pesquisa segura (OPP-23) ja da trava parcial no vetor web; esta skill cobre o
payload colado.

Roda SOB DEMANDA, no momento em que entra um payload de dominio - NAO no boot/AGENTS.md.
Adicionar isso ao caminho sempre-carregado violaria MAP.md / biblioteca-sob-demanda
(nao por peso no boot por uma defesa que so importa quando ha payload).

## O que neutraliza (5 passos, regex, custo-zero)

| # | Vetor | Acao |
|---|-------|------|
| 1 | Payload-bomba (tamanho) | trunca em `-MaxChars` (default 20000) e marca o corte |
| 2 | Control chars / ANSI | remove ESC[...m e C0/C1 invisiveis (tab/nl/cr preservados) |
| 3 | Tag `<x>` | vira `(x)` - inerta HTML/pseudo-tag de injecao |
| 4 | `@mention` / bot-trigger | `@nome` vira `(at:nome)`; `/comando` no inicio de linha vira `(cmd:comando)` |
| 5 | URI nao-HTTPS | `http://`, `ftp://`, `file://`, `data:`, `javascript:` viram `(redacted)` |

**CORTADO** (veredito do cetico): a normalizacao de homoglifo Unicode - subset pesado;
fica de fora deste lote.

## Como usar

Entrada: `-Path` (arquivo do payload) OU `-Text` (string) OU stdin (pipe).
Opcional: `-OutPath` (grava o texto neutralizado) e `-MaxChars` (limite, default 20000).

Saida: o texto neutralizado (stdout, util para pipe), um relatorio `[sanitize-input]`
com a contagem por categoria, e exit 0 sempre - e sanitizador, nao gate: nunca bloqueia,
so desarma.

## Invariante

So executa o deterministico (regex de subset). Nao julga o MERITO do conteudo (isso e o
Gate/Specialist). Custo zero de token de modelo. Nao normaliza homoglifo (cortado). E
borda de ENTRADA, sob demanda - nunca peso no boot.
