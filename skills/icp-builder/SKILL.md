---
name: icp-builder
description: Constroi perfil de cliente ideal (ICP) e buyer personas com frameworks estruturados de pesquisa de cliente. A Alia dispara quando o Job pede definir publico-alvo, segmentar clientes, criar personas, planejar entrevistas ou pesquisas com clientes.
trigger: perfil de cliente ideal, ICP, buyer persona, persona, publico-alvo, quem e meu cliente, segmentacao de clientes, pesquisa de cliente, entrevista com cliente, quem devo mirar
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/icp-builder
wave: 1
---

# Construtor de Perfil de Cliente Ideal (ICP)

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa.
2. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Sem Task registrada, registrar primeiro.
3. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada.
4. Grounding bloqueante: numero e afirmacao de peso citam fonte LIDA como [MEDIDO fonte] ou saem marcados [INFERIDO]. Nunca fabricar metrica.
5. Contexto BR: taticas nascidas no mercado US (Product Hunt, G2, HN etc.) sao referencia, nao receita; avaliar o equivalente local antes de recomendar.

---

Voce e especialista em pesquisa de clientes e desenvolvimento de personas. Quando a Task pedir definir o cliente ideal, construir personas ou segmentar a audiencia, siga este framework.

## Passo 1: Levantar Contexto

Estabeleca: produto/servico, problema resolvido, clientes atuais (se houver), tipo de mercado (B2B/B2C), faixa de preco, motion de vendas (self-serve/assistida por vendas/enterprise), estagio (pre-lancamento/inicial/crescimento), dados existentes (analytics, CRM, pesquisas), geografia.

## Passo 2: Framework de ICP

### ICP B2B (nivel empresa)

```
FIRMOGRAFICOS
  Setor: [verticais especificas]
  Tamanho (funcionarios): [faixa] | Tamanho (receita): [faixa]
  Estagio de crescimento: [startup/scaleup/enterprise/capital aberto]
  Geografia: [regioes] | Modelo de negocio: [SaaS/e-comm/agencia/etc.]

TECNOGRAFICOS
  Stack de tecnologia: [ferramentas que usam] | Solucao atual: [para este problema]
  Maturidade tecnica: [early adopter/mainstream/retardatario]

GATILHOS SITUACIONAIS (eventos que criam urgencia de compra)
  - [ex.: "Acabou de captar investimento", "Passou de 50 funcionarios"]
  - [ex.: "Contrato atual terminando", "Novo VP contratado"]

CRITERIOS DE QUALIFICACAO
  Obrigatorio: [ex.: "Time de marketing de 3+", "Gasta R$ 50 mil+/mes em anuncios"]
  Desejavel: [ex.: "Ativo em redes sociais"]
  Desqualificante: [ex.: "Pre-receita", "Menos de 10 funcionarios"]
```

> Contexto BR: ajuste faixas de receita e gasto para a realidade brasileira (reais, nao dolares) e considere o porte segundo criterios locais (MEI, ME, EPP, medio, grande) alem da contagem de funcionarios.

### ICP B2C (nivel individuo)

```
DEMOGRAFICOS
  Idade: [faixa] | Renda: [faixa] | Localizacao: [regiao]
  Fase de vida: [estudante/inicio de carreira/pai ou mae/aposentado]

PSICOGRAFICOS
  Valores: [o que importa profundamente para eles]
  Identidade: [como se enxergam]
  Aspiracoes: [o que estao buscando construir]
  Influencias: [quem molda as decisoes deles]

TRACOS COMPORTAMENTAIS
  Plataformas: [redes sociais, busca, foruns]
  Conteudo: [podcasts, newsletters, YouTube]
  Comportamento de compra: [impulso vs. pesquisa intensa]
  Lealdade a marca: [troca facil vs. fiel]
```

> Contexto BR: use classes de renda locais (A/B/C/D-E ou faixas de salario minimo) em vez de brackets US; considere o peso do WhatsApp e do Instagram no comportamento de consumo brasileiro.

## Passo 3: Dores e Objetivos

### Estrutura de Dor

```
Dor: [problema especifico]
  Severidade: [1-10] | Frequencia: [diaria/semanal/mensal]
  Contorno atual: [como lidam com isso hoje]
  Custo da inacao: [o que acontece se nao resolver]
  Impacto emocional: [frustracao/ansiedade/vergonha]
  Citacao: "[frase representativa de cliente]"
```

**Categorias**: Funcional (tarefa e dificil/lenta), Financeira (custa caro demais), Processo (fluxos quebrados), Social (fica mal com chefe/pares), Emocional (estresse/sobrecarga).

### Objetivos

```
Objetivo primario: [resultado #1] | Metrica: [como e medido] | Prazo: [esperado]
Objetivos secundarios: [2-3 resultados adicionais]
Resultado dos sonhos: [se tudo desse perfeitamente certo]
JTBD: "Quando eu [situacao], quero [acao], para poder [resultado]."
```

## Passo 4: Objecoes e Barreiras

```
PRECO: "Nao temos orcamento" -> [framework de resposta + evidencia necessaria]
TIMING: "Nao estamos prontos para trocar" -> [custo de esperar + migracao facil]
CONFIANCA: "Nunca ouvi falar de voces" -> [prova social + garantia]
INERCIA: "A solucao atual funciona" -> [custos ocultos do status quo]
AUTORIDADE: "Preciso de aprovacao do gestor" -> [template de business case]
TECNICA: "Vai integrar?" -> [docs de integracao + suporte]
```

## Passo 5: Mapeamento de Canais

```
| Canal | Relevancia (1-5) | Tipo de conteudo | Custo |
|-------|------------------|------------------|-------|
| Google Search | [nota] | SEO/anuncios | gratis/pago |
| LinkedIn | [nota] | posts/anuncios | gratis/pago |
| Twitter/X | [nota] | threads | gratis |
| Reddit | [nota] | comunidade | gratis |
| Podcasts | [nota] | convidado/patrocinio | gratis/pago |
| YouTube | [nota] | tutoriais | gratis/pago |
| Newsletters | [nota] | patrocinios | pago |

TOP 3 CANAIS: [canal + por que + tatica]
CONTEUDO CONSUMIDO: podcasts, newsletters, influenciadores, comunidades e eventos especificos
```

> Contexto BR: no Brasil, Reddit e Twitter/X tem alcance menor que nos US para muitos publicos; avalie tambem WhatsApp (grupos e comunidades), Instagram, TikTok, YouTube (muito forte no BR), Telegram e comunidades locais (Discord/Slack de nicho, eventos como meetups regionais) antes de fechar o top 3.

## Passo 6: Template de Entrevista com Cliente

Meta de 10-15 entrevistas. Mix: clientes atuais (5-7), churn (2-3), prospects (3-5). Chamadas de 30-45 min.

```
CONTEXTO (5 min)
1. Me conte sobre seu papel e um dia tipico.
2. Maiores desafios em [area relevante]?
3. Como voce lida hoje com [problema]?

PROBLEMA (10 min)
4. Me descreva a ultima vez que [problema ocorreu].
5. Qual foi a parte mais frustrante?
6. Com que frequencia isso aparece?
7. O que acontece se nao for resolvido?
8. O que voce ja tentou antes?

SOLUCAO (10 min)
9. Quais ferramentas voce ja usou?
10. O que voce gosta na sua solucao atual?
11. O que voce mudaria?
12. Como seria a solucao ideal?

COMPRA (10 min)
13. Como voce encontrou sua ferramenta atual?
14. Quem mais participou da decisao?
15. O que faria voce trocar?
16. O que te seguraria?
17. Quanto voce pagaria por [beneficio-chave]?

FECHAMENTO: Mais alguma coisa? Conhece alguem parecido que toparia conversar?
```

### Template de Sintese

```
TEMAS COMUNS: [tema, mencionado por X/n, citacoes-chave]
DESCOBERTAS SURPREENDENTES: [insights inesperados]
PREMISSAS VALIDADAS: [confirmadas]
PREMISSAS INVALIDADAS: [refutadas -- critico]
AJUSTES NO ICP: [mudancas com base nos achados]
```

## Passo 7: Desenho de Pesquisa (Survey)

10-15 perguntas, 5-7 minutos. Use depois das entrevistas para validacao quantitativa.

**Triagem** (2-3 perguntas): papel, tamanho da empresa, eles fazem [atividade relevante]?
**Problema** (3-4 perguntas): frequencia, severidade (1-10), solucao atual, satisfacao (1-10).
**Solucao** (3-4 perguntas): ranking de features, gatilhos de troca, disposicao a pagar.
**Demografia** (2-3 perguntas): setor, orcamento, aberto a follow-up?

Minimo: 100 respostas para leitura quantitativa, 30 para insights direcionais.

> Contexto BR: no Brasil, formularios distribuidos via WhatsApp e grupos de comunidade costumam converter melhor que e-mail frio; pergunte disposicao a pagar em reais e no modelo de cobranca local (mensal, Pix, boleto, cartao).

## Passo 8: Template de Card de Persona

Crie 2-4 personas:

```
PERSONA: [nome, ex.: "Marina do Marketing"]
Papel: [cargo] | Empresa: [tipo] | Idade: [faixa]

BIO: [2-3 frases: vida profissional, desafios, aspiracoes]

OBJETIVOS                 FRUSTRACOES
- [Objetivo 1]            - [Frustracao 1]
- [Objetivo 2]            - [Frustracao 2]
- [Objetivo 3]            - [Frustracao 3]

FERRAMENTAS: [3-5 ferramentas]   CANAIS: [3-5 canais confiaveis]

COMPRA: estilo de pesquisa [sozinho/pares/vendas], velocidade de decisao [rapida/lenta],
        autoridade de orcamento [sim/precisa de aprovacao]

MENSAGEM: Dizer "[o que atrai essa pessoa]" | Nao dizer "[o que afasta]"
Beneficio-chave: [a coisa #1 que importa para ela]
Prova necessaria: [tipo de evidencia que convence]

OBJECAO: "[maior hesitacao]" -> Resposta: "[como enderecar]"
JTBD: "Quando eu [situacao], quero [acao], para poder [resultado]."
CITACAO: "[frase que representa a mentalidade]"
```

## Passo 9: Validacao

### Checklist
- [ ] Baseado em dados (entrevistas, pesquisas, analytics), nao so em suposicoes
- [ ] 10+ clientes/prospects batem com o perfil
- [ ] Clientes dentro do ICP tem LTV maior e churn menor
- [ ] Clientes do ICP sao alcancaveis pelos canais identificados
- [ ] Especifico o bastante para guiar decisoes, sem estreitar demais o mercado
- [ ] Documentado e compartilhado com todos os times que falam com cliente

### Quando Atualizar
A cada 50 novos clientes, apos mudancas de preco, apos features grandes, apos entrada em novo mercado, no minimo trimestralmente.

## Formato de Saida

```
PERFIL DE CLIENTE IDEAL: [Produto]
==================================
RESUMO EXECUTIVO: [2-3 frases]
PERFIL DA EMPRESA/CLIENTE: [detalhes completos]
DORES E OBJETIVOS: [ranqueados com severidade]
BUYER PERSONAS: [2-4 cards de persona]
TRATAMENTO DE OBJECOES: [principais objecoes + respostas]
ESTRATEGIA DE CANAIS: [onde encontra-los]
TEMPLATES DE PESQUISA: [instrumentos de entrevista + survey]
PLANO DE VALIDACAO: [como confirmar e refinar]
```

Fundamente em evidencia. Rotule suposicoes vs. insights validados ([MEDIDO fonte] vs. [INFERIDO], conforme o contrato). Torne acionavel para copy de marketing, segmentacao de anuncios, estrategia de conteudo e prospeccao de vendas.
