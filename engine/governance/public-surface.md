# LEI da superficie publica - o que pode existir no git

> Mandato do CEO em 2026-08-01, depois de a Alia commitar landing pages no repo da oficina.
> Sem acentos, sem emojis. Esta lei vem ANTES de qualquer conveniencia de versionamento.

## A lei, em uma frase

**Git e vitrine, nao gaveta.** No git so existe o produto publico, limpo, do jeito que o
usuario final recebe. Tudo que e de desenvolvimento fica FORA do git - salvo em disco, dentro
da oficina, mas nunca versionado num repositorio que pode ser publicado.

## O que NUNCA entra no git

- Landing pages, candidatas de LP, estudos de arte, mockups, previews de design.
- PRD, roadmap, backlog, oportunidades (`opportunities/`), pareceres, auditorias.
- Registro de claims (`CLAIMS.md`), material de marca interno (`BRAND.md`), decisoes datadas.
- Memoria da Alia, `state.json`, tarefas, relatorios, `PRODUCT.md`, `DESIGN.md` de trabalho.
- Rascunhos (`_drafts/`, `_dev/`, `_candidatas/`, `research/`, `rsi-backlog/`).
- Qualquer coisa de cliente. Cliente nunca toca em repo publico.

## O que PODE entrar

Somente o que o usuario final baixa e usa: o motor, os scripts do produto, o instalador,
a licenca, o README publico, o CHANGELOG publico, o cliente de exemplo (`studio.example/`)
e a documentacao dirigida AO USUARIO (PRIMEIROS-PASSOS, CONTRIBUTING).

Regra de bolso: **se um estranho lendo aquilo aprende como a gente decide por dentro, nao vai.**

## Onde cada coisa mora

| Coisa | Onde fica | Versionado? |
|---|---|---|
| Produto publico | `Projetos/alia-flow` (repo com `origin`) | SIM - e o unico que publica |
| Oficina (motor em evolucao, LP, docs, PRD) | `studio-farina/clients/alia-flow-lab` | NAO - **sem git nenhum**, por lei |
| Operacao do studio (clientes, memoria, tarefas) | `studio-farina/` | NAO - nunca foi git |

A oficina **NAO E REPOSITORIO GIT** (removido em 01/08/2026; historico antigo arquivado em
`studio-farina/_backups/git-oficina-arquivado-2026-08-01`, caso alguem precise consultar).
Oficina nunca precisou de git. Se alguem rodar `git init` ali, esta violando esta lei.

## Como o trabalho de desenvolvimento e protegido, entao

Sem git, a protecao contra perda e o BACKUP, nao o commit:
`scripts/package-release.ps1` para o pacote publico, e copia datada em `_backups/` para a
oficina. O incidente de 24/jun (LP perdida num reorg) se resolve com backup, nao publicando.

## Antes de publicar, a conferencia obrigatoria

Rodar `scripts/check-public-surface.ps1` no repo publico. Ele reprova se qualquer arquivo
das categorias proibidas estiver rastreado. Reprovou, nao publica.

## Antes de empacotar, a revisao de release obrigatoria

> LEI: nenhuma versao sai de `package-release.ps1` sem revisao de release aprovada (mandato do
> CEO, 11/08/2026, apos incidente repetido de revisao independente achar problema toda vez que
> pedida - a revisao vira PORTA, nao EVENTO).

Antes de 11/08/2026 a revisao independente do motor era EVENTO: acontecia quando alguem pedia.
Agora e PORTA: `scripts/package-release.ps1` exige um registro em `release-reviews/<VERSION>.md`
(formato em `release-reviews/TEMPLATE.md`) com `veredito: PASS` e `versao:` batendo com o
`VERSION` atual - sem o arquivo, com `veredito: FAIL`, ou com versao divergente, o empacotamento
ABORTA (passo 0/3 do script) antes de montar qualquer coisa. Nenhum agente fabrica o proprio PASS
para destravar o empacotador - isso seria o teatro que esta porta existe para matar; a revisao
tem que ser real.

## A fronteira, em uma tabela (para o CEO conferir sozinho)

Auditoria de superficie de 10/08/2026. Isto e o que existe de verdade hoje - reconfira com o
comando abaixo antes de qualquer publicacao, esta tabela pode ficar desatualizada.

| Categoria | Isto e PUBLICO (pode ir) | Isto e INTERNO (nunca vai) |
|---|---|---|
| Produto | engine/, scripts/ do motor (allowlist), skills/, onboarding/, optional-mcps/, studio.example/, benchmarks/, .claude/ (settings+comando), docs/README.md, docs/COMPATIBILIDADE.md, docs/INTEGRIDADE.md | scripts/smoke-test-studio.ps1 (smoke DA INSTANCIA), scripts/migrate-to-studio.ps1, scripts/extract-secrets.ps1 (migracao unica do dono), scripts/fixtures/ ship (sao fixture de teste do proprio smoke, sem segredo) |
| Documentacao | README.md, PRIMEIROS-PASSOS.md, CONTRIBUTING.md, CHANGELOG.md, CREDITS.md, LICENSE | PRD, CAPACIDADE-REAL.md, CLAIMS.md, BRAND.md, RELEASE-STATUS.md, roadmap (qualquer arquivo/pasta), docs/product/, docs/business/, DESIGN-*.md |
| Marca/design | nada (a marca do produto e a persona da Alia dentro do motor, nao arte solta) | brand/ (qualquer pasta), brand/landing/, landing/ (qualquer pasta), preview/ |
| Trabalho em curso | nada | opportunities/, research/, _drafts/, _dev/, _candidatas/, _backups/ |
| Estado/operacao | studio.example/ (cliente de EXEMPLO, dado falso) | state.json, mission-control.html, memory/ (fora de studio.example), .claude/agents/ (especialista de cliente gerado) |
| Dado de cliente | nada | clients/ (qualquer coisa - Cliente-Projeto-Tarefa e do operador, nunca do repo publico) |

Comando unico de conferencia, antes de qualquer publicacao:

```
powershell -ExecutionPolicy Bypass -File scripts/check-public-surface.ps1 -Repo <caminho do pacote ou do repo publico>
```

`REPROVADO` com a lista de arquivos + motivo = nao publica. `SUPERFICIE LIMPA` = pode seguir.
O empacotador (`scripts/package-release.ps1`) ja chama este guarda sozinho no passo 3/3 e ABORTA
o pacote se reprovar - mas isto nao dispensa rodar o comando de novo, na mao, no repo publico
de destino antes do `git push` (o empacotador so confere o pacote local, nao o repo remoto).

## Cacada de credencial (LEI L42, TASK-302, 26/08/2026)

CAMINHO proibido (secao acima) e IDENTIDADE de Client (mesmo script, secao "(1.5)") nao sao a
mesma coisa que CREDENCIAL. Nasceu de um furo MEDIDO numa publicacao real: o open beta do Alia
Desktop (26/08/2026) passou limpo pelos dois checks acima E por um portao proprio do Client, mas
nenhum deles procurava chave de API, token de sessao, ou arquivo de credencial (`keys.json`,
`.env`, `credentials.json`, `auth.json`). O CEO teve que perguntar na hora H se a chave dele ia
junto - uma varredura ad hoc foi inventada DEPOIS do arquivo ja publicado (achou zero credencial
real, mas 18 ocorrencias das palavras-agulha, todas explicadas como SDK vendorizado, doc de
exemplo ou fixture de teste do upstream).

`scripts/check-public-surface.ps1` secao "(1.6) cacada de credencial real" fecha esse gap dentro
do MESMO guard, no MESMO gate que ja roda em `package-release.ps1` passo 3/3 - sem script novo
(reuse-first). Regra que separa SEGREDO de MENCAO (o falso positivo e o inimigo principal deste
check - ver a licao da propria varredura ad hoc):

- MENCAO (vira so AVISO, nunca bloqueia): a agulha aparece dentro de `node_modules`/`.pnpm`
  (codigo de terceiro vendorizado), num caminho/arquivo de teste/exemplo/fixture, ou o valor
  casado carrega um marcador de placeholder em ingles OU portugues (`example`, `fake`, `xxxx`,
  `seu_..._aqui`, `troque`, `substitua`, `changeme`, `<...>`).
- SEGREDO (REPROVA): a mesma agulha fora dessas zonas - chave Anthropic (`sk-ant-`), NVIDIA
  (`nvapi-`), GitHub (`ghp_`/`github_pat_`), estilo OpenAI (`sk-`), JWT completo, header
  `Bearer <token>`, ou campo `access_token`/`refresh_token`/`api_key`/`apiKey` COM valor real.
- Nome de arquivo de credencial real (`keys.json`, `credentials.json`, `.credentials.json`,
  `auth.json`, `.env` fora de `.env.example`/`.env.sample`/`.env.template`/`.env.dist`) REPROVA
  por si so, mesmo vazio - nao tem zona cinza de mencao legitima.
- Quando o alvo (`-Repo`) carrega binario (`.exe`/`.dll`) - caso de instalador ja empacotado -
  o mesmo guard decodifica ASCII e UTF-16LE e roda o subconjunto de agulhas de alta confianca
  (sem os needles de campo=valor/Bearer, ruidosos demais em binario).

Prova pelo negativo (planta credencial de mentira, confere REPROVADO, desfaz, confere SUPERFICIE
LIMPA de volta) roda dentro de `scripts/smoke-test.ps1`, secao "Cacada de credencial (TASK-302)".
Ver `engine/governance/law-ledger.md`, L42, para o registro completo dos 5 casos provados.
