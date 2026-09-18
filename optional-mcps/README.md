# optional-mcps - Catalogo curado de MCP (presenca = aprovacao)

> A forma curada de DECLARAR quais servidores MCP o Studio pode usar. Cada MCP vira um diretorio com
> um `manifest.yaml`. A regra de governanca e simples: estar neste diretorio = aprovado para uso
> (presenca = aprovacao), espelhando o ciclo proposed/active da provenance. A gerencia de MCP e
> exclusiva do DevOps; este catalogo e a fonte que o DevOps cura.

---

## Por que existe

A doutrina de ferramentas e "nativa primeiro, MCP so quando a nativa nao cobre" - navegador, banco,
API externa, web search ([engine/tools.md](../engine/tools.md), secao Prioridade de ferramentas). E a
gerencia de MCP (instalar, configurar, remover) e EXCLUSIVA do DevOps; os demais agentes apenas
consomem o que esta provisionado (engine/tools.md, secao Governanca de MCP; devops.yaml: `mcp_manage`).

Faltava, porem, um lugar onde os MCP aprovados sejam DECLARADOS de forma curada e legivel por maquina.
Sem isso, a declaracao de MCP fica solta. Este catalogo resolve: um diretorio por servidor, com um
manifesto verificavel.

## A convencao

- Cada MCP e um diretorio: `optional-mcps/{nome}/`.
- Dentro, um unico arquivo obrigatorio: `manifest.yaml`.
- O nome do diretorio e o id curto e estavel do servidor (minusculas, hifens; ASCII puro).

```
optional-mcps/
  README.md            (este arquivo)
  context7/
    manifest.yaml      (1 manifesto de exemplo)
  {outro-mcp}/
    manifest.yaml
```

### Presenca = aprovacao

Estar neste diretorio = aprovado para uso. E o mesmo principio do ciclo de vida da provenance
([engine/governance/provenance.md](../engine/governance/provenance.md)): o ciclo proposed -> active
-> retired. Aqui:

- diretorio PRESENTE no catalogo = `active` (aprovado, o instalador pode mesclar na config de MCP);
- remover/arquivar o diretorio = retirar a aprovacao (nunca deletar a esmo - arquivar, no espirito do
  "nunca deletar, so arquivar" da provenance);
- quem move o diretorio para dentro/fora e o DevOps. Os consumidores nao tocam o catalogo.

Quem aprova e o operador via DevOps - colocar o diretorio aqui E o ato de aprovacao registrado, igual
"presenca no diretorio espelha proposed/active".

## Os campos do manifest.yaml

Contrato minimo de cada `manifest.yaml`:

| Campo | Obrigatorio | O que e |
|-------|-------------|---------|
| `nome` | sim | id curto e estavel do servidor (igual ao nome do diretorio) |
| `transport` | sim | `stdio` ou `http` - como o cliente fala com o servidor |
| `command` | se stdio | o executavel + args que sobem o servidor local (stdio) |
| `url` | se http | o endpoint do servidor remoto (http) |
| `tools` | sim | lista das tools que o servidor expoe, cada uma com `default_enabled: true|false` |
| `approval` | sim | a nota de governanca: "presenca = aprovacao" (estar no diretorio = aprovado) |

Regra de transport: stdio EXIGE `command` (e proibe `url`); http EXIGE `url` (e proibe `command`).
`default_enabled` por tool deixa o catalogo declarar a allow-list fina: liga so o que o squad precisa,
o resto entra desligado e o DevOps habilita sob demanda.

## Como um instalador mesclaria isso na config de MCP

NAO ha instalador a implementar agora - so a convencao e o ponto de integracao. Quando existir, ele
segue o mesmo padrao de qualquer script determinista do motor: le o manifesto e gera a config num
passo, dry-run por padrao (flag explicita para gravar de verdade):

1. Varrer `optional-mcps/*/manifest.yaml` (presenca = candidato aprovado).
2. Para cada manifesto: validar o contrato (campos acima; coerencia transport <-> command/url).
3. Montar a entrada de MCP a partir do manifesto:
   - `transport: stdio` -> entrada com `command` (+ args);
   - `transport: http` -> entrada com `url`;
   - filtrar as `tools` por `default_enabled: true` para a allow-list inicial.
4. MESCLAR na config de MCP do cliente (ex: `.mcp.json`), de forma ADITIVA e IDEMPOTENTE:
   - servidor ja presente na config -> atualizar (mesma chave, sem duplicar);
   - servidor no catalogo mas fora da config -> adicionar;
   - servidor na config mas SEM diretorio no catalogo -> sinalizar (perdeu a aprovacao);
   - nunca apagar entradas alheias a esmo: o merge e aditivo, nao destrutivo.
5. Dry-run por padrao (so mostra o diff de config); flag explicita para gravar de verdade.

Ponto de integracao: o produto ainda nao tem `.mcp.json` versionado, entao o merge parte do zero. O
instalador, quando vier, e quem materializa a config; o catalogo e a fonte de verdade curada que ele
le. A gerencia continua exclusiva do DevOps (engine/tools.md, Governanca de MCP).

## Liga com

[engine/tools.md](../engine/tools.md) (Prioridade de ferramentas + Governanca de MCP) -
[engine/governance/provenance.md](../engine/governance/provenance.md) (presenca = aprovacao espelha
proposed/active) - o padrao "le manifesto, gera config, dry-run por padrao" que o merge imita.
