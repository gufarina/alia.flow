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

## [2.0.2] - 2026-09-25

A 2.0.2 saiu em 25/09 às 00:15 e trouxe seis mudanças:

- Histórico de versões obrigatório: a conferência automática reprova versão nova sem entrada neste
  histórico, e nenhuma versão é publicada sem revisão aprovada.
- Tarefa conferida agora fecha: a conferência grava a prova, e a tarefa só fecha com essa prova e
  com o mesmo veredito. Critério reprovado na conferência não deixa a tarefa sair aprovada.
- A divisão de tarefas não parte mais um pedido pequeno: o jeito como o pedido pode falhar não vira
  tarefa separada, e o título de cada parte vem sempre do que foi pedido.
- A migração do estúdio passa a levar o histórico de versões junto.
- As proteções do motor passam a vigiar também os comandos do PowerShell, não só os do Bash, e
  reconhecem mais formas de escrever, copiar, mover e apagar arquivo.
- A Alia passa a falar com você só quando precisa de uma decisão sua ou para entregar o resultado,
  com um resumo no fim.

## [2.0.1] - 2026-09-24

A 2.0.1 saiu em 24/09 às 20:49 e trouxe cinco mudanças:

- Aviso de conferência pendente: quando um especialista entrega e a entrega ainda não passou pela
  conferência, a Alia é avisada antes de encerrar a resposta. Antes isso travava a conversa; agora
  só avisa, e ficou mais rápido.
- Checagem de idioma: resposta em inglês é barrada antes de chegar a você.
- Proteção dos arquivos centrais do motor: olha só o arquivo que o comando vai alterar de verdade.
  Comando que só lê passa.
- Tarefa grande é dividida em partes, cada uma com seu critério de aceite. A parte seguinte só abre
  depois que a anterior passa na conferência.
- A linha de status mostra a versão certa depois de migrar o estúdio (antes ficava presa na versão
  antiga).

## [2.0.0] - 2026-09-24

A Alia Flow 2.0 chega mais rapida e mais economica, com numeros que voce confere. Ela responde na
hora: cada acao, que antes esperava de 426 a 1.050 milissegundos, agora leva 60 milissegundos. O
texto que o motor carrega para comecar a trabalhar caiu 61% (de 18.873 para 7.343 bytes). A
conferencia completa, que levava 279 segundos em 611 checagens, agora leva de 4,1 a 4,6 segundos.

Toda entrega agora fecha com prova registrada: antes isso acontecia em pouco mais de 1 a cada 3
tarefas (36,5%); na 2.0 e obrigatorio, sem prova a tarefa nao fecha.

Nos mesmos pedidos reais, depois da dieta de tokens: num prototipo real de cliente, a 1.84
reprovou (190 mil tokens, aumentou o raio que era para diminuir) e a 2.0 gastou 34% menos (125 mil
tokens), com ressalva (o raio da tarefa ficou 1px acima do atual). No texto publico de uma pagina,
a 1.84 ficou com ressalva (310 mil tokens, numeros sem fonte) e a 2.0 gastou 27% menos (227 mil
tokens), aprovada de primeira. Ressalva sobre os dois numeros: a 2.0 rodou primeiro em cada par (a
vantagem de cache ficou com a 1.84) e o brief da 2.0 no segundo pedido ja trazia a licao
"infografico abstrato reprova".

Como usar: a pasta v2/ chega junto deste pacote, ao lado do motor atual (que continua sendo o que
responde por padrao). Abra uma copia do seu estudio, rode a 2.0 nela e compare com seus proprios
olhos. Aprovado, a troca do seu estudio de verdade e um comando (`python v2/bin/migrate.py
apply --source v2 --target <sua instancia>`), com backup automatico e um comando de volta
(`python v2/bin/migrate.py undo --target <sua instancia>`).

O que a 2.0 ainda nao faz: o modo gerente de time (Gateway) nao foi provado ao vivo; Codex e
OpenCode seguem so contrato, sem sessao real ponta a ponta; a Laya (roteamento aprendido) perdeu
nos 5 testes com dado real e fica opcional, nunca decidindo sozinha.

Quem ja tem o Alia Flow instalado: rode `scripts/update-online.ps1` (ou `atualizar-alia.bat`) DUAS
vezes em sequencia para receber a pasta v2/ (a primeira rodada atualiza o proprio script de
atualizacao; a segunda traz a 2.0 - o motor atual em uso hoje nao e tocado). Prova da 2.0:
`python v2/proof/check.py`.

## [1.83.0] - 2026-09-21

O Quality Gate ganhou uma porta de saída em máquina. Antes do julgamento em prosa, seis checagens
determinísticas passam sobre o arquivo que a Task declara como prova: se ele existe mesmo em disco e
tem conteúdo, se tem travessão, se tem emoji, se uma peça interna está vestida com a marca do
produto, se não é um esqueleto vazio e se o texto está íntegro. O operador ganha o óbvio: defeito que
a máquina pega de graça para de chegar até ele, e o veredito sai tipado, aprovado, reprovado ou com
ressalva. Nada disso bloqueia nada. Ao fechar uma Task com veredito e prova, o registro chama a
checagem, avisa se reprovou e guarda o resultado junto da Task; quem decide continua sendo o humano.

A mudança mais importante é a ressalva. Prova que ninguém consegue abrir, uma URL ou uma frase
descrevendo o que foi feito, nunca mais vira aprovação automática: vira ressalva, porque ausência de
prova não é prova de qualidade. Medido sobre as 323 Tasks que o Gate em prosa já tinha aprovado: 95
(29,4%) seriam reprovadas pela máquina, 159 (49,2%) ficariam com ressalva por prova não verificável e
só 69 (21,4%) passariam limpas. Os motivos das reprovações foram conferidos um a um à mão: 66
apontavam para um arquivo de prova que não existe, 23 tinham travessão, 9 citavam marca do produto em
peça interna e 3 tinham emoji. A regra de marca é dirigida por dado: sem o arquivo de regras da casa,
essa checagem não opina.

Honestidade sobre o caminho até aqui: a porta só foi ligada depois de cinco rodadas de conserto de
alarme falso, todas sobre casos reais que ela acusava errado, caminho relativo resolvido contra a
pasta errada, marca deduzida por tonalidade parecida, peça grande tratada como esqueleto vazio,
arquivo íntegro acusado de corrompido e um visto simples confundido com emoji. Alarme falso em portão
de qualidade custa mais caro que buraco, porque ensina a ignorar o portão. Por isso a bateria ganhou
também checks de NÃO alarme, e não só a prova pelo negativo.

## [1.82.1] - 2026-09-18

Conserto pequeno na versao anterior: o aviso de estouro de orcamento (teto cumulativo por
especialista e teto de Budget por delegacao) passou a AVISAR em vez de TRAVAR o fechamento da
resposta. O numero que ele acusa ja aconteceu quando o aviso dispara - nao existia acao que
baixasse esse numero no mesmo turno, entao travar so tirava do operador a resposta que ja estava
pronta e travava de novo no proximo fechamento, em loop. A medida continua identica: os dois
ledgers de orcamento seguem recebendo a mesma linha, e o aviso continua aparecendo no console de
quem coordena. Nenhuma outra regra de disciplina (delegacao obrigatoria, citar a fonte, ritual de
apresentacao) mudou - essas continuam travando normalmente.

## [1.82.0] - 2026-09-18

Versao de disciplina: cinco mecanismos que a casa tinha no papel passam a existir na maquina - e um
deles so foi descoberto quebrado porque alguem foi medir se ele algum dia tinha disparado.

- Pedido ambiguo passa a ser alinhado ANTES do trabalho comecar. A regua de quando parar e perguntar
  ja existia; faltava alguem puxar essa regua na hora certa. Agora o proprio texto do pedido e
  pontuado por sinais de superficie (voltar atras, refazer, volume de leitura, distancia do assunto)
  e a obrigacao de alinhar aparece so acima do limiar - abaixo dele, silencio total, nem uma linha a
  mais no caminho. Calibrado contra o historico real de uso: dispara em cerca de 11 de cada 100
  pedidos. Limite honesto: ele le o TEXTO do pedido, nunca a intencao - pedido ambiguo escrito com
  cara de trivial passa batido. E desligavel.
- O teto de chamadas por especialista virou medida de verdade. Ele existia desde setembro e NUNCA
  tinha disparado uma unica vez: a condicao que o ligava nunca e verdadeira neste tipo de host, e o
  registro que ele deveria alimentar estava vazio desde o dia em que nasceu. Agora a contagem e
  cumulativa por especialista - reabrir o mesmo especialista soma no mesmo saldo em vez de zerar,
  que era exatamente o buraco por onde oito reaberturas de vinte e cinco chamadas viraram quase
  duzentas sem ninguem reclamar. Limite honesto, e e o motivo desta versao existir: neste host nao
  da para travar em tempo real; o aviso sai no FIM da rodada, quando o gasto ja aconteceu. Mecanismo
  que interrompe no meio ainda nao existe, e dizer o contrario seria mentira.
- Briefing de delegacao passa a ter contrato: sete campos obrigatorios, entre eles a lista de
  desfechos previsiveis com a regra de decisao de cada um (minimo tres, sempre incluindo "achei algo
  fora do escopo" e "a premissa do brief caiu"). E a duvida sem dono que faz a rodada reabrir -
  medidas 547 reaberturas em 30 dias, um quarto do trafego. Todo especialista gerado daqui em diante
  nasce com um gabarito de briefing ao lado, ja preenchido com o que o gerador sabe. Limite honesto:
  a bateria confere o contrato e o gabarito; ela nao le o briefing que voce escreve na hora.
- Painel de desperdicio que roda sem chamar IA: quantas perguntas a Alia faz antes de executar,
  quantas vezes o mesmo especialista e reaberto, e quanto do que o operador digita e retrabalho. A
  primeira coisa que ele fez foi derrubar um numero que a propria casa vinha usando: os 16,9% de
  retrabalho saiam de denominador sujo, porque metade das "mensagens do operador" contadas era texto
  que o sistema injeta sozinho. Sobre a populacao limpa o medido e 6,3% (bruto 14,1%). O painel
  mostra bruto e limpo lado a lado, sempre - numero de retrabalho sozinho nao volta a existir.
- O guarda de disciplina parou de confundir recado automatico do sistema com fala do operador. Aviso
  de tarefa concluida chega pelo mesmo canal de quem digita, e o guarda ancorava a rodada nesses
  avisos: 11 rodadas medidas foram reprovadas por engano, com a ordem do operador devidamente
  registrada. Agora esse texto e filtrado nos dois lugares que decidem "o que o operador disse". O
  efeito e nos dois sentidos, e o mais importante e o segundo: recado automatico tambem deixa de
  valer como licenca para a coordenadora escrever direto.

---

## [1.81.1] - 2026-09-18

Versao de seguranca, nascida de um incidente real desta madrugada.

- A bateria passa a reprovar quando a protecao que mora FORA dela desaparece. Duas protecoes do
  produto vivem em lugares que nao sobrevivem a recriacao do repositorio: o gancho que impede
  publicar sem o portao verde, e a identidade de quem assina os commits. Quando o repositorio foi
  recriado, as duas sumiram em silencio e o e-mail pessoal do operador voltou a assinar commit.
  Agora a bateria acusa a ausencia das duas.
- O portao de identidade passa a julgar o que VAI ser publicado, e nao o que o servidor ja tem.
  Antes ele varria tambem o retrato local do servidor, entao travava exatamente o conserto que ele
  existe para exigir: enquanto o passado estivesse sujo, ninguem conseguia publicar a limpeza.
  Commit local com identidade fora da lista continua reprovando igual.
- O numero de verificacoes anunciado no README deixa de reprovar quando conferido fora do contexto
  em que foi escrito. Ele e um retrato tirado no pacote recem-montado; conferido dentro de um
  repositorio git, o total conta diferente por natureza. Onde o numero e escrito, errar continua
  reprovando; nos outros lugares vira aviso que mostra os dois numeros, em vez de travar
  atualizacao legitima.

---

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
