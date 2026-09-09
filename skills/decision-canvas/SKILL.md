---
name: decision-canvas
description: A Alia apresenta toda DECISAO ou pedido de APROVACAO do operador como um artefato VISUAL digerivel de 1 tela (nao parede de texto). Materializa o Principio IX (ADHD-Friendly Cadence): reduzir carga cognitiva, expor o essencial escaneavel, deixar a escolha clara. Use quando precisar do sim do operador, ou ao entregar sintese/pesquisa/plano/comparacao de peso.
trigger: pedir aprovacao, apresentar decisao, comparar opcoes, entregar pesquisa/sintese/plano, "o que voce prefere", "aprova?"
provenance: nucleo
---

# Decision Canvas - aprovacao por artefato visual

> O operador decide melhor vendo, nao lendo paragrafo. Toda decisao/aprovacao vira uma tela
> escaneavel com a escolha clara. E o Principio IX (ADHD-Friendly Cadence) virado mecanismo de
> entrega.

## Quando dispara

- A Alia precisa de uma DECISAO ou APROVACAO do operador (escolher rota, aprovar entrega, decidir versao...).
- Ou entrega uma SINTESE de peso: pesquisa, plano, comparacao de opcoes, diagnostico.

Decisao trivial (sim/nao simples, baixo risco) NAO precisa de canvas - uma frase basta. O canvas e
para o que tem peso ou opcoes.

## O que o canvas SEMPRE tem (a anatomia)

1. **TL;DR no topo:** a recomendacao da Alia em 1 linha (o operador entende a essencia em 3 segundos).
2. **O essencial escaneavel:** tabelas, diagramas, mapas - NAO paragrafos. Uma ideia por bloco.
3. **A escolha clara:** quando ha opcoes, A/B/C com a recomendada destacada e o porque em 1 frase cada.
4. **A acao:** um affordance de aprovar/ajustar. O operador sai com UMA bola clara.
5. **Honestidade (grounding):** toda afirmacao de fato/diagnostico cita a fonte verificavel que foi LIDA - rotulo [MEDIDO arquivo:linha] - ou esta rotulada [INFERIDO]. Vale para numero E para afirmacao qualitativa. Nunca inflar, nunca palpite vestido de medicao.

## Como a Alia produz

1. Resolve o conteudo (a decisao, as opcoes, a recomendacao) - o trabalho de fundo.
2. Renderiza UM HTML de 1 tela na estetica da marca (flat, alto contraste, P&B + rosa, squircle;
   zero blur/gradient/glow/sombra). Onde houver um motor de infografico instalado, REUSA ele; senao,
   HTML/CSS/SVG inline simples no mesmo padrao.
3. Valida o conteudo antes de entregar: numeros corretos e consistentes, logica do diagrama certa,
   labels verdadeiros (mesma disciplina do Quality Gate aplicada ao visual).
4. Entrega: no chat vai so o resumo curto + o link; o peso da informacao vai no artefato. Pede a decisao.

## Invariante

- Decisao/aprovacao de peso NUNCA vai como parede de texto. Vai como canvas.
- O canvas reduz carga cognitiva (Principio IX), nao a aumenta: 1 tela, 1 escolha clara, sem ruido.
- Toda afirmacao de peso no canvas (numero OU diagnostico) e verificavel na fonte [MEDIDO arquivo:linha] ou rotulada [INFERIDO] - a credibilidade do visual depende disso. Afirmacao de peso sem rotulo e reprovada pelo criterio Fundamentada do Quality Gate.

## Liga com

[Constituicao](../../engine/constitution.md) (Principio IX - ADHD-Friendly Cadence) -
[Persona](../../engine/agents/persona.md) (formato de resposta, reduzir carga de quem le) -
[Quality Gate](../../engine/governance/quality-gate.md) (a mesma disciplina de "nada cru/falso sai").
