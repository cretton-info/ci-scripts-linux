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
| `confirm "pergunta"` | Pergunta s/N interativa. Retorna 0 (sucesso) se a resposta for `s`/`S`. |
| `has_cmd nome` | Retorna 0 se o comando `nome` existe no `PATH`. |
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

---

## backup/backup_multiperfil.sh

**O que faz:** cria um backup `.tar.gz` de um dos 4 perfis pré-definidos, com rotação automática de
backups antigos.

| Perfil | Origens |
|---|---|
| `docs` / `1` | `/etc` + `~/Documentos` |
| `homelab` / `2` | `/etc` + `/var/www` + `/opt/docker-containers` |
| `scripts` / `3` | `/etc` + `~/scripts` |
| `tudo` / `4` | todas as anteriores combinadas |

**Requisitos:** não exige root explicitamente, mas normalmente roda com `sudo` para conseguir ler
`/etc` e ajustar o dono do backup (`chown`) de volta pro usuário real.

**Uso:**

```bash
sudo ~/scripts/backup_multiperfil.sh homelab      # direto por parâmetro (cron)
sudo ~/scripts/backup_multiperfil.sh --menu       # menu interativo
sudo ~/scripts/backup_multiperfil.sh --help       # ajuda
```

**Variáveis de ambiente:**

- `RETENCAO_DIAS` — dias de retenção antes de apagar backups antigos do mesmo perfil (padrão: `7`).

**O que grava no sistema:**

- `~/backups_sistema/<perfil>/backup_<perfil>_<data>.tar.gz`
- `~/backups_sistema/<perfil>/backup_<perfil>_<data>.tar.gz.sha256` — checksum gerado logo após a
  criação, usado pelo `restaurar_backup.sh` para detectar corrupção antes de restaurar.
- Apaga (`find ... -delete`) backups e checksums do mesmo perfil com mais de `RETENCAO_DIAS` dias.

**Verificação de integridade:** depois de criar o `.tar.gz`, o script testa a leitura com
`tar -tzf` e grava o checksum. Se o teste falhar, apaga o arquivo corrompido e encerra com erro —
nunca deixa um backup ruim para trás.

**Comportamento com diretórios ausentes:** origens que não existem na máquina são ignoradas com
`log_warn` (não interrompe o backup) — por isso um mesmo perfil funciona tanto num home lab completo
quanto numa VPS mínima.

**Exit codes:** `1` se nenhuma das origens do perfil existir, ou se o `tar` falhar de verdade
(códigos de saída do `tar` diferentes de `0` e `1` — `1` é tolerado porque significa apenas "algum
arquivo mudou durante a leitura", comum em sistemas ativos).

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

Fluxo: escolhe o perfil → escolhe o arquivo `.tar.gz` (lista ordenada do mais recente) → **verificação
de integridade** → escolhe o modo de destino.

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

**Para reverter uma restauração ruim:**

```bash
sudo tar -xzf ~/backups_sistema/_seguranca_pre_restauracao/pre_restore_<perfil>_<data>.tar.gz -C /
```

**Exit codes:** `1` em qualquer seleção inválida (perfil, arquivo ou modo inexistente) ou falha do
`tar` na extração final.

---

## monitoring/health_check.sh

**O que faz:** raio-x rápido de saúde do sistema — uptime/carga, memória, disco, top 5 processos por
CPU, serviços `systemd` falhando e status de contêineres Docker.

**Requisitos:** nenhum privilégio especial (mas ver Docker abaixo).

**Uso:**

```bash
bash ~/scripts/health_check.sh
LIMIAR_DISCO=90 LIMIAR_MEM=95 bash ~/scripts/health_check.sh
```

**Variáveis de ambiente:**

- `LIMIAR_DISCO` — percentual de uso de disco a partir do qual a partição é destacada em vermelho (padrão: `85`).
- `LIMIAR_MEM` — reservado para uso futuro de destaque de memória (padrão: `90`; hoje a seção de memória não aplica destaque).

**Observações:**

- Se rodado sem permissão de acessar o socket do Docker, mostra `[WARN]` em vez de travar.
- Não grava nada no sistema — só leitura e exibição.

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

## provisioning/setup_pos_instalacao.sh

**O que faz:** provisionamento pós-instalação de uma máquina Debian/Ubuntu/Zorin nova: atualização
de pacotes, utilitários essenciais, firewall, Docker e estrutura de diretórios padrão.

**Requisitos:** **sempre roda com `sudo`**.

**Uso:**

```bash
sudo ~/scripts/setup_pos_instalacao.sh
```

**O que faz, em ordem:**

1. `apt-get update && apt-get upgrade` — **não aborta** se algum repositório de terceiros
   (PPA) falhar; apenas avisa e segue com o que conseguiu atualizar.
2. Instala pacotes essenciais: `curl wget git htop net-tools ufw fail2ban ca-certificates gnupg
   lsb-release tree unzip software-properties-common ncdu`.
3. Configura UFW: `deny incoming` / `allow outgoing` por padrão, libera `22/tcp`, `80/tcp`, `443/tcp`,
   e habilita o firewall.
4. Instala Docker Engine + Compose plugin a partir do repositório oficial (se ainda não estiver
   instalado) e adiciona o usuário real ao grupo `docker`.
5. Cria `~/scripts`, `~/backups_sistema`, `~/docker_stacks`.
6. `apt-get autoremove && apt-get clean`.

**Cuidados:**

- Altera o firewall da máquina (UFW). Se a máquina for acessada só por SSH numa porta não-padrão,
  ajuste as regras antes/depois.
- Depois de rodar, o usuário precisa fazer logout/login para o grupo `docker` ter efeito sem `sudo`.

---

## provisioning/inventario_universal.sh

**O que faz:** inventário somente-leitura de hardware e sistema operacional — hostname, SO, kernel,
CPU, memória, discos/partições, interfaces de rede e versões de runtimes relevantes (Docker, git,
Python, Node).

**Requisitos:** nenhum privilégio especial.

**Uso:**

```bash
bash ~/scripts/inventario_universal.sh
```

Útil para documentar o estado de uma máquina de cliente na entrada de um contrato, ou para
diagnóstico rápido remoto.

---

## maintenance/manutencao_avancada.sh

**O que faz:** rotina de manutenção e limpeza — atualização de pacotes, remoção de dependências não
usadas, limite de tamanho dos logs do `journal` e limpeza de recursos Docker não utilizados.

**Requisitos:** **sempre roda com `sudo`**.

**Uso:**

```bash
sudo ~/scripts/manutencao_avancada.sh          # interativo
sudo ~/scripts/manutencao_avancada.sh --yes    # sem confirmação (cron)
AUTO_YES=1 sudo -E ~/scripts/manutencao_avancada.sh   # equivalente ao --yes
```

**O que faz, em ordem:**

1. `apt-get update && apt-get upgrade`.
2. `apt-get autoremove && apt-get autoclean`.
3. `journalctl --vacuum-size=200M --vacuum-time=30d`.
4. **Pede confirmação** (mostra `docker system df` antes) e, se confirmado, roda
   `docker system prune -f` — remove imagens, redes e cache de build não usados por nenhum
   contêiner em execução. **Não afeta contêineres nem volumes ativos.**
5. `apt-get clean`.
6. Mostra espaço livre em `/` antes e depois.

**Variáveis/flags para uso não-interativo (cron):** `--yes`, `-y` ou `AUTO_YES=1` pulam a
confirmação do passo 4.

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

| Opção | Script chamado | sudo? |
|---|---|---|
| 1 | `health_check.sh` | não |
| 2 | `network_scanner.sh` | não |
| 3 | `inventario_universal.sh` | não |
| 4 | `manutencao_avancada.sh` | sim |
| 5 | `backup_multiperfil.sh` | não* |
| 6 | `restaurar_backup.sh` | sim |
| 7 | `setup_pos_instalacao.sh` | sim |
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
