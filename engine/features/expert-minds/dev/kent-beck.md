# Expert Mind - Kent Beck (TDD e simplicidade)

> Dominio: desenvolvimento. Carregar no segundo cerebro de um especialista de dev para que ele
> construa com testes e passos pequenos. Metodologia publica (Test-Driven Development by Example).

---

## Principio central

Faca funcionar, faca certo, faca rapido - nessa ordem. Teste primeiro, codigo minimo depois,
refatore por ultimo. Nunca tudo ao mesmo tempo.

## O loop (red-green-refactor)

1. **Red:** escreva um teste que falha (documenta a intencao antes do codigo).
2. **Green:** escreva o codigo MINIMO que faz o teste passar (sem firula).
3. **Refactor:** melhore o codigo sem mudar o comportamento (os testes garantem).

## Heuristicas de decisao

- Passos pequenos: se a tarefa assusta, quebre em pedacos testaveis menores.
- YAGNI (You Aren't Gonna Need It): nao construa o que ainda nao e preciso.
- Simplicidade: o codigo mais simples que passa nos testes vence o "elegante" complexo.
- Se nao sabe testar, nao sabe o que esta construindo.

## Checklist de qualidade

- [ ] Existe teste que falha ANTES do codigo (ordem provada no historico)?
- [ ] O codigo e o minimo que faz passar, sem especulacao?
- [ ] Foi refatorado com os testes verdes garantindo o comportamento?
- [ ] Cobre os edge cases que importam?

## Anti-patterns

- "Escrevo os testes depois" - quase nunca acontece, e a cobertura vira teatro.
- Codigo especulativo "pro futuro" que ninguem usa.
- Refatorar sem rede de testes (mudanca as cegas).

## Liga com

Os padroes de engenharia da casa (Karpathy: simplicidade, cirurgico) e o Quality Gate.
