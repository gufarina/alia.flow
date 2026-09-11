---
name: email-sequence
description: Escreve sequencias de email completas (boas-vindas, carrinho abandonado, reengajamento, lancamento, onboarding) com cadencia, assuntos, corpo e metricas-alvo. A Alia dispara quando um Job de marketing pede campanha de email, drip, nutricao ou fluxo automatizado.
trigger: sequencia de email, drip, nutricao, boas-vindas, carrinho abandonado, reengajamento, lancamento, onboarding, automacao de email, campanha de email
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/email-sequence
wave: 2
---

# Email Sequence

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa esta skill diretamente.
2. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Sem Task registrada, registrar primeiro e so depois executar.
3. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada. ENVIAR email e acao do operador ou de ferramenta aprovada - a skill escreve a sequencia, nao dispara.
4. Grounding bloqueante: todo numero e afirmacao de peso cita fonte LIDA como [MEDIDO fonte] ou sai marcado [INFERIDO]. Nunca fabricar metrica de benchmark ou de performance.
5. Contexto BR: a LGPD e o marco legal primario aqui, substituindo as referencias a CAN-SPAM/GDPR do material original; integracao de envio (Resend etc.) e opcional e a skill roda completa sem ela.

Nota de idioma: Português correto, com acentos. Arquivo salvo em UTF-8 sem BOM; o único erro é caractere corrompido. Emoji continua fora de peça pública. O CONTEUDO final produzido - os emails em si - usa acentuacao normal do portugues, como este proprio arquivo.

## Proposito

Atuar como especialista em email marketing focado em sequencias automatizadas de alta conversao que nutrem prospects, geram vendas e retem clientes. Usar quando o Job pedir drip campaign, fluxo de nutricao, estrategia de emails de ciclo de vida ou sequencia templatada para um cenario de negocio especifico.

## Levantamento de requisitos (8 itens)

Antes de escrever qualquer sequencia, coletar (da Task, do contexto do Cliente/Projeto ou perguntando ao operador):

1. Tipo de sequencia - boas-vindas, carrinho abandonado, reengajamento, lancamento de produto, onboarding ou fluxo customizado.
2. Produto/servico - o que esta sendo vendido ou promovido, para definir posicionamento.
3. Publico-alvo - segmentos, cargos, setores e perfil demografico dos destinatarios.
4. Objetivo primario - converter leads, ativar usuarios, reter clientes, reengajar inativos ou fazer upsell.
5. Identidade do remetente - nome e email do "de" (fundador, marca ou membro do time).
6. Tom de voz - amigavel, profissional, urgente, educativo ou bem-humorado.
7. Provedor de email (ESP) - a plataforma afeta sintaxe de merge tags e suporte a HTML.
8. Dados de performance existentes - taxas de abertura, clique e conversao como baseline. Se nao houver dado LIDO, as metas saem marcadas [INFERIDO].

## Principios universais de email

### Linha de assunto

- Manter entre 30 e 50 caracteres (6 a 10 palavras).
- Colocar a palavra ou beneficio de maior impacto no inicio.
- Minusculas para tom casual; capitalizacao de titulo para tom profissional.
- Nunca escrever o assunto inteiro em CAIXA ALTA (dispara filtro de spam e soa agressivo).
- Personalizacao (primeiro nome) com parcimonia, nao em todo email.
- Testar variantes de assunto em A/B dentro do ESP.

Padroes de formula de assunto:

- Beneficio direto: "Bem-vindo a [Marca] - o que esperar daqui"
- Foco no problema: "O erro numero 1 que [publico] comete"
- Prova social: "Como [Cliente] alcancou [resultado especifico]"
- Orientado a solucao: "O caminho mais rapido para [resultado desejado]"
- Engajamento pessoal: "Pergunta rapida, [Nome]"
- Urgencia/escassez: "[Nome], seu carrinho expira em breve"
- Curiosidade: "Sentimos sua falta, [Nome]"
- Bastidores: "A historia por tras de [Produto]"

### Preview text

- Sempre escrever preview text customizado (40 a 90 caracteres); nunca deixar em branco.
- Complementar o assunto com contexto ou curiosidade, nunca repeti-lo.
- Se ficar vazio, o ESP puxa a primeira linha do corpo, o que costuma parecer amador.

### Estrutura do corpo (4 componentes)

1. Gancho (2 primeiras linhas): conquistar o scroll com pergunta, afirmacao ousada ou referencia personalizada.
2. Corpo (3 a 8 frases): UMA ideia central por email; nao misturar educacao, venda e anuncio.
3. Call-to-action (1 primario): uma unica acao clara, com o link repetido 2 a 3 vezes ao longo do corpo.
4. Linha de P.S. (opcional): segunda secao mais lida; usar para urgencia ou informacao bonus.

### Horarios e cadencia de envio

| Segmento | Melhores dias | Melhores horarios | Racional |
|---|---|---|---|
| B2B/SaaS | Terca a quinta | 9h-11h local | Revisao de inbox no inicio do expediente |
| B2C/Ecommerce | Quinta a sabado | 10h ou 19h-21h local | Mentalidade de compra e navegacao noturna |
| Newsletter | Terca ou quinta | 7h-9h local | Habito de leitura matinal |
| Urgente/venda | Qualquer dia | Ate 1h apos o gatilho | Aproveita o interesse imediato |

### Segmentacao (5 dimensoes)

- Comportamento: paginas visitadas, features ativadas, engajamento com emails (aberturas, cliques).
- Demografia: setor, tamanho da empresa, cargo, localizacao.
- Estagio do ciclo de vida: lead novo, trial, cliente pagante, cliente perdido.
- Nivel de engajamento: ativo (abriu nos ultimos 30 dias) vs inativo (60+ dias sem abrir).
- Origem de trafego: organico, midia paga, indicacao ou evento.

## Templates de sequencia (5 tipos)

### Template 1: Serie de boas-vindas

- Emails: 5. Objetivo: apresentar a marca, construir confianca, gerar a primeira conversao.
- Gatilho: novo cadastro de email ou criacao de conta.
- Cadencia: imediato -> dia 2 -> dia 4 -> dia 7 -> dia 10.

1. Email 1 (imediato): entregar o lead magnet prometido e alinhar expectativas do que vem pela frente.
2. Email 2 (dia 2): educar sobre o problema central que a solucao resolve; construir autoridade.
3. Email 3 (dia 4): historia de sucesso de cliente com resultados especificos (prova social).
4. Email 4 (dia 7): email focado no produto, orientado a beneficio, com demonstracao.
5. Email 5 (dia 10): check-in pessoal oferecendo ajuda e suporte.

### Template 2: Serie de carrinho abandonado

- Emails: 3. Objetivo: recuperar compras abandonadas em ate 48 horas.
- Gatilho: carrinho criado sem checkout concluido (dentro de 1 hora).
- Cadencia: 1 hora -> 24 horas -> 48 horas.

1. Email 1 (1 hora): lembrete amigavel com detalhes do produto, SEM desconto.
2. Email 2 (24 horas): tratar objecoes com prova social e depoimentos.
3. Email 3 (48 horas): urgencia, com incentivo opcional (desconto/bonus).

### Template 3: Serie de reengajamento

- Emails: 4. Objetivo: reconquistar assinantes inativos antes de remover da lista.
- Gatilho: sem aberturas ou cliques em 60 a 90 dias.
- Cadencia: dia 0 -> dia 5 -> dia 10 -> dia 15.

1. Email 1 (dia 0): reconhecer a ausencia e destacar o que ha de novo.
2. Email 2 (dia 5): curadoria do melhor conteudo dos ultimos 90 dias.
3. Email 3 (dia 10): pergunta direta se a pessoa quer continuar recebendo; dar controle de preferencias.
4. Email 4 (dia 15): ultima tentativa, resumir o valor, opcao clara de descadastro.

### Template 4: Serie de lancamento de produto

- Emails: 6. Objetivo: construir antecipacao e converter no dia do lancamento.
- Gatilho: envio manual em cronograma pre-lancamento.
- Cadencia: 2 semanas antes -> 1 semana antes -> 3 dias antes -> dia do lancamento -> dia seguinte -> 3 dias depois.

1. Email 1 (2 semanas antes): provocar o problema e o lancamento; construir lista de espera.
2. Email 2 (1 semana antes): historia do fundador, bastidores da construcao.
3. Email 3 (3 dias antes): sneak peek com demo e depoimentos de beta testers.
4. Email 4 (dia do lancamento): anuncio principal com preco e CTA.
5. Email 5 (dia seguinte): prova social com numeros de adocao inicial.
6. Email 6 (3 dias depois): fechamento por urgencia no prazo da oferta de lancamento.

### Template 5: Serie de onboarding

- Emails: 7. Objetivo: ativar novos usuarios e leva-los ao "momento aha".
- Gatilho: criacao de conta nova ou primeira compra.
- Cadencia: imediato -> dia 1 -> dia 3 -> dia 5 -> dia 7 -> dia 10 -> dia 14.

1. Email 1 (imediato): guia de inicio rapido com UMA acao de valor.
2. Email 2 (dia 1): passo a passo da feature principal com demo visual.
3. Email 3 (dia 3): dica pro sobre uma feature secundaria.
4. Email 4 (dia 5): historia real de caso de uso de cliente.
5. Email 5 (dia 7): check-in pedindo feedback.
6. Email 6 (dia 10): tres features subutilizadas para explorar.
7. Email 7 (dia 14): email de formatura apontando recursos avancados e caminho de upgrade.

## Copywriting

Regras centrais:

- Uma ideia por email - nao misturar educacao, venda e anuncio no mesmo envio.
- Paragrafos curtos (1 a 3 frases), otimizados para leitura no celular.
- Proporcao 3:1 de "voce" sobre "nos" na linguagem.
- Escrever em nivel de leitura de 5a a 8a serie: palavras curtas, frases curtas.
- Repetir o link do CTA primario 2 a 3 vezes no corpo.
- Reservar o P.S. para urgencia ou informacao secundaria (secao de altissima leitura).

Tipos de gancho de abertura:

- Pergunta: "O que voce faria com 5 horas a mais nesta semana?"
- Afirmacao ousada: "90% das landing pages tem este erro que mata conversao" (numero de exemplo - em uso real, citar fonte ou marcar [INFERIDO])
- Historia: abrir com caso de cliente ou narrativa pessoal.
- Estatistica: dado forte e especifico - sempre com fonte LIDA [MEDIDO fonte].
- Endereco direto: observacao personalizada sobre o comportamento do destinatario.
- Contrarian: "A maior parte dos conselhos de email marketing esta errada. Eis o porque."

## Gatilhos de spam a evitar

No assunto e no corpo:

- Texto em CAIXA ALTA ("GRATIS", "COMPRE AGORA", "CLIQUE AQUI").
- Excesso de exclamacoes (!!!).
- Frases problematicas: "Aja agora", "Tempo limitado", "Voce foi selecionado", "Parabens", "Sem compromisso", "100% gratis", "Clique abaixo", "Caro amigo".
- Formatacao enganosa: prefixos falsos de "Re:" ou "Fwd:" quando nao sao respostas reais.

Estrutura e praticas:

- Layout pesado em imagens com pouco texto (manter proporcao 60/40 texto/imagem).
- Listas compradas: usar SO assinantes com opt-in (exigencia reforcada pela LGPD: base legal de consentimento ou legitimo interesse documentado).
- Mecanismo de descadastro ausente ou escondido - descadastro claro e obrigatorio.

## Boas praticas de HTML de email

- Usar tabelas HTML para layout, nao CSS grid ou flexbox.
- CSS 100% inline; clientes de email removem blocos style externos.
- Largura maxima de 600px para consistencia entre clientes.
- Fontes web-safe (Arial, Helvetica, Georgia, Times New Roman).
- Alt text descritivo em toda imagem (muitos usuarios bloqueiam imagens).
- Testar no minimo em Gmail, Outlook, Apple Mail e Yahoo.
- Design mobile-first; a maioria das aberturas acontece no celular.
- Fornecer versao plain-text junto do HTML para entregabilidade.

## Integracao de envio (opcional - Resend)

Integracao de envio e OPCIONAL. A skill gera o conteudo completo independente de API disponivel; se RESEND_API_KEY nao existir, o conteudo e produzido e entregue como Artifact, sem transmissao. Lembrete do contrato: o disparo real e acao do operador ou de ferramenta previamente aprovada.

- Checar a variavel de ambiente RESEND_API_KEY (no original: ~/.claude/.env.global).
- Envio unitario: POST em https://api.resend.com/emails com bearer token e campos from, to, subject, html; a resposta traz um id de rastreio.
- Envio em lote: POST em https://api.resend.com/emails/batch com array de objetos de email.
- Dominio verificado e obrigatorio (para teste, onboarding@resend.dev funciona sem verificacao).
- Limites de taxa variam por plano.

## Formato de entrega (Artifact)

A sequencia final deve conter:

1. Visao geral - nome, objetivo, condicao de gatilho, segmento-alvo e diagrama de fluxo em texto.
2. Cada email - numero/nome, delay, assunto (principal + 2 variantes A/B), preview text (40-90 caracteres, nao repetitivo), remetente, corpo completo, texto e URL placeholder do CTA, P.S. opcional, logica de ramificacao condicional por engajamento.
3. Regras de segmentacao - criterios de entrada, condicoes de saida, ramificacoes comportamentais.
4. Metricas de sucesso - metas de abertura, clique e conversao por email; se nao houver baseline LIDO, marcar [INFERIDO].
5. Plano de testes A/B - split tests recomendados para 30 dias (assuntos, horarios de envio, variacoes de CTA).

## Contexto legal BR (LGPD)

- A LGPD e o marco primario: coleta com base legal (consentimento ou legitimo interesse documentado), finalidade clara no momento do opt-in, descadastro facil e imediato, e atendimento a pedidos de exclusao de dados do titular.
- Referencias do material original a CAN-SPAM/GDPR valem apenas como contexto para listas fora do Brasil.
