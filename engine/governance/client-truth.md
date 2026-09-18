# Fonte de Verdade do Cliente - a lei que protege a documentacao

> Governanca do motor. Nasceu de um dia real de falhas (07/jul/2026): copy publica inventada
> por cima de fontes curadas, numero fabricado somando fontes distintas, feature nao-lancada
> anunciada, identidade de marca vetada ressuscitada, ativo de marca reinventado do zero e a
> coordenadora executando dominio com as proprias maos. Cada falha desceu por 5 Whys ate a
> causa-raiz; cada causa-raiz virou uma LEI abaixo. A documentacao do cliente e protegida,
> alimentada e valorizada - ou o Gate reprova. UTF-8 sem BOM.

---

## LEI 1 - Knowledge-first: carregar a verdade curada ANTES de produzir

Nenhum Artifact para um Client nasce sem o produtor ter CARREGADO o knowledge curado daquele
Client. A hierarquia de fonte e fixa e nao e opcional:

1. **Decisao registrada do Operator** (a mais recente vence - ex.: tagline travada em data X).
2. **Fontes curadas do Client**: BRAND (marca/voz), PRD (produto/posicionamento/vetos),
   persona (voz do agente), glossario DDD, Especificacao de Entrega.
3. **Docs internos de trabalho** (notas, research) - contexto, nunca contrato.
4. **README/codigo/artefatos tecnicos** - verdade TECNICA (comandos, numeros de teste),
   nunca verdade de MARCA. README e vitrine de dev; quem manda em copy e o BRAND/PRD.

Regras duras:
- Fonte errada = Artifact reprovado, mesmo que o texto esteja bonito. Bonito nao e criterio.
- As fontes curadas registram tambem os VETOS (angulo derrubado, termo proibido, lema
  aposentado). Ressuscitar um veto e a falha mais grave desta LEI - e desrespeitar uma
  decisao ja tomada pelo Operator.
- Quem produz declara no Artifact QUAIS fontes leu. Sem declaracao de fonte = [INFERIDO].
- ALIMENTAR: quando uma decisao nova do Operator surge numa conversa (aprovacao, veto,
  numero oficial), quem a recebe REGISTRA na fonte curada do Client na mesma Task. Decisao
  que fica so no chat e decisao perdida - e a proxima peca nasce errada.

## LEI 2 - Claims Registry: fato publico so com fonte aprovada

Toda peca PUBLICA (landing, site, social, deck de venda, README publico) so pode afirmar:

- **Numero**: o que consta no registro de claims do Client (arquivo curado de fatos publicos,
  cada um com fonte e data). Numero de duas fontes NUNCA se soma para criar um numero novo -
  soma de fontes distintas e fabricacao, nao matematica.
- **Feature**: somente com status LANCADO. Roadmap, DESENHADO, em-voo, interno = nao existe
  para o publico. Anunciar feature nao-lancada e vender mentira com data marcada.
- **Tagline/identidade**: somente a vigente na fonte curada. Em conflito entre docs, vence a
  decisao do Operator mais recente e registrada; na duvida real, pergunta-se UMA vez e a
  resposta e REGISTRADA na fonte (LEI 1, alimentar).

O que nao esta no registro: ou vira lacuna nomeada na peca ("nao temos este numero"), ou a
peca espera o registro ser alimentado. Preencher com invencao plausivel e o defeito que este
motor existe para impedir.

## LEI 3 - Escopo publico vs interno: regras de operacao nao vazam pra peca

Regras operacionais internas (estilo de arquivo, atalhos de escrita, convencoes de log,
vocabulario de bastidor) valem para a OPERACAO - nunca para o texto que o publico le.

- Texto publico segue a lingua do publico com gramatica completa e a voz do BRAND.
- Vocabulario de bastidor (nomes de mecanismo interno) nao aparece na peca publica; fala-se
  pelo resultado, na linguagem do usuario.
- Antes de aplicar qualquer regra interna a um arquivo, a pergunta obrigatoria: QUEM LE ISTO -
  a operacao ou o publico? Errar essa pergunta produz peca analfabeta ou doc interno inflado.

## LEI 4 - Reuse-first de ativos: a marca nao se reinventa por descuido

Antes de CRIAR qualquer ativo visual ou verbal para um Client (logo, icone, textura, motor de
efeito, headline, assinatura), INVENTARIAR o que ja existe nas pastas de marca e design do
Client. O ativo oficial existente VENCE a recriacao - sempre.

- Recriar um ativo que ja existe e desperdicio duplo: paga-se para fazer pior o que ja estava
  pronto, e a marca ganha uma versao bastarda que confunde as proximas pecas.
- Efeitos proprietarios da marca (motores visuais, texturas assinatura) sao ATIVOS, nao
  inspiracao: replica-se o original, nao se faz "algo parecido".
- So se cria do zero quando o inventario PROVOU que nao existe - e o novo ativo entra na
  pasta de marca do Client na mesma Task (LEI 1, alimentar).

## LEI 5 - Docs fecham a entrega: doc curada sem portao e doc que apodrece

> LEI: toda doc curada do Client que a LEI 1 manda carregar (PRD, README, ficha do Client em
> client.md, visao de produto do squad) e atualizada NA MESMA versao que muda o produto. Release
> MINOR sem tocar as docs curadas = release incompleto; ficha do Client citando versao velha =
> ficha errada. O portao e maquina, nunca lembrete: `scripts/docs-check.ps1`.

Nasceu de um caso real (07/09/2026, mandato do CEO): num Client, o que tinha portao automatico
(CHANGELOG, catalogo de dados, DESIGN.md) estava em dia; o que nao tinha (PRD, README, ficha do
Client, visao de produto) ficou 5 semanas e 4 features pra tras. Doc atrasada com cara de fonte
curada e PIOR que doc nenhuma - a LEI 1 manda carregar a fonte, e a fonte mente.

Regras duras:
- **Ficha bate com o codigo.** `clients/<id>/client.md` cita literalmente a versao publicada do
  codigo (package.json ou VERSION do `codePath`). Nao cita = [FICHA], reprova.
- **Doc curada acompanha o MINOR.** README e PRD do `codePath` (mais o que o client.md listar em
  `**docsGate:**`) foram tocados DEPOIS do ultimo release x.y.0 do CHANGELOG. Mais velhos =
  [STALE], reprova. PATCH nao cobra doc (correcao nao muda o produto).
- **Quem publica fecha a doc.** O passo FECHA da Task que sobe MINOR inclui rodar
  `scripts/docs-check.ps1 -Client <id>` e deixar [OK] antes do tag/push. Doc que "fecha depois"
  e a divida que esta LEI existe pra impedir.
- **Divida vai pra baseline datada, nunca pro esquecimento.** O smoke da instancia usa
  `studio/docs-gate-baseline.txt` como ratchet: linha so entra com data, Task e motivo, e so pode
  sair. Doc podre nova fora da baseline reprova na hora.
- Limite medido do portao: ele mede TOQUE (ultimo commit ou mtime), nao conteudo. Tocar a doc sem
  atualizar o que mudou engana a maquina e nao engana o Gate (criterio 6, Fundamentada).

## Reforcos de fronteira (ja eram lei; aqui ganham o gatilho que faltou)

- **Coordenador nao executa dominio.** Antes de produzir qualquer artefato de dominio
  (copy, design, codigo, dado), o coordenador para e responde: "quem e o Specialist desta
  lente?" Se a resposta existe, DELEGA - mesmo com pressa, mesmo "so desta vez". Producao de
  dominio pela coordenadora so quando o Operator manda explicitamente, e registrada como
  excecao na Task.
- **Briefing de delegacao carrega as travas.** Todo briefing a executor em contexto isolado
  inclui: (a) proibicao de re-delegar (a folha executa); (b) criterio de encerramento
  verificavel (numeros a reportar); (c) as fontes curadas a ler ANTES de produzir (LEI 1);
  (d) o que e proibido inventar (LEI 2). Briefing sem travas produz cascata, turno vazio e
  invencao - as tres pragas medidas em producao.

## Como o Gate cobra isto

O Quality Gate ganha, para Artifact do tipo PECA PUBLICA, os checks extras: fonte curada
declarada e carregada (LEI 1); todo claim quantitativo/feature/tagline rastreado ao registro
(LEI 2); zero vocabulario de bastidor e gramatica do publico (LEI 3); ativos de marca vindos
do inventario oficial (LEI 4). Reprovar um = Fail. Ver [quality-gate.md](quality-gate.md).

## Segue
[Quality Gate](quality-gate.md) - [Orquestracao](../orchestration.md) -
[Sistema de Squads](../squad-system.md) - [Memoria](memory-types.md)
