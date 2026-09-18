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

## [1.81.0] - 2026-09-18

- Comando de publicar rodado por um especialista passa a ser bloqueado no terminal. Ate agora o
  motor vigiava quem EDITAVA arquivo e deixava passar quem rodava comando - e foi por ai que, em
  16/09, um especialista publicou no repositorio publico no meio da propria rodada, sem passar por
  ninguem. Quem conduz a sessao segue publicando normalmente, e ha interruptor de emergencia.
  Limite honesto: a cerca reconhece o especialista pelo sinal que o proprio host da; se um dia esse
  sinal faltar, ela deixa passar em vez de travar o operador, e ela cobre o terminal, nao todo
  caminho possivel ate o git.
- O mapa de navegacao da documentacao passa a enxergar tambem a ligacao que um documento faz a
  outro no formato [[assim]], que antes era invisivel para ele. Vale entre documentos da mesma
  pasta.
- Memoria sob medida: a ficha de um especialista pode declarar de quais documentos ele precisa, e
  recebe so aquilo em vez da pasta inteira. O campo e opcional, e ficha que nao declara nada nao
  muda de caminho - continua sendo gerada exatamente como antes.
- Duas travas novas na bateria de testes: ligacao de memoria apontando para nota que nao existe
  nao pode aumentar, e o indice da memoria nao pode passar do tamanho que o modelo consegue ler de
  uma vez. O indice da propria casa tinha estourado esse tamanho e parte dele nao carregava.

---

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
