# Provisionamento

| Script | Descrição |
|---|---|
| `setup_pos_instalacao.sh` | Provisionamento pós-instalação (Debian/Ubuntu/Zorin): pacotes essenciais, UFW, fail2ban, Docker + Compose plugin, estrutura de diretórios padrão. Requer `sudo`. |
| `inventario_universal.sh` | Inventário de hardware e SO: CPU, memória (+ slots de RAM ocupados/livres, requer `sudo`), discos, interfaces de rede, runtimes (Docker, git, python3, node) e apps desktop (Obsidian, VS Code, Antigravity, Wine). |

## Uso

```bash
sudo ~/scripts/setup_pos_instalacao.sh
bash ~/scripts/inventario_universal.sh          # sem sudo: tudo menos slots de RAM
sudo ~/scripts/inventario_universal.sh          # com sudo: inclui slots de RAM (via dmidecode)
```

A detecção de apps desktop (Obsidian, VS Code, Antigravity, Wine) verifica comando no PATH, pacote
apt, flatpak, snap e atalho `.desktop` — cobre as formas mais comuns de instalação. Slots de memória
usam `dmidecode -t 17` e exigem root; em VMs sem BIOS/firmware completo pode não retornar dados.
