# Changelog

Histórico de mudanças do `ci-scripts-linux`. Formato baseado em
[Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) — cada release lista o que foi
**Adicionado**, **Corrigido** ou **Alterado**, com o número do PR entre parênteses.

Pra saber a versão instalada numa máquina: `painel` mostra no cabeçalho, ou confira
`~/scripts/VERSION` diretamente.

## [Não lançado]

### Adicionado

- `maintenance/verificar_agendamentos.sh` — detecta se o cron parou de chamar o backup (por
  perfil), a atualização automática ou o simulado de restauração, mesmo sem nenhum deles ter
  "falhado" no sentido que `alert_webhook` entende (o problema clássico: ninguém percebe que o
  backup parou de rodar até precisar restaurar). Compara o heartbeat mais recente de cada um com
  um limite esperado — pra atualização automática, estimado a partir da própria linha de cron
  criada pelo `--agendar`. Nova função `marcar_execucao_ok` em `lib/common.sh`, chamada por
  `backup_multiperfil.sh`, `atualizar_sistema.sh` e `simulado_restauracao.sh` ao terminar com
  sucesso. Também disponível no `painel` (opção 11).
- `maintenance/atualizar_sistema.sh` — só `apt-get update` + `apt-get full-upgrade`, sem o resto da
  limpeza do `manutencao_avancada.sh` (Docker, Flatpak, Snap etc.), pra deixar agendado sem
  supervisão com menos risco. Assistente embutido (`--agendar`/`--desagendar`) cria/remove a entrada
  no crontab do root, sem precisar editar `crontab -e` manualmente; rodar `--agendar` de novo
  substitui o agendamento anterior em vez de duplicar. Também disponível no `painel` (opção 10).
- `rclone_usuario` (roda o rclone como o usuário real sob `sudo`) movida de `backup_multiperfil.sh`
  pra `lib/common.sh`, compartilhada com o novo fluxo de download do `restaurar_backup.sh`.
- `restaurar_backup.sh` pode baixar do remoto (`RCLONE_REMOTO`) antes de restaurar, se o backup
  local não existir mais — fecha o ciclo do backup remoto pra recuperação de desastre de verdade.
- `backup_multiperfil.sh` lê a configuração de `~/scripts/backup.conf` (`RETENCAO_DIAS`,
  `EXCLUDE_PATTERNS`, `RCLONE_REMOTO`, `RCLONE_FLAGS`, `WEBHOOK_URL`), criado pelo `install.sh` na
  primeira instalação. Antes, o envio remoto só funcionava com `sudo -E` e a variável no ambiente,
  então pelo `painel` (que chama `sudo` sem `-E`) nunca era enviado nada. O arquivo é lido sem
  `source` (só os nomes permitidos), pela nova função `load_conf` de `lib/common.sh`.
- `RCLONE_REMOTO` aceita pasta local como destino (ex.: segundo HD); se ela não existir (disco
  desmontado), o envio é pulado com aviso em vez de gravar no disco do sistema.

### Alterado

- Via `sudo`, o envio do `backup_multiperfil.sh` roda o rclone como o usuário real: usa o
  `rclone.conf` dele e não grava como root no destino nem no `rclone.conf` (que o rclone reescreve
  ao renovar o token). Quem configurou o remote com `sudo rclone config` e roda o backup via `sudo`
  precisa configurar o remote também no usuário normal.

### Corrigido

- Rodando pelo cron do root (`/etc/cron.d`, `crontab -e` como root — o próprio exemplo de crontab
  do `backup/README.md`), sem `sudo`, `detect_real_user` concluía que o usuário real era o root: o
  backup ia pra `/root/backups_sistema` em vez de `~/backups_sistema`, e o perfil `docs` procurava
  `/root/Documentos` e saía só com o `/etc`, sem erro nenhum. Agora, como root e sem `SUDO_USER`,
  usa o dono do script (os scripts ficam em `~/scripts` do usuário); `CI_REAL_USER` força um
  usuário explicitamente. `rclone_usuario` também deixa de depender de `SUDO_USER`, pra o envio
  remoto usar o `rclone.conf` do usuário real no cron. Achado real no PC da recepção em 2026-10-20,
  depois de 18 dias de backup indo pro lugar errado.
- `simulado_restauracao.sh` conta como falha um backup mais recente com mais de `IDADE_MAX_DIAS`
  dias (padrão 3) — antes ele "passava" testando sempre o mesmo arquivo antigo enquanto o backup de
  verdade tinha parado (ou ia pra outra pasta), escondendo o problema acima.
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
