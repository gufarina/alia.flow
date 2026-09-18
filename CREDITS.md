# Creditos e fontes

Alia Flow nao nasceu do nada. Ela se apoia em frameworks, metodos e mestres que vieram antes.
Creditamos com gratidao - e recomendamos beber direto da fonte.

## Bases diretas

A linhagem completa, para registro: **BMad Method -> aiox-core -> Alia Flow**.

- **AIOX Squad / aiox-core** (pacote `@aiox-squads/core`), por **SynkraAI Inc.**
  (github.com/SynkraAI/aiox-core, MIT) - o framework do qual o motor da Alia evoluiu. O esqueleto
  de entrega autonoma e parte da governanca herdaram a inteligencia do aiox-core, enxugados para
  caber num job real (cortamos a burocracia, mantivemos a inteligencia). Mecanica reescrita para o
  nosso caso de uso, nao copiada linha a linha.
- **BMAD-METHOD** - "Breakthrough Method for Agile AI-Driven Development", por **BMad Code, LLC**
  (Brian Madison; github.com/bmad-code-org/BMAD-METHOD, MIT) - a origem do proprio aiox-core.
  Metodo de desenvolvimento agentico: agentes especializados, workflows e quality gates. O ciclo de
  Story (Create / Validate / Implement / Gate), a disciplina de spec-antes-de-codigo e os gates de
  qualidade bebem daqui. "BMad", "BMad Method" e "BMad Core" sao marcas registradas de
  BMad Code, LLC - citadas aqui so como credito de origem, nunca como marca nossa.

## Metodos e disciplinas

- **Domain-Driven Design** - Eric Evans. Linguagem ubiqua e bounded contexts; a base do nosso
  anti-drift de DDD.
- **Guidelines de engenharia inspiradas no Andrej Karpathy** (forrestchang/andrej-karpathy-skills) -
  pensar antes de codar, simplicidade, mudancas cirurgicas, execucao orientada a meta. Em
  engine/engineering.md.
- **ponytail** (Dietrich Gebert, github.com/DietrichGebert/ponytail, MIT) - o mindset do "senior
  preguicoso": a escada da simplicidade (YAGNI -> stdlib -> nativo -> dep existente -> one-liner ->
  minimo) e a convencao de comentario, batizada `frugal-debito:` no nosso motor (teto + caminho de
  upgrade), em engine/engineering.md e generalizada para qualquer Artifact em
  engine/features/artifact-ladder.md. Adaptado, nao copiado - o motor ja vivia o principio.
- **Jobs To Be Done** (Clayton Christensen) e **The Effective Executive** (Peter Drucker) - os filtros
  de pensamento da constituicao: contribuir acima de parecer, causa-raiz, a forca certa para cada job.

## Os mestres (Expert Minds)

A profundidade de cada especialista vem do metodo de um mestre real (ver engine/features/expert-minds/):

- Copy: **David Ogilvy**.
- Ads / grandes promessas: **Eugene Schwartz**.
- Dev / TDD: **Kent Beck**.
- Design systems: **Brad Frost**.
- Growth: **Sean Ellis**.

## Plataforma

- **Anthropic / Claude** - o runtime de agente (Claude Code) e as praticas de engenharia de prompt,
  incluindo o Model Context Protocol (MCP).
- **Graphify** (pacote `graphifyy`, por Safi Shamsi - github.com/sponsors/safishamsi) - o mapa de
  conhecimento (requisito da instalacao, desde 10/08/2026) que a Alia usa para turbinar a memoria de
  dominio (grafo de conexoes).

---

> Onde uma ideia foi adaptada, adaptamos com respeito a fonte. Erros de atribuicao sao nossos - abra
> uma issue e a gente corrige.
