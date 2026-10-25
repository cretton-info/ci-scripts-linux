# Ideias e Melhorias Futuras

Backlog de sugestões levantadas em revisão do repositório (2026-09-30, atualizado 2026-10-25). Não
são compromissos, só ideias anotadas para não perder — implementar sob demanda.

## 💾 Backup remoto (adicionado em outubro/2026)

- ~~**Envio remoto do backup (rclone)**~~ — feito: `RCLONE_REMOTO` no `backup_multiperfil.sh`,
  múltiplos destinos simultâneos (rclone e/ou pasta local), configurável via `backup.conf`.
  Guia completo pro Google Drive em `docs/BACKUP_REMOTO.md`.
- ~~**Restaurar a partir do remoto**~~ — feito: `restaurar_backup.sh` baixa do remoto antes de
  restaurar quando o backup local não existe mais (recuperação de desastre de verdade, não só
  "ter uma cópia na nuvem").
- ~~**Pastas extras no backup (`ORIGENS_EXTRAS`)**~~ — feito: soma pastas extras a qualquer perfil
  (ex.: cofre do Obsidian fora de `~/Documentos`), restrito ao home do usuário real.
- ~~**Aviso de criptografia ausente**~~ — feito: `backup_multiperfil.sh` detecta se o destino
  remoto não é do tipo `crypt` do rclone e avisa (não bloqueia) — o backup inclui `/etc` e às vezes
  dados de cliente.

## ⏰ Agendamento (adicionado em outubro/2026)

- ~~**Agendar atualização automática do sistema**~~ — feito: `maintenance/atualizar_sistema.sh`
  (só `apt update` + `full-upgrade`, mais leve que a manutenção completa), com assistente
  `--agendar`/`--desagendar` que grava direto no crontab do root.
- ~~**Detectar cron que parou de rodar**~~ — feito: `maintenance/verificar_agendamentos.sh` +
  heartbeat (`marcar_execucao_ok` em `lib/common.sh`) gravado pelo backup (por perfil), pela
  atualização automática e pelo simulado de restauração — alerta se algum estiver atrasado ou
  nunca tiver rodado com sucesso apesar de agendado. Validou a própria necessidade: um bug real
  (ver abaixo) deixou o backup de documentos rodando errado por 18 dias sem ninguém notar.
- ~~**Visão unificada do que está agendado**~~ — feito: `maintenance/listar_agendamentos.sh`,
  lista as linhas do crontab (root + usuário real) relacionadas ao repositório de uma vez.

## 🐛 Bugs reais encontrados em produção

- ~~**`detect_real_user` caía pro root rodando sem `sudo` no cron do root**~~ — corrigido: achado
  no PC da recepção de um cliente (backup do perfil `docs` sem `~/Documentos` por 18 dias, sem
  nenhum erro visível). Prioridade agora: `CI_REAL_USER` > `SUDO_USER` > dono do script > usuário
  atual. `rclone_usuario` também parou de depender de `SUDO_USER`.
- ~~**`simulado_restauracao.sh` passava testando um backup velho**~~ — corrigido: agora reprova se
  o backup mais recente do perfil tiver mais de `IDADE_MAX_DIAS` (padrão 3) — antes um backup
  parado de rodar silenciosamente ainda "passava" o simulado testando o último arquivo que
  existia, por mais antigo que fosse.
- ~~**`ALERTA_COOLDOWN_HORAS` não tinha efeito via `backup.conf`**~~ — corrigido: faltava na lista
  de variáveis aceitas pelo `load_conf`.
- ~~**`rclone copy` não aceita duas origens + destino numa chamada**~~ — corrigido: uma chamada por
  arquivo (`.tar.gz` e `.sha256` separados).

## 🔔 Observabilidade

- ~~**Estender o webhook de alerta além do `health_check.sh`.**~~ — feito: `alert_webhook()` movida
  pra `lib/common.sh`, agora usada também por `backup_multiperfil.sh` (origem ausente, tar falhou,
  backup corrompido), `restaurar_backup.sh` (checksum não confere, espaço insuficiente) e
  `manutencao_avancada.sh` (falha em `full-upgrade`/`install -f`).
- ~~**Modo `--json` em `health_check.sh` e `inventario_universal.sh`**~~ — feito nos dois, validado
  com `jq`. `json_escape()` novo em `lib/common.sh` (trata aspas, barras, quebras de linha e
  caracteres de controle tipo cores ANSI). No caminho, achei e corrigi 3 bugs pré-existentes sem
  relação direta com o JSON: `free`/`lscpu` sem `LC_ALL=C` nunca casavam a etiqueta traduzida em
  locale pt_BR (alerta de memória e campo de CPU ficavam sempre vazios/nunca disparavam,
  silenciosamente); e `detectar_app` sem `</dev/null`+`timeout` travava o inventário inteiro se um
  app (ex.: Obsidian, Antigravity) não tratasse `--version` direito.
- ~~**Painel de frota**~~ — feito: novo script `monitoring/status_frota.sh` (opção 9 no `painel.sh`),
  agrega `health_check.sh --json` via SSH de vários hosts numa tabela só; host fora do ar não trava
  os outros. Config em `hosts.conf` (exemplo em `hosts.conf.example`).

## 🛡️ Confiabilidade

- ~~**Lock de concorrência no backup** (`flock`)~~ — feito em `backup_multiperfil.sh` (lock por
  perfil em `~/backups_sistema/.lock_<perfil>`).
- ~~**Guard-rail no `RETENCAO_DIAS`**~~ — feito em `backup_multiperfil.sh` (recusa valores < 1).
- ~~**Checar espaço livre antes de restaurar em `/`**~~ — feito em `restaurar_backup.sh` (soma o
  tamanho descompactado via `tar -tvzf` e compara com `df` do destino, nos dois modos).
- ~~**"Simulado de restauração" agendável**~~ — feito: novo script `backup/simulado_restauracao.sh`,
  não interativo, integrado ao `painel.sh` (opção 7) e ao `alert_webhook`.
- ~~**`--dry-run` na manutenção e no backup**~~ — feito nos dois: `manutencao_avancada.sh` usa
  `apt-get -s` pras etapas de pacote e só avisa nas demais; `backup_multiperfil.sh` mostra
  diretórios/exclusões/tamanho estimado sem criar nada.

## 🧪 Testes automatizados

- ~~**Testes com bats-core para `lib/common.sh`.**~~ — feito: `tests/common.bats` (18 testes) cobre
  `has_cmd`, `confirm`, `detect_real_user`, `log_*`/`die`, `require_root` e `alert_webhook`
  (incluindo cooldown), rodando no CI junto do ShellCheck. Parsing de `apps.conf` ficou de fora —
  vive em `inventario_universal.sh`, não em `lib/common.sh`; precisaria ser extraído pra uma função
  testável primeiro.

## ✨ Funcionalidades novas

- ~~**Notificação de conclusão, não só de falha**~~ — feito: `health_check.sh --resumo` manda um
  heartbeat pro webhook mesmo sem alerta, cooldown próprio via `RESUMO_COOLDOWN_HORAS` (padrão 24h,
  independente do cooldown dos alertas).
- ~~**Múltiplos destinos rclone simultâneos**~~ — feito: `RCLONE_REMOTO` aceita lista separada por
  vírgula, cada destino independente (falha num não impede os outros), alerta por destino via
  `alert_webhook`.
- ~~**`update.sh`**~~ — feito: `git pull` + `sudo ./install.sh`, com checagem de checkout git,
  aviso de alterações não commitadas, e relato correto se o `install.sh` falhar depois do pull
  (não finge sucesso).

## 📦 Distribuição / DX

- ~~**Versionamento com tags/CHANGELOG**~~ — feito: `CHANGELOG.md` novo (formato Keep a Changelog,
  release `v1.0.0` retroativa cobrindo tudo até aqui) e convenção de tags documentada no README.
- ~~**`painel.sh` mostrar a versão instalada**~~ — feito: `install.sh` grava `git describe --tags`
  em `~/scripts/VERSION`, mostrado no cabeçalho do `painel.sh`.

---

Todos os itens deste backlog foram implementados (última atualização: 2026-10-25). Novas ideias,
anote aqui.
