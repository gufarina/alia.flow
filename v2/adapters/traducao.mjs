// traducao.mjs - a UNICA tabela evento-do-host -> chamada `alia` dos adaptadores JS (OpenCode, Pi).
// Regra de dominio: nenhuma. Quem recusa e a CLI (v2/bin/alia.py); aqui so se traduz e se repassa a recusa.
// Declaracao do que cada host BLOQUEIA e do que so AVISA: v2/adapters/matriz.json (conferida em test_espinha.py).
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// Nome da ferramenta no host -> acao na espinha.
export const FERRAMENTAS = {
  opencode: { task: "dispatch", grep: "varredura", glob: "varredura", read: "leitura" },
  pi: { grep: "varredura", find: "varredura", read: "leitura" },
};
// A CLI sai 1 por falta de espinha na instancia ou por quebra interna: o adaptador nao vota (falha aberta).
export const SEM_VOTO = ["state_ausente", "erro_interno", "uso_invalido"];

const caminho = (a) => String((a && (a.path ?? a.filePath ?? a.file_path ?? a.directory)) ?? "");

/** evento do host -> argv da CLI `alia` (ou null: a espinha nao tem nada a ver com essa chamada). */
export function traduzir(host, tool, args, sessionID, cwd = "") {
  const acao = (FERRAMENTAS[host] || {})[String(tool).toLowerCase()];
  if (!acao || !sessionID) return null;
  const a = args || {};
  if (acao === "dispatch") {
    const agente = a.subagent_type ?? a.agent ?? a.subagentType;
    return agente ? ["task", "dispatch", "--specialist", String(agente), "--session", String(sessionID)] : null;
  }
  if (acao === "varredura")
    return ["graph", "check", "--session", String(sessionID), "--tool", String(tool), "--path", caminho(a), "--cwd", cwd, "--host", host];
  return ["graph", "read", "--session", String(sessionID), "--path", caminho(a), "--cwd", cwd];
}

export function abreSessao(sessionID) {
  return sessionID ? ["open", "--session", String(sessionID)] : null;
}

export function binAlia() {
  return process.env.ALIA_BIN || join(dirname(fileURLToPath(import.meta.url)), "..", "bin", "alia.py");
}

/** chama a CLI; devolve {code, json}. */
export function chamarAlia(argv, python = process.env.ALIA_PYTHON || "python") {
  const r = spawnSync(python, [binAlia(), ...argv], { encoding: "utf-8", env: process.env });
  let json = {};
  try { json = JSON.parse((r.stdout || "").trim().split("\n").pop() || "{}"); } catch { /* sem JSON: trata como sem voto */ }
  return { code: r.status ?? 1, json };
}

/** null = liberado; string = motivo da recusa (o adaptador do host barra com ele). */
export function recusa(res) {
  if (res.code === 0 || SEM_VOTO.includes(res.json.regra) || !res.json.regra) return null;
  return `espinha: ${res.json.error} [${res.json.regra}]`;
}
