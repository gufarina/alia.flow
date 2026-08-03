# Runner de todos os benchmarks deterministicos do Alia Flow.
# Roda cada bench_*.py, imprime a saida e agrega VERDICTs. Sai 0 se todos passam.
# Sem acentos, sem emojis. UTF-8 sem BOM.

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

BENCHES = [
    "bench_knowledge_lift.py",
    "bench_zero_token_checks.py",
    "bench_boot_weight.py",
    "bench_resume_steps.py",
    "bench_library_ondemand.py",
]


def main():
    results = []
    for b in BENCHES:
        print("==================== " + b + " ====================")
        proc = subprocess.run(
            [sys.executable, os.path.join(HERE, b)],
            capture_output=True,
            text=True,
        )
        sys.stdout.write(proc.stdout)
        if proc.stderr.strip():
            sys.stdout.write(proc.stderr)
        results.append((b, proc.returncode))
        print("")

    print("==================== RESUMO ====================")
    ok = True
    for b, rc in results:
        verdict = "PASS" if rc == 0 else "FAIL"
        if rc != 0:
            ok = False
        print(("[" + verdict + "] ").ljust(8) + b)
    print("")
    print("BENCHMARKS: " + ("ALL PASS" if ok else "HAS FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
