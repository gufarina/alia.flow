"""trava.py - lock de arquivo e escrita atomica (TASK-862, 2.1.3). So biblioteca padrao.

Dois hooks (ou duas sessoes) rodando ao mesmo tempo liam, alteravam e regravavam o mesmo JSON
(contador de subagentes, sidecar do grafo): o ultimo a gravar apagava o do outro, e uma
leitura no meio de uma escrita truncada via JSON invalido e zerava o teto (falha aberta).

    with trava.trava(caminho):          # exclusao mutua entre processos (O_CREAT|O_EXCL + retry)
        dados = ler(caminho)
        trava.gravar_atomico(caminho, json.dumps(dados))

`trava` e fail-soft: lock preso por mais de `velha_s` e retomado; passou `espera_s` sem conseguir, segue
SEM o lock (um hook nunca trava o operador). `gravar_atomico` escreve num tmp por pid e troca com
os.replace: um leitor ve o arquivo antigo inteiro ou o novo inteiro, nunca pela metade.
"""
from __future__ import annotations

import contextlib
import os
import time


@contextlib.contextmanager
def trava(caminho: str, espera_s: float = 5.0, velha_s: float = 10.0):
    lock = caminho + ".lock"
    fd = None
    try:
        os.makedirs(os.path.dirname(lock) or ".", exist_ok=True)
    except OSError:
        pass
    fim = time.monotonic() + espera_s
    while True:
        try:
            fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            break
        except (FileExistsError, PermissionError):  # Windows: a disputa do O_EXCL tambem vem como PermissionError
            try:
                if time.time() - os.path.getmtime(lock) > velha_s:
                    os.remove(lock)  # dono morreu com o lock na mao
                    continue
            except OSError:
                pass
            if time.monotonic() >= fim:
                break
            time.sleep(0.01)
        except OSError:
            break
    try:
        yield
    finally:
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass
            try:
                os.remove(lock)
            except OSError:
                pass


def gravar_atomico(caminho: str, texto: str) -> None:
    os.makedirs(os.path.dirname(caminho) or ".", exist_ok=True)
    tmp = f"{caminho}.{os.getpid()}.tmp"
    try:
        with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(texto)
        for tentativa in range(20):
            try:
                os.replace(tmp, caminho)
                return
            except PermissionError:  # Windows: leitor com o destino aberto; tenta de novo
                if tentativa == 19:
                    raise
                time.sleep(0.01)
    finally:
        if os.path.exists(tmp):
            try:
                os.remove(tmp)
            except OSError:
                pass
