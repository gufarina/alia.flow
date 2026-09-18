# Loop Plan - Acme SaaS (raciocinio do Loop Designer)

> Raciocinio da Alia (Loop Designer) ao selecionar os loops do projeto a partir do
> catalogo engine/governance/loops.catalog.yaml.

## Decisao
O projeto e novo e precisa de sinal de saude e de RSI desde o inicio.

## Loops selecionados
- health-check (diario): confirma que o projeto esta vivo e consistente.
- ddd-drift-scan (diario): mede drift contra a linguagem ubiqua do Client.
- deep-research (diario): sustenta a promessa de RSI, atualiza o segundo cerebro.
- debt-scan (semanal): cobra Concerns abertos.

## Frugalidade
Loops de cadencia diaria sao de custo baixo a medio. Nenhum loop caro foi ligado.
Cada loop consulta a Memory antes de reprocessar.