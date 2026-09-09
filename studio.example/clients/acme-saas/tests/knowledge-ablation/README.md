# Ablacao de conhecimento - o que este teste E e o que ele NAO E

>

## O que existe aqui hoje

- `test.yaml` - a especificacao (pergunta, 5 palavras-chave, limiar).
- `out-blind.md` e `out-informed.md` - duas saidas ESCRITAS A MAO em 14/jun/2026, simulando o que
 seria uma resposta sem e com o segundo cerebro do squad carregado.
- `score.py` - conta quantas das 5 palavras-chave aparecem em cada saida e compara com o limiar.
- `RESULT.md` - o registro do ultimo `python score.py` (VERDICT: PASS).

## Por que isto NAO e uma prova de ablacao de verdade

`out-informed.md` foi escrito ja contendo as 5 palavras-chave; `out-blind.md` foi escrito sem
nenhuma. O placar 0/5 vs 5/5 e uma consequencia de COMO os arquivos foram escritos, nao de um
experimento em que um agente real respondeu duas vezes (uma sem acesso ao segundo cerebro, outra
com). Rodar `score.py` de novo sempre da o mesmo resultado, porque as entradas sao fixas - isso
prova que o scorer funciona, nao que o segundo cerebro muda a saida de um agente.

Por isso `docs/CLAIMS.md` e `docs/product/PRD.md` (secao 16, item 1) descrevem isto como
demonstracao ILUSTRATIVA, nao como prova, e nao pode ser anunciado como "prova de ablacao" em
peca publica ate virar um experimento de verdade.

## O que um experimento de verdade exigiria

1. Rodar o MESMO especialista (mesmo squad, mesmo prompt de tarefa) duas vezes de verdade:
 - uma vez SEM acesso ao segundo cerebro (knowledge/ removido ou vazio da sessao);
 - uma vez COM o segundo cerebro carregado normalmente.
2. Gravar as duas saidas GERADAS NA HORA (nao escritas a mao) como `out-blind.md` e
 `out-informed.md` - idealmente com timestamp e hash do prompt usado, pra provar que vieram de
 uma execucao real.
3. Repetir os dois bracos em regeneracao (nao reusar a mesma saida gravada indefinidamente) sempre
 que o squad, o segundo cerebro ou o modelo mudar - senao o teste volta a ficar tautologico com
 o tempo.
4. Manter `score.py` (ou evoluir pra um scorer mais rico que so contagem de palavra-chave) medindo
 a DIFERENCA entre os dois bracos regenerados, nao entre fixtures congeladas.

Ate essas quatro condicoes existirem, o correto e chamar isto de demonstracao/fixture ilustrativa,
nunca de prova.
