# Benchmark 2 - Verificacoes a custo zero de token de modelo.
# Roda o smoke-test.ps1 (todas as checagens deterministicas do motor) e captura o numero
# de PASS reportado na linha "Checks: N PASS, M FAIL". Nenhuma checagem chama LLM.
# Tambem confirma que as 4 Frugal Skills (validate-artifact, state-resume, apply-safe-output,
# sanitize-input) sao scripts deterministicos (ja exercitados dentro do smoke).
#
# Determinista, sem LLM. Saida METRIC + VERDICT. Sai 0 quando o smoke fica ALL GREEN.
# Sem acentos, sem emojis. UTF-8 sem BOM.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SMOKE = os.path.join(ROOT, "scripts", "smoke-test.ps1")

FRUGAL_SKILLS = [
    "validate-artifact",
    "state-resume",
    "apply-safe-output",
    "sanitize-input",
]


def main():
    if not os.path.isfile(SMOKE):
        print("METRIC error=smoke-test.ps1 ausente")
        print("VERDICT: FAIL")
        return 1

    proc = subprocess.run(
        ["powershell", "-ExecutionPolicy", "Bypass", "-File", SMOKE],
        capture_output=True,
        text=True,
    )
    out = proc.stdout

    m = re.search(r"Checks:\s*(\d+)\s*PASS,\s*(\d+)\s*FAIL", out)
    passes = int(m.group(1)) if m else None
    fails = int(m.group(2)) if m else None
    all_green = "ALL GREEN" in out

    # Confirma que as 4 Frugal Skills existem como script determinista (.ps1).
    frugal_present = 0
    for name in FRUGAL_SKILLS:
        script = os.path.join(ROOT, "skills", name, name + ".ps1")
        if os.path.isfile(script):
            frugal_present += 1

    print("METRIC source=scripts/smoke-test.ps1 (motor + Frugal Skills, sem LLM)")
    print("METRIC smoke_pass=" + str(passes))
    print("METRIC smoke_fail=" + str(fails))
    print("METRIC all_green=" + str(all_green).lower())
    print("METRIC frugal_skills_deterministic=" + str(frugal_present) + "/4")
    print(
        "METRIC frugal_skills="
        + ",".join(FRUGAL_SKILLS)
        + " (todas .ps1, exit 0/1, zero token de modelo)"
    )

    ok = all_green and fails == 0 and passes is not None and frugal_present == 4
    print("VERDICT: " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
