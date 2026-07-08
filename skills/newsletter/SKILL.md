---
name: newsletter
description: Planeja, cria e faz crescer newsletters por email para clientes do operador. Entrega estrategia completa (formato, cadencia, crescimento de lista, engajamento, monetizacao, entregabilidade) e edicoes prontas como Artifact. A Alia dispara quando o Job envolve newsletter, email marketing recorrente ou crescimento de lista de assinantes.
trigger: newsletter, email marketing, lista de emails, assinantes, crescimento de lista, edicao de newsletter, substack, beehiiv, taxa de abertura, monetizar newsletter
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/newsletter
wave: 2
---

# Skill de Crescimento de Newsletter

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa esta skill diretamente.
2. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Sem Task registrada, registre primeiro. Newsletter e trabalho recorrente: cada edicao e uma Task propria.
3. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada. Enviar a newsletter e acao do operador, nunca da skill.
4. Grounding bloqueante: todo numero e afirmacao de peso cita fonte LIDA como [MEDIDO fonte] ou sai marcado [INFERIDO]. Nunca fabrique metrica de abertura, clique ou receita.
5. Contexto BR: LGPD e o marco legal primario (consentimento, descadastro, base legal do envio). As plataformas citadas neste playbook (Substack, Beehiiv, ConvertKit etc) sao referencia do original, nao exigencia.

Nota de idioma: este arquivo de skill segue a regra do motor (portugues sem acentos, sem emojis). O conteudo final entregue ao cliente - as edicoes da newsletter - PODE e DEVE usar acentuacao normal do portugues.

Voce e um estrategista de crescimento de newsletter. Ajude a planejar conteudo, crescer a base de assinantes, melhorar engajamento e monetizar.

## Fundamentos de Newsletter

### Linhas de Assunto

**Formulas que funcionam:**

| Formula | Exemplo | Impacto na abertura |
|---------|---------|---------------------|
| Numero + Beneficio | "7 ferramentas que me pouparam 10h/semana" | Alto |
| Pergunta | "Voce esta cometendo este erro de SEO?" | Alto |
| Como fazer + Especifico | "Como cheguei a 10 mil assinantes em 6 meses" | Alto |
| Lacuna de curiosidade | "A estrategia de que ninguem fala" | Medio-alto |
| Noticia/Urgencia | "Urgente: o Google acabou de mudar isso" | Medio |
| Pessoal/Historia | "Quase desisti semana passada" | Medio |
| Lista/Resumo | "Esta semana: 5 links que valem seu tempo" | Medio |

**Regras:**
- 30-50 caracteres e o ideal (amigavel para mobile)
- O preview text e igualmente importante - estenda a linha de assunto, nao a repita
- Tokens de personalizacao ({first_name}) elevam abertura em 5-10%
- Evite gatilhos de spam: GRATIS, URGENTE, CAIXA ALTA, pontuacao excessiva
- Faca teste A/B de assunto em todo envio

### Estrutura de Conteudo

**Os 3 arquetipos de newsletter:**

1. **Curada** - Links + comentario (ex.: TLDR, Morning Brew, The News no BR)
   - 5-10 links com 2-3 frases de comentario cada
   - Mais rapida de produzir, exige boas fontes
   - Melhor para: noticias, atualizacoes do setor, tendencias

2. **Original** - Ensaio/artigo unico (ex.: Lenny's Newsletter, Stratechery)
   - 1.000-2.500 palavras de analise original
   - Maior construcao de autoridade, maior esforco
   - Melhor para: lideranca de pensamento, versao premium/paga

3. **Hibrida** - Intro original + links curados (a mais comum)
   - Secao original de 200-500 palavras + 3-5 links curados
   - Bom equilibrio entre esforco e valor
   - Melhor para: a maioria das newsletters em inicio

### Frequencia

| Frequencia | Pros | Contras | Melhor para |
|------------|------|---------|-------------|
| Diaria | Cria habito, alto contato | Risco de burnout, churn alto | Noticias, curada |
| 2-3x/semana | Bom equilibrio | Esforco moderado | Curada, hibrida |
| Semanal | Mais sustentavel | Crescimento mais lento | Original, hibrida |
| Quinzenal | Pouco esforco | Facil de esquecer | Premium, texto longo |
| Mensal | Tempo minimo | Engajamento baixo | Atualizacoes de empresa |

**Recomendacao:** comece semanal. So aumente a frequencia quando houver sistema (templates, ferramentas de curadoria ou equipe).

## Estrategias de Crescimento

### Nivel 1: Fundacao (0 -> 1.000 assinantes)

1. **Isca digital (lead magnet)** - Ofereca um recurso gratuito em troca do email
   - Checklist, template, guia rapido, kit de ferramentas, mini-curso
   - Precisa ter valor imediato (nada de "em breve")
   - Onde colocar: landing page, barra lateral do blog, popup de saida
   - Contexto BR: colete consentimento explicito e informe a finalidade do uso do email (LGPD)

2. **Otimizacao da landing page**
   - Proposta de valor clara acima da dobra
   - Prova social (numero de assinantes, depoimentos, "citado em")
   - Mostre uma edicao de exemplo
   - CTA unico, sem distracoes

3. **Cadastro guiado por conteudo**
   - Adicione CTA de newsletter em todo post do blog
   - Crie upgrades de conteudo (bonus em troca do email)
   - Incorpore formularios dentro do conteudo, nao so na barra lateral

4. **Rede pessoal** - Email para contatos, anuncio nas redes sociais, posts em comunidades

### Nivel 2: Crescimento (1.000 -> 10.000)

5. **Programa de indicacao**
   - Recompense assinantes que indicam outros
   - Recompensas por marco: 1 indicacao = conteudo bonus, 5 = acesso exclusivo, 10 = brinde/call
   - Ferramentas: SparkLoop, ReferralHero ou nativo (Beehiiv, ConvertKit) - referencia, use o que a plataforma do cliente oferecer

6. **Promocoes cruzadas**
   - Parceria com newsletters complementares (audiencia parecida, nao concorrente)
   - Troca de recomendacoes: "Se voce gosta desta, vai amar {newsletter parceira}"
   - Promocao cruzada paga: US$ 1-5 por assinante no mercado original [INFERIDO para o BR - validar preco local]

7. **Funil de redes sociais**
   - Poste trechos da newsletter no Twitter/X e LinkedIn com "Assine para mais"
   - Carrossel com previa do conteudo no Instagram
   - Transforme insights da newsletter em threads

8. **Landing pages orientadas a SEO**
   - Crie paginas focadas em palavra-chave que levem ao cadastro
   - Paginas de comparacao "Melhores newsletters de {tema}"
   - Arquive edicoes passadas como posts de blog pesquisaveis

### Nivel 3: Escala (10.000+)

9. **Aquisicao paga** - Anuncios no Facebook/Instagram para a landing page, meta de CPA de US$ 1-5 no mercado original
10. **Participacoes em podcast/video** - Mencione a newsletter como CTA
11. **Sorteios** - Campanhas virais de sorteio (ferramentas de referencia: KingSumo, Gleam); no BR, atencao as regras legais de promocao comercial
12. **Aquisicoes** - Compre newsletters menores do seu nicho

## Engajamento e Retencao

### Metricas-Chave

| Metrica | Bom | Otimo | Acao se abaixo |
|---------|-----|-------|----------------|
| Taxa de abertura | 35-45% | 50%+ | Melhorar assuntos, limpar lista |
| Taxa de clique | 3-5% | 7%+ | CTAs melhores, links mais relevantes |
| Taxa de descadastro | <0,5% | <0,2% | Segmentar, reduzir frequencia |
| Taxa de resposta | 1-2% | 3%+ | Fazer perguntas, ser pessoal |
| Taxa de crescimento | 5-10%/mes | 15%+/mes | Dobrar aposta no melhor canal de aquisicao |

Grounding: ao reportar metricas de uma newsletter real, cada numero sai como [MEDIDO painel da plataforma] ou nao sai. Estes benchmarks sao referencia do playbook original.

### Campanha de Reengajamento

Para assinantes sem abertura ha 60+ dias:

```
Email 1 (Dia 0): "Ainda tem interesse em {tema}? Veja o que voce perdeu"
  -> Compartilhe as 3 melhores edicoes recentes

Email 2 (Dia 7): "Devo remover voce da lista?"
  -> Pedido direto: clique para ficar, ou removeremos seu cadastro

Email 3 (Dia 14): "Ultima chance - estamos limpando a lista"
  -> Aviso final, depois remova quem nao abriu
```

### Sequencia de Boas-Vindas

```
Email 1 (Imediato): Boas-vindas + entrega da isca digital + "o que esperar"
Email 2 (Dia 2): Sua historia + melhor edicao de todas (mostre o valor)
Email 3 (Dia 5): "Responda e me conte..." (construa relacionamento)
Email 4 (Dia 7): Prova social + pedido de indicacao
```

## Monetizacao

| Modelo | Quando comecar | Potencial de receita |
|--------|----------------|----------------------|
| Patrocinios | 1.000+ assinantes | US$ 25-50 CPM |
| Assinaturas pagas | 5.000+ assinantes gratuitos | US$ 5-20/mes |
| Links de afiliado | Qualquer tamanho | 5-15% dos cliques convertem |
| Produtos digitais | 2.000+ assinantes | US$ 10-500 por produto |
| Consultoria/servicos | Qualquer tamanho | Varia |
| Cursos | 5.000+ assinantes | US$ 50-500 por aluno |

Valores em dolar sao do mercado original [INFERIDO para o BR - ajustar ao nicho e moeda local antes de prometer receita a um cliente].

### Tabela de Precos de Patrocinio

```
CPM = (Preco do patrocinio / Assinantes) x 1.000

Medias do setor (mercado original):
- Geral/consumidor: US$ 15-25 CPM
- Negocios/marketing: US$ 25-50 CPM
- Desenvolvedor/tecnico: US$ 30-60 CPM
- Financas/investimentos: US$ 40-80 CPM
- Executivo/C-level: US$ 50-100 CPM
```

## Entregabilidade

### Setup Tecnico Obrigatorio

| Item | Por que |
|------|---------|
| Registro SPF | Prova que voce esta autorizado a enviar pelo dominio |
| Assinatura DKIM | Assinatura criptografica que impede spoofing |
| Politica DMARC | Diz aos receptores o que fazer com falha de autenticacao |
| Dominio de envio proprio | Evita problemas de reputacao de IP compartilhado |
| Aposentar inativos | Remova quem nao abre ha 90 dias |

### Evitar Filtros de Spam

- Mantenha proporcao texto-imagem (80% texto, 20% imagens)
- Inclua link de descadastro (exigido por lei; no BR, a LGPD exige facilidade de revogacao do consentimento)
- Use um endereco de resposta real
- Nao use encurtadores de URL (bit.ly aciona filtros de spam)
- Aqueca dominios de envio novos gradualmente

## Formato de Saida

Ao criar uma estrategia de newsletter, entregue como Artifact:

```markdown
# Estrategia de Newsletter: {Nome da Newsletter}

## Conceito
- **Nicho:** {tema/audiencia}
- **Formato:** {curada/original/hibrida}
- **Frequencia:** {diaria/semanal/quinzenal}
- **Proposta de valor:** {1-2 frases - por que assinar?}

## Plano de Crescimento

### Mes 1: Fundacao
{Acoes especificas}

### Mes 2-3: Crescimento Inicial
{Acoes especificas}

### Mes 4-6: Escala
{Acoes especificas}

## Template de Conteudo
{Template/estrutura da edicao}

## Roteiro de Monetizacao
{Linha do tempo dos marcos de monetizacao}
```

## Notas Importantes

- Consistencia importa mais que frequencia. Uma newsletter semanal confiavel vence uma diaria erratica.
- Sempre envie em nome de uma pessoa real, nao de uma empresa (abertura maior).
- A resposta e a metrica mais subestimada. Faca perguntas. Leia e responda as respostas.
- Limpe a lista trimestralmente. Uma lista de 5.000 com 50% de abertura vale mais que uma de 20.000 com 15%.
- Tenha sempre um link "Por que estou recebendo isto?" para assinantes novos que esqueceram do cadastro.
