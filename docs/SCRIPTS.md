# Referência dos Scripts

Documentação detalhada de cada script do repositório: o que faz, requisitos, parâmetros,
o que altera no sistema e cuidados. Para instalação e padrões gerais, veja o [README principal](../README.md).

Convenção: comandos assumem os scripts já instalados via `sudo ./install.sh` (ficam em `~/scripts/`).

---

## lib/common.sh

Não é executado diretamente — é a biblioteca compartilhada que todo script `source`ia.

**Fornece:**

| Função/Variável | O que faz |
|---|---|
| `log_info "msg"` | Imprime `[INFO]` em azul no terminal. |
| `log_ok "msg"` | Imprime `[ OK ]` em verde no terminal. |
| `log_warn "msg"` | Imprime `[WARN]` em amarelo no terminal (stderr) **e grava em arquivo de log**. |
| `log_error "msg"` | Imprime `[ERRO]` em vermelho no terminal (stderr) **e grava em arquivo de log**. |
| `die "msg"` | Chama `log_error` e encerra o script com `exit 1`. |
| `require_root` | Aborta (`die`) se o script não estiver rodando como root/sudo. |
| `detect_real_user` | Preenche `REAL_USER` e `USER_HOME` com o usuário real por trás do `sudo` (usa `getent passwd`, não `eval`). |
| `load_conf arquivo VAR...` | Lê `VAR=valor` de um arquivo **sem executá-lo** (nunca faz `source`), aceitando só os nomes passados, tirando aspas em volta do valor e sem sobrescrever o que já veio do ambiente. Usado pelo `backup_multiperfil.sh` para o `backup.conf`. |
| `confirm "pergunta"` | Pergunta s/N interativa. Retorna 0 (sucesso) se a resposta for `s`/`S`. |
| `has_cmd nome` | Retorna 0 se o comando `nome` existe no `PATH`. |
| `alert_webhook "motivo" "detalhe"` | Envia um alerta em JSON para `WEBHOOK_URL` (se definida), com cooldown por motivo. Usado por qualquer script para reportar falhas — não faz nada se `WEBHOOK_URL` não estiver definida. |
| `json_escape "valor"` | Escapa uma string pra entrar com segurança dentro de um valor JSON (aspas, barra invertida, quebra de linha, tab e outros caracteres de controle, ex.: cores ANSI). Usado pelo modo `--json` de `health_check.sh` e `inventario_universal.sh`. |
| `rclone_usuario comando ...` | Roda `rclone` como o usuário real por trás do `sudo`, não como root — usa o `rclone.conf` de quem configurou os remotes. Requer `detect_real_user` já chamado antes. Usado por `backup_multiperfil.sh` e `restaurar_backup.sh`. |
| `marcar_execucao_ok "nome"` | Grava um timestamp em `<pasta do log>/heartbeats/<nome>.last`, marcando que um script terminou com sucesso. Usado por `backup_multiperfil.sh` (por perfil), `atualizar_sistema.sh` e `simulado_restauracao.sh`, lido por `verificar_agendamentos.sh` pra detectar se o cron parou de chamar algum deles. |
| `LOG_FILE` | Caminho do arquivo de log da execução atual (definido automaticamente ao sourcear). |

**Log automático:** toda chamada a `log_warn`/`log_error`/`die` grava uma linha com timestamp e PID
no arquivo de log, além de imprimir no terminal. Local:

- Root: `/var/log/ci-scripts-linux/<nome-do-script>.log`
- Usuário comum: `~/.local/state/ci-scripts-linux/logs/<nome-do-script>.log`
- Fallback: `/tmp/ci-scripts-linux-logs/<nome-do-script>.log`
- Customizável com a variável `CI_LOG_DIR`

Mensagens de `log_info`/`log_ok` (sucesso normal) **não** vão para o arquivo, só para o terminal —
o log guarda apenas avisos e erros.

**Resolução de symlinks:** todos os scripts calculam seu próprio diretório com
`readlink -f "${BASH_SOURCE[0]}"` antes de sourcear a lib, para funcionar corretamente mesmo quando
chamados por um link simbólico (caso do atalho global `painel` em `/usr/local/bin`).

**Alerta via webhook (`alert_webhook`):** função compartilhada usada por vários scripts para
reportar falhas remotamente, sem duplicar a lógica em cada um. Não faz nada se `WEBHOOK_URL` não
estiver definida.

- Payload: `{"hostname":"...","script":"...","motivo":"...","detalhe":"...","data":"..."}` — `script`
  é o nome do arquivo que chamou (ex.: `backup_multiperfil`), útil para distinguir a origem quando
  vários scripts alertam pro mesmo webhook.
- **Cooldown por motivo:** não reenvia o mesmo `motivo` antes de `ALERTA_COOLDOWN_HORAS` horas
  (padrão: `6`) — evita spam se o problema persistir entre execuções. O estado fica em arquivos
  `.last` dentro de `<diretório do log>/alertas/`, limpos manualmente se quiser resetar o cooldown.
- Se `WEBHOOK_URL` estiver definida mas `curl` não existir, avisa e segue sem travar o script.
- Quem chama hoje: `health_check.sh` (disco/memória/serviços), `backup_multiperfil.sh` (origem
  ausente, tar falhou, backup corrompido), `restaurar_backup.sh` (checksum não confere, espaço
  insuficiente) e `manutencao_avancada.sh` (falha grave de pacotes).

---

## backup/backup_multiperfil.sh

**O que faz:** cria um backup `.tar.gz` de um dos 4 perfis pré-definidos, com rotação automática de
backups antigos.

| Argumento | Pasta gerada em `~/backups_sistema/` | Origens |
|---|---|---|
| `docs` / `documentos` / `1` | `documentos/` | `/etc` + `~/Documentos` |
| `homelab` / `docker` / `2` | `homelab/` | `/etc` + `/var/www` + `/opt/docker-containers` |
| `scripts` / `automacao` / `3` | `scripts/` | `/etc` + `~/scripts` |
| `tudo` / `completo` / `4` | `completo/` | todas as anteriores combinadas |

Atenção: o nome da pasta gerada **não é sempre igual ao argumento** — `docs` grava em `documentos/`
e `tudo` grava em `completo/`. É esse nome de pasta (não o argumento) que o `restaurar_backup.sh`
lista na hora de escolher o que restaurar.

**Requisitos:** não exige root explicitamente, mas normalmente roda com `sudo` para conseguir ler
`/etc` e ajustar o dono do backup (`chown`) de volta pro usuário real.

**Uso:**

```bash
sudo ~/scripts/backup_multiperfil.sh homelab      # direto por parâmetro (cron)
sudo ~/scripts/backup_multiperfil.sh --menu       # menu interativo
sudo ~/scripts/backup_multiperfil.sh --help       # ajuda
sudo ~/scripts/backup_multiperfil.sh homelab --dry-run   # só mostra o que faria
```

**`--dry-run`:** mostra os diretórios incluídos, os padrões excluídos e um tamanho estimado (sem
contar exclusões nem compressão) — e sai, sem criar o `.tar.gz`, sem travar o lock, sem enviar pro
remoto e sem apagar backups antigos. Bom pra conferir a configuração de um cliente novo antes de
deixar rodando de verdade.

**Configuração:** as variáveis abaixo podem ficar em `~/scripts/backup.conf` (`VAR=valor`, uma
por linha), que o `install.sh` cria a partir de `backup/backup.conf` na primeira instalação e não
sobrescreve depois. O arquivo é lido sem ser executado (só as variáveis desta lista são aceitas), e
uma variável definida no ambiente tem prioridade sobre ele. `BACKUP_CONF` aponta para outro arquivo.
Vale só para este script — `restaurar_backup.sh` (`RETENCAO_PREVENTIVOS_DIAS`) e
`simulado_restauracao.sh` não leem `backup.conf`, só variável de ambiente.

**Variáveis de ambiente:**

- `RETENCAO_DIAS` — dias de retenção antes de apagar backups antigos do mesmo perfil (padrão: `7`).
  Precisa ser um inteiro >= 1; valores inválidos (0, negativo, texto) fazem o script recusar
  execução, em vez de arriscar apagar backups recém-criados na primeira rotação.
- `EXCLUDE_PATTERNS` — padrões extras a excluir do `.tar.gz`, separados por vírgula (ex.:
  `"*.log,tmp/*"`), somados aos padrões padrão sempre excluídos: `.git`, `node_modules`,
  `__pycache__`, `.cache`. Use `sudo -E` para a variável chegar ao processo com privilégio.
- `RCLONE_REMOTO` — `remote:caminho` do [rclone](https://rclone.org/) (ex.: `"b2:bucket/cliente-x"`).
  Se definida, envia o `.tar.gz` e o `.sha256` recém-criados para
  `<RCLONE_REMOTO>/<perfil>/` via `rclone copy` logo após a verificação de integridade local.
  Requer `rclone` instalado e configurado (`rclone config`); se o binário não existir, só avisa
  (`log_warn`) e segue com o backup local. Falha no envio remoto não afeta o backup local nem a
  rotação, e alerta via [`alert_webhook`](#libcommonsh) se `WEBHOOK_URL` estiver definida. Aceita
  **mais de um destino separados por vírgula** (ex.: `"b2:bucket-x,gdrive:pasta-y"`) pra redundância
  3-2-1 real — cada destino é enviado de forma independente, a falha num não impede o envio pros
  outros. Um destino que começa com `/` é uma pasta local (ex.: segundo HD); ela precisa existir,
  senão o envio pra ela é pulado com aviso (e alerta via webhook), para não gravar no disco do
  sistema quando o HD está desmontado. Via `sudo`, o rclone roda como o usuário real, com o
  `rclone.conf` dele. Defina em `backup.conf` ou use `sudo -E` para a variável chegar ao processo
  com privilégio.
- `RCLONE_FLAGS` — flags extras passadas ao `rclone copy` (ex.: `"--transfers 4"`).
- `WEBHOOK_URL` — se definida, alerta via [`alert_webhook`](#libcommonsh) quando não há nenhuma
  origem válida para o perfil, o `tar` falha, o backup sai corrompido logo após a criação, ou falha
  o envio para algum destino de `RCLONE_REMOTO`. Variável compartilhada com outros scripts
  (`health_check.sh`, `restaurar_backup.sh`) — cada um lê do próprio ambiente/`.conf`, mudar aqui
  não afeta os outros.
- `ALERTA_COOLDOWN_HORAS` — intervalo mínimo em horas entre alertas repetidos do mesmo motivo via
  webhook (padrão: `6`, definido em [`alert_webhook`](#libcommonsh)). Só tem efeito com
  `WEBHOOK_URL` definida.

  Passo a passo completo de configuração (Google Drive): [docs/BACKUP_REMOTO.md](BACKUP_REMOTO.md).

**O que grava no sistema:**

- `~/backups_sistema/<perfil>/backup_<perfil>_<data>.tar.gz`
- `~/backups_sistema/<perfil>/backup_<perfil>_<data>.tar.gz.sha256` — checksum gerado logo após a
  criação, usado pelo `restaurar_backup.sh` para detectar corrupção antes de restaurar.
- `~/backups_sistema/.lock_<perfil>` — arquivo de lock (`flock`) usado só para evitar execuções
  sobrepostas do mesmo perfil; fica vazio, não é um backup.
- Apaga (`find ... -delete`) backups e checksums do mesmo perfil com mais de `RETENCAO_DIAS` dias.

**Lock de concorrência:** antes de compactar, o script tenta um `flock` não bloqueante em
`~/backups_sistema/.lock_<perfil>`. Se já houver uma execução do mesmo perfil em andamento (ex.:
cron disparando de novo enquanto a anterior ainda está compactando uma origem grande), a nova
execução aborta na hora em vez de rodar em paralelo e arriscar um `.tar.gz` corrompido. Perfis
diferentes não bloqueiam um ao outro. Se `flock` não estiver disponível, o script avisa e segue sem
proteção (não é um requisito, é uma camada extra de segurança).

**Verificação de integridade:** depois de criar o `.tar.gz`, o script testa a leitura com
`tar -tzf` e grava o checksum. Se o teste falhar, apaga o arquivo corrompido e encerra com erro —
nunca deixa um backup ruim para trás.

**Comportamento com diretórios ausentes:** origens que não existem na máquina são ignoradas com
`log_warn` (não interrompe o backup) — por isso um mesmo perfil funciona tanto num home lab completo
quanto numa VPS mínima.

**Exit codes:** `1` se nenhuma das origens do perfil existir, ou se o `tar` falhar de verdade
(códigos de saída do `tar` diferentes de `0` e `1` — `1` é tolerado porque significa apenas "algum
arquivo mudou durante a leitura", comum em sistemas ativos). Uma falha no envio remoto (rclone)
**não** derruba o exit code — é só um `log_warn`.

---

## backup/restaurar_backup.sh

**O que faz:** assistente interativo para restaurar um backup gerado pelo `backup_multiperfil.sh`,
em dois modos:

1. **Locais originais** — sobrescreve os arquivos no sistema (`/`).
2. **Diretório temporário** — extrai em `~/restauracao_temp_<data>/` para auditoria/conferência sem
   tocar no sistema.

**Requisitos:** **sempre roda com `sudo`** (`require_root`).

**Uso:**

```bash
sudo ~/scripts/restaurar_backup.sh
```

Fluxo: (se houver `RCLONE_REMOTO` configurado) escolhe baixar do remoto ou usar backup local →
escolhe o perfil → escolhe o arquivo `.tar.gz` (lista ordenada do mais recente) → **verificação
de integridade** → escolhe o modo de destino.

**Baixar do remoto antes de restaurar:** se `RCLONE_REMOTO` estiver configurado em `backup.conf`
(mesmo arquivo do `backup_multiperfil.sh` — ver seção anterior) e o `rclone` estiver instalado, o
script pergunta se quer restaurar a partir dos backups locais ou baixar do remoto primeiro. Nesse
segundo caso: lista os perfis (pastas) disponíveis no remote, lista os `.tar.gz` desse perfil (mais
recente primeiro), baixa o escolhido junto com o `.sha256` (se existir) para
`~/backups_sistema/<perfil>/`, e segue o fluxo normal de restauração a partir daí. Se o arquivo já
tiver sido baixado antes (mesmo nome), não baixa de novo. Existindo mais de um destino em
`RCLONE_REMOTO` (redundância 3-2-1), pergunta de qual deles baixar. É a forma de recuperar um backup
quando o disco local original foi perdido e só resta a cópia na nuvem/HD externo — sem essa opção, o
backup remoto não servia pra nada numa recuperação de desastre de verdade.

**Verificação de integridade (antes de qualquer restauração, nos dois modos):** confere o checksum
`.sha256` salvo junto do backup, se existir. Se não bater, aborta sem tocar em nada. Se o backup for
antigo e não tiver `.sha256`, cai para um teste de leitura com `tar -tzf` como fallback.

**Rede de segurança no modo "locais originais":**

1. Lista os primeiros 20 itens do backup antes de pedir confirmação.
2. Pede confirmação explícita (`s`/N) antes de sobrescrever qualquer coisa.
3. **Cria automaticamente um backup preventivo** do estado atual dos caminhos que serão
   sobrescritos, em `~/backups_sistema/_seguranca_pre_restauracao/pre_restore_<perfil>_<data>.tar.gz`,
   antes de extrair o backup escolhido.

O preventivo é calculado a partir das raízes reais do backup (ex.: `etc/`, `root/scripts/`), não do
primeiro componente do caminho — isso evita que um perfil com um caminho dentro do home (como
`~/scripts`) acabe copiando o diretório home inteiro.

**Retenção dos preventivos:** depois de criar um novo preventivo, o script remove os anteriores
(`pre_restore_*.tar.gz` em `~/backups_sistema/_seguranca_pre_restauracao/`) com mais de
`RETENCAO_PREVENTIVOS_DIAS` dias (padrão: `30`) — sem isso, cada restauração no modo "locais
originais" deixaria mais um arquivo acumulando pra sempre.

**Para reverter uma restauração ruim:**

```bash
sudo tar -xzf ~/backups_sistema/_seguranca_pre_restauracao/pre_restore_<perfil>_<data>.tar.gz -C /
```

**Verificação de espaço livre (antes de extrair, nos dois modos):** soma o tamanho descompactado de
todos os arquivos do backup (via `tar -tvzf`) e compara com o espaço livre no destino (via `df`). Se
o espaço disponível for menor que o necessário, aborta **antes** de começar a extrair — uma extração
interrompida pela metade por falta de espaço é pior que não restaurar nada, especialmente com
`TARGET_DIR=/`. Se não for possível calcular um dos dois lados, apenas avisa e segue sem a checagem.

**Exit codes:** `1` em qualquer seleção inválida (perfil, arquivo ou modo inexistente), espaço em
disco insuficiente no destino, ou falha do `tar` na extração final.

**Alerta via webhook:** se `WEBHOOK_URL` estiver definida, alerta via
[`alert_webhook`](#libcommonsh) quando o checksum não confere (ou não é possível ler o backup) e
quando falta espaço no destino.

---

## backup/simulado_restauracao.sh

**O que faz:** confere que os backups realmente restauram, sem alterar nada no sistema real. Pega o
backup mais recente de um perfil (ou de todos os perfis encontrados, se nenhum for passado), extrai
num diretório temporário (`mktemp -d`), confere a integridade (mesma lógica do
`restaurar_backup.sh`: checksum se existir, senão `tar -tzf`) e a presença de um arquivo-chave
dentro do conteúdo extraído — depois apaga o diretório temporário. Não interativo, pensado pra rodar
via cron sem supervisão.

**Requisitos:** nenhum privilégio especial (só precisa conseguir ler `~/backups_sistema`).

**Uso:**

```bash
bash ~/scripts/simulado_restauracao.sh              # todos os perfis encontrados
bash ~/scripts/simulado_restauracao.sh homelab       # só um perfil
```

**Variáveis de ambiente:**

- `ARQUIVO_CHAVE` — caminho (relativo à raiz do `.tar.gz`) que precisa existir no backup extraído
  pra ele ser considerado válido (padrão: `etc/passwd` — presente em todo perfil, já que `/etc`
  sempre é incluído em `backup_multiperfil.sh`).
- `WEBHOOK_URL` — se definida, alerta via [`alert_webhook`](#libcommonsh) quando um simulado falha
  (perfil sem backup, checksum não confere, extração falha ou arquivo-chave ausente).

**Exit codes:** `1` se qualquer perfil testado tiver falhado (útil pra cron detectar problema via
código de saída, sem precisar parsear a saída); `0` se todos os perfis passaram.

---

## monitoring/health_check.sh

**O que faz:** raio-x rápido de saúde do sistema — modelo de CPU, uptime/carga, memória, disco, top 5
processos por CPU, top 5 processos por RAM, conectividade com a internet e resolução DNS, serviços
`systemd` falhando e status de contêineres Docker.

**Requisitos:** nenhum privilégio especial (mas ver Docker abaixo).

**Uso:**

```bash
bash ~/scripts/health_check.sh
LIMIAR_DISCO=90 LIMIAR_MEM=95 bash ~/scripts/health_check.sh
bash ~/scripts/health_check.sh --json          # saída em JSON pra dashboard/script
```

**`--json`:** imprime um único objeto JSON em vez do texto colorido (nada de `echo` decorado) — só
dados, pra alimentar um dashboard, um `jq`, ou qualquer outra automação sem precisar interpretar
texto. Campos: `hostname`, `data`, `cpu_modelo`, `uptime`, `memoria_uso_pct`, `disco` (array),
`top_cpu`/`top_mem` (arrays), `conectividade` (`internet`/`dns` booleanos), `servicos_falhando`
(array de nomes) e `docker_containers` (array, vazio se Docker não estiver instalado). Os alertas via
webhook continuam disparando normalmente nesse modo.

**Variáveis de ambiente:**

- `LIMIAR_DISCO` — percentual de uso de disco a partir do qual a partição é destacada em vermelho e dispara alerta (padrão: `85`).
- `LIMIAR_MEM` — percentual de uso de memória a partir do qual dispara alerta (padrão: `90`).
- `WEBHOOK_URL` — se definida, alerta via [`alert_webhook`](#libcommonsh) quando disco/memória
  passam do limiar ou há serviço `systemd` em falha (vazio por padrão — nenhum alerta é enviado).
- `ALERTA_COOLDOWN_HORAS` — intervalo mínimo entre alertas do mesmo motivo, pra não repetir o mesmo aviso a cada execução enquanto o problema persiste (padrão: `6`).
- `RESUMO_COOLDOWN_HORAS` — intervalo mínimo entre resumos de conclusão (ver `--resumo` abaixo), independente do cooldown dos alertas (padrão: `24`).

**Conectividade:** testa `ping` para `1.1.1.1` (internet por IP) e `google.com` (resolução DNS),
2 tentativas de 2s cada. Falha aqui pode ser rede real ou um ambiente que bloqueia ICMP (ex.:
firewall corporativo, sandbox restrita) — não é necessariamente um problema na máquina.

**Alerta via webhook:** um alerta por partição/serviço/memória que estourar o limiar, via
`alert_webhook` (ver `lib/common.sh` acima para payload e cooldown). Só é útil de verdade rodando
via cron (ver `monitoring/README.md`) — chamado manualmente, o alerta só sai na hora que você rodou.

**`--resumo`:** além dos alertas de problema, manda um "heartbeat" pro webhook com um resumo
(`mem X%, disco máx Y%, N serviço(s) falhando, internet=.../dns=...`) mesmo quando está tudo bem —
motivo `resumo`, cooldown próprio via `RESUMO_COOLDOWN_HORAS` (padrão 24h, independente do cooldown
dos alertas normais). Serve pra saber que o cron ainda está rodando: silêncio total pode significar
"tudo bem" ou "o cron parou", e sem isso não dá pra diferenciar de fora.

**Observações:**

- Se rodado sem permissão de acessar o socket do Docker, mostra `[WARN]` em vez de travar.
- Não grava nada no sistema — só leitura e exibição (exceto os arquivos de cooldown do webhook, se usado).
- O cálculo de uso de memória usa `LC_ALL=C free` internamente — em locales que traduzem a etiqueta
  `Mem:` (ex.: pt_BR usa `Mem.`), o `free` sem essa variável faz o cálculo (e o alerta) nunca
  disparar, silenciosamente.

---

## monitoring/network_scanner.sh

**O que faz:** descobre hosts ativos na sub-rede local (ping sweep paralelo, 254 IPs) e testa um
conjunto de portas comuns (22, 80, 443, 3389, 8080, 8443) em cada host encontrado.

**Requisitos:** nenhum privilégio especial. Precisa conseguir detectar o gateway padrão
(`ip route show default`) — falha com mensagem clara se não houver rede configurada.

**Uso:**

```bash
bash ~/scripts/network_scanner.sh
```

**Como funciona:**

1. Detecta a sub-rede a partir do gateway padrão (assume `/24`).
2. Dispara pings em paralelo (`ping -c 1 -W 1`) para os 254 hosts possíveis.
3. Para cada host que respondeu, mostra IP, MAC (tabela ARP) e hostname reverso (se houver).
4. Testa as portas comuns via `/dev/tcp` com timeout de 0.6s por porta.

**Cuidados:** faz uma varredura de portas em toda a sub-rede — em ambiente de cliente, confirme que
isso está dentro do escopo autorizado antes de rodar contra redes que não são suas.

---

## monitoring/status_frota.sh

**O que faz:** roda `health_check.sh --json` via SSH em cada host listado em `hosts.conf` e mostra
um resumo numa tabela só (host, status, % memória, % disco máximo, serviços falhando,
conectividade). Não altera nada nos hosts remotos — só leitura. Útil pra checar vários
clientes/VPS de uma vez sem entrar host por host.

**Requisitos:** `jq` e `ssh` instalados; acesso SSH sem senha (chave configurada previamente) a
cada host; o `ci-scripts-linux` já instalado (`~/scripts/`) em cada host remoto.

**Uso:**

```bash
cp ~/scripts/hosts.conf.example ~/scripts/hosts.conf   # na primeira vez
nano ~/scripts/hosts.conf                               # edite com seus hosts
bash ~/scripts/status_frota.sh
```

**Configuração (`hosts.conf`):** um destino SSH por linha (alias do `~/.ssh/config` ou
`usuario@host`). Linhas em branco ou começando com `#` são ignoradas. **Uma reinstalação
(`install.sh`) nunca sobrescreve um `hosts.conf` já existente.**

**Variáveis de ambiente:**

- `HOSTS_CONF` — caminho do arquivo de hosts (padrão: `hosts.conf` ao lado do script).
- `LIMIAR_DISCO` / `LIMIAR_MEM` — mesmos limiares do `health_check.sh` (padrão: `85`/`90`), usados
  aqui só para decidir se a linha do host aparece como `ALERTA` na tabela.
- `SSH_TIMEOUT` — timeout de conexão por host em segundos (padrão: `8`) — um host fora do ar não
  trava a checagem dos outros, só aparece como `OFFLINE`.

**Status `ALERTA`** quando memória ou disco passam do limiar, há algum serviço `systemd` falhando,
ou não há conectividade com a internet naquele host. **`OFFLINE`** quando o SSH falha ou a resposta
não é um JSON válido (ex.: `ci-scripts-linux` desatualizado sem `--json`, ou não instalado).

**Exit codes:** `1` se algum host ficou em `ALERTA` ou `OFFLINE` (útil pra cron detectar problema
pelo código de saída), `0` se todos os hosts estão OK.

---

## provisioning/setup_pos_instalacao.sh

**O que faz:** provisionamento pós-instalação de uma máquina Debian/Ubuntu/Zorin nova: atualização
de pacotes, utilitários essenciais, firewall, Docker e estrutura de diretórios padrão.

**Requisitos:** **sempre roda com `sudo`**.

**Uso:**

```bash
sudo ~/scripts/setup_pos_instalacao.sh
```

**O que faz, em ordem (5 etapas anunciadas no terminal):**

1. `apt-get update && apt-get upgrade` — **não aborta** se algum repositório de terceiros
   (PPA) falhar; apenas avisa e segue com o que conseguiu atualizar.
2. Instala pacotes essenciais: `curl wget git htop net-tools ufw fail2ban ca-certificates gnupg
   lsb-release tree unzip software-properties-common ncdu`.
3. Configura UFW: `deny incoming` / `allow outgoing` por padrão, libera `22/tcp`, `80/tcp`, `443/tcp`,
   e habilita o firewall.
4. Instala Docker Engine + Compose plugin a partir do repositório oficial (se ainda não estiver
   instalado) e adiciona o usuário real ao grupo `docker`.
5. Cria `~/scripts`, `~/backups_sistema`, `~/docker_stacks`.

Ao final, roda `apt-get autoremove && apt-get clean` silenciosamente (sem número de etapa próprio no
terminal, mas sempre executado).

**Cuidados:**

- Altera o firewall da máquina (UFW). Se a máquina for acessada só por SSH numa porta não-padrão,
  ajuste as regras antes/depois.
- Depois de rodar, o usuário precisa fazer logout/login para o grupo `docker` ter efeito sem `sudo`.

---

## provisioning/inventario_universal.sh

**O que faz:** inventário de hardware e sistema operacional — hostname, modelo da máquina, SO,
kernel, CPU, GPU, memória, slots de RAM (ocupados/livres), placa-mãe, BIOS, discos/partições,
interfaces de rede, versões de runtimes relevantes (Docker, Compose, git, Python, Node, NPM), status
do UFW e do Tailscale, presença do Ollama e presença de apps desktop. Mostra o essencial no terminal
**e grava dois relatórios em Markdown** — `hardware_<modelo>.md` e `software_<modelo>.md` — com mais
detalhe que o terminal: GPU e status do UFW/Tailscale/Ollama só aparecem nos arquivos gerados, não
na tela (apps desktop aparecem nos dois).

**Requisitos:** nenhum privilégio especial para a exibição básica; modelo da máquina, placa-mãe,
BIOS e slots de memória exigem root (`dmidecode`) — sem `sudo` essas seções mostram um aviso e caem
em fallback (modelo = hostname) sem travar o resto.

**Uso:**

```bash
bash ~/scripts/inventario_universal.sh          # sem modelo/placa-mãe/BIOS/slots de RAM
sudo ~/scripts/inventario_universal.sh          # inventário completo
bash ~/scripts/inventario_universal.sh --json   # saída em JSON, sem gravar nada em disco
```

**`--json`:** imprime um único objeto JSON pra stdout em vez de mostrar na tela — e, diferente do
modo normal, **não grava os relatórios `.md`** (é um modo "só dados", pensado pra rodar com
frequência num dashboard sem acumular arquivo repetido). Campos: `hostname`, `modelo`, `placa_mae`,
`bios`, `so`, `kernel`, `arquitetura`, `cpu` (`modelo`/`nucleos`), `memoria` (`total`/slots), `gpu`,
`discos` (array), `armazenamento_raiz`, `interfaces_rede` (array), `enderecos_mac` (array), `ufw`,
`tailscale`, `ollama`, `runtimes` (docker/compose/git/python3/node/npm) e `apps_desktop` (array de
`nome`/`status`).

**O que grava no sistema (modo normal, sem `--json`):** a cada execução, sobrescreve
`~/inventario/hardware_<modelo>.md` e `~/inventario/software_<modelo>.md` — `<modelo>` é a primeira
palavra do `dmidecode -s system-product-name` (ou o hostname, sem `sudo` ou sem dados de BIOS). Os
arquivos ficam na home do usuário real, mesmo rodando com `sudo` (`chown` de volta pro usuário real
no fim). Útil para levar pro Obsidian ou documentar o estado de uma máquina de cliente.

**Detecção de apps desktop:** a lista de apps vem de `apps.conf` (instalado junto em
`~/scripts/apps.conf`, formato `Nome|termo de busca|comando1,comando2,...` documentado no próprio
arquivo). Para cada app, verifica nesta ordem — comando no `PATH` (com `timeout 3` e stdin
redirecionado de `/dev/null`, pra não travar nem quebrar a leitura do `apps.conf` se o app ignorar
`--version`), pacote `apt`, `flatpak`, `snap`, atalho `.desktop` em `/usr/share/applications` ou
`~/.local/share/applications` — e para no primeiro método que encontrar. Se `apps.conf` não existir,
cai para uma lista padrão embutida reduzida (Obsidian, VS Code, Antigravity, Wine). **Uma
reinstalação (`install.sh`) nunca sobrescreve um `apps.conf` já existente** — edite-o livremente
para adicionar/remover apps. Alguns apps Electron (Obsidian, Antigravity) não tratam `--version`
direito e chegam a abrir a janela normal antes do timeout cortar — a detecção funciona mesmo assim,
só a "versão" exibida pra eles é decorativa (ver aviso em `provisioning/apps.conf`).

**Slots de memória:** usa `dmidecode -t 17`, contando entradas "Memory Device" (total de slots) e
quantas têm `Size: No Module Installed` (slots livres). Em VMs sem BIOS/firmware completo, o
`dmidecode` pode não retornar dados mesmo como root — o script avisa e segue sem travar.

Útil para documentar o estado de uma máquina de cliente na entrada de um contrato, ou para
diagnóstico rápido remoto.

O modelo da CPU usa `LC_ALL=C lscpu` internamente — em locales que traduzem a etiqueta `Model name`
(ex.: pt_BR usa `Nome do modelo`), o `lscpu` sem essa variável deixava o campo sempre vazio.

---

## maintenance/manutencao_avancada.sh

**O que faz:** rotina completa de manutenção e limpeza — atualização e correção de pacotes,
limpeza de Flatpak/Snap/Docker, lixeira/cache do usuário, TRIM de SSD e verificação de reboot
pendente.

**Requisitos:** **sempre roda com `sudo`**.

**Uso:**

```bash
sudo ~/scripts/manutencao_avancada.sh          # interativo
sudo ~/scripts/manutencao_avancada.sh --yes    # sem confirmação (cron)
AUTO_YES=1 sudo -E ~/scripts/manutencao_avancada.sh   # equivalente ao --yes
sudo ~/scripts/manutencao_avancada.sh --dry-run       # só mostra o que faria
```

**`--dry-run`:** mostra o que cada uma das 9 etapas faria, sem alterar nada de verdade. Nas etapas
de pacotes (1, 2 e 3) usa o modo `--simulate` (`-s`) nativo do `apt-get`, que lista os pacotes reais
que seriam instalados/removidos. Nas demais, só avisa o que não foi executado (ex.: tamanho atual
dos logs do journal, revisões do Snap que seriam removidas). Ainda precisa de `sudo` porque algumas
consultas (`apt-get -s`, `journalctl`) exigem privilégio mesmo só pra simular.

**O que faz, em ordem (9 etapas):**

1. `apt-get update && apt-get full-upgrade` — não aborta se um repositório de terceiros falhar.
2. `apt-get install -f && apt-get check` — corrige dependências quebradas.
3. `apt-get autoremove --purge && apt-get autoclean`.
4. `journalctl --vacuum-size=$JOURNAL_MAX_SIZE --vacuum-time=$JOURNAL_MAX_AGE`.
5. `flatpak uninstall --unused` — só se o Flatpak estiver instalado.
6. Limpa cache do Snap (`/var/lib/snapd/cache`) e remove revisões desabilitadas — só se o Snap
   estiver instalado.
7. **Pede confirmação** (mostra `docker system df` antes) e, se confirmado, roda
   `docker system prune -f` — remove imagens, redes e cache de build não usados por nenhum
   contêiner em execução. **Não afeta contêineres nem volumes ativos.**
8. Limpa `~/.local/share/Trash` e `~/.cache/thumbnails` do usuário real.
9. `fstrim -av` — só se o comando existir; ignora silenciosamente discos que não suportam TRIM.

No final: `apt-get clean`, espaço livre em `/` antes/depois, memória, e um aviso se
`/var/run/reboot-required` existir (atualização de kernel/lib crítica pendente).

**Etapas puladas automaticamente** (sem travar) se a ferramenta não estiver instalada: Flatpak,
Snap, Docker, `fstrim`, `journalctl`.

**Variáveis de ambiente:**

- `JOURNAL_MAX_SIZE` — tamanho máximo dos logs do journal (padrão: `200M`).
- `JOURNAL_MAX_AGE` — idade máxima dos logs do journal (padrão: `30d`).
- `WEBHOOK_URL` — se definida, alerta via [`alert_webhook`](#libcommonsh) quando `apt-get
  full-upgrade` ou `apt-get install -f` falham (etapas 1 e 2) — a manutenção não aborta nesses
  casos, mas o alerta avisa que algo precisa de atenção manual.

**Variáveis/flags para uso não-interativo (cron):** `--yes`, `-y` ou `AUTO_YES=1` pulam a
confirmação da etapa 7 (Docker).

---

## maintenance/atualizar_sistema.sh

**O que faz:** só `apt-get update` + `apt-get full-upgrade`, nada mais — nenhuma limpeza, nenhum
`autoremove`, não toca em Docker/Flatpak/Snap. Mais leve e previsível que o `manutencao_avancada.sh`
pra deixar agendado sem supervisão num servidor de cliente, onde uma limpeza mais agressiva (ex.:
`docker system prune`) poderia incomodar. Tem um assistente embutido pra agendar no crontab do root
sem precisar editar `crontab -e` manualmente.

**Requisitos:** **sempre roda com `sudo`**.

**Uso:**

```bash
sudo ~/scripts/atualizar_sistema.sh              # roda agora
sudo ~/scripts/atualizar_sistema.sh --dry-run    # só mostra o que seria atualizado (apt-get -s)
sudo ~/scripts/atualizar_sistema.sh --agendar    # assistente: agenda no crontab do root
sudo ~/scripts/atualizar_sistema.sh --desagendar # remove o agendamento criado por --agendar
```

**`--agendar`:** pergunta a frequência (diária, ou semanal com dia da semana) e o horário (`HH:MM`),
valida as respostas, e grava uma linha no crontab do root terminada no marcador
`# ci-scripts-linux:atualizar_sistema`. Rodar `--agendar` de novo **substitui** o agendamento
anterior (filtra pelo marcador antes de adicionar a nova linha) em vez de duplicar — seguro chamar
mais de uma vez, inclusive pra só trocar o horário. Também disponível no `painel` (opção 10).

**`--desagendar`:** remove a linha do crontab do root que tem o marcador, se existir; avisa (não
falha) se não houver nenhum agendamento ativo.

**Atualização em si (sem `--agendar`/`--desagendar`):** `apt-get update` (continua mesmo se algum
repositório de terceiros falhar) seguido de `apt-get full-upgrade -y` com
`DEBIAN_FRONTEND=noninteractive` e `Dpkg::Options::="--force-confdef"`/`"--force-confold"` — mantém
a configuração atual em vez de travar esperando resposta sobre um arquivo de config modificado,
essencial pra não enguiçar rodando sem ninguém olhando via cron. Ao final, avisa se
`/var/run/reboot-required` existir (igual ao `manutencao_avancada.sh`).

**`--dry-run`:** `apt-get update` roda de verdade (só lê os repositórios, não altera nada); o
`full-upgrade` usa `apt-get full-upgrade -s` (simulação nativa do apt, lista os pacotes reais que
seriam instalados sem instalar nada).

**Variáveis de ambiente:**

- `WEBHOOK_URL` — se definida, alerta via [`alert_webhook`](#libcommonsh) quando `apt-get
  full-upgrade` falha.

**Exit codes:** `1` se o `apt-get full-upgrade` falhar (e nesse caso também alerta via webhook);
`0` em qualquer outro caso, incluindo `--dry-run`, `--agendar` e `--desagendar`.

---

## maintenance/verificar_agendamentos.sh

**O que faz:** detecta se o cron parou de chamar `backup_multiperfil.sh` (por perfil),
`atualizar_sistema.sh` ou `simulado_restauracao.sh`, mesmo que nenhum deles tenha "falhado" no
sentido que `alert_webhook` entende. Esses três scripts só alertam de dentro de si mesmos — se o
cron nunca chamar o script (crontab apagado, disco cheio, permissão quebrada depois de uma
reinstalação), nenhum alerta sai, porque o código que alertaria nunca roda. Este script verifica
por fora, comparando a idade do heartbeat mais recente de cada um ([`marcar_execucao_ok`]
(#libcommonsh)) com um limite esperado.

**Requisitos:** **sempre roda com `sudo`** (precisa ler o crontab do root e `/var/log/`).

**Uso:**

```bash
sudo ~/scripts/verificar_agendamentos.sh
```

**O que verifica, e só se encontrar configurado** (não precisa ter os três pra usar este script):

1. **Backup, por perfil** — qualquer pasta em `~/backups_sistema/<perfil>/` que já tenha pelo menos
   um `.tar.gz`. Limite: `AGENDAMENTO_MAX_HORAS_BACKUP` (padrão `48`).
2. **Atualização automática** — só se houver uma linha no crontab do root com o marcador do
   `atualizar_sistema.sh --agendar`. O limite não é uma variável: é estimado a partir do próprio
   campo "dia da semana" dessa linha de cron (`*` → diária, 36h de limite; específico → semanal,
   218h de limite) — o agendamento real é a fonte da verdade, não uma configuração duplicada.
3. **Simulado de restauração** — se `simulado_restauracao.sh` aparecer em qualquer crontab (do
   root ou do usuário real — ele não exige `sudo`, então pode estar em qualquer um dos dois). Limite:
   `AGENDAMENTO_MAX_HORAS_SIMULADO` (padrão `192` = 8 dias, pra agendamento semanal com margem).

Pra cada um: heartbeat ausente (nunca rodou com sucesso apesar de configurado) ou mais velho que o
limite → `log_error` + [`alert_webhook`](#libcommonsh) (motivos: `agendamento_backup_<perfil>`,
`agendamento_atualizacao`, `agendamento_simulado`). Dentro do limite → `log_ok`. Nada configurado
→ `log_info`, sem alertar (evita falso positivo em quem não usa os três).

**Onde procura o heartbeat:** em `/var/log/ci-scripts-linux/heartbeats/` (convenção de script
rodando como root, via `sudo crontab`) **e** em
`~/.local/state/ci-scripts-linux/logs/heartbeats/` do usuário real (convenção de script sem
exigência de `sudo` no crontab do próprio usuário) — usa o mais recente dos dois, já que
`backup_multiperfil.sh`/`atualizar_sistema.sh` sempre exigem root mas `simulado_restauracao.sh`
não.

**Variáveis de ambiente:**

- `AGENDAMENTO_MAX_HORAS_BACKUP` — padrão `48`; ajuste se o backup daquele perfil for semanal, não
  diário.
- `AGENDAMENTO_MAX_HORAS_SIMULADO` — padrão `192`.
- `WEBHOOK_URL` — se definida, alerta via [`alert_webhook`](#libcommonsh) quando algo está atrasado
  ou nunca rodou.

**Bom candidato pra rodar diariamente via cron** (inclusive no crontab do root, já que exige
`sudo`):

```
0 8 * * * WEBHOOK_URL="https://seu-n8n.exemplo.com/webhook/alerta" /home/<usuario>/scripts/verificar_agendamentos.sh > /dev/null 2>&1
```

**Exit codes:** `1` se encontrar pelo menos um agendamento atrasado/nunca executado; `0` se tudo
estiver em dia (ou nada estiver configurado). Não altera nada no sistema — só leitura.

---

## panel/painel.sh

**O que faz:** menu interativo central (TUI simples em loop) que dá acesso a todos os outros
scripts instalados em `~/scripts`, com o nível de privilégio correto para cada um (chama `sudo`
internamente quando necessário — você não precisa ter rodado o painel com `sudo`).

**Requisitos:** nenhum privilégio especial pra abrir o menu; algumas opções pedem senha de `sudo`
na hora de rodar.

**Uso:**

```bash
painel                      # se o atalho global foi criado pelo install.sh
bash ~/scripts/painel.sh    # direto, sem atalho
```

O cabeçalho mostra a versão instalada (lida de `~/scripts/VERSION`, gravada pelo `install.sh`) —
útil pra saber rapidinho se uma máquina de cliente está desatualizada.

| Opção | Script chamado | sudo? |
|---|---|---|
| 1 | `health_check.sh` | não |
| 2 | `network_scanner.sh` | não |
| 3 | `inventario_universal.sh` | não |
| 4 | `manutencao_avancada.sh` | sim |
| 5 | `backup_multiperfil.sh` | não* |
| 6 | `restaurar_backup.sh` | sim |
| 7 | `simulado_restauracao.sh` | não |
| 8 | `setup_pos_instalacao.sh` | sim |
| 9 | `status_frota.sh` | não |
| 10 | `atualizar_sistema.sh --agendar` | sim |
| 11 | `verificar_agendamentos.sh` | sim |
| 0 | sai do painel | — |

\* `backup_multiperfil.sh` não exige `sudo`, mas normalmente precisa dele pra conseguir ler `/etc`.

Se um script não estiver instalado em `~/scripts` (ex.: rodou o painel sem passar pelo
`install.sh`), a opção mostra um erro claro em vez de travar.

---

## install.sh

**O que faz:** instala (copia, não symlinka) todos os scripts das subpastas do repositório para
`~/scripts/` numa estrutura plana, e oferece criar o atalho global `painel` em `/usr/local/bin`.

**Requisitos:** roda melhor com `sudo` (necessário para criar o atalho global e ajustar o dono dos
arquivos para o usuário real por trás do `sudo`).

**Uso:**

```bash
sudo ./install.sh
```

**Por que copia em vez de symlinkar:** o `painel.sh` e os crontabs de clientes já existentes esperam
os scripts num caminho fixo e plano (`~/scripts/nome.sh`), então o `install.sh` reproduz essa
estrutura a partir das subpastas do repositório (`backup/`, `monitoring/`, etc.), mantendo
compatibilidade mesmo com automações configuradas antes da reorganização em categorias.

**Arquivos de configuração (`*.conf`, ex.: `apps.conf`):** também são copiados para `~/scripts/`,
mas **só na primeira instalação** — se o arquivo já existir no destino, o `install.sh` não
sobrescreve, para preservar customizações feitas depois da instalação.

**Rotação de logs:** se rodado como root e `/etc/logrotate.d` existir, instala
`lib/logrotate.conf` em `/etc/logrotate.d/ci-scripts-linux` — mesma regra "só na primeira
instalação" dos arquivos `.conf`, não sobrescreve uma versão já existente.

**Versão instalada:** grava `~/scripts/VERSION` com a saída de `git describe --tags --always
--dirty` rodado no checkout do repositório (ex.: `v1.0.0`, ou `v1.0.0-3-gabc1234` se houver
commits depois da tag, ou só o SHA curto se não houver nenhuma tag ainda). Se o `SCRIPT_DIR` não
for um checkout git (ex.: baixado como zip), grava `desconhecida`. O `painel.sh` mostra esse valor
no cabeçalho. Sempre sobrescrito a cada instalação/atualização — não é um arquivo pra editar.

---

## update.sh

**O que faz:** `git pull` + `install.sh` numa tacada só, pra atualizar uma máquina que já tem o
repositório clonado e os scripts instalados.

**Requisitos:** precisa ser rodado de dentro do checkout git (não de `~/scripts/`, que é a cópia
plana sem histórico git). Pede senha de `sudo` na hora do `install.sh`, se não estiver rodando como
root.

**Uso:**

```bash
cd ci-scripts-linux   # o checkout git, não ~/scripts/
./update.sh
```

**O que faz, em ordem:**

1. Confere que está num checkout git (`.git` existe) — aborta com mensagem clara se não estiver.
2. Avisa (sem abortar) se houver alterações locais não commitadas, já que isso pode fazer o
   `git pull` falhar ou gerar conflito.
3. `git pull`. Se falhar (conflito, rede, credenciais, branch sem upstream, etc.), aborta e mostra
   a saída do próprio `git` pra você resolver manualmente.
4. `sudo ./install.sh` (ou sem `sudo` se já estiver rodando como root). Se isso falhar, avisa
   claramente que o repositório foi atualizado mas `~/scripts/` pode ter ficado com versões antigas
   — não finge que deu tudo certo.

**Exit codes:** `1` se não for um checkout git, se o `git pull` falhar, ou se o `install.sh`
falhar; `0` só quando as duas etapas completam com sucesso.
