# Provisionamento

| Script | Descrição |
|---|---|
| `setup_pos_instalacao.sh` | Provisionamento pós-instalação (Debian/Ubuntu/Zorin): pacotes essenciais, UFW, fail2ban, Docker + Compose plugin, estrutura de diretórios padrão. Requer `sudo`. |
| `inventario_universal.sh` | Inventário de hardware e SO: CPU, memória, discos, interfaces de rede, runtimes instalados (Docker, git, python3, node). |

## Uso

```bash
sudo ~/scripts/setup_pos_instalacao.sh
bash ~/scripts/inventario_universal.sh
```
