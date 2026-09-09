# Biblioteca de Squads (presets + segundo cerebro em camadas)

> A estante da qual o Squad Creator MONTA, em vez de inventar do zero. O Alia Flow nao chega em
> branco: chega com presets testados e Expert Minds prontos. Mantem o comportamento do legado
> (identificar tema/assunto e criar os especialistas) e ADICIONA o que e nosso: o segundo cerebro
> aplicado EM CAMADAS - o lider sempre tem, nem todo agente precisa.

---

## O que o Squad Creator faz (comportamento + a diferenca do Alia Flow)

Herdado do legado (mantido):

1. **Le a atuacao** do Operator - texto livre ("sou de marketing, faco gestao de trafego e
   conteudo") OU um preset escolhido.
2. **Identifica o tema/assunto** e mapeia os dominios/especialistas necessarios.
3. **Cria os Specialists** desses dominios.

A diferenca do Alia Flow (o que adicionamos):

4. **Casa com o preset** mais proximo desta biblioteca e instancia em cima dele, customizando pra
   atuacao descrita - nao monta a estrutura do zero a cada Client.
5. **Anexa o segundo cerebro EM CAMADAS** (regra abaixo): alimenta quem decide, sem inchar quem
   apenas executa.
6. Nomeia o Gateway (Squad Owner), escreve `squad.yaml`, registra Client e Squad no estado, e
   devolve a bola pra Alia rodar o [Loop Designer](../loop-designer.md).

> Dois modos de entrada: **selecionar um preset** OU **descrever a atuacao em texto livre**. No texto
> livre, o Squad Creator mapeia pro preset mais proximo e ajusta (ex: "marketing com foco em
> trafego" -> preset marketing, reforcando o Specialist de trafego e subindo o Analista de Dados).

## A regra do segundo cerebro EM CAMADAS (o coracao)

Segundo cerebro custa contexto e manutencao. Ele escala com a necessidade de **julgamento profundo**
do papel - nao se da cerebro pesado a todo mundo (Frugality Without Quality Loss). A ablacao provou
que o segundo cerebro muda a saida de forma medivel; por isso quem decide nunca pode ficar cego, e
quem so executa nao precisa carregar peso.

| Camada | Quem | Segundo cerebro | `brain:` |
|--------|------|-----------------|----------|
| **A - Lider / Gateway** | Squad Owner; lideres de Client/time | **COMPLETO e SEMPRE**: knowledge do Client + bounded contexts (DDD) + decisoes passadas. Quem governa e bate o Gate precisa do contexto inteiro. | `full` |
| **B - Specialist de dominio** | papeis que exigem julgamento especializado (copy, design, dev, trafego, dados...) | **Expert Mind** (metodo de um mestre) + a fatia de knowledge relevante ao seu dominio. | `expert` |
| **C - Suporte / execucao** | papeis genericos ou operacionais | **LEVE**: referencia o knowledge compartilhado do Squad quando precisa; sem cerebro dedicado. | `light` |

Principio: **o lider sempre tem segundo cerebro; o Specialist tem quando o dominio pede; o suporte
nao tem dedicado.** Isso mantem o Squad conciso e barato sem deixar quem decide no escuro.

> Por que o lider e inegociavel: a ablacao mostrou que cegar o lider degrada toda a cadeia de
> decisao. Specialists de dominio ganham um Expert Mind porque o metodo do mestre eleva o output de
> forma medivel (provado: copy 48 -> 100 com o Expert Mind do Ogilvy).

## Anatomia de um preset (o schema)

Cada arquivo em `presets/` (ou os moldes neste diretorio) define:

```
preset: <nome>
dominio: <setor/atuacao>
gateway: <papel do lider>            # Camada A - segundo cerebro COMPLETO
papeis:
  - papel: <nome>
    camada: A | B | C
    expert_mind: <id do registry ou vazio>   # id em expert-minds/registry.yaml; so em A/B
    brain: full | expert | light             # full=A, expert=B, light=C
knowledge_skeleton:                  # o que popular no segundo cerebro do Client
  - client-brief
  - <dominio>-frameworks
  - ...
ajustes_tipicos: <como customizar pela atuacao descrita>
```

> O campo `expert_mind` referencia um `id` do catalogo em
> [`../expert-minds/registry.yaml`](../expert-minds/registry.yaml). Camada A (lider) e Camada C
> (suporte) deixam o campo vazio - o lider carrega o cerebro completo do Client, o suporte nao
> carrega mente dedicada.

## Presets disponiveis

| Preset | Para quem | Arquivo |
|--------|-----------|---------|
| SaaS / Produto | produto web, app | [saas.md](saas.md) |
| Marketing | trafego, conteudo, growth | [presets/marketing.md](presets/marketing.md) |
| Conteudo / Infoproduto | criadores, cursos, lancamentos | [presets/content-infoproduto.md](presets/content-infoproduto.md) |

> A estante cresce com o uso: preset novo nasce quando um dominio se repete - sempre seguindo o
> schema acima e a regra de camadas. Indice legivel por maquina em
> [`library.yaml`](library.yaml), que o Squad Creator consulta pra listar presets e validar camadas.

## Expert Minds disponiveis

Metodos de mestres, publicos e documentados, carregaveis no segundo cerebro de um Specialist
(Camada B). O catalogo vive em [`../expert-minds.md`](../expert-minds.md), com indice em
[`../expert-minds/registry.yaml`](../expert-minds/registry.yaml):

| Dominio | Mestre | Quando usar |
|---------|--------|-------------|
| copy | Ogilvy | copy de venda, landing, email |
| ads | Eugene Schwartz | anuncio e lancamento por estagio de mercado |
| design | Brad Frost | UI, design system, componentizacao |
| dev | Kent Beck | implementacao com TDD |
| growth | Sean Ellis | aquisicao, retencao, experimentos |
| analytics | Avinash Kaushik | leitura de dados de marketing por segmento |

O Squad Creator escolhe o(s) Expert Mind(s) do dominio ao montar cada Specialist de Camada B.

## Liga com

[Squad Creator](../../agents/squad-creator.md) (quem usa esta biblioteca) - 
[Sistema de Squads](../../squad-system.md) (a anatomia) - 
[Expert Minds](../expert-minds.md) (os metodos de mestre).
