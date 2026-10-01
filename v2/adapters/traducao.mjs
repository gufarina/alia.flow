// traducao.mjs - a UNICA tabela evento-do-host -> chamada `alia` dos adaptadores JS (OpenCode, Pi).
// Regra de dominio: nenhuma. Quem recusa e a CLI (v2/bin/alia.py); aqui so se traduz e se repassa a recusa.
// Declaracao do que cada host BLOQUEIA e do que so AVISA: v2/adapters/matriz.json (conferida em test_espinha.py).
import { spawnSync } from "node:child_process";
import { appendFileSync, mkdirSync } from "node:fs";
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
  return { code: r.status ?? 1, json, argv };
}

/** falha aberta deixa rastro no ledger (o `alia task pending` avisa host sem trava). Nunca lanca. */
export function registrarFalhaAberta(host, motivo, sessao = "") {
  try {
    const led = process.env.ALIA_LEDGER_PATH || join(process.env.CLAUDE_PROJECT_DIR || process.cwd(), "activity.jsonl");
    mkdirSync(dirname(led), { recursive: true });
    appendFileSync(led, JSON.stringify({ event: "adapter_falha_aberta", host, motivo: String(motivo).slice(0, 200), session_id: sessao || null, v: 1, ts: Date.now() / 1000 }) + "\n");
  } catch { /* o rastro nunca derruba o host */ }
}

/** null = liberado; string = motivo da recusa (o adaptador do host barra com ele). */
export function recusa(res, host = "?") {
  if (res.code === 0) return null;
  if (SEM_VOTO.includes(res.json.regra) || !res.json.regra) {  // sem voto: libera, mas registra (C8)
    const i = (res.argv || []).indexOf("--session");
    registrarFalhaAberta(host, res.json.regra || "sem_json_python_ausente", i >= 0 ? res.argv[i + 1] : "");
    return null;
  }
  return `espinha: ${res.json.error} [${res.json.regra}]`;
}
