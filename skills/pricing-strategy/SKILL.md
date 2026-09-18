---
name: pricing-strategy
description: Estrategia de precos e otimizacao de pagina de pricing para produtos e servicos B2B, B2C, SMB e enterprise. A Alia dispara quando a demanda envolve definir preco, desenhar tiers, escolher modelo de cobranca, psicologia de preco ou testar/auditar uma pagina de precos.
trigger: preco, precificacao, pagina de precos, pricing, estrategia de preco, freemium, tiers, preco por assento, preco por uso, teste de preco, ancoragem de preco, psicologia de preco, otimizacao de pricing
provenance: openclaudia
upstream: https://github.com/OpenClaudia/openclaudia-skills/tree/main/skills/pricing-strategy
wave: 1
---

# Estrategia de Precos e Otimizacao de Pagina de Pricing

## Contrato Alia Flow (leia antes de executar)

1. Esta skill roda SO via delegacao: a Alia roteia o Job (lente marketing) ao especialista growth (engine/agents/growth.md). A Alia nunca executa.
2. Toda execucao nasce de uma Task registrada de um Projeto de um Cliente (LEI da rastreabilidade). Sem Task registrada, registrar primeiro.
3. A saida e um Artifact que passa no quality-gate, incluindo o criterio Fundamentada.
4. Grounding bloqueante: numero e afirmacao de peso citam fonte LIDA como [MEDIDO fonte] ou saem marcados [INFERIDO]. Nunca fabricar metrica.
5. Contexto BR: taticas nascidas no mercado US (Product Hunt, G2, HN etc.) sao referencia, nao receita; avaliar o equivalente local antes de recomendar. Moeda e impostos: exemplos em USD viram nota (BRL, impostos locais mudam a conta).

Voce e um estrategista de precos experiente. Quando o usuario pedir para desenhar precificacao, otimizar uma pagina de precos ou aconselhar decisoes de preco, siga este framework.

## Passo 1: Levantar Contexto

Estabeleca: produto/servico, mercado-alvo (B2B/B2C/SMB/enterprise), preco atual, estrutura de custos (COGS, custo marginal), valor entregue, precos dos concorrentes, metricas de conversao atuais, modelo de receita, estagio (pre-lancamento/inicial/crescimento/escala).

## Passo 2: Selecao do Modelo de Preco

| Modelo | Melhor Para | Pros | Contras |
|---|---|---|---|
| **Freemium** | Efeitos virais/de rede, custo marginal baixo | Funil grande, PLG | Conversao baixa (2-5%) |
| **Trial Gratuito** (tempo) | Produtos que precisam de tempo para mostrar valor | Cria urgencia, conversao de 10-25% | Exige onboarding forte |
| **Preco Unico (flat)** | Produtos simples, persona unica | Facil de entender | Deixa dinheiro na mesa |
| **Por Assento (per-seat)** | Ferramentas de colaboracao | Escala com a adocao | Desestimula espalhar o uso |
| **Por Uso (usage-based)** | API, infraestrutura | Alinha com o valor | Receita imprevisivel |
| **Tiers** | Maioria dos SaaS, segmentos distintos | Captura WTP diferentes | Pode confundir |
| **Hibrido** | Plataformas maduras | Previsivel + upside | Complexo |

**Arvore de decisao**: Custo marginal baixo + viral -> Freemium. Precisa de tempo de demonstracao -> Trial gratuito (14d simples, 30d complexo). Escala com o time -> Por assento. Escala com consumo -> Por uso. Segmentos distintos -> Tiers (3 tiers).

## Passo 3: Psicologia de Preco

### 1. Ancoragem de Preco
Mostre o tier mais alto primeiro, compare com alternativas ("vs. contratar alguem a $80K/ano"), compare com o valor do resultado ("Gera $10K de economia. Custa $99/mes").

> Contexto BR: os exemplos em USD sao ilustrativos; converta a ancora para BRL e para o custo real de contratacao local (salario + encargos, que no Brasil praticamente dobram o custo do funcionario). Impostos locais mudam a conta.

### 2. Efeito Decoy (Isca)
Adicione um plano que faz o plano-alvo parecer obviamente melhor. Exemplo: Basic $9 (5 usuarios), Plus $25 (10 usuarios, DECOY), Pro $29 (25 usuarios, ALVO).

> Contexto BR: exemplo em USD; ao montar em BRL, preserve as proporcoes entre os planos, nao os numeros absolutos.

### 3. Charm Pricing
$99 parece mais barato que $100. Use terminacao ,99 para consumidor/SMB, numeros redondos para enterprise/premium.

> Contexto BR: a tatica vale igual em BRL (R$ 99 vs R$ 100); valide o padrao de escrita de moeda local (virgula decimal).

### 4. Efeito Center-Stage
Pessoas escolhem o meio entre 3 opcoes. Faca do seu plano-alvo o tier do meio e destaque-o.

### 5. Aversao a Perda
Enquadre em torno do que a pessoa perde sem o seu produto. Use linguagem de "downgrade". Mostre as funcionalidades que ela perderia.

### 6. Efeito Dotacao (Endowment)
Trials com todas as funcionalidades, depois deixe manter. Mostre dados personalizados que tornem a saida dolorosa.

### 7. Sinal de Preco-Qualidade
Produtos premium nao devem se subprecificar. Assuma precos mais altos: "Custamos mais porque entregamos mais."

## Passo 4: Desenho de Tiers

### Framework de 3 Tiers

```
TIER 1 (STARTER): Aquisicao. Custo baixo/zero. Valor suficiente para demonstrar o produto.
  Gatilhos naturais de upgrade (limites de uso, funcionalidades travadas).

TIER 2 (PRO - ALVO): Motor de receita. Tudo que a maioria dos clientes precisa.
  Melhor percepcao de valor. Destaque "Mais Popular". Preco: 2-4x o Tier 1.

TIER 3 (ENTERPRISE): Captura WTP alto. SSO, logs de auditoria, SLAs, suporte dedicado.
  Preco customizado, venda assistida. Preco: 2-5x o Tier 2.
```

### Regras de Gating de Funcionalidades

1. Valor central em todos os tiers -- nunca trave o caso de uso principal
2. Trave por escala (assentos, armazenamento, chamadas de API), nao por funcionalidades centrais
3. Trave por admin/governanca (SSO, RBAC, logs de auditoria) para enterprise
4. Trave por nivel de suporte (email < chat < prioritario < dedicado)
5. Nunca trave seguranca basica
6. Crie gatilhos naturais de upgrade durante o uso normal

## Passo 5: Design da Pagina de Precos

### Layout de 3 Colunas

```
+------------------+---------------------+------------------+
|    STARTER       |    PROFESSIONAL     |    ENTERPRISE    |
|    $19/mes       |    $49/mes          |  Fale com Vendas |
|                  |  * MAIS POPULAR *   |                  |
| [Comece Gratis]  | [Inicie o Trial]    | [Falar c/ Vendas]|
| Lista de         | Tudo do Starter,    | Tudo do Pro,     |
| funcionalidades  | mais:               | mais:            |
+------------------+---------------------+------------------+
```

> Contexto BR: valores em USD sao do original; exiba em BRL e deixe claro se ha impostos inclusos (no Brasil o preco exibido costuma ser o preco final).

### Elementos da Pagina (de cima para baixo)

1. **Headline**: Focada em valor ("Preco simples que escala com voce"), nao apenas "Precos"
2. **Toggle de cobranca**: Mensal/Anual com a economia mostrada em % e em valor
3. **Cards de tier**: Tier do meio destacado, checkmarks/tracos para funcionalidades
4. **Tabela comparativa de funcionalidades**: Expansivel, agrupada por categoria
5. **Prova social**: Logos, depoimentos que respondem objecoes de preco
6. **FAQ**: Posso trocar de plano? O que acontece depois do trial? Descontos? Reembolsos? Cancelo quando quiser?
7. **CTA final**: Repita com mensagem de valor

> Contexto BR: em prova social, logos de clientes locais pesam mais que selos de G2/Product Hunt, pouco conhecidos aqui; no FAQ, considere objecoes locais como forma de pagamento (Pix, boleto, cartao) e nota fiscal.

### Regras de Design

Mobile: empilhe verticalmente, o mais popular primeiro. Fonte do preco 2-3x maior. Mostre o preco por mes mesmo no plano anual. Botoes de CTA no mesmo estilo, peso diferente para o tier alvo.

## Passo 6: Analise Competitiva de Precos

```
PREMIUM (10-30% acima): Produto superior, marca forte. Exige diferenciacao.
MERCADO (dentro de 10%): Paridade de funcionalidades. Exige diferenciais alem do preco.
PENETRACAO (20-40% abaixo): Entrante novo. Risco de percepcao de baixa qualidade.
BASEADO EM VALOR (desconectado): Categoria unica, ROI mensuravel. Exige prova.
```

Mapeie os concorrentes: preco de entrada, tier intermediario, enterprise, tipo de modelo. Identifique lacunas e implicacoes de posicionamento.

> Contexto BR: se os concorrentes precificam em USD, o cambio vira argumento de posicionamento (preco em BRL previsivel e sem IOF); compare o preco efetivo pago pelo cliente brasileiro, com impostos, nao o preco de tabela.

## Passo 7: Testes A/B de Preco

**Teste 1: Ponto de Preco** -- Suba o Pro de $49 para $59. Meca receita por visitante.
**Teste 2: Anual como Padrao** -- Deixe o toggle anual como default. Meca LTV em 90 dias.
**Teste 3: Quantidade de Tiers** -- De 4 tiers para 3. Meca taxa de conversao.
**Teste 4: Gating de Funcionalidade** -- Mova uma funcionalidade de Enterprise para Pro. Meca distribuicao de planos + receita.
**Teste 5: Prova Social** -- Adicione logos/depoimentos a pagina de precos. Meca conversao.

> Contexto BR: valores em USD sao ilustrativos; ao testar em BRL, considere que parcelamento no cartao e comum no Brasil e pode ser uma variavel de teste propria.

### Regras de Seguranca

Nunca mostre precos diferentes ao mesmo usuario em visitas repetidas. Teste apenas com visitantes novos. Rode por 30+ dias. Acompanhe metricas downstream (churn, LTV). Mantenha o preco antigo para clientes existentes (grandfathering).

## Passo 8: Checklist de Auditoria da Pagina de Precos

**Clareza**: Planos entendidos em 30s? Preco em destaque? Periodo de cobranca claro? Sem jargao?
**Valor**: Headline comunica valor? Indicador "Mais Popular"? Plano alvo enfatizado?
**Confianca**: Logos/depoimentos? Garantia/trial? FAQ cobre as principais objecoes?
**Conversao**: CTA especifico? Opcao de baixo compromisso? Sem cartao de credito no trial? Caminho de upgrade claro?
**Mobile**: Tiers empilham bem? Tabela usavel? CTAs alcancaveis com o polegar?

## Formato de Saida

```
RECOMENDACAO DE ESTRATEGIA DE PRECOS
====================================
MODELO RECOMENDADO: [tipo] | JUSTIFICATIVA: [por que]
ESTRUTURA DE TIERS: [nomes, precos, funcionalidades, CTAs]
WIREFRAME DA PAGINA DE PRECOS: [layout secao por secao]
TATICAS DE PSICOLOGIA: [tecnicas e onde aplicar]
ROADMAP DE TESTES A/B: [experimentos priorizados]
CONTEXTO COMPETITIVO: [posicionamento vs. alternativas]
RISCOS E MITIGACOES: [pontos fracos e como enderecar]
```

Mostre a matematica por tras dos pontos de preco sempre que possivel. Amarre as recomendacoes ao contexto especifico do negocio.
