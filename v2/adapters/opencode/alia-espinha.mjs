// alia-espinha.mjs - ADAPTADOR OpenCode da espinha Cliente>Projeto>Tarefa. Sem regra propria.
// BLOQUEIA (tool.execute.before lancando erro): `task` -> alia task dispatch; grep|glob -> alia graph check.
// SO AVISA/REGISTRA: session.created -> alia open; read -> alia graph read.
// Lacuna declarada (doc oficial): nao diz se tool.execute.before vale para chamada de subagente.
// Instalar: copiar para .opencode/plugins/ com ALIA_BIN apontando para v2/bin/alia.py (ou manter no lugar).
import { traduzir, abreSessao, chamarAlia, recusa } from "../traducao.mjs";

export const DECLARA = {
  host: "opencode",
  bloqueia: ["tool.execute.before task", "tool.execute.before grep|glob"],
  avisa: ["session.created", "tool.execute.before read (so registra)"],
};

export const AliaEspinha = async ({ directory }) => ({
  "tool.execute.before": async (input, output) => {
    const argv = traduzir("opencode", input.tool, output.args, input.sessionID, directory);
    if (!argv) return;
    const motivo = recusa(chamarAlia(argv), "opencode");
    if (motivo) throw new Error(motivo);
  },
  event: async ({ event }) => {
    if (event?.type !== "session.created") return;
    const id = event.properties?.info?.id ?? event.properties?.sessionID;
    const argv = abreSessao(id);
    if (argv) chamarAlia(argv);
  },
});
