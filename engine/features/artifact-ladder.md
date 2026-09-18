# Escada de Frugalidade de Saida - Artifact Ladder

> Frugalidade de SAIDA: o motor ja tinha frugalidade de ENTRADA (ler menos, grafo antes de
> varredura - tools.md). Esta e a metade que faltava: produzir menos, na forca certa, sem perder
> qualidade. Adaptada do mindset "senior preguicoso" do skill ponytail (Dietrich Gebert, MIT - ver
> CREDITS), generalizada para QUALQUER Artifact (codigo, config, doc, persona, plano) - nao so
> codigo (a instancia-codigo continua em engine/engineering.md, "Escada da simplicidade").
> UTF-8 sem BOM.

---

## A escada (7 degraus)

Antes de produzir Artifact novo, suba NA ORDEM. Pare no primeiro degrau que resolve - nunca pule
degrau, nunca va direto ao 7.

1. **Precisa existir?** - o pedido resolve sem este Artifact? (YAGNI - corta o especulativo)
2. **Ja existe interno pra reusar?** - Memory, grafo, `knowledge/examples/`, codigo do Client (IDS:
   REUSE > ADAPT > CREATE, engineering.md).
3. **O padrao da casa resolve?** - convencao/template/skill ja escrita no motor (Frugal Skills,
   skeleton, workflow existente).
4. **O recurso nativo resolve?** - da plataforma, linguagem ou ferramenta (nativa antes de MCP,
   tools.md).
5. **O que ja esta provisionado resolve?** - dependencia/MCP/ativo ja instalado, sem adicionar novo.
6. **Cabe na menor forma que comunica?** - uma linha, um campo, uma frase - antes de um arquivo, uma
   secao, um modulo novo.
7. **So entao, o minimo que passa no Gate.** - o menor Artifact novo que cumpre os 6 criterios do
   Quality Gate, nem um passo a mais.

## Regra de parada

Pare no primeiro degrau que resolve com qualidade. Subir a escada sem parar (chegar ao 7 tendo
pulado o 2 ou o 4) e o mesmo desvio que "varrer sem consultar o grafo" e no lado da entrada
(tools.md, "Grafo obrigatorio"): nao e lembrete, e passo obrigatorio, so aceitavel pular com
justificativa explicita (o degrau nao se aplica, ou o Artifact e claramente o degrau 7 desde o
principio - ex.: logica de dominio genuinamente nova).

## O que NUNCA se corta por aqui

A escada decide QUANTO Artifact novo se produz - nunca SE uma parte do pedido e atendida. Nunca
serve de desculpa para cortar:

- entendimento do problema (as tres leituras do pedido, judgment-discipline.md);
- validacao de fronteira (o que a Task pediu, contado por partes - "conte as partes");
- erro que preserva dado (nunca engolir falha em silencio, engineering.md);
- seguranca;
- acessibilidade;
- requisito explicito do pedido (mesmo que o jeito mais simples de cumprir nao seja o mais bonito).

Se subir a escada faria cortar algo desta lista, o degrau nao serve - desca pro proximo, ou aceite
o degrau 7.

## O marcador: frugal-debito:

Simplificacao DELIBERADA (voce escolheu um degrau mais baixo sabendo o teto dela) leva o marcador,
sempre com teto conhecido + caminho de upgrade:

    frugal-debito: <teto conhecido> - upgrade: <caminho>

Exemplo (instancia-codigo, engineering.md): `// frugal-debito: lista linear; teto ~1k itens; trocar
por indice se crescer`.

Exemplo (instancia-persona/doc): `frugal-debito: skeleton nao cobre fluxo assincrono; upgrade: nova
secao quando o 2o Specialist async aparecer`.

Onde escrever: (a) inline, junto do trecho simplificado, para quem le o Artifact depois; (b) ecoado
na nota de Memory que ja se escreve ao FECHAR a Task (passo 5, AGENTS.md) - e o que faz o
`debt-scan.ps1` enxergar (o regex dele ja casa `debito` dentro de `frugal-debito`, ZERO mudanca de
codigo - `scripts/debt-scan.ps1`). Nenhum registro novo: o marcador entra no mesmo pipeline que
Concerns ja usa (quality-gate.md - "vira input de RSI; se nao resolvida, vira debito, pego pelo
debt-scan").

Marcador sem teto ou sem upgrade e pior que nao marcar: e decisao maquiada de disciplina. Isso e
Fail no Gate, nao Concerns.

## Clausula de precedencia (a escada nunca vence o Gate)

O Gate vence qualquer degrau. Economia que reprova um dos 6 criterios minimos do Quality Gate
(quality-gate.md) nao economizou nada - Principio VIII e claro: reduzir custo e obrigatorio,
reduzir qualidade e proibido, as duas regras valem juntas (constitution.md).

Em caso de colisao:

1. Requisito explicito do pedido sempre vence o degrau escolhido - a escada decide COMO/QUANTO
   produzir a parte pedida, nunca SE ela e produzida.
2. Marcador `frugal-debito:` sem teto+upgrade explicitos = Fail, nao Concerns.
3. Simplificacao que corta item da lista "nunca se corta" acima = Fail, mesmo com marcador presente
   - o marcador declara divida aceitavel, nao autoriza cortar o inegociavel.
4. A escada nunca e usada para justificar entrega parcial: "economizei nao implementando X" nao e
   um degrau da escada, e devolver a Task pela metade (persona-skeleton.md, Clausula anti-preguica).

## Por camada (quem sobe a escada, e o quanto)

- **Camada B (Specialist)** - sobe os 7 degraus inteiros. E quem produz a maioria dos Artifacts de
  dominio.
- **Camada C (execucao mecanica)** - versao comprimida: so degraus 2 (reusa?) e 6 (cabe na menor
  forma?). Julgamento de padrao-da-casa/nativo/provisionado (3-5) e escopo de Camada B - Camada C
  roda tarefa curta e bem definida (model-matrix.yaml), pouco espaco de decisao arquitetural.
- **Camada A (Gateway)** - nao sobe a escada por si (lei de nucleo: delega, nunca produz dominio com
  as maos). Usa a escada como criterio de cobranca ao bater o Gate (quality-gate.md, criterio 5) -
  confere que o Specialist subiu, nao sobe ela mesma.

## Enforcement (honestidade, nao aspiracao)

- **Contrato lido:** o texto acima, e o bloco equivalente em `agents/persona-skeleton.md`, dependem
  do Specialist seguir - nao ha hook que bloqueie Write/Edit antes da producao hoje. Mesma
  honestidade do "Grafo obrigatorio" (tools.md) antes do sensor existir.
- **Grep-avel, sem custo de LLM:** a presenca do marcador `frugal-debito:` num Artifact E checavel
  por script (regex), e o `debt-scan.ps1` ja pega a palavra sem mudanca de codigo (regex existente
  casa `debito`).
- **Semi-enforcado pelo Gate:** o criterio 5 (Atrito) do Quality Gate cobra a evidencia (Artifact
  minimo OU marcador presente) - Fail volta ao loop `fix-on-fail`, com custo real de retrabalho.
- **Nao construido ainda:** um hook `PreToolUse` em Write/Edit (molde `graph-usage-sensor.ps1`) que
  bloqueasse a producao sem checagem previa de reuso seria o unico enforcement mecanico de verdade
  antes do fato. Fica nomeado aqui como proximo passo, territorio de WARDEN - nao construido nesta
  rodada.

## Segue

[engineering.md](../engineering.md) - a instancia-codigo ("Escada da simplicidade"). -
[tools.md](../tools.md) - "Escada obrigatoria (saida)", o espelho da entrada. -
[Quality Gate](../governance/quality-gate.md) - criterio 5, a evidencia que cobra o marcador. -
[Esqueleto de Persona](../agents/persona-skeleton.md) - o bloco que todo Specialist carrega. -
[CREDITS.md](../../CREDITS.md) - a origem (ponytail, Dietrich Gebert, MIT).

---

*Alia - Delegue. Nao opere.*
