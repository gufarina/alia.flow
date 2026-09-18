# Especificacoes de Entrega - Acme SaaS

> Contrato de CONSISTENCIA do Client: as regras objetivas que TODA peca deste squad respeita, para
> que tudo que sair - landing, story, email, painel - pareca feito pela mesma mao. Consultar ANTES de
> produzir (como o examples/ para reuso). O Squad Owner cobra a aderencia no Quality Gate.
> Convencao em engine/squad-system.md ("Especificacoes de entrega").

## Design (identidade visual)
- Paleta: preto #000, branco #fff, um unico acento (rosa #f5569b) em fill chapado.
- Tipografia: geometrica para titulo/numero; serif editorial so em headline; monospace em rotulo tecnico.
- Superficie: fills solidos + regua de 1px; sem blur, sem glow, sem sombra suave, sem gradiente-cor.
- Cantos: squircle no container externo; celulas internas retas.

## Formato (o entregavel)
- Copy: headline carrega o beneficio; UMA unica Chamada de acao por peca; auto-contido.
- Documento: frontmatter no topo (description + updated) e secoes previsiveis (grep-then-read, OPP-69).
- Numero: sempre com a fonte ([MEDIDO] ou rotulo de estimativa); nunca precisao falsa.

## Tom (herda 03-tom-e-mensagem.md)
- Direto, concreto, sem jargao; fala de resultado, nao de funcionalidade.

## Checklist de consistencia (o Owner confere antes do Gate)
- [ ] Paleta e tipografia batem com esta spec.
- [ ] Uma unica Chamada de acao.
- [ ] Termos so da linguagem ubiqua (02-linguagem-ubiqua.md).
- [ ] Tom conforme 03-tom-e-mensagem.md.
- [ ] Reuso conferido em examples/ antes de criar do zero.
