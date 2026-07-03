# Alia - Primeiros passos (versao beta)

> Voce recebeu este pacote porque esta testando a Alia antes de todo mundo. Obrigada.
> Este guia leva uns 10 minutos. Nada aqui exige saber programar.

## O que e a Alia, em uma frase

Voce diz o que precisa ficar pronto (um anuncio, um post, um plano), em palavras suas -
e a Alia conduz: pergunta o que falta, aciona quem entende do assunto, confere a
qualidade e te devolve pronto. E ela lembra do seu contexto: na segunda vez voce
nao explica tudo de novo.

## Antes de comecar (voce precisa de 1 coisa)

A Alia mora dentro do **Claude Code** (um programa da Anthropic, criadora do Claude).

1. Baixe o Claude Code em: https://claude.com/claude-code
2. Instale e entre com uma conta Claude (o plano pago e necessario para uso de verdade).

Ja tem o Claude Code? Pula direto pro passo 1.

## Instalar (3 passos, sem terminal)

1. **Descompacte** este pacote numa pasta sua. Sugestao: crie a pasta
   `Documentos\meu-estudio` e extraia tudo la dentro.
2. **De dois cliques em `iniciar-alia.bat`.** Abre uma pagina de boas-vindas no seu
   navegador - leia, e a Alia se apresentando. (Se o Windows perguntar se confia, pode
   confirmar: e so um atalho que abre uma pagina local, nada e instalado.)
3. **Abra a pasta no Claude Code.** O jeito mais facil no Windows:
   - abra a pasta no Explorador de Arquivos;
   - clique na barra de endereco (onde aparece o caminho), digite `cmd` e aperte Enter;
   - na janela preta que abrir, digite `claude` e aperte Enter.

   O Claude Code abre ja dentro da pasta - e nesse momento ele vira a Alia.

## A primeira conversa

Digite so isto:

```
pronto
```

A Alia assume dali: ela se apresenta, liga a memoria dela sozinha e te pergunta o que
voce precisa. Nao decore comando nenhum - e conversa.

### O melhor primeiro pedido (copie, preencha e cole)

A Alia trabalha por cliente. O melhor comeco e apresentar VOCE e UM trabalho real:

```
Meu nome e [seu nome]. Eu tenho [seu negocio - ex: uma barbearia em Curitiba].
Meu publico e [quem compra de voce]. Quero comecar com uma tarefa real:
[a tarefa - ex: um post de Instagram anunciando o novo horario de sabado].
```

Quanto mais concreto, melhor o resultado. "Me ajuda com marketing" rende pouco;
"um post anunciando o horario novo de sabado, tom descontraido" rende muito.

## 5 exemplos reais de pedido (para inspirar, nao para copiar cru)

1. **Dono de barbearia:** "Tenho uma barbearia em Curitiba, publico jovem, corte na
   regua. Quero um post de Instagram anunciando que agora abrimos sabado ate as 20h,
   com uma legenda no meu tom - descontraido, sem parecer propaganda de banco."
2. **Loja de suplementos:** "Vendo suplementos online, meu cliente e quem treina cedo.
   Monta 10 respostas prontas pras duvidas mais comuns no WhatsApp (prazo de entrega,
   troca, se creatina da pra menor de idade), no tom direto que eu uso."
3. **Advogada autonoma:** "Sou advogada de direito do consumidor. Quero um texto pro
   meu site explicando quando vale a pena processar companhia aerea por voo cancelado,
   em linguagem que um leigo entende, sem juridiques."
4. **Quem esta testando uma ideia:** "Tenho uma ideia de aplicativo pra dividir conta
   de restaurante entre amigos. Me ajuda a testar se ela para em pe: quem e o publico,
   o que ja existe de concorrente e qual seria o primeiro passo barato pra validar."
5. **Agencia pequena:** "Minha agencia atende 3 clientes de gastronomia. Cadastra o
   restaurante [nome] como meu primeiro cliente: cardapio italiano, publico familia,
   Instagram e o canal principal. Primeira tarefa: o calendario de posts da semana."

Repare no padrao: quem e voce + pra quem e + o que precisa ficar pronto. E so isso.

## Atualizar (nesta fase beta)

O botao `atualizar-alia.bat` avisa quando a atualizacao automatica nao esta disponivel.
Na fase beta funciona assim: quando houver versao nova, voce recebe um novo pacote -
descompacte POR CIMA da mesma pasta. Seus dados (a pasta `studio/`, seus clientes,
sua memoria) nao sao tocados: a atualizacao troca so o motor.

## Seguranca e privacidade (o que e honesto voce saber)

- Tudo que a Alia guarda (clientes, memoria, tarefas) fica **na sua maquina**, nessa
  pasta - nao existe servidor nosso recebendo seus dados.
- O que voce conversa passa pelo Claude (Anthropic), como em qualquer uso do Claude.
- O pacote e leve (menos de 1 MB) e nao instala nada no Windows: e uma pasta de
  arquivos abertos que voce pode ler, mover ou apagar.

## Voce e beta tester: o que vale ouro reportar

Manda print + o que voce tinha pedido quando:

1. A Alia falar dificil (termo tecnico, resposta que sua mae nao entenderia).
2. Ela te devolver algo cru, generico ou fora do seu tom.
3. Ela esquecer algo que voce ja tinha explicado antes.
4. Qualquer coisa travar, dar erro ou parecer que "sumiu".
5. O momento em que voce pensou "nao sei o que fazer agora" - esse e o mais valioso.

Bom trabalho. E lembra: voce diz o resultado, a Alia corre atras.
