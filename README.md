# ci-scripts-linux

Scripts de infraestrutura para Home Labs, VPS e ambientes de clientes: backup, monitoramento,
provisionamento, manutenção e um painel central de acesso.

## Estrutura

```
backup/          backup_multiperfil.sh, restaurar_backup.sh
monitoring/      health_check.sh, network_scanner.sh
provisioning/    setup_pos_instalacao.sh, inventario_universal.sh
maintenance/     manutencao_avancada.sh
panel/           painel.sh (menu central)
lib/common.sh    funções compartilhadas (log, require_root, detect_real_user, confirm)
install.sh       instala os scripts em ~/scripts (flat), compatível com o painel e crontabs
```

Cada categoria tem seu próprio `README.md` com detalhes de uso.

## Instalação

```bash
git clone <url-do-repo> ci-scripts-linux
cd ci-scripts-linux
sudo ./install.sh
```

Isso copia todos os scripts para `~/scripts/` (mantendo a estrutura plana esperada pelo `painel.sh`
e por crontabs já configurados em máquinas de clientes) e oferece criar o atalho global `painel`.

Depois:

```bash
painel
```

## Padrões usados em todos os scripts

- `set -uo pipefail` + tratamento explícito de código de saída onde `set -e` atrapalharia (ex.: `tar`).
- `lib/common.sh`: logging padronizado (`log_info`, `log_ok`, `log_warn`, `log_error`, `die`),
  `require_root`, `detect_real_user` (sem `eval`) e `confirm`.
- Scripts que alteram o sistema (provisionamento, manutenção, restauração) exigem `sudo` e falham
  cedo se rodados sem privilégio.
- Arrays em vez de strings com word-splitting para listas de caminhos/portas.

## CI

Todo push/PR roda [ShellCheck](https://www.shellcheck.net/) via GitHub Actions
(`.github/workflows/shellcheck.yml`). Rode localmente antes de commitar:

```bash
shellcheck **/*.sh
```

## Scripts adicionados nesta organização

`health_check.sh`, `inventario_universal.sh` e `manutencao_avancada.sh` eram referenciados pelo
`painel.sh` original mas ainda não existiam — foram criados do zero seguindo o mesmo padrão dos
demais. Revise os limiares e comandos antes de rodar em produção de cliente.
