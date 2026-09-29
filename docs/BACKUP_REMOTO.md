# Backup remoto com rclone (Google Drive)

Guia completo para configurar o envio automático dos backups do `backup_multiperfil.sh` para o
Google Drive via [rclone](https://rclone.org/). Depois de configurado, basta definir
`RCLONE_REMOTO` (ver [backup/README.md](../backup/README.md)) — o script já faz o resto.

## 1. Instalar o rclone no servidor

```bash
sudo apt-get update && sudo apt-get install -y rclone
rclone version
```

(Se a versão do repositório da distro estiver muito antiga, use o instalador oficial:
`curl https://rclone.org/install.sh | sudo bash`.)

## 2. Ponto de atenção antes de começar: qual usuário roda o cron

O `backup_multiperfil.sh` normalmente roda como **root** (via `sudo` no crontab), para conseguir
ler `/etc`. O rclone guarda a configuração (com o token OAuth do Google) em
`~/.config/rclone/rclone.conf` — **do usuário que roda o comando**. Se você configurar o rclone
logado como seu usuário normal mas o backup rodar como root, o script não vai achar o remote.

Duas opções, escolha uma:

- **Configurar direto como root** (mais simples): `sudo rclone config` — grava em
  `/root/.config/rclone/rclone.conf`, que é onde o script vai procurar quando rodar via `sudo`.
- **Configurar como seu usuário e apontar explicitamente**: defina `RCLONE_CONFIG` no crontab
  apontando pro seu `rclone.conf` (ex.: `RCLONE_CONFIG=/home/seu_usuario/.config/rclone/rclone.conf`).

Este guia assume a primeira opção (`sudo rclone config`).

## 3. Criar o remote do Google Drive

```bash
sudo rclone config
```

Siga o assistente:

```
n) New remote
name> gdrive

Storage> drive          # (digite "drive" ou o número correspondente a "Google Drive")

client_id>               # deixe em branco (usa as credenciais compartilhadas do rclone)
client_secret>           # deixe em branco

scope> 1                 # 1 = drive.full-access (lê/grava tudo que a conta permitir)

root_folder_id>          # deixe em branco por enquanto (ajustamos depois, ver seção 4)
service_account_file>    # deixe em branco (não é conta de serviço, é sua conta pessoal/Workspace)

Edit advanced config?
y/n> n

Use auto config?
y/n> n            # IMPORTANTE: responda "n" — o servidor não tem navegador
```

Ao responder `n` em "Use auto config", o rclone mostra um comando parecido com:

```
rclone authorize "drive"
```

**Rode esse comando em outra máquina que tenha navegador** (seu notebook/desktop, com rclone
instalado — `sudo apt install rclone` ou `brew install rclone`):

```bash
rclone authorize "drive"
```

Isso abre o navegador, você faz login na conta Google e autoriza. O terminal do seu computador
mostra um token (uma linha longa começando com `{"access_token":...}`). **Copie esse token
inteiro** e cole de volta no prompt do servidor onde ficou esperando (`config_token>`).

Depois disso:

```
Configure this as a Shared Drive (Team Drive)?
y/n> n            # "n" a menos que você use Shared Drive do Google Workspace

y) Yes this is OK
e) Edit this remote
d) Delete this remote
y/e/d> y

q) Quit config
```

## 4. (Recomendado) Restringir o remote a uma pasta específica do Drive

Por padrão o escopo `drive.full-access` enxerga o Drive inteiro da conta. Pra reduzir o raio de
alcance do backup (e evitar que um bug no script varra arquivos pessoais), crie uma pasta
dedicada no Drive e aponte o remote só pra ela:

1. No Google Drive (web), crie uma pasta, ex.: `backups-ci-scripts-linux`.
2. Pegue o ID da pasta na URL: `https://drive.google.com/drive/folders/`**`ESSE_TRECHO_AQUI`**.
3. Edite o remote:
   ```bash
   sudo rclone config
   # e) Edit existing remote > gdrive
   # avança as perguntas mantendo tudo igual, até "root_folder_id" — cole o ID da pasta
   ```

A partir daí, `gdrive:` já aponta direto pra dentro dessa pasta.

## 5. Testar

```bash
sudo rclone lsd gdrive:
sudo rclone mkdir gdrive:teste
sudo rclone copy /etc/hostname gdrive:teste
sudo rclone ls gdrive:teste
sudo rclone purge gdrive:teste   # limpa o teste
```

Se `rclone lsd gdrive:` listar (mesmo vazio, sem erro), a autenticação está funcionando.

## 6. Usar com o backup_multiperfil.sh

```bash
sudo -E RCLONE_REMOTO="gdrive:cliente-x" /home/<usuario>/scripts/backup_multiperfil.sh homelab
```

No crontab (raiz, `sudo crontab -e`):

```
0 3 * * * RCLONE_REMOTO="gdrive:cliente-x" /home/<usuario>/scripts/backup_multiperfil.sh homelab > /dev/null 2>&1
```

Os arquivos acabam em `gdrive:cliente-x/<perfil>/backup_<perfil>_<data>.tar.gz` (+ `.sha256`).

Multi-cliente: use um remote (`gdrive`) por conta Google diferente, ou um único remote com
caminhos diferentes por cliente (`RCLONE_REMOTO="gdrive:cliente-x"`, `"gdrive:cliente-y"`, etc.),
dependendo de como você organiza o Drive.

## 7. Segurança: considere criptografar antes de subir pro Drive

O Google Drive é um serviço de terceiros. Os backups incluem `/etc` (configurações do sistema,
possivelmente com segredos) e, dependendo do perfil, dumps de aplicação — dados sensíveis de
cliente. Duas opções, do mais simples ao mais robusto:

- **Aceitar o risco assumindo a segurança da conta Google** (2FA obrigatório, conta dedicada só
  pra backups, nunca a conta pessoal) — mínimo aceitável.
- **Camada de criptografia do rclone (`rclone config` → tipo `crypt`)**, apontando pra um remote
  `gdrive` já configurado: os arquivos sobem cifrados, e só quem tem a senha/config decifra.
  Recomendado se os backups guardam dados de cliente (ex.: perfil `homelab` com dumps de banco).
  Documentação: https://rclone.org/crypt/

Se quiser, isso pode ser configurado depois — não bloqueia o uso básico deste guia.

## 8. Limites a saber

- **Cota de armazenamento:** conta pessoal do Google tem 15 GB compartilhados entre Drive, Gmail e
  Fotos. Para volume maior, considere Google Workspace (mais espaço) ou um backend diferente
  (Backblaze B2, S3-compatível — trocar só o `RCLONE_REMOTO` por outro remote).
- **Rate limit da API:** as credenciais `client_id`/`client_secret` em branco usam a cota
  compartilhada de todos os usuários do rclone no mundo — raramente é um problema para backups
  diários de scripts pequenos, mas se notar erros de `rate limit exceeded`, crie suas próprias
  credenciais OAuth no [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
  (API "Google Drive API") e informe `client_id`/`client_secret` na configuração do remote.
- **Token expira?** O token OAuth salvo em `rclone.conf` se renova sozinho (refresh token) nos
  usos normais — não precisa repetir esse processo, a menos que revogue o acesso manualmente em
  https://myaccount.google.com/permissions.

## Troubleshooting

| Sintoma | Causa provável |
|---|---|
| `didn't find section in config file` | Rodou como usuário diferente de quem configurou o remote (ver seção 2). |
| `couldn't find remote` / `remote not found` | Nome do remote em `RCLONE_REMOTO` não bate com o `name>` dado no `rclone config` (confira com `sudo rclone listremotes`). |
| `googleapi: Error 403: rate limit exceeded` | Cota compartilhada saturada — crie credenciais próprias (seção 8). |
| Backup local funciona mas nada aparece no Drive | Confira `[WARN] Falha ao enviar backup ao remoto` no log (`~/.local/state/ci-scripts-linux/logs/` ou `/var/log/ci-scripts-linux/`) — o script nunca falha o backup local por causa disso, só avisa. |
