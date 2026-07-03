# Validated Artifacts

> O Quality Gate valida o CONTRATO do entregavel, nao so se "parece ok". Versao propria da validacao
> por schema do legado, generalizada para qualquer tipo de Artifact. Roda como [Frugal
> Skill](frugal-skills.md) (script, sem LLM) - robusta e barata. Contrato maquinavel em
> [validated-artifacts.yaml](validated-artifacts.yaml).

---

## O que e

Cada tipo de Artifact (um JSON, um componente, um texto de copy, uma migracao) tem um CONTRATO: o
formato e as regras estruturais que ele DEVE cumprir pra existir como aquele tipo. A validacao confere
o entregavel contra esse contrato de forma deterministica, antes que qualquer modelo gaste token
avaliando conteudo. E o filtro de formato que protege o filtro de julgamento.

## Como funciona

1. O tipo de Artifact aponta um contrato (schema ou checklist de formato).
2. No Quality Gate, a Frugal Skill `validate-artifact` confere o entregavel contra o contrato - script,
   custo zero de token.
3. Falhou o contrato -> Fail automatico, com o desvio exato apontado (campo faltante, formato errado).
4. Passou -> segue pra revisao de CONTEUDO (o julgamento que so um Specialist faz).

A validacao de formato e barata e binaria; a de conteudo e cara e subjetiva. Rodar a barata primeiro
evita pagar um modelo pra reprovar uma virgula.

## Por que importa

- **Frugalidade**: pega erro de FORMATO sem acionar um modelo caro pra isso.
- **Foco do Specialist**: o LLM gasta julgamento na qualidade do conteudo, nao em checar estrutura.
- **Robustez**: nada quebrado por formato passa do Gate - o Fail e automatico e aponta o desvio.

## Relacao com os 4 criterios do Gate

Validated Artifacts e a porta deterministica do criterio Funciona ([quality-gate](../governance/quality-gate.md)):
se a estrutura nao bate o contrato, o entregavel nao funciona como aquele tipo, e o Gate reprova antes
de gastar token em revisao de conteudo, DDD ou rastreabilidade.

## Diferenca frente ao legado

| Eixo | Legado | Alia Flow |
|------|--------|-----------|
| Escopo | JSON Schema preso aos templates de task (infra de service) | Contrato pra QUALQUER tipo de Artifact, parte do Gate de toda entrega |
| Execucao | Validacao embutida na plataforma | Frugal Skill explicita (script, custo zero de token) |
| Resultado | Aprovacao implicita | Fail automatico com o desvio apontado - evidencia auditavel |

## Liga com

[Quality Gate](../governance/quality-gate.md) (onde a validacao roda e o contrato vive em
[quality-gate.yaml](../governance/quality-gate.yaml)), [Frugal Skills](frugal-skills.md) (a skill
`validate-artifact` que executa).
