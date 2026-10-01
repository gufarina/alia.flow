// alia-espinha.mjs - ADAPTADOR Pi da espinha Cliente>Projeto>Tarefa. Sem regra propria.
// BLOQUEIA (tool_call devolvendo block): grep|find -> alia graph check. Falha do handler tambem barra (doc do Pi).
// SO AVISA/REGISTRA: before_agent_start -> alia open; read -> alia graph read.
// Pi nao tem subagente nativo: `task dispatch` nao se aplica aqui.
// ATENCAO (host): `--no-extensions` desliga a descoberta de extensoes e esta trava junto. O host
// DEVE proibir essa flag ao lancar o Pi (decisao do CEO, nao editada daqui).
import { traduzir, abreSessao, chamarAlia, recusa } from "../traducao.mjs";

export const DECLARA = {
  host: "pi",
  bloqueia: ["tool_call grep|find"],
  avisa: ["before_agent_start", "tool_call read (so registra)"],
};

const sessao = (ctx) => ctx?.sessionManager?.getSessionId?.() ?? ctx?.sessionId ?? process.env.PI_SESSION_ID ?? "";

export default function (pi) {
  pi.on("tool_call", async (event, ctx) => {
    const argv = traduzir("pi", event.toolName, event.input, sessao(ctx), ctx?.cwd ?? process.cwd());
    if (!argv) return undefined;
    const motivo = recusa(chamarAlia(argv), "pi");
    return motivo ? { block: true, reason: motivo } : undefined;
  });
  pi.on("before_agent_start", async (_event, ctx) => {
    const argv = abreSessao(sessao(ctx));
    if (argv) chamarAlia(argv);
    return undefined;
  });
}
