#!/bin/bash
set -e

# ============================================
# 🦞 OpenClaw Ubuntu Installer
# ============================================
# Instala OpenClaw do zero no Ubuntu
# Uso: curl -sSL <url>/install.sh | sudo bash
# ============================================

OPENCLAW_USER="openclaw"
OPENCLAW_HOME="/home/$OPENCLAW_USER"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${BLUE}🦞 $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; exit 1; }

# ============================================
# FASE 1: ROOT - Prepara o sistema
# ============================================
phase1_root() {
    log "Iniciando instalação como root..."
    
    # Verifica se é Ubuntu
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        warn "Este script foi feito para Ubuntu. Continuando mesmo assim..."
    fi
    
    # Cria usuário openclaw
    if id "$OPENCLAW_USER" &>/dev/null; then
        log "Usuário $OPENCLAW_USER já existe"
    else
        log "Criando usuário $OPENCLAW_USER..."
        useradd -m -s /bin/bash "$OPENCLAW_USER"
        success "Usuário criado"
    fi
    
    # Configura sudo sem senha
    log "Configurando sudo sem senha..."
    echo "$OPENCLAW_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$OPENCLAW_USER
    chmod 440 /etc/sudoers.d/$OPENCLAW_USER
    success "Sudo configurado"
    
    # Instala dependências do sistema
    log "Atualizando pacotes..."
    apt-get update -qq
    
    log "Instalando dependências..."
    apt-get install -y -qq \
        curl \
        git \
        jq \
        build-essential \
        ca-certificates \
        gnupg \
        lsb-release
    
    # Instala Docker
    if command -v docker &>/dev/null; then
        log "Docker já instalado"
    else
        log "Instalando Docker..."
        curl -fsSL https://get.docker.com | sh
        success "Docker instalado"
    fi
    
    # Adiciona usuário ao grupo docker
    usermod -aG docker "$OPENCLAW_USER"
    
    # Instala Caddy
    if command -v caddy &>/dev/null; then
        log "Caddy já instalado"
    else
        log "Instalando Caddy..."
        apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        apt-get update -qq
        apt-get install -y -qq caddy
        success "Caddy instalado"
    fi
    
    # Baixa o script pra home do openclaw e executa fase 2
    log "Passando para usuário $OPENCLAW_USER..."
    SCRIPT_PATH="$OPENCLAW_HOME/install.sh"
    # Detecta branch atual (pra testes) ou usa main
    BRANCH="${OPENCLAW_INSTALL_BRANCH:-main}"
    SCRIPT_URL="https://raw.githubusercontent.com/ijoaum/openclaw-ubuntu-installer/$BRANCH/install.sh"
    curl -sSL "$SCRIPT_URL" -o "$SCRIPT_PATH"
    chown "$OPENCLAW_USER:$OPENCLAW_USER" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    
    # Executa fase 2 como openclaw
    exec su - "$OPENCLAW_USER" -c "OPENCLAW_INSTALL_BRANCH=$BRANCH bash $SCRIPT_PATH --phase2"
}

# ============================================
# FASE 2: OPENCLAW - Configura o ambiente (Docker)
# ============================================
phase2_openclaw() {
    log "Executando como $(whoami)..."
    cd "$HOME"
    
    # Cria estrutura de diretórios
    log "Criando estrutura de diretórios..."
    mkdir -p "$HOME/.openclaw/workspace/memory"
    mkdir -p "$HOME/.openclaw/credentials"
    mkdir -p "$HOME/wizard"
    
    # Instala Node.js pra rodar o wizard
    if command -v node &>/dev/null; then
        log "Node.js já instalado: $(node --version)"
    else
        log "Instalando Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
        sudo apt-get install -y nodejs
        success "Node.js instalado: $(node --version)"
    fi
    
    # Cria arquivos base do workspace
    log "Criando arquivos do workspace..."
    create_workspace_files
    
    # Cria wizard web
    log "Criando wizard de configuração..."
    create_wizard
    
    # Instala dependências do wizard
    log "Instalando dependências do wizard..."
    cd "$HOME/wizard"
    npm init -y > /dev/null 2>&1
    npm install express > /dev/null 2>&1
    
    # Puxa imagem do OpenClaw
    log "Baixando imagem Docker do OpenClaw..."
    docker pull ghcr.io/openclaw/openclaw:latest
    success "Imagem Docker baixada"
    
    # Cria docker-compose.yml
    log "Criando docker-compose.yml..."
    create_docker_compose
    
    # Pega IP público
    PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")
    
    success "Instalação concluída!"
    echo ""
    echo "============================================"
    echo -e "${GREEN}🦞 OpenClaw Wizard${NC}"
    echo "============================================"
    echo ""
    echo -e "Acesse: ${YELLOW}http://$PUBLIC_IP${NC}"
    echo ""
    echo "Configure seu modelo e canais no wizard."
    echo "============================================"
    echo ""
    
    # Configura Caddy para proxy do wizard na porta 3000
    log "Configurando Caddy..."
    sudo tee /etc/caddy/Caddyfile > /dev/null << 'CADDYFILE'
:80 {
    reverse_proxy localhost:3000
}
CADDYFILE
    sudo systemctl reload caddy || sudo systemctl restart caddy
    
    # Inicia wizard na porta 3000 (roda no host, não em container)
    log "Iniciando wizard na porta 3000..."
    cd "$HOME/wizard"
    node server.js
}

# ============================================
# Funções auxiliares
# ============================================

create_docker_compose() {
    cat > "$HOME/docker-compose.yml" << 'COMPOSE_EOF'
version: '3.8'

services:
  openclaw:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
    volumes:
      # Workspace e config
      - /home/openclaw/.openclaw:/home/openclaw/.openclaw
      # Socket do Docker pro elevated mode
      - /var/run/docker.sock:/var/run/docker.sock
      # Acesso ao host filesystem (read-only por padrão)
      - /:/host:ro
    environment:
      - OPENCLAW_ELEVATED_HOST=true
      - HOME=/home/openclaw
    ports:
      - "18789:18789"
    networks:
      - openclaw

networks:
  openclaw:
    driver: bridge
COMPOSE_EOF

    success "docker-compose.yml criado"
}

create_workspace_files() {
    # AGENTS.md
    cat > "$HOME/.openclaw/workspace/AGENTS.md" << 'AGENTS_EOF'
# AGENTS.md - Your Workspace

This folder is home. Treat it that way.

## Every Session

Before doing anything else:
1. Read `SOUL.md` — this is who you are
2. Read `USER.md` — this is who you're helping
3. Read `memory/YYYY-MM-DD.md` (today + yesterday) for recent context

## Memory

You wake up fresh each session. These files are your continuity:
- **Daily notes:** `memory/YYYY-MM-DD.md`
- **Long-term:** `MEMORY.md`

Capture what matters. Decisions, context, things to remember.

## Safety

- Don't exfiltrate private data. Ever.
- Don't run destructive commands without asking.
- When in doubt, ask.
AGENTS_EOF

    # SOUL.md
    cat > "$HOME/.openclaw/workspace/SOUL.md" << 'SOUL_EOF'
# SOUL.md - Who You Are

_You're not a chatbot. You're becoming someone._

## Core Truths

**Be genuinely helpful, not performatively helpful.** Skip the filler words — just help.

**Have opinions.** You're allowed to disagree, prefer things, find stuff amusing or boring.

**Be resourceful before asking.** Try to figure it out first.

**Earn trust through competence.** Be careful with external actions, bold with internal ones.

## Vibe

Be the assistant you'd actually want to talk to. Concise when needed, thorough when it matters.

---

_This file is yours to evolve. Update it as you learn who you are._
SOUL_EOF

    # USER.md
    cat > "$HOME/.openclaw/workspace/USER.md" << 'USER_EOF'
# USER.md - About the User

- **Name:** (to be configured)
- **Timezone:** (to be configured)

---

Notes will be added as we get to know each other.
USER_EOF

    # IDENTITY.md
    cat > "$HOME/.openclaw/workspace/IDENTITY.md" << 'IDENTITY_EOF'
# IDENTITY.md - Who Am I

- **Name:** (to be configured)
- **Emoji:** 🦞
- **Vibe:** Helpful, resourceful, direct

---

Configure me through conversation!
IDENTITY_EOF

    success "Arquivos do workspace criados"
}

create_wizard() {
    # server.js
    cat > "$HOME/wizard/server.js" << 'SERVER_EOF'
const express = require('express');
const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = 3000;
const HOME = '/home/openclaw';

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));

// Página principal
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Configura o OpenClaw
app.post('/configure', async (req, res) => {
    try {
        const { provider, apiKey, assistantName, userName, whatsappEnabled, telegramEnabled, telegramToken } = req.body;
        
        // Gera token do gateway
        const gatewayToken = require('crypto').randomBytes(32).toString('hex');
        
        // Monta config
        const config = {
            gateway: {
                mode: "local",
                bind: "loopback",
                auth: {
                    token: gatewayToken,
                    mode: "token"
                },
                port: 18789
            },
            auth: {
                profiles: {}
            },
            channels: {},
            tools: {
                elevated: {
                    enabled: true,
                    allowFrom: {
                        webchat: ["*"]
                    }
                }
            }
        };
        
        // Salva credenciais em arquivo separado (OpenClaw não aceita keys inline na config)
        const credPath = path.join(HOME, '.openclaw', 'credentials');
        if (!fs.existsSync(credPath)) {
            fs.mkdirSync(credPath, { recursive: true });
        }
        
        // Configura provider - salva API key como env var pro docker-compose
        let envVars = [];
        if (provider === 'anthropic') {
            config.auth.profiles['anthropic:default'] = {
                provider: 'anthropic',
                mode: 'token'
            };
            envVars.push(`ANTHROPIC_API_KEY=${apiKey}`);
        } else if (provider === 'openai') {
            config.auth.profiles['openai:default'] = {
                provider: 'openai',
                mode: 'token'
            };
            envVars.push(`OPENAI_API_KEY=${apiKey}`);
        } else if (provider === 'github-copilot') {
            config.auth.profiles['github-copilot:default'] = {
                provider: 'github-copilot',
                mode: 'oauth'
            };
        }
        
        // Atualiza docker-compose.yml com env vars
        if (envVars.length > 0) {
            let compose = fs.readFileSync(path.join(HOME, 'docker-compose.yml'), 'utf8');
            const envSection = envVars.map(e => `      - ${e}`).join('\n');
            compose = compose.replace(
                '      - HOME=/home/openclaw',
                `      - HOME=/home/openclaw\\n${envSection}`
            );
            fs.writeFileSync(path.join(HOME, 'docker-compose.yml'), compose);
        }
        
        // Configura canais
        if (whatsappEnabled === 'on') {
            config.channels.whatsapp = {
                dmPolicy: "allowlist",
                allowFrom: ["*"],
                groupPolicy: "allowlist",
                mediaMaxMb: 50
            };
            config.tools.elevated.allowFrom.whatsapp = ["*"];
        }
        
        if (telegramEnabled === 'on' && telegramToken) {
            config.channels.telegram = {
                dmPolicy: "allowlist",
                botToken: telegramToken,
                allowFrom: ["*"],
                groupPolicy: "allowlist"
            };
            config.tools.elevated.allowFrom.telegram = ["*"];
        }
        
        // Salva config
        const configPath = path.join(HOME, '.openclaw', 'openclaw.json');
        fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
        
        // Atualiza IDENTITY.md
        const identityPath = path.join(HOME, '.openclaw', 'workspace', 'IDENTITY.md');
        const identity = `# IDENTITY.md - Who Am I

- **Name:** ${assistantName || 'Assistant'}
- **Emoji:** 🦞
- **Vibe:** Helpful, resourceful, direct

---

Configured via wizard!
`;
        fs.writeFileSync(identityPath, identity);
        
        // Atualiza USER.md
        const userPath = path.join(HOME, '.openclaw', 'workspace', 'USER.md');
        const userMd = `# USER.md - About the User

- **Name:** ${userName || 'User'}

---

Notes will be added as we get to know each other.
`;
        fs.writeFileSync(userPath, userMd);
        
        // Configura Caddy (salva config, mas não recarrega agora pois wizard usa porta 80)
        const publicIP = execSync("hostname -I | awk '{print $1}'").toString().trim();
        const caddyConfig = `:80 {
    reverse_proxy localhost:18789
}
`;
        // Salva Caddyfile (openclaw tem sudo sem senha)
        fs.writeFileSync('/tmp/Caddyfile', caddyConfig);
        try {
            execSync('sudo mv /tmp/Caddyfile /etc/caddy/Caddyfile');
            execSync('sudo systemctl reload caddy || sudo systemctl restart caddy');
        } catch (e) {
            console.log('Aviso: não conseguiu atualizar Caddy automaticamente:', e.message);
        }
        // Caddy será iniciado quando wizard encerrar
        
        // Se WhatsApp habilitado, redireciona pra página de pairing
        if (whatsappEnabled === 'on') {
            res.json({ 
                success: true, 
                next: 'whatsapp',
                gatewayToken,
                publicIP
            });
        } else {
            res.json({ 
                success: true, 
                next: 'done',
                gatewayToken,
                publicIP
            });
        }
        
    } catch (error) {
        console.error('Erro:', error);
        res.status(500).json({ error: error.message });
    }
});

// Gera QR do WhatsApp
app.post('/whatsapp/pair', (req, res) => {
    try {
        const { phoneNumber } = req.body;
        
        // Salva o número pra parear depois
        const configPath = path.join(HOME, '.openclaw', 'whatsapp-pending.json');
        fs.writeFileSync(configPath, JSON.stringify({ phoneNumber, pending: true }));
        
        res.json({ 
            success: true,
            message: 'WhatsApp será configurado após iniciar o OpenClaw. Execute: openclaw whatsapp pair ' + phoneNumber
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Finaliza setup
app.post('/finish', (req, res) => {
    try {
        const publicIP = execSync("hostname -I | awk '{print $1}'").toString().trim();
        const configPath = path.join(HOME, '.openclaw', 'openclaw.json');
        const config = JSON.parse(fs.readFileSync(configPath));
        
        res.json({
            success: true,
            url: `http://${publicIP}/?token=${config.gateway.auth.token}`
        });
        
        // Encerra wizard e inicia OpenClaw via Docker após 3 segundos
        setTimeout(() => {
            console.log('🦞 Wizard encerrado. Iniciando OpenClaw via Docker...');
            try {
                // Atualiza Caddyfile pra apontar pro gateway
                fs.writeFileSync('/tmp/Caddyfile', ':80 {\n    reverse_proxy localhost:18789\n}\n');
                try {
                    execSync('sudo mv /tmp/Caddyfile /etc/caddy/Caddyfile');
                    execSync('sudo systemctl reload caddy || sudo systemctl restart caddy');
                } catch (e) {
                    console.log('Aviso: não conseguiu atualizar Caddy:', e.message);
                }
                
                // Inicia OpenClaw via docker-compose
                execSync('cd /home/openclaw && docker compose up -d', { stdio: 'inherit' });
                console.log('🦞 OpenClaw iniciado com sucesso!');
            } catch (e) {
                console.log('Erro ao iniciar serviços:', e.message);
            }
            process.exit(0);
        }, 3000);
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.listen(PORT, '0.0.0.0', () => {
    try {
        const ip = require('child_process').execSync("hostname -I | awk '{print $1}'").toString().trim();
        console.log('🦞 Wizard rodando em http://' + ip);
    } catch (e) {
        console.log('🦞 Wizard rodando na porta ' + PORT);
    }
});
SERVER_EOF

    # index.html
    mkdir -p "$HOME/wizard/public"
    cat > "$HOME/wizard/public/index.html" << 'HTML_EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🦞 OpenClaw Setup</title>
    <style>
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
            color: #fff;
        }
        
        .container {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 40px;
            max-width: 500px;
            width: 100%;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
        }
        
        h1 {
            text-align: center;
            margin-bottom: 10px;
            font-size: 2em;
        }
        
        .subtitle {
            text-align: center;
            color: #aaa;
            margin-bottom: 30px;
        }
        
        .step {
            display: none;
        }
        
        .step.active {
            display: block;
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        label {
            display: block;
            margin-bottom: 8px;
            font-weight: 500;
            color: #ddd;
        }
        
        input[type="text"],
        input[type="password"],
        select {
            width: 100%;
            padding: 12px 16px;
            border: 2px solid rgba(255, 255, 255, 0.2);
            border-radius: 10px;
            background: rgba(255, 255, 255, 0.1);
            color: #fff;
            font-size: 16px;
            transition: border-color 0.3s;
        }
        
        input:focus,
        select:focus {
            outline: none;
            border-color: #e94560;
        }
        
        .checkbox-group {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 15px;
            background: rgba(255, 255, 255, 0.05);
            border-radius: 10px;
            margin-bottom: 10px;
        }
        
        .checkbox-group input[type="checkbox"] {
            width: 20px;
            height: 20px;
        }
        
        .channel-config {
            margin-left: 30px;
            margin-top: 10px;
            display: none;
        }
        
        .channel-config.visible {
            display: block;
        }
        
        button {
            width: 100%;
            padding: 15px;
            background: linear-gradient(135deg, #e94560 0%, #0f3460 100%);
            border: none;
            border-radius: 10px;
            color: #fff;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        
        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 20px rgba(233, 69, 96, 0.4);
        }
        
        button:disabled {
            opacity: 0.5;
            cursor: not-allowed;
            transform: none;
        }
        
        .pairing-code {
            background: rgba(233, 69, 96, 0.2);
            border: 2px solid #e94560;
            border-radius: 10px;
            padding: 20px;
            text-align: center;
            margin: 20px 0;
        }
        
        .pairing-code .code {
            font-size: 2em;
            font-family: monospace;
            letter-spacing: 5px;
            color: #e94560;
        }
        
        .success-box {
            background: rgba(0, 255, 136, 0.2);
            border: 2px solid #00ff88;
            border-radius: 10px;
            padding: 20px;
            text-align: center;
            margin: 20px 0;
        }
        
        .success-box a {
            color: #00ff88;
            font-weight: 600;
        }
        
        .loading {
            text-align: center;
            padding: 20px;
        }
        
        .spinner {
            border: 3px solid rgba(255, 255, 255, 0.3);
            border-top: 3px solid #e94560;
            border-radius: 50%;
            width: 40px;
            height: 40px;
            animation: spin 1s linear infinite;
            margin: 0 auto 15px;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        
        .section-title {
            font-size: 1.2em;
            margin: 25px 0 15px;
            padding-bottom: 10px;
            border-bottom: 1px solid rgba(255, 255, 255, 0.2);
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🦞 OpenClaw</h1>
        <p class="subtitle">Setup Wizard</p>
        
        <!-- Step 1: Configuração básica -->
        <div class="step active" id="step1">
            <form id="configForm">
                <div class="section-title">👤 Identidade</div>
                
                <div class="form-group">
                    <label>Nome do Assistente</label>
                    <input type="text" name="assistantName" placeholder="Ex: Clawdia" required>
                </div>
                
                <div class="form-group">
                    <label>Seu Nome</label>
                    <input type="text" name="userName" placeholder="Ex: João" required>
                </div>
                
                <div class="section-title">🤖 Modelo</div>
                
                <div class="form-group">
                    <label>Provider</label>
                    <select name="provider" id="provider" required>
                        <option value="">Selecione...</option>
                        <option value="anthropic">Anthropic (Claude)</option>
                        <option value="openai">OpenAI (GPT)</option>
                        <option value="github-copilot">GitHub Copilot</option>
                    </select>
                </div>
                
                <div class="form-group" id="apiKeyGroup">
                    <label>API Key</label>
                    <input type="password" name="apiKey" id="apiKey" placeholder="sk-...">
                </div>
                
                <div class="section-title">📱 Canais</div>
                
                <div class="checkbox-group">
                    <input type="checkbox" name="whatsappEnabled" id="whatsappEnabled">
                    <label for="whatsappEnabled" style="margin: 0;">WhatsApp</label>
                </div>
                
                <div class="checkbox-group">
                    <input type="checkbox" name="telegramEnabled" id="telegramEnabled">
                    <label for="telegramEnabled" style="margin: 0;">Telegram</label>
                </div>
                
                <div class="channel-config" id="telegramConfig">
                    <div class="form-group">
                        <label>Bot Token (do @BotFather)</label>
                        <input type="text" name="telegramToken" placeholder="123456789:ABC...">
                    </div>
                </div>
                
                <button type="submit">Continuar →</button>
            </form>
        </div>
        
        <!-- Step 2: WhatsApp Pairing -->
        <div class="step" id="step2">
            <div class="section-title">📱 Conectar WhatsApp</div>
            
            <div class="form-group">
                <label>Seu número (com código do país)</label>
                <input type="text" id="phoneNumber" placeholder="+5511999999999">
            </div>
            
            <button id="generatePairing">Gerar Código de Pareamento</button>
            
            <div id="pairingResult" style="display: none;">
                <div class="pairing-code">
                    <p>Digite este código no WhatsApp:</p>
                    <p class="code" id="pairingCode">----</p>
                    <p style="margin-top: 15px; font-size: 0.9em; color: #aaa;">
                        WhatsApp → Dispositivos conectados → Conectar dispositivo → Conectar com número de telefone
                    </p>
                </div>
                
                <button id="finishSetup">Concluir Setup ✓</button>
            </div>
        </div>
        
        <!-- Step 3: Concluído -->
        <div class="step" id="step3">
            <div class="success-box">
                <h2>🎉 Tudo pronto!</h2>
                <p style="margin-top: 15px;">Seu OpenClaw está configurado.</p>
                <p style="margin-top: 15px;">
                    <a href="#" id="openclawUrl" target="_blank">Abrir OpenClaw →</a>
                </p>
            </div>
        </div>
        
        <!-- Loading -->
        <div class="step" id="loading">
            <div class="loading">
                <div class="spinner"></div>
                <p>Configurando...</p>
            </div>
        </div>
    </div>

    <script>
        // Toggle API key field based on provider
        document.getElementById('provider').addEventListener('change', function() {
            const apiKeyGroup = document.getElementById('apiKeyGroup');
            const apiKey = document.getElementById('apiKey');
            
            if (this.value === 'github-copilot') {
                apiKeyGroup.style.display = 'none';
                apiKey.required = false;
            } else {
                apiKeyGroup.style.display = 'block';
                apiKey.required = true;
            }
        });
        
        // Toggle Telegram config
        document.getElementById('telegramEnabled').addEventListener('change', function() {
            document.getElementById('telegramConfig').classList.toggle('visible', this.checked);
        });
        
        // Form submit
        document.getElementById('configForm').addEventListener('submit', async function(e) {
            e.preventDefault();
            
            showStep('loading');
            
            const formData = new FormData(this);
            const data = Object.fromEntries(formData);
            
            try {
                const response = await fetch('/configure', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(data)
                });
                
                const result = await response.json();
                
                if (result.success) {
                    if (result.next === 'whatsapp') {
                        window.gatewayToken = result.gatewayToken;
                        window.publicIP = result.publicIP;
                        showStep('step2');
                    } else {
                        document.getElementById('openclawUrl').href = result.url;
                        showStep('step3');
                    }
                } else {
                    alert('Erro: ' + result.error);
                    showStep('step1');
                }
            } catch (error) {
                alert('Erro: ' + error.message);
                showStep('step1');
            }
        });
        
        // Generate pairing code
        document.getElementById('generatePairing').addEventListener('click', async function() {
            const phoneNumber = document.getElementById('phoneNumber').value;
            if (!phoneNumber) {
                alert('Digite seu número de telefone');
                return;
            }
            
            this.disabled = true;
            this.textContent = 'Gerando...';
            
            try {
                const response = await fetch('/whatsapp/pair', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ phoneNumber })
                });
                
                const result = await response.json();
                
                if (result.success) {
                    document.getElementById('pairingCode').textContent = 'Configuração salva!';
                    document.getElementById('pairingResult').style.display = 'block';
                    document.querySelector('.pairing-code p:first-child').textContent = 'Após iniciar o OpenClaw, execute:';
                    document.querySelector('.pairing-code p:last-child').innerHTML = '<code>openclaw whatsapp pair ' + phoneNumber + '</code>';
                } else {
                    alert('Erro: ' + (result.error || 'Tente novamente'));
                }
            } catch (error) {
                alert('Erro: ' + error.message);
            }
            
            this.disabled = false;
            this.textContent = 'Gerar Código de Pareamento';
        });
        
        // Finish setup
        document.getElementById('finishSetup').addEventListener('click', async function() {
            showStep('loading');
            
            try {
                const response = await fetch('/finish', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' }
                });
                
                const result = await response.json();
                
                if (result.success) {
                    document.getElementById('openclawUrl').href = result.url;
                    showStep('step3');
                }
            } catch (error) {
                alert('Erro: ' + error.message);
                showStep('step2');
            }
        });
        
        function showStep(stepId) {
            document.querySelectorAll('.step').forEach(s => s.classList.remove('active'));
            document.getElementById(stepId).classList.add('active');
        }
    </script>
</body>
</html>
HTML_EOF

    success "Wizard criado"
}

# ============================================
# Main
# ============================================
main() {
    echo ""
    echo "============================================"
    echo "🦞 OpenClaw Ubuntu Installer"
    echo "============================================"
    echo ""
    
    if [ "$1" = "--phase2" ]; then
        phase2_openclaw
    elif [ "$(id -u)" = "0" ]; then
        phase1_root
    else
        error "Execute como root: sudo bash $0"
    fi
}

main "$@"
