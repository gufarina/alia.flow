## O que muda

Descreva a mudanca em uma ou duas frases. Uma mudanca = um incremento isolavel.

## Por que

A dor ou o motivo. Se fecha uma issue, referencie (`Closes #N`).

## Checklist do contrato de qualidade

- [ ] `VERSION` subida (PATCH / MINOR / MAJOR conforme o tipo de mudanca)
- [ ] Entrada no `CHANGELOG.md` (topo, com o porque)
- [ ] Smoke test ALL GREEN: `powershell -ExecutionPolicy Bypass -File scripts/smoke-test.ps1`
- [ ] Sem acentos/emojis nos arquivos do produto (motor, scripts, docs de produto)
- [ ] Termos novos entraram em `engine/glossary.md` antes de usar no codigo/doutrina

## Tipo

- [ ] Correcao (bug / doc)
- [ ] Feature (retrocompativel)
- [ ] Quebra de contrato (constituicao, glossario, schema) - explique a migracao
