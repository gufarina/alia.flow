# Examples-driven Development + Formato Anti-desculpa

> Antes de criar, olhe o que ja virou padrao-ouro. Esta convencao da um lugar concreto ao
> REUSE do IDS (o "registro" do que ja existe vira a pasta examples/ por squad) e um formato
> padrao para rebater a desculpa que mais fura o REUSE First: "nao tinha exemplo, criei do zero".
>

---

## A tese

O IDS manda REUSE > ADAPT > CREATE ([engineering.md](../engineering.md), tabela linhas 23-34):
"Antes de criar, consulte o registro do que ja existe". Mas o "registro" precisava de um endereco
fisico por squad. Examples padrao-ouro sao esse endereco: artefatos exemplares que viram template,
guardados onde o Specialist os encontra antes de criar. Sem examples/ declarado, o REUSE vira boa
intencao; com examples/, vira o primeiro passo verificavel de toda Task de criacao.

## Examples padrao-ouro (o que sao)

Um example padrao-ouro e um snippet ou artefato exemplar - uma landing copy que converteu, uma
story bem formada com Given/When/Then, um Gate modelo - que o squad elege como referencia a copiar.
Nao e qualquer entrega antiga: e a que o squad marcou como digna de virar template.

Tres marcas de um padrao-ouro:

- Tem cabecalho curto dizendo POR QUE e padrao-ouro (o que ele resolve bem).
- E auto-contido: da pra reusar sem ler o Project inteiro de onde nasceu.
- Carrega o metodo (Expert Mind, principio) que o tornou bom, para o reuso herdar o motivo.

## Onde a pasta vive

Ao lado do segundo cerebro do squad ([squad-system.md](../squad-system.md), linhas 54-65):

```
studio/clients/{id}/squad/knowledge/examples/
  README.md                 # indice + bloco anti-desculpa de amostra
  {dominio}-{nome}.md       # 1 example padrao-ouro (cabecalho diz por que e ouro)
  ...
```

A pasta examples/ e `agent-authored` por estar em `studio/`
([provenance.md](../governance/provenance.md), linhas 81-88): a automacao pode propor novos
examples via diff; nunca deleta, so arquiva em `_retired/`.

## Como liga ao IDS REUSE > ADAPT > CREATE

A pasta examples/ e a primeira parada do Frugality Check de criacao. A regra do fit do IDS
(engineering.md:27-31) decide a rota DEPOIS de consultar examples/:

| Rota | Fit do example mais proximo | O que fazer |
|------|-----------------------------|-------------|
| Reuse | >= 90% | Usar o example direto como base, sem copia cega. |
| Adapt | 60-89% | Estender o example com mudanca <= 30%, documentar o delta. |
| Create | < 60% | Justificar (nada na examples/ servia) e registrar o novo como candidato a padrao-ouro. |

Invariante: consultar `knowledge/examples/` ANTES de criar nao e opcional. Criar sem checar fura
o REUSE First e e o anti-pattern mais caro do IDS (engineering.md:32-34).

## O formato anti-desculpa (anti-rationalization)

Toda rule ou skill pode carregar um bloco "Desculpa -> Rebatida": a desculpa que o agente diria
para pular o REUSE, e a rebatida que o devolve ao trilho. E o mesmo espirito das secoes
"O que eu nunca faco" ([agents/persona.md](../agents/persona.md), linhas 60-69) e "Anti-patterns"
([rsi/rsi.md](../rsi/rsi.md), linhas 101-106): nomear o erro comum antes que ele aconteca.

### Template reutilizavel

```
Desculpa: <a racionalizacao que justifica pular o passo certo>
Rebatida: <o passo certo + por que a desculpa fura a regra (cite a regra)>
```

### Exemplos concretos

Desculpa: nao ha exemplo, vou criar do zero.
Rebatida: consulte knowledge/examples/ primeiro; criar sem checar fura o REUSE First
(engineering.md:32-34). So Create com fit < 60% registrado.

Desculpa: adaptar o example daria mais trabalho que reescrever.
Rebatida: Adapt com mudanca <= 30% e a rota do IDS para fit 60-89% (engineering.md:30); reescrever
duplica logica e cega a proxima reutilizacao. O trabalho extra e o custo da entropia que voce evita.

Desculpa: este caso e unico, nao vale virar example.
Rebatida: o padrao-ouro nasce de UM caso que ficou bom. Se passou no Gate e e auto-contido, vira
candidato a example - e a forma do REUSE se pagar na proxima Task.

## Liga com

[Engineering / IDS](../engineering.md) (REUSE > ADAPT > CREATE - a pasta examples e o registro) -
[Squad System](../squad-system.md) (knowledge/ - onde examples/ encaixa) -
[Frugal Skills](frugal-skills.md) (reuso de capacidade por script, mesma logica de nao recriar) -
[Provenance](../governance/provenance.md) (examples/ e agent-authored: propor via diff, arquivar nao deletar).
