# SLICE.md - fatiar tarefa grande (TASK-812, Shopify 02)

`slice.py` e puro, so stdlib, nao importa lib/ nem a entidade Task (Warden mexe nelas agora).
3 funcoes: `is_tarefa_grande(brief)` (motivos: frentes > 1, modulos_tocados > 2 - mesmo limiar
de risk.py, ou oracao separada por ";" no objetivo/exemplo_falha), `fatiar(brief)` (lista de
fatias em ordem; Task pequena devolve 1 fatia so) e `pode_comecar_fatia(indice, veredito_anterior)`
(regra 3: so True no indice 0, ou se o veredito da fatia anterior foi PASS).

Provado contra os 12 casos de `cases.json` em `test_slice.py`: TASK-577 e TASK-603 (2+ frentes)
saem grandes, os outros 10 pequenos; mais prova negativa (TASK-717, "e" solto no exemplo_falha
NAO fatia) e positiva (";" de verdade fatia).

## Onde o Warden chama isto

1. `task open` (hoje em `bin/task.py`, ou onde a entidade Task absorveu isso): depois de calcular
   risco/modo e ANTES de salvar a Task nova, chamar `slice.is_tarefa_grande(brief)`. Se `grande`,
   `task open` recusa abrir 1 Task so - exige `slice.fatiar(brief)` e abre 1 Task por fatia, cada
   uma com o `criterio_aceite` proprio da fatia (nunca o do brief original inteiro).
2. `bin/brief.py`, `cmd_open`: antes de montar o brief de uma fatia que nao e a primeira, chamar
   `slice.pode_comecar_fatia(indice, veredito_fatia_anterior)`. `False` recusa o `open` com
   `_err("fatia anterior sem PASS ainda")` - mesmo padrao de recusa que a fatia de leitura ja usa.
