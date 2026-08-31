# Fixture do guard de superficie publica - credencial DEPOIS do placeholder

Arquivo de teste do smoke-test.ps1 (code review adversarial, 31/08/2026). Nao e material
publico e nao documenta nada: existe so para provar, pelo negativo, o furo que foi consertado
em check-public-surface.ps1.

O furo: a cacada de credencial olhava so a PRIMEIRA ocorrencia de cada agulha no arquivo. Um
placeholder antes da chave real - a ordem mais comum que existe, "cole a sua chave no lugar do
exemplo" seguido da chave de verdade esquecida logo abaixo - fazia o arquivo inteiro ser
classificado como mencao, e o guard imprimia SUPERFICIE LIMPA com credencial dentro.

Nenhuma das duas linhas abaixo e uma chave de verdade: as duas tem formato valido de proposito,
e nenhuma delas funciona em lugar nenhum.

PLACEHOLDER (o guard TEM que tratar como mencao, sozinho nao reprova):

    sk-ant-api03-seu_token_aqui_aqui_aqui

FORMATO REAL (o guard TEM que REPROVAR esta, mesmo vindo depois do placeholder acima):

    sk-ant-api03-ZQ8vN2mK4pR7tW1yB6dH3jL5xC9fS0gA

Observacao: quando este arquivo e varrido no proprio lugar onde mora (scripts/fixtures/), o
guard o classifica como mencao pelo CAMINHO - por isso o smoke o copia para uma pasta neutra
antes de rodar a prova. E o mesmo criterio da fixture de vetos (superficie-publica-suja.md):
prova de guard precisa conter o que o guard procura.
