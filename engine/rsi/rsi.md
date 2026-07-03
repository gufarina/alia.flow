# Alia - RSI (Recursive Self Improvement)

> O coracao do aprendizado do Alia Flow. A cada Artifact entregue, o sistema guarda o que aprendeu
> e melhora a si mesmo - sem um humano reescrevendo prompts a mao. Amanha e melhor que hoje, sempre.
> Politica estruturada ao lado: [rsi.yaml](rsi.yaml). Termos em [glossary.md](../glossary.md).

---

## A tese

O legado tratava memoria e melhoria como subprodutos: anotava o que deu errado, mas a correcao
dependia de alguem ler a anotacao e agir. O Alia Flow inverte: o aprendizado e um Loop fechado.
A Memory nao e um diario passivo - e o combustivel que dispara propostas de melhoria no proprio
framework. RSI e o Principio X da Constituicao virando mecanismo.

## O que o RSI melhora (e o que NUNCA toca)

| Alvo | Camada | RSI pode? |
|------|--------|-----------|
| Prompts de agente, instrucoes de Specialist | evoluivel | Sim - propoe versao melhor |
| Definicao de Gate (criterios, thresholds) | evoluivel | Sim - aperta ou afrouxa com evidencia |
| Domain Pack / Expert Mind (conhecimento de dominio) | evoluivel | Sim - enriquece a cada projeto |
| Rota/fluxo de uma Task recorrente | evoluivel | Sim - troca caro por barato |
| Cadencia de um Loop | evoluivel | Sim - acelera o util, aposenta o inutil |
| Constituicao, principios, fronteira Engine/Studio | **nucleo** | **Nunca** |
| Codigo do motor (orquestracao, governanca) | **nucleo** | **Nunca** |

Tres frentes concretas de ganho: **Qualidade** (o que falhou no Gate vira versao que passa),
**Custo** (caminho caro vira caminho barato - casa com a Frugalidade), **Expertise** (o Domain Pack
fica mais rico a cada entrega do dominio).

## O Loop RSI (assincrono, em 4 estagios)

```
1. COLETA   Loops gravam feedback estruturado na Memory (gate verdict, custo,
            drift de DDD, tentativas de fix, resultado de deep research).

2. DETECTA  O RSI le a Memory e procura padrao, nao incidente isolado:
            - mesma Task falha no mesmo Gate >= N vezes
            - mesmo caminho gasta acima do Budget de forma repetida
            - mesmo Domain Pack gera Concerns recorrentes
            - deep research trouxe pratica nova que muda o output

3. PROPOE   proposeImprovement(alvo, mudanca, evidencia)
            alvo = prompt | fluxo | Domain Pack | Gate | cadencia de Loop
            A proposta carrega a evidencia da Memory que a justifica.

4. APLICA   applyWithGuardrails(proposta)
            roda contra um caso de teste -> passa por um Gate proprio ->
            so entao substitui a versao antiga. Versao anterior fica versionada
            (rollback possivel). A proxima execucao da Task sai melhor e/ou barata.
```

A regra do estagio 2 e o que separa RSI de ruido: **padrao, nunca incidente**. Uma falha isolada
e um fato; tres falhas iguais sao um sinal. So sinal vira proposta. O detector vive em
[rsi.yaml](rsi.yaml) -> `triggers` (os thresholds que disparam cada tipo de proposta).

## De onde vem o combustivel (ligacao com os Loops)

O RSI nao gera dados - ele consome o que os Loops ja produzem. Cada Loop agendado ou dinamico
escreve seu resultado na Memory; o RSI le esse rastro.

| Loop | O que entrega ao RSI |
|------|----------------------|
| Quality Gate (no Artifact) | verdict + razao da reprova - materia-prima da melhoria de Qualidade |
| fix-on-fail | quantas abordagens foram precisas - sinal de prompt/fluxo fraco |
| ddd-drift-scan | desvio da linguagem ubiqua - sinal de Domain Pack desatualizado |
| debt-scan | Concerns que nunca fecham - candidatos a mudanca de Gate ou de rota |
| deep-research | pratica externa nova - enriquece Domain Pack / Expert Mind |
| rsi-friction | atrito real do operador (frustracao ao vivo) - aponta onde o workflow trava de verdade |

A fonte `rsi-friction` (skill `skills/rsi-friction/SKILL.md`) e a unica que vem de gente, nao de
metrica: capta a frustracao do operador em silencio, grava no `rsi-backlog` do Studio com
prioridade (severidade x recorrencia) e alimenta o trigger `operator-friction-pattern`. A
melhoria roda como `/loop` do Claude sobre esse backlog (Procedimento B da skill rsi-friction):
pega um item por vez, testa antes/depois e so mantem se reduziu atrito sem complicar a Alia.

Catalogo dos Loops: [governance/loops.md](../governance/loops.md). Quem receita por projeto: a Alia
via Loop Designer ([features/loop-designer.md](../features/loop-designer.md)). O loop que mais
alimenta a frente de Expertise e o
[deep-research-loop](../features/deep-research-loop.md).

## Guardrails (inegociavel)

A parte que se auto-modifica **nunca** toca o nucleo do Engine. Um sistema que se reescreve sem
freio pode "se melhorar" para um buraco - por isso o RSI vive dentro de cercas:

1. **Escopo fechado** - so a camada evoluivel da tabela acima. O nucleo e imutavel pelo RSI.
2. **Evidencia obrigatoria** - sem o padrao na Memory que a justifica, a proposta e rejeitada.
3. **Teste antes de aplicar** - toda proposta roda contra um caso e passa por um Gate proprio.
4. **Versionamento + rollback** - a versao anterior fica guardada; melhoria que piora a metrica
   e revertida.
5. **Aprovacao humana em mudanca de Gate** - mexer no que define qualidade exige o sinal do
   Operator. O sistema propoe; quem afrouxa o crivo e gente.
6. **Verificacao independente (CONFERE)** - quem propoe a melhoria nao a aprova. O teste do passo
   APLICA roda numa instancia separada (a Alia ou um sub-agente dedicado), nunca no mesmo agente que
   gerou a proposta. Auto-aprovacao e o furo que deixa um erro virar verdade no ciclo seguinte; a
   separacao de instancias fecha esse furo ANTES de promover. So promove com verdict independente +
   evidencia anexada.

Os limites numericos (N de falhas, janela de observacao, teto de propostas por ciclo) ficam em
[rsi.yaml](rsi.yaml) -> `guardrails`, para serem auditaveis e ajustaveis sem reescrever esta spec.

## Metrica viva

A prova de que o RSI funciona e uma so: **o custo medio de tokens por Artifact entregue deve cair
ao longo do tempo**, sem queda de qualidade (taxa de PASS no Gate estavel ou subindo). Essa queda
e a evidencia de que RSI e Frugalidade trabalham juntos - o sistema fica melhor *e* mais barato.

A fonte do numero e o `state.json` do Studio (custo por Task) cruzado com os verdicts de Gate na
Memory. A definicao formal da metrica e da janela esta em [rsi.yaml](rsi.yaml) -> `metric`.

## Anti-patterns (o que NAO e RSI)

- Reagir a uma unica falha como se fosse padrao (estagio 2 existe pra impedir isso).
- Aplicar melhoria sem teste nem rollback (vira aposta, nao engenharia).
- "Melhorar" tocando o nucleo do Engine ou a Constituicao (fora do escopo, sempre).
- Otimizar custo derrubando qualidade (a Frugalidade do Alia Flow proibe trade de qualidade).
- Aprovar a propria proposta - quem produz nao confere (viola a separacao de instancias e o CONFERE).

## Liga com

[Constituicao](../constitution.md) (Principio X - RSI Discipline) - 
[Governanca / Loops](../governance/loops.md) (de onde vem o feedback) - 
[Quality Gate](../governance/quality-gate.md) (o crivo que o RSI usa e respeita) - 
[Deep Research Loop](../features/deep-research-loop.md) (RSI alimentado por pesquisa externa).

---

*Alia - Delegue. Nao opere.*
