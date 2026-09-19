# Monitoramento

| Script | Descrição |
|---|---|
| `health_check.sh` | Saúde geral: modelo de CPU, uptime/carga, memória, disco (destaca partições acima do limiar), top 5 processos por CPU e por RAM, conectividade/DNS, serviços systemd falhando e status de contêineres Docker. |
| `network_scanner.sh` | Descobre hosts ativos na sub-rede local (ping sweep paralelo) e testa portas comuns (22, 80, 443, 3389, 8080, 8443). |

## Uso

```bash
bash ~/scripts/health_check.sh
bash ~/scripts/network_scanner.sh
```

Limiares do `health_check.sh` configuráveis via variável de ambiente:

```bash
LIMIAR_DISCO=90 LIMIAR_MEM=95 bash ~/scripts/health_check.sh
```
