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
todo arquivo do pacote (exceto o proprio `MANIFEST.sha256`, qualquer coisa
dentro de `.git` e dado de operador sob `studio/` - regra em
`scripts/_manifest-exclude.ps1`) e escreve o manifesto na raiz do pacote. Assim, todo pacote
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

## Gate obrigatorio antes do push (L62)

O passo "aplicar o pacote no repo do produto" (Projetos/alia-flow) e feito a mao pelo COURIER
(robocopy), nao por script automatico - e foi exatamente nesse intervalo manual que um
`git checkout` restaurou um README.md antigo DEPOIS do manifesto ter sido gerado, deixando o
manifesto divergente do disco sem ninguem perceber ate o instalador publico abortar (TASK-565,
14/09/2026). Por isso, depois de aplicar o pacote no repo do produto e ANTES de `git push`, rode:

```
powershell -File scripts/release-gate.ps1 -Repo <caminho do repo do produto>
```

Ele roda `check-public-surface.ps1` + `verify-manifest.ps1` contra o repo (nao o staging) e sai 1
se qualquer um reprovar. Push so acontece com este script verde.

## Identidade de commit (L69)

TASK-617 (17/09/2026): o repositorio publico novo foi publicado com o e-mail PESSOAL do CEO no
campo `committer` do commit - so foi descoberto porque o CEO pediu revisao adversarial DEPOIS do
push. Auditoria mediu que NENHUM script da oficina conferia identidade de commit: mesmo rodando o
gate, o vazamento passava.

Por isso `release-gate.ps1` roda, como passo 1/3 (antes da superficie publica e do manifesto),
`git log --all --format='%H|%an|%ae|%cn|%ce'` no repo alvo e reprova qualquer commit cujo `author`
ou `committer` (nome OU e-mail) caia fora de uma allowlist estreita, declarada no topo do proprio
script (hoje: `Alia Flow <noreply@alia-flow.local>`). A falha cita o hash curto do commit e o campo
exato (`author` ou `committer`) - sem isso, ninguem conserta rapido. Repo sem `.git` (staging puro)
pula esta etapa com aviso, nunca falha por engano.

## Hook pre-push (L69): torna impossivel pular o gate

A falha real da TASK-617 nao foi o gate estar incompleto - foi o `git push` ter rodado POR FORA
dele. Um script que so PODE ser esquecido volta a falhar do mesmo jeito. Por isso existe
`scripts/install-release-hooks.ps1`: instala um hook `pre-push` em `.git/hooks/` do repo alvo que
chama `release-gate.ps1` contra o proprio repo e aborta o push (`exit 1`) se o gate sair diferente
de zero.

```
powershell -ExecutionPolicy Bypass -File scripts/install-release-hooks.ps1 -Repo <caminho do repo do produto>
```

**Reinstalar sempre que o repo for recriado.** `.git/hooks` NUNCA viaja no clone - e uma
limitacao do proprio git, nao um defeito deste mecanismo. Se o repositorio publico for clonado de
novo, ou se `.git` for apagado e recriado, o hook some e precisa ser reinstalado com o comando
acima antes do proximo push. Nao ha lembrete automatico para isso: quem recria o repo e quem
reinstala.

## Revisao adversarial antes de publicar (L69)

A revisao que achou o vazamento da TASK-617 so aconteceu porque o CEO pediu - nao porque o
processo exigia. Isso muda aqui: toda publicacao publica (qualquer `git push` para um repositorio
publico do Alia Flow) exige revisao adversarial ANTES do push, cobrindo no minimo:

1. **Identidade de commit** - `author`/`committer` de todo commit contra a allowlist (`release-gate.ps1`).
2. **Dado pessoal em conteudo** - nome, e-mail, caminho de maquina do operador em qualquer arquivo
   rastreado (`check-public-surface.ps1`).
3. **Dado pessoal em metadado** - o mesmo dado, mas em campos que nao aparecem ao ler o arquivo
   (autor/committer de commit, propriedades de binario, timestamps com fuso de maquina).
4. **Segredo** - chave, token ou credencial em texto ou em historico de commit (`check-public-surface.ps1` secao 1.7).
5. **Execucao remota de terceiro** - qualquer `curl | sh`, `irm | iex` ou equivalente que baixe e
   rode codigo de fora sem verificacao de integridade.
6. **Cadeia de confianca do instalador** - o instalador publico verifica o que baixa
   (`MANIFEST.sha256`, ver secao acima) antes de aplicar.

## Referencia rapida

| Comando | O que faz |
|---|---|
| `powershell -File scripts/make-manifest.ps1 -Dir <pasta>` | Gera `MANIFEST.sha256` na raiz de `<pasta>` (roda automaticamente no empacotamento) |
| `powershell -File scripts/verify-manifest.ps1 -Dir <pasta>` | Recalcula os hashes e compara com `MANIFEST.sha256`; exit 0 se integro, exit 1 se houver divergencia |
| `... -Json` (em qualquer um dos dois) | Saida em JSON em vez de texto, para uso por outro script |
