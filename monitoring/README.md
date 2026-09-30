# Monitoramento

| Script | Descrição |
|---|---|
| `health_check.sh` | Saúde geral: modelo de CPU, uptime/carga, memória, disco (destaca partições acima do limiar), top 5 processos por CPU e por RAM, conectividade/DNS, serviços systemd falhando e status de contêineres Docker. |
| `network_scanner.sh` | Descobre hosts ativos na sub-rede local (ping sweep paralelo) e testa portas comuns (22, 80, 443, 3389, 8080, 8443). |
| `status_frota.sh` | Roda `health_check.sh --json` via SSH em vários hosts (lista em `hosts.conf`) e agrega tudo numa tabela só. Requer `jq` e acesso SSH sem senha. |

## Uso

```bash
bash ~/scripts/health_check.sh
bash ~/scripts/network_scanner.sh
```

Limiares do `health_check.sh` configuráveis via variável de ambiente:

```bash
LIMIAR_DISCO=90 LIMIAR_MEM=95 bash ~/scripts/health_check.sh
```

## Saída em JSON

Pra alimentar um dashboard ou outro script, sem precisar interpretar o texto colorido:

```bash
bash ~/scripts/health_check.sh --json | jq .
```

Sai um único objeto JSON com os mesmos dados que apareceriam na tela (CPU, memória, disco, top
processos, conectividade, serviços falhando, contêineres Docker). Detalhes dos campos em
[docs/SCRIPTS.md](../docs/SCRIPTS.md).

## Alerta via webhook

Se `WEBHOOK_URL` estiver definida, o `health_check.sh` envia um `POST` em JSON pra essa URL sempre
que disco ou memória passarem do limiar, ou houver serviço `systemd` em falha — dá pra apontar pra um
workflow do n8n, por exemplo, e decidir lá como notificar (WhatsApp, e-mail, etc.).

```bash
WEBHOOK_URL="https://seu-n8n.exemplo.com/webhook/alerta" bash ~/scripts/health_check.sh
```

Payload enviado:

```json
{"hostname":"servidor01","script":"health_check","motivo":"disco_/","detalhe":"/dev/sda1 em / com 92% (limiar 85%)","data":"2026-01-01 03:00:00"}
```

Tem cooldown por motivo (`ALERTA_COOLDOWN_HORAS`, padrão 6h) pra não mandar o mesmo alerta toda vez
que o script rodar enquanto o problema persistir. Pra alertar de verdade (não só quando você rodar
manualmente), coloque no cron:

```
*/15 * * * * WEBHOOK_URL="https://seu-n8n.exemplo.com/webhook/alerta" /home/<usuario>/scripts/health_check.sh > /dev/null 2>&1
```

## Status de vários hosts de uma vez (frota)

Se você atende mais de um cliente/VPS, o `status_frota.sh` roda `health_check.sh --json` via SSH em
cada host listado em `hosts.conf` e mostra um resumo numa tabela só, sem precisar entrar host por
host:

```bash
cp ~/scripts/hosts.conf.example ~/scripts/hosts.conf
nano ~/scripts/hosts.conf   # um host por linha (alias do ~/.ssh/config ou usuario@host)
bash ~/scripts/status_frota.sh
```

Requer `jq`, acesso SSH sem senha a cada host, e o `ci-scripts-linux` já instalado (`~/scripts/`)
neles. Host fora do ar aparece como `OFFLINE` em vez de travar a checagem dos outros. Detalhes em
[docs/SCRIPTS.md](../docs/SCRIPTS.md).
