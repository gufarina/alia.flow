# Benchmark 1 - Lift de Conhecimento (ablacao do segundo cerebro).
# NAO reinventa o teste: REUSA o score.py de T14 (knowledge-ablation) e so re-roda + reporta
# o numero real em formato de metrica. Determinista, sem LLM, custo zero de token.
#
# Saida: linhas METRIC <chave>=<valor> e um VERDICT. Sai 0 quando o teste-fonte passa.
# Sem acentos, sem emojis. UTF-8 sem BOM.

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ABLATION = os.path.join(
    ROOT, "studio.example", "clients", "acme-saas", "tests", "knowledge-ablation"
)


def main():
    score = os.path.join(ABLATION, "score.py")
    if not os.path.isfile(score):
        print("METRIC error=score.py ausente em " + ABLATION)
        print("VERDICT: FAIL")
        return 1

    # Re-roda o scorer-fonte na pasta dele (ele le out-blind.md / out-informed.md por path relativo).
    proc = subprocess.run(
        [sys.executable, "score.py"],
        cwd=ABLATION,
        capture_output=True,
        text=True,
    )
    out = proc.stdout

    blind = informed = gain = threshold = None
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("Termos cobertos (blind):"):
            blind = int(s.split(":")[1].strip())
        elif s.startswith("Termos cobertos (informed):"):
            informed = int(s.split(":")[1].strip())
        elif s.startswith("Ganho do informed:"):
            # "Ganho do informed: 5 (threshold 3)"
            tail = s.split(":")[1].strip()
            gain = int(tail.split("(")[0].strip())
            threshold = int(tail.split("threshold")[1].replace(")", "").strip())

    total = 5  # KEY_TERMS no score.py
    print("METRIC source=studio.example/.../tests/knowledge-ablation/score.py (T14, REUSE)")
    print("METRIC key_terms_total=" + str(total))
    print("METRIC covered_blind=" + str(blind))
    print("METRIC covered_informed=" + str(informed))
    print("METRIC gain=" + str(gain) + " threshold=" + str(threshold))
    if blind is not None and informed is not None:
        print("METRIC coverage_blind_pct=" + str(round(100.0 * blind / total)))
        print("METRIC coverage_informed_pct=" + str(round(100.0 * informed / total)))

    ok = proc.returncode == 0 and gain is not None and gain >= (threshold or 0)
    print("VERDICT: " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
