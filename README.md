# 🦞 OpenClaw Ubuntu Installer

Script de instalação automatizada do OpenClaw para Ubuntu.

## Instalação Rápida

```bash
curl -sSL https://raw.githubusercontent.com/ijoaum/openclaw-ubuntu-installer/main/install.sh | sudo bash
```

## O que o script faz

### Fase 1 (como root)
- Cria usuário `openclaw` com sudo sem senha
- Instala dependências do sistema (curl, git, jq, build-essential)
- Instala Docker
- Instala Caddy
- Passa execução para usuário `openclaw`

### Fase 2 (como openclaw)
- Instala Homebrew
- Instala Node.js via Homebrew
- Baixa última release do OpenClaw
- Cria estrutura de diretórios e arquivos base
- Inicia wizard web na porta 80

## Wizard de Configuração

Após a instalação, acesse `http://<IP-DO-SERVIDOR>` para configurar:

### Identidade
- Nome do assistente
- Seu nome

### Modelo
- **Anthropic** (Claude) - requer API key
- **OpenAI** (GPT) - requer API key
- **GitHub Copilot** - usa OAuth

### Canais
- **WhatsApp** - gera código de pareamento
- **Telegram** - requer bot token do @BotFather

## Estrutura de Arquivos

```
/opt/openclaw/              # Binários do OpenClaw
/home/openclaw/
├── .openclaw/
│   ├── openclaw.json       # Configuração principal
│   ├── credentials/        # Tokens e credenciais
│   └── workspace/          # Arquivos do agente
│       ├── AGENTS.md
│       ├── SOUL.md
│       ├── USER.md
│       ├── IDENTITY.md
│       └── memory/
├── homebrew/               # Instalação do Homebrew
└── wizard/                 # Wizard de configuração
```

## Requisitos

- Ubuntu 20.04+ (testado em 22.04 e 24.04)
- Mínimo 2GB RAM (recomendado 4GB+)
- Acesso root
- Porta 80 livre

## Após Instalação

1. Acesse o Web UI: `http://<IP>/?token=<gateway-token>`
2. Converse com seu assistente para personalizar
3. Configure mais canais se necessário

## Comandos Úteis

```bash
# Status do OpenClaw
sudo systemctl status openclaw

# Logs
sudo journalctl -u openclaw -f

# Reiniciar
sudo systemctl restart openclaw

# Parar
sudo systemctl stop openclaw
```

## Licença

MIT

---

Feito com 🦞 por OpenClaw
