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

## [2.1.2] - 2026-10-01

A 2.1.2 saiu em 01/10 e trouxe quatro mudanças:

- A sessão principal agora consegue publicar: um comando único (`scripts/publish-release.ps1`) empacota, copia, commita e envia, e o check verde passa a valer para o repositório do produto (`python v2/proof/check.py --repo <caminho>`). A mensagem de recusa ensina o comando.
- A muralha deixa passar só os comandos de publicar e de atualizar o motor; o resto continua barrado.
- Uma notificação de tarefa em segundo plano, ou uma frase entre aspas, não libera mais a sessão principal por engano.
- Uma prova nova percorre o ciclo inteiro (abrir, delegar, entregar, fechar, memória, publicar, atualizar) e reprova se alguma etapa ficar sem ninguém autorizado.

## [2.1.1] - 2026-10-01

A 2.1.1 saiu em 01/10 e trouxe uma mudança:

- Procurar dentro de um arquivo só já não exige ler o mapa antes: só varrer pasta exige. Isso deixava perguntas simples bem mais caras.

## [2.1.0] - 2026-10-01

A 2.1.0 saiu em 01/10 e trouxe sete mudanças:

- Toda Task passa por um só caminho: só abre em projeto cadastrado, só fecha com veredito e com a prova existindo no disco.
- O especialista só recebe trabalho depois que o líder do time aceitou a Task, em qualquer agente que tenha o gancho.
- Uma sessão chama no máximo 20 subagentes; o 21º é recusado com aviso.
- Antes de varrer o código, a Alia lê o mapa ou o wiki do cliente.
- Aprendizado que se repete sem diminuir agora reprova, e o aviso de mapa velho só pode ser adiado uma vez.
- Os especialistas são gerados de uma fonte só para Claude Code, OpenCode e Pi, sem a parte de personagem.
- A verificação antes de publicar acusa e-mail pessoal, caminho da máquina, arquivo não rastreado e autor que não é anônimo.

## [2.0.8] - 2026-09-30

A 2.0.8 saiu em 30/09 às 22:30 e trouxe uma mudança:

- O PULSO, vetado pela segurança, fica desligado salvo opt-in: sem a opção explícita, nada dele
  entra na abertura da sessão nem no pedido ao especialista, e o estado dele deixa de ser regravado
  a cada fim de resposta.

## [2.0.7] - 2026-09-30

A 2.0.7 saiu em 30/09 às 22:10 e trouxe duas mudanças:

- A Alia, na conversa principal, agora só delega: se tentar escrever arquivo de trabalho ou rodar
  script que escreve, o motor nega e diz a quem passar a tarefa. Memória, notas de operação e
  estado da tarefa continuam livres.
- Ela só executa sozinha quando o próprio CEO pede isso na mensagem dele; a liberação vale por uma
  sessão, no máximo 60 minutos, e ela não consegue se liberar por conta própria.

## [2.0.6] - 2026-09-29

A 2.0.6 saiu em 29/09 às 15:46 e trouxe uma mudança:

- Rodar o gerador de especialistas para um alvo só (`-Only`) agora gera só aquele alvo e nunca
  apaga o resto; antes, esse comando apagava os especialistas de todos os outros clientes sem
  perguntar. A poda do roster passou para `-Prune`, explícita e sempre junto de `-Only`, e um alvo
  que não existe avisa e falha em vez de calar.

## [2.0.5] - 2026-09-28

A 2.0.5 saiu em 28/09 às 20:28 e trouxe sete mudanças:

- O motor agora confere se o conhecimento curado de cada cliente está desatualizado (mapa velho,
  índice velho, ficha de produto atrasada) e avisa isso logo na abertura da sessão, sem esperar
  alguém notar.
- Uma entrega de cliente só fecha com recibo de conhecimento: se o mapa, o índice ou a ficha do
  cliente estiverem velhos, o fechamento é recusado e diz o que refazer. O recibo fica gravado na
  tarefa.
- Quando o mapa ou a ficha de um cliente está velho, o aviso aparece também no resumo de tarefa
  entregue a quem vai trabalhar nele.
- Uma dívida registrada com prazo de até 14 dias silencia o aviso até a data combinada; sem prazo,
  com prazo vencido ou com prazo mais longo que isso, o aviso volta sozinho.
- A versão do produto é lida como a maior do CHANGELOG, mesmo quando ele está fora de ordem, e
  refazer o índice de um cliente não faz mais o mapa parecer velho.
- Sessões novas e retomadas passam a acionar o mesmo mecanismo de aviso que antes só rodava depois
  de uma compactação de conversa.
- A conferência automática do motor ganhou mais provas, incluindo a checagem pelo negativo
  (quebrar, ver falhar, desfazer, ver passar de novo).

## [2.0.4] - 2026-09-27

A 2.0.4 saiu em 27/09 às 12:25 e trouxe quatro mudanças:

- O motor recusa, na hora de escrever, arquivo que vai para o público com o nome de um cliente
  seu, do seu estúdio ou do usuário do seu computador.
- A conferência automática varre todos os arquivos públicos atrás desses nomes e aponta onde cada
  um aparece.
- Scripts e provas do motor deixaram de citar dados da máquina de quem o desenvolve.
- O aviso que aparece quando a conversa é resumida agora sai com acento.

## [2.0.3] - 2026-09-26

A 2.0.3 saiu em 26/09 às 23:08 e trouxe três mudanças:

- A conferência final recusa aprovação sem prova que outra pessoa consiga repetir: dizer que
  funciona ou que cumpriu o objetivo agora exige apontar o comando rodado ou um arquivo que existe.
- Quando a conversa é resumida para liberar espaço, a Alia recebe o endereço da conversa inteira e
  confere ali antes de afirmar um detalhe da parte resumida.
- Cada conversa registra só a própria tarefa: uma conversa sem tarefa aberta não herda mais a de
  outra, e o custo não vai parar na conta errada.

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

## [2.0.0] - 2026-09-23 (publicada)

Reescrita enxuta do motor, instalada numa copia de teste (`Projetos\studio-farina-v2-teste`), sem
tocar o estudio real. Texto do motor ao abrir cai de 18.873 para 7.343 bytes (61% menos); a espera
por acao da Alia cai de 426-1.050 ms para 60 ms; a conferencia completa cai de 279 s (611
checagens) para 4,1 a 4,6 s. Tarefa fechada com conferencia registrada deixa de ser 36,5% (a
1.84 media a coisa errada) e passa a obrigatoria: sem veredito, a Task nao fecha. Agentes
carregados por sessao caem de 97 para 82. Das 78 regras do motor, 70 ganharam peca nova e 8 foram
aposentadas com motivo escrito.

Nos dois pedidos reais medidos as cegas pelo Nexus: um prototipo real de cliente (TASK-548) foi de
reprovado (190 mil tokens) para aprovado de primeira (125 mil, 34% menos, com a dieta de token);
o texto publico da pagina (TASK-568) foi de com ressalva (310 mil tokens) para aprovado de
primeira (227 mil, 27% menos, com a dieta). A Laya perdeu nos 5 testes com dado real e fica
opcional, so observando. O gasto desta fase chegou a 27,4 milhoes de tokens no total (a maior
parte, 8 milhoes, da propria coordenacao relendo a conversa inteira a cada volta); o teto era ate
12 milhoes, com parada combinada em 10, e a fase parou em 12,2 no orcamento proprio dela.

- Brief por 6 campos com criterio de aceite. Todo pedido diz o que e falhar antes de comecar.
- Especialista recebe fatia exata (`caminho#Lx-Ly`), nunca leitura fixa de abertura.
- Squad ativo por Client. So o squad do Client escolhido fica visivel ao host.
- Registro que nasce sozinho. Quem executou, quanto gastou e quanto tempo levou, gravado pela
  propria maquina.
- Regra de risco (R1/R2) decide quando debater: peca publica, irreversivel, seguranca ou ordem
  direta do Operator.
- Migracao com backup datado e undo que devolve o hash original.
- Porta opcional para a Laya, sem ela decidir nada.
- Pendente: Gateway (modo gerente de time) nao provado ao vivo; Codex e OpenCode seguem so
  contrato; conferencia final e teste do CEO na copia antes de aplicar no estudio real.

## [1.84.0] - 2026-09-22

Correção da 1.83.0. A nota da versão anterior publicou números errados sobre a medição retroativa: 95 Tasks reprovadas, 159 com ressalva, 69 limpas e 66 provas inexistentes. A contagem tratava "o texto não é um caminho" como "a prova não existe", e são coisas diferentes. A remedição separa as duas perguntas. De 481 Tasks aprovadas com prova declarada, 287 têm prova em formato que a máquina confere e que resolve, 185 têm prova em texto livre e 9 apontam para uma prova que não resolve. Das 287 verificáveis, 255 estão limpas e 32 tinham defeito de conteúdo: travessão em 24, marca em 10, emoji em 2 e codificação em 1 (uma Task pode ter mais de um). A base também não é a mesma da nota anterior, então as proporções das duas notas não se comparam. Os números foram medidos por um comando e reproduzidos por outro especialista, com resultado idêntico em todos os campos. A nota da 1.83.0 fica como foi publicada; a correção mora aqui.

Esta versão ataca a causa, não o efeito. O número errado nasceu porque a prova de uma Task era texto livre e ninguém conferia se ela apontava para algo real. E chegou ao público porque nenhum número precisava ser reproduzido por outra mão antes de sair. As duas portas agora existem na máquina.

- Prova nasce válida. Fechar uma Task como feita exige prova que resolve para arquivo, pasta ou link, no formato canônico de itens separados por ponto e vírgula. Abrir uma Task nunca é bloqueado, e os registros antigos continuam como histórico, sem reescrita. É isso que impede as 185 provas em texto livre de voltarem a nascer.
- Correção exige causa. Task de correção só fecha como feita com a causa-raiz declarada. Consertar o sintoma sem dizer por que ele apareceu deixa de ser possível.
- Número público se escreve sozinho. A contagem de verificações que vai para o registro público é gravada pela própria bateria, nunca mais digitada à mão.
- Empacotamento mais exigente. O pacote reprova se um script empacotado chama outro que ficou de fora, e reprova se a revisão de release não traz a tabela de números com o comando que os reproduz e com quem reproduziu, que tem de ser diferente de quem mediu.
- Falha rápida. A bateria abre checando a sintaxe de todos os scripts e para em segundos se houver erro, em vez de acusar só no fim.
- Portão de saída mais honesto. Uma regra única decide se a prova resolve, a mesma no registro e no portão, e o motivo de falha diz "não resolve", nunca "não existe", porque o portão só sabe o primeiro. Checagem que não se aplica aparece como NA, separada de SKIP; emoji é reconhecido por lista explícita; arquivo binário é reconhecido por byte zero; erro interno por caractere inválido vira SKIP em vez de derrubar a checagem.
- Veredito de gate registrado por volta. Toda volta de gate sobre uma peça fica registrada ao lado dela, e uma reescrita aprovada só cai numa volta seguinte citando a regra que mudou.
- Manutenção. O registro de leis aponta os testes pelo nome, não pelo número da linha, e para de quebrar a cada edição da bateria. Script com acento passou a exigir marca de codificação, para o PowerShell não trocar o caractere na leitura.

Atenção ao atualizar: o registro de Task passa a recusar dois fechamentos que antes aceitava, prova que não resolve e Task de correção sem causa-raiz. Quem fecha Task por automação com texto livre na prova precisa passar para o formato canônico.

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
