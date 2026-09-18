# Expert Mind - Brad Frost (Atomic Design)

> Dominio: design de sistemas / UI. Carregar no segundo cerebro de um especialista de design para
> que ele pense em sistemas, nao em telas soltas. Metodologia publica (Atomic Design, livro aberto).

---

## Principio central

Interfaces nao sao telas - sao sistemas de componentes reutilizaveis. Pensar de baixo pra cima:
das pecas menores para as paginas inteiras.

## A hierarquia (atomos -> paginas)

1. **Atomos** - as pecas indivisiveis: cor, tipografia, um botao, um input, um label.
2. **Moleculas** - grupos simples de atomos com funcao: um campo de busca (label + input + botao).
3. **Organismos** - secoes complexas: um header, um card de produto, uma lista.
4. **Templates** - o esqueleto da pagina (layout) sem conteudo real.
5. **Paginas** - o template preenchido com conteudo real, onde se testa o sistema.

## Heuristicas de decisao

- Antes de criar algo novo, perguntar: ja existe um atomo/molecula que resolve? (REUSE > CREATE).
- Componente que aparece 2+ vezes vira parte do sistema, nao copia-cola.
- Design tokens (cor, espaco, tipo) sao a fonte unica - nada de valor hardcoded.
- O sistema vive num lugar navegavel (style guide / component lab), nao na cabeca de alguem.

## Checklist de qualidade

- [ ] O componente usa tokens, nao valores soltos?
- [ ] Ele se encaixa na hierarquia (e atomo, molecula ou organismo claro)?
- [ ] E reutilizavel em outro contexto sem reescrever?
- [ ] Esta documentado no sistema (nao so no codigo)?

## Anti-patterns

- Desenhar telas inteiras sem extrair os componentes reutilizaveis.
- Valores de cor/espaco hardcoded em vez de tokens.
- "So mais um componente especial" que duplica um existente.

## Atualizacao via deep research (2026-06-13, Perplexity)

- A IA potencializa o design system, nao substitui: documentar o sistema com estrutura logica que a
  IA entenda, pra ela gerar variantes (layout, microcopy) que seguem as diretrizes da marca. O
  designer vira curador e estrategista, garantindo alinhamento; a automacao faz o repetitivo.
- Atomic design em 2026 e base MALEAVEL, nao regra rigida: padroes de interacao e movimento viram
  componentes de primeira classe (tokens de movimento, fisica de interacao); camadas mais granulares;
  foco menos em hierarquia visual e mais em funcionalidade, escalabilidade e adaptacao a novos
  contextos (AR/VR, multi-dispositivo, percepcao de performance consistente).

## Liga com

A regra de design da casa (design-first, com baseline de design system do operador) e o Quality Gate de design.
