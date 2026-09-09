# Integridade do pacote (manifesto SHA256)

Todo pacote do Alia Flow (o que sai de `scripts/package-release.ps1`) traz um
arquivo `MANIFEST.sha256` na raiz. Ele lista o hash SHA256 de cada arquivo do
pacote, uma linha por arquivo:

```
a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447 scripts/doctor.ps1
7ebd9253943ba3a0e5a56cea696b802091218b49747fd5e9fea9604126eef25f README.md
...
```

Isso permite VERIFICAR, depois de baixar ou copiar o pacote, que o conteudo
nao foi corrompido nem alterado desde que foi montado.

## Como verificar

Na raiz da pasta que voce baixou (onde o `MANIFEST.sha256` esta):

```
powershell -File scripts/verify-manifest.ps1 -Dir .
```

Saida esperada quando esta tudo integro:

```
[OK] integridade confirmada: N arquivos
```

Se algo foi alterado, faltando ou adicionado fora do manifesto, o script
reporta exatamente quais arquivos e sai com codigo de erro (exit 1):

```
[FALHA] divergencia encontrada:
 ALTERADOS:
 - scripts/doctor.ps1
 FALTANDO:
 - README.md
 EXTRA (nao listado no manifesto):
 - arquivo-nao-esperado.txt
```

- **ALTERADO** - o arquivo existe, mas o hash nao bate com o do manifesto
 (conteudo mudou).
- **FALTANDO** - o manifesto lista o arquivo, mas ele nao esta no disco.
- **EXTRA** - o arquivo esta no disco, mas nao consta no manifesto (nao fazia
 parte do pacote original).

## Como o manifesto e gerado

`scripts/make-manifest.ps1` roda automaticamente no fim de
`scripts/package-release.ps1`, depois que o pacote ja foi montado e validado
(zero vazamento de dado de operador, smoke verde). Ele calcula o SHA256 de
todo arquivo do pacote (exceto o proprio `MANIFEST.sha256` e qualquer coisa
dentro de `.git`) e escreve o manifesto na raiz do pacote. Assim, todo pacote
publicado ja sai com o manifesto dentro - nao e um passo extra que alguem
pode esquecer de rodar.

## Nota honesta: integridade, nao autenticidade de origem

Isto e importante para nao prometer mais do que o mecanismo entrega.

O que o `MANIFEST.sha256` PROVA: o conteudo do pacote que voce tem em maos e
byte-a-byte identico ao que foi empacotado no momento em que o manifesto foi
gerado. Se um arquivo for corrompido no download, alterado em transito, ou
modificado depois de extraido, `verify-manifest.ps1` detecta e aponta
exatamente o que mudou. Isso e **integridade**.

O que o `MANIFEST.sha256` NAO PROVA: que o pacote realmente veio do Alia
Flow oficial, ou que ninguem interceptou o download inteiro e trocou tanto
os arquivos quanto o manifesto junto (um atacante que controla os dois pode
regenerar um manifesto que bate com o conteudo adulterado). Isso seria
**autenticidade de origem**, e exige assinatura criptografica real (PKI -
uma chave privada que so o publicador tem, verificavel contra uma chave
publica conhecida). O manifesto SHA256 sozinho nao oferece isso.

Em termos praticos: o manifesto protege contra corrupcao acidental e
adulteracao pontual depois que voce ja tem o pacote em maos (por exemplo,
confirmar que uma copia entre maquinas nao truncou um arquivo, ou que nada
mudou depois de instalado). Ele nao substitui uma cadeia de confianca
criptografica de origem.

Assinatura de origem (GPG, Sigstore, ou equivalente) fica registrada como
evolucao futura - nao esta implementada nesta versao.

## Referencia rapida

| Comando | O que faz |
|---|---|
| `powershell -File scripts/make-manifest.ps1 -Dir <pasta>` | Gera `MANIFEST.sha256` na raiz de `<pasta>` (roda automaticamente no empacotamento) |
| `powershell -File scripts/verify-manifest.ps1 -Dir <pasta>` | Recalcula os hashes e compara com `MANIFEST.sha256`; exit 0 se integro, exit 1 se houver divergencia |
| `... -Json` (em qualquer um dos dois) | Saida em JSON em vez de texto, para uso por outro script |
