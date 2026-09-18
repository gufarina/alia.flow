Fixture do docs-check.ps1 (LEI 5, client-truth.md). fresh = OK; stale = doc mais velha que o MINOR; ficha = client.md sem a versao publicada.
Datas: doc = mtime do arquivo (sem git); o CHANGELOG stale esta datado em 2999 de proposito, determinismo sem relogio.
Pasta "fixture-clients" (nao "clients"): renomeada 07/09/2026 pra nao casar o padrao de material de
cliente real do check-public-surface.ps1; docs-check.ps1 chama com -ClientsDir fixture-clients.
