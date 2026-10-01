# Changelog

Histórico de mudanças do `ci-scripts-linux`. Formato baseado em
[Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) — cada release lista o que foi
**Adicionado**, **Corrigido** ou **Alterado**, com o número do PR entre parênteses.

Pra saber a versão instalada numa máquina: `painel` mostra no cabeçalho, ou confira
`~/scripts/VERSION` diretamente.

## [Não lançado]

### Corrigido

- `backup_multiperfil.sh` agora exige root de verdade (`require_root`) antes de rodar — todos os
  4 perfis incluem `/etc` (chaves SSH, segredos do Dokploy, `/etc/shadow`), então sem sudo o `tar`
  sempre falhava com "Permission denied" em dezenas de arquivos e saía com código 2, sem nenhuma
  pista do motivo (a mensagem de erro do `tar` ia pro `/dev/null`). `-h`/`--help` continua
  funcionando sem root. Achado real testando o `painel` no `ac8` em 2026-10-01.
- `backup_multiperfil.sh` não suprime mais o `stderr` do `tar` — se o backup falhar de verdade por
  outro motivo no futuro, as primeiras linhas do erro real aparecem no log em vez de só o código
  numérico.

## [1.0.0] — 2026-09-30

Primeira versão tagueada. Reúne tudo que existia até aqui — o repositório já vinha evoluindo desde
a organização inicial em categorias, só não tinha versionamento formal até agora.

### Adicionado

- Estrutura por categoria: `backup/`, `monitoring/`, `provisioning/`, `maintenance/`, `panel/`,
  `lib/common.sh` compartilhada (#1).
- Log automático de avisos/erros em arquivo, além da saída no terminal (#3).
- Documentação de referência de cada script em `docs/SCRIPTS.md` (#6).
- Verificação de integridade (checksum SHA-256) nos backups (#8).
- Detecção de apps desktop e slots de memória no inventário; `apps.conf` configurável (#9, #10).
- Retenção automática dos backups preventivos de restauração (#15).
- Rotação automática de logs e alerta via webhook no `health_check.sh` (#16).
- Envio remoto opcional de backup via rclone, com guia completo pro Google Drive (`docs/BACKUP_REMOTO.md`).
- Guard-rail no `RETENCAO_DIAS` — recusa valores inválidos em vez de arriscar apagar backups (#18).
- Lock de concorrência (`flock`) no `backup_multiperfil.sh` — evita execuções sobrepostas (#19).
- Verificação de espaço livre antes de restaurar, nos dois modos (#20).
- `alert_webhook()` estendida pra além do `health_check.sh` — `backup_multiperfil.sh`,
  `restaurar_backup.sh` e `manutencao_avancada.sh` também alertam (#21).
- `backup/simulado_restauracao.sh` — testa que os backups realmente restauram, sem alterar nada,
  seguro pra cron (#22).
- `--dry-run` no `backup_multiperfil.sh` e no `manutencao_avancada.sh` (#23).
- Testes automatizados (`bats-core`) pras funções de `lib/common.sh`, rodando no CI (#24).
- `--json` no `health_check.sh` e no `inventario_universal.sh`, pra alimentar dashboards (#25).
- `monitoring/status_frota.sh` — agrega `health_check.sh --json` via SSH de vários hosts numa
  tabela só (#26).
- `--resumo` no `health_check.sh` — heartbeat via webhook mesmo sem alerta, pra saber que o cron
  não parou (#27).
- `RCLONE_REMOTO` aceita vários destinos separados por vírgula, pra redundância 3-2-1 (#28).
- `update.sh` — `git pull` + `sudo ./install.sh` numa tacada só (#29).
- Versionamento: `install.sh` grava a versão instalada em `~/scripts/VERSION`, mostrada pelo
  `painel.sh` (este release).

### Corrigido

- Backup preventivo que engolia o `/root` inteiro ao restaurar um perfil com caminho dentro do
  home (#4).
- Painel quebrava via symlink e com permissão de execução perdida após clone (#5).
- Provisionamento abortava por inteiro se um repositório de terceiros (PPA) estivesse fora do ar
  (#2).
- `free`/`lscpu` sem `LC_ALL=C`: em locale pt_BR, alerta de memória nunca disparava e campo de CPU
  do inventário ficava sempre vazio, silenciosamente (#25).
- `detectar_app` sem `</dev/null`+`timeout`: travava a leitura do `apps.conf` depois do primeiro
  app, ou travava o script inteiro se um app (Obsidian, Antigravity) não tratasse `--version`
  direito (#25).
- `rclone copy` não aceita duas origens + destino numa chamada só — envio remoto do backup
  corrigido para uma chamada por arquivo.
