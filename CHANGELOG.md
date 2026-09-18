# Changelog - Alia Flow

Todas as mudancas relevantes do motor (engine) sao registradas aqui.
Formato baseado em Keep a Changelog. Versionamento semantico adaptado ao produto.
Portugues correto, com acentos. Arquivo salvo em UTF-8 sem BOM; o unico erro e caractere corrompido. Emoji continua fora de peca publica.

## Esquema de versao (o contrato de update)

`MAJOR.MINOR.PATCH`

- PATCH (0.1.x): correcao de doc, adicao modular pequena, scaffolding. NAO muda contrato de
  orquestracao nem a constituicao. Smoke verde obrigatorio.
- MINOR (0.x.0): nova feature/cluster de OPP, retrocompativel. Smoke verde + teste na instancia aplicada.
- MAJOR (x.0.0): mudanca que quebra contrato (constitution, glossario, schema de loops/squads).

Regra de ouro (modularidade): cada OPP do backlog vira UM incremento de versao auto-contido,
testado na instancia viva (a instancia aplicada) antes de fechar. Um update = uma mudanca isolavel e
reversivel. Fluxo: alterar engine -> bump VERSION -> entrada no CHANGELOG -> smoke-test-studio
ALL GREEN -> tag.

## [1.80.2] - 2026-09-16

Higiene interna: ajustes de consistencia no registro de eventos da instancia e nos documentos de
governanca do motor. Sem mudanca de comportamento para quem usa.

---

## [1.80.1] - 2026-09-16

- Empacotador: um arquivo derivado que nao deveria viajar no pacote passava a entrar de novo por
  efeito colateral da propria validacao interna. Corrigido - pacotes publicados a partir de agora
  nao carregam mais esse arquivo.
- Todo projeto novo passa a ganhar, por padrao e sem custo extra de IA, um indice de navegacao da
  propria documentacao. Um mapa mais profundo (cruzando varios documentos) continua disponivel sob
  demanda para projetos grandes ou muito ativos.
- Registro de planos de trabalho passa a exigir evidencia real do artefato entregue antes de marcar
  uma etapa como concluida - reduz o risco de plano dizer "feito" sem provar.

---

## [1.80.0] - 2026-09-15

- O motor passa a registrar um diario de eventos por tarefa (criacao, mudanca de status, veredito,
  fechamento), para quem quiser consultar o historico de uma tarefa sem abrir o estado inteiro.
- O contexto injetado automaticamente para os especialistas do motor passa a ser selecionado por
  relevancia, em vez de cortado por tamanho fixo - mais cobertura util sem aumentar o custo.
- Todo projeto novo passa a ganhar, por padrao e sem custo extra de IA, um indice de navegacao da
  propria documentacao (a mesma mudanca descrita em 1.80.1, aqui na origem).

## [1.79.0] - 2026-09-14

Especialistas do motor (sub-agentes gerados) passam a poder usar um leitor de arquivos mais barato
para leituras grandes, dentro de limites fixos de seguranca (escopo restrito, quantidade maxima por
sessao, sem repasse para outro agente). Reduz custo sem abrir brecha de escopo.


Historico anterior a 1.79.0 nao e publicado neste repositorio.
