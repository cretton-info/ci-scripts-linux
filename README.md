# ci-scripts-linux

Scripts de infraestrutura para Home Labs, VPS e ambientes de clientes: backup, monitoramento,
provisionamento, manutenção e um painel central de acesso.

## Estrutura

```
backup/          backup_multiperfil.sh, restaurar_backup.sh, simulado_restauracao.sh
monitoring/      health_check.sh, network_scanner.sh
provisioning/    setup_pos_instalacao.sh, inventario_universal.sh, apps.conf
maintenance/     manutencao_avancada.sh
panel/           painel.sh (menu central)
lib/common.sh    funções compartilhadas (log, require_root, detect_real_user, confirm)
lib/logrotate.conf  regra de rotação dos logs, instalada automaticamente em /etc/logrotate.d
install.sh       instala os scripts em ~/scripts (flat), compatível com o painel e crontabs
docs/SCRIPTS.md  referência detalhada de cada script
docs/BACKUP_REMOTO.md  passo a passo do backup remoto via rclone (Google Drive)
tests/           testes automatizados (bats-core) de lib/common.sh
```

Cada categoria tem seu próprio `README.md` com detalhes de uso. Para a documentação completa de
cada script (o que faz, parâmetros, variáveis de ambiente, o que altera no sistema), veja
[docs/SCRIPTS.md](docs/SCRIPTS.md).

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

## Destaques

- **Backup verificado**: todo backup ganha um checksum SHA-256 na criação; a restauração confere
  esse checksum antes de tocar em qualquer arquivo e recusa restaurar um backup corrompido.
- **Backup preventivo automático**: restaurar no modo "locais originais" salva o estado atual antes
  de sobrescrever, para permitir reverter.
- **Exclusão de lixo no backup**: `.git`, `node_modules`, `__pycache__` e `.cache` ficam de fora por
  padrão; padrões extras via `EXCLUDE_PATTERNS`.
- **Inventário configurável**: apps desktop verificados (`inventario_universal.sh`) vêm de
  `apps.conf`, editável sem tocar no script; sobrevive a reinstalações.
- **Provisionamento resiliente**: um PPA de terceiro fora do ar não aborta o provisionamento inteiro.

## Logs automáticos

Todo `log_warn`/`log_error` (e portanto `die`) grava automaticamente em arquivo, além de aparecer no
terminal — não precisa de nenhuma configuração extra por script. Local, um arquivo por script:

- `sudo` / root: `/var/log/ci-scripts-linux/<script>.log`
- Usuário comum: `~/.local/state/ci-scripts-linux/logs/<script>.log`
- Se nenhum dos dois for gravável: `/tmp/ci-scripts-linux-logs/<script>.log`

Para forçar outro local: `CI_LOG_DIR=/caminho sudo ~/scripts/manutencao_avancada.sh`.

**Rotação automática:** rodando `sudo ./install.sh`, a regra de rotação (`lib/logrotate.conf`) é
instalada em `/etc/logrotate.d/ci-scripts-linux` automaticamente — o `logrotate` do sistema (já roda
diariamente sozinho) cuida do resto. Numa reinstalação, um `logrotate.d/ci-scripts-linux` já existente
nunca é sobrescrito.

## CI

Todo push/PR roda [ShellCheck](https://www.shellcheck.net/) e os testes automatizados via GitHub
Actions (`.github/workflows/shellcheck.yml`). Rode localmente antes de commitar:

```bash
shellcheck **/*.sh
bats tests/
```

`bats` ([bats-core](https://github.com/bats-core/bats-core)) é um framework de testes pra scripts
Bash. Instale com `sudo apt-get install -y bats` (Debian/Ubuntu) ou veja outras opções no repositório
oficial. Os testes cobrem as funções de `lib/common.sh` (`has_cmd`, `confirm`, `detect_real_user`,
`alert_webhook`, etc.) — não precisam de root e não alteram nada no sistema.
