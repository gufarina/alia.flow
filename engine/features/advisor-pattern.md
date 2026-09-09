# Advisor Pattern - cerebro forte aconselha, cerebro rapido executa

> Feature do motor. Padrao executor + conselheiro: um agente rodando em modelo barato/rapido
> (executor) pode CONSULTAR o tier forte (advisor) no meio da execucao para receber um plano ou
> correcao de rumo - sem trocar de modelo, sem escalar, sem parar a Task. Origem: advisor tool da
> Anthropic (beta `advisor-tool-2026-03-01`). UTF-8 sem BOM.

---

## O problema que resolve

O Alia Flow ja casa modelo ao papel (model-matrix.yaml): Opus julga, Sonnet executa, Haiku empacota.
O furo era o MEIO da execucao: um Specialist em `standard` que encontra uma decisao dificil tinha so
dois caminhos - se virar sozinho (risco de rumo errado) ou escalar ao Owner (para a Task e sobe a
cadeia). O Advisor Pattern abre o terceiro caminho: **pedir conselho ao tier forte e seguir**.

Resultado medido pela Anthropic no padrao original: qualidade proxima do modelo forte sozinho,
pagando preco do modelo barato na maior parte dos tokens. Em codigo, Sonnet em effort medio +
Opus advisor entrega inteligencia comparavel a Sonnet em effort padrao, a custo MENOR.

## Conselho nao e escalacao

| | Conselho (advisor) | Escalacao (escalate) |
|---|---|---|
| Quando | Decisao de rumo, plano, incerteza de abordagem | Bloqueio real, outro dominio, 3 abordagens falharam |
| Quem responde | Tier `strong` (le a conversa inteira, devolve plano curto) | Squad Owner / Alia (re-roteia ou decide) |
| A Task para? | NAO - o executor recebe o rumo e segue | SIM - a Task volta ao coordenador |
| Custo | 400-700 tokens de conselho | Handoff completo + re-roteamento |

O advisor NUNCA executa. Ele le tudo, devolve rumo, e some. Quem escreve, edita e entrega continua
sendo o executor. A fronteira coordenador-nao-executa permanece intacta.

## As duas formas no Alia Flow

### Forma A - nativa no harness (Claude Code / sub-agentes)

O coordenador (Alia ou Squad Owner, tier `strong`) E o advisor dos seus executores. Ao delegar
(passo DELEGA), o briefing do sub-agente declara o direito de conselho:

> "Voce roda em modelo rapido. Em ate N pontos da Task voce pode DEVOLVER uma pergunta de rumo
> curta em vez de decidir sozinho. Use nos dois checkpoints: (1) depois de se orientar e ANTES de
> trabalho substantivo (escrever, editar, cravar interpretacao); (2) depois que escrita e testes
> estao na mesa, ANTES de fechar. Orientar-se nao e trabalho substantivo."

O coordenador responde com conselho curto (plano, correcao de rumo - nunca a execucao) e devolve a
bola. Isso roda hoje, sem API nova, via SendMessage/continuacao do sub-agente.

### Forma B - advisor tool da API (pipelines headless / scripts)

Quando um fluxo roda direto na API (scripts, batch, loops agendados), usar a ferramenta nativa:

```json
{
  "model": "claude-sonnet-4-6",
  "tools": [{ "type": "advisor_20260301", "name": "advisor", "model": "claude-opus-4-8" }]
}
```

Header beta: `anthropic-beta: advisor-tool-2026-03-01`. O executor chama `advisor()` sem
parametros; a API encaminha a conversa inteira ao modelo conselheiro e injeta o conselho de volta.

## Regras duras (doutrina)

1. **Teto de consultas: 2-3 por Task.** O ideal medido e uma consulta cedo (apos orientacao) e uma
   no fim (apos testes). Mais que isso e sintoma de Task mal dimensionada - quebrar ou re-rotear.
2. **Conselho e curto.** 400-700 tokens de texto. Advisor que despeja transcript viola o handoff
   compactado (tools.md).
3. **Advisor ve tudo, executa nada.** A conversa inteira do executor vai ao conselheiro; a resposta
   e rumo, nunca artefato.
4. **Timing importa.** Consulta ANTES de se orientar e conselho cego (a Anthropic mediu queda de
   3-4 pontos percentuais quando o conselho vem cedo demais). Primeiro orientar, depois perguntar.
5. **Cache a partir da 3a consulta.** Na Forma B, habilitar `caching: {type: ephemeral, ttl: 5m}`
   so em loops longos - abaixo de 3 consultas o cache custa mais do que economiza.
6. **Advisor nao substitui o Gate.** O Quality Gate (CONFERE) continua obrigatorio e independente.
   Conselho melhora o caminho; o Gate julga o resultado.

## Como casa com o protocolo de 5 passos

- **DELEGA**: o briefing do executor declara o direito de conselho e o teto (regras acima).
- **MONITORA**: o checkpoint de conselho E monitoramento ativo - o coordenador corrige rumo no meio,
  em vez de descobrir o desvio so no Gate. Menos retrabalho, menos Fail no CONFERE.
- **Escalacao continua existindo**: conselho e para rumo; bloqueio real segue a regra das 3
  abordagens + escalate. Um nao substitui o outro.

## Economia (por que o Operator aprova)

- A maior parte dos tokens sai no preco do executor (standard/fast), nao do strong.
- O conselho reduz total de chamadas de ferramenta e comprimento da conversa - o ganho vem de
  errar menos rumo, nao de escrever mais rapido.
- Elevacao permanente de tier (ex.: QA -> strong) vira ultimo recurso: antes de pagar Opus o tempo
  todo, dar ao papel o direito de CONSULTAR Opus 2-3 vezes.

## Segue
[Matriz de modelos](../agents/model-matrix.yaml) - [Orquestracao](../orchestration.md) -
[Tools e frugalidade](../tools.md)
