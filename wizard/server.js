const express = require('express');
const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const app = express();
app.use(express.json());

const HOME = '/home/openclaw';
const OPENCLAW_BIN = '/home/linuxbrew/.linuxbrew/bin/openclaw';
const CREDS_PATH = path.join(HOME, '.openclaw', 'credentials', 'whatsapp', 'default', 'creds.json');

const execEnv = {
    ...process.env,
    HOME: HOME,
    PATH: '/home/linuxbrew/.linuxbrew/bin:' + process.env.PATH
};

let lastQrDataUrl = null;
let pairingStatus = 'idle';
let qrRefreshInterval = null;
let lastQrTime = 0;
let lastError = null;

const HTML = `<!DOCTYPE html>
<html>
<head>
    <title>OpenClaw Setup</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: system-ui; max-width: 600px; margin: 40px auto; padding: 20px; background: #1a1a2e; color: #eee; }
        h1 { color: #ff6b6b; }
        .step { background: #16213e; padding: 20px; border-radius: 10px; margin: 20px 0; }
        input, select { width: 100%; box-sizing: border-box; padding: 10px; margin: 10px 0; border-radius: 5px; border: 1px solid #444; background: #0f0f23; color: #eee; }
        button { background: #ff6b6b; color: white; padding: 15px 30px; border: none; border-radius: 5px; cursor: pointer; font-size: 16px; }
        button:hover { background: #ee5a5a; }
        button:disabled { background: #666; cursor: not-allowed; }
        #qr-container { text-align: center; margin: 20px 0; }
        #qr-container img { max-width: 300px; background: white; padding: 10px; border-radius: 10px; }
        .status { padding: 10px; border-radius: 5px; margin: 10px 0; }
        .status.success { background: #2d5a27; }
        .status.error { background: #5a2727; }
        .status.waiting { background: #5a4a27; }
        .hidden { display: none; }
        .spinner { display: inline-block; width: 20px; height: 20px; border: 3px solid #fff; border-top-color: transparent; border-radius: 50%; animation: spin 1s linear infinite; margin-right: 10px; }
        @keyframes spin { to { transform: rotate(360deg); } }
    </style>
</head>
<body>
    <h1>🦞 OpenClaw Setup</h1>
    
    <div id="step1" class="step">
        <h2>1. Configurar API</h2>
        <select id="provider">
            <option value="anthropic">Anthropic (Claude)</option>
            <option value="openai">OpenAI (GPT)</option>
        </select>
        <input type="password" id="apiKey" placeholder="API Key">
        <button onclick="saveConfig()">Salvar e Continuar</button>
        <div id="config-status"></div>
    </div>
    
    <div id="step2" class="step hidden">
        <h2>2. Conectar WhatsApp</h2>
        <button id="pairBtn" onclick="startPairing()">Gerar QR Code</button>
        <div id="qr-container"></div>
        <div id="pair-status"></div>
    </div>
    
    <div id="step3" class="step hidden">
        <h2>3. Pronto!</h2>
        <p>OpenClaw configurado com sucesso!</p>
        <p>Numero conectado: <strong id="connected-phone"></strong></p>
    </div>

    <script>
        async function saveConfig() {
            const provider = document.getElementById('provider').value;
            const apiKey = document.getElementById('apiKey').value;
            const status = document.getElementById('config-status');
            
            if (!apiKey) {
                status.innerHTML = '<div class="status error">Insira a API key</div>';
                return;
            }
            
            status.innerHTML = '<div class="status waiting"><span class="spinner"></span>Salvando...</div>';
            
            try {
                const res = await fetch('/configure', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ provider, apiKey })
                });
                const data = await res.json();
                
                if (data.success) {
                    status.innerHTML = '<div class="status success">Configurado!</div>';
                    document.getElementById('step2').classList.remove('hidden');
                } else {
                    status.innerHTML = '<div class="status error">Erro: ' + data.message + '</div>';
                }
            } catch(e) {
                status.innerHTML = '<div class="status error">Erro: ' + e.message + '</div>';
            }
        }
        
        let pollInterval = null;
        
        async function startPairing() {
            const btn = document.getElementById('pairBtn');
            const container = document.getElementById('qr-container');
            const status = document.getElementById('pair-status');
            
            // Stop any existing polling
            if (pollInterval) {
                clearInterval(pollInterval);
                pollInterval = null;
            }
            
            btn.disabled = true;
            btn.innerHTML = '<span class="spinner"></span>Gerando QR...';
            container.innerHTML = '';  // Hide QR
            status.innerHTML = '<div class="status waiting"><span class="spinner"></span>Iniciando...</div>';
            
            try {
                const res = await fetch('/whatsapp/pair', { method: 'POST' });
                const data = await res.json();
                
                if (data.success) {
                    status.innerHTML = '<div class="status waiting"><span class="spinner"></span>Aguardando QR...</div>';
                    btn.innerHTML = 'Gerar Novo QR';
                    btn.disabled = false;
                    startPolling();
                } else {
                    status.innerHTML = '<div class="status error">Erro: ' + (data.message || 'Falha') + '</div>';
                    btn.innerHTML = 'Tentar Novamente';
                    btn.disabled = false;
                }
            } catch(e) {
                status.innerHTML = '<div class="status error">Erro: ' + e.message + '</div>';
                btn.innerHTML = 'Tentar Novamente';
                btn.disabled = false;
            }
        }
        
        function startPolling() {
            if (pollInterval) clearInterval(pollInterval);
            
            pollInterval = setInterval(async () => {
                try {
                    const res = await fetch('/whatsapp/status');
                    const data = await res.json();
                    
                    const container = document.getElementById('qr-container');
                    const status = document.getElementById('pair-status');
                    
                    if (data.status === 'connected' && data.phone) {
                        clearInterval(pollInterval);
                        document.getElementById('step2').classList.add('hidden');
                        document.getElementById('step3').classList.remove('hidden');
                        document.getElementById('connected-phone').textContent = data.phone;
                    } else if (data.qrImage) {
                        container.innerHTML = '<img src="' + data.qrImage + '" alt="QR Code">';
                        let msg = 'Escaneie o QR no WhatsApp - Dispositivos Vinculados';
                        if (data.error) {
                            msg += '<br><small style="color:#ff6b6b">Erro: ' + data.error + '</small>';
                        }
                        status.innerHTML = '<div class="status waiting"><span class="spinner"></span>' + msg + '</div>';
                    } else if (data.status === 'error') {
                        container.innerHTML = '';
                        status.innerHTML = '<div class="status error">' + (data.message || 'Erro desconhecido') + '</div>';
                    }
                } catch(e) {
                    console.log('Poll error:', e);
                }
            }, 2000);
        }
    </script>
</body>
</html>`;

app.get('/', (req, res) => res.send(HTML));

app.post('/configure', (req, res) => {
    const { provider, apiKey } = req.body;
    
    try {
        const configPath = path.join(HOME, '.openclaw', 'openclaw.json');
        let config = {};
        
        if (fs.existsSync(configPath)) {
            config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
        }
        
        config.env = config.env || {};
        if (provider === 'anthropic') {
            config.env.ANTHROPIC_API_KEY = apiKey;
            config.agents = config.agents || {};
            config.agents.defaults = config.agents.defaults || {};
            config.agents.defaults.model = { primary: 'anthropic/claude-sonnet-4-5' };
        } else {
            config.env.OPENAI_API_KEY = apiKey;
            config.agents = config.agents || {};
            config.agents.defaults = config.agents.defaults || {};
            config.agents.defaults.model = { primary: 'openai/gpt-4o' };
        }
        
        config.channels = config.channels || {};
        config.channels.whatsapp = config.channels.whatsapp || { dmPolicy: 'open' };
        
        config.plugins = config.plugins || {};
        config.plugins.entries = config.plugins.entries || {};
        config.plugins.entries.whatsapp = { enabled: true };
        
        fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
        
        res.json({ success: true });
    } catch(e) {
        res.json({ success: false, message: e.message });
    }
});

async function generateNewQR() {
    try {
        console.log('Gerando novo QR...');
        const result = execSync(
            OPENCLAW_BIN + " gateway call web.login.start --params '{\"force\":true,\"timeoutMs\":25000}' --timeout 30000 --json 2>/dev/null",
            { timeout: 35000, encoding: 'utf8', env: execEnv, maxBuffer: 1024 * 1024 }
        );
        
        const data = JSON.parse(result);
        if (data.qrDataUrl) {
            lastQrDataUrl = data.qrDataUrl;
            lastQrTime = Date.now();
            lastError = null;
            console.log('QR gerado!');
            
            // Start waiting for scan in background
            waitForScan();
            
            return true;
        } else {
            console.log('Sem qrDataUrl:', JSON.stringify(data));
            lastError = data.message || 'Sem QR retornado';
            return false;
        }
    } catch(e) {
        console.log('Erro ao gerar QR:', e.message);
        lastError = e.message;
        return false;
    }
}

async function waitForScan() {
    console.log('Aguardando scan...');
    const { exec } = require('child_process');
    
    exec(
        OPENCLAW_BIN + " gateway call web.login.wait --params '{\"timeoutMs\":60000}' --timeout 65000 --json 2>/dev/null",
        { timeout: 70000, env: execEnv, maxBuffer: 1024 * 1024 },
        (error, stdout, stderr) => {
            if (error) {
                console.log('Wait error:', error.message);
                lastError = error.message;
                return;
            }
            
            try {
                const data = JSON.parse(stdout);
                console.log('Wait result:', JSON.stringify(data));
                
                if (data.connected) {
                    console.log('Conectado via wait!');
                    pairingStatus = 'connected';
                    lastError = null;
                    if (qrRefreshInterval) {
                        clearInterval(qrRefreshInterval);
                        qrRefreshInterval = null;
                    }
                } else if (data.message) {
                    lastError = data.message;
                }
            } catch(e) {
                console.log('Parse error:', e.message);
            }
        }
    );
}

app.post('/whatsapp/pair', async (req, res) => {
    console.log('Iniciando pareamento WhatsApp...');
    
    // Stop any existing refresh loop
    if (qrRefreshInterval) {
        clearInterval(qrRefreshInterval);
        qrRefreshInterval = null;
    }
    
    pairingStatus = 'waiting';
    lastQrDataUrl = null;
    lastError = null;
    
    try {
        execSync(OPENCLAW_BIN + ' gateway call status --json 2>/dev/null', { env: execEnv, timeout: 5000 });
        console.log('Gateway rodando');
    } catch(e) {
        console.log('Iniciando gateway...');
        spawn(OPENCLAW_BIN, ['gateway'], { env: execEnv, detached: true, stdio: 'ignore' }).unref();
        await new Promise(r => setTimeout(r, 10000));
    }
    
    res.json({ success: true, message: 'Gerando QR...' });
    
    // Generate first QR
    setImmediate(async () => {
        const success = await generateNewQR();
        if (!success) {
            pairingStatus = 'error';
            return;
        }
        
        // Start refresh loop every 18 seconds (QR expires in ~20s)
        qrRefreshInterval = setInterval(async () => {
            // Check if already connected
            try {
                if (fs.existsSync(CREDS_PATH)) {
                    const creds = JSON.parse(fs.readFileSync(CREDS_PATH, 'utf8'));
                    if (creds.registered === true) {
                        console.log('Conectado! Parando refresh.');
                        clearInterval(qrRefreshInterval);
                        qrRefreshInterval = null;
                        pairingStatus = 'connected';
                        return;
                    }
                }
            } catch(e) {}
            
            // Generate new QR
            await generateNewQR();
        }, 18000);
        
        // Stop after 3 minutes
        setTimeout(() => {
            if (qrRefreshInterval) {
                clearInterval(qrRefreshInterval);
                qrRefreshInterval = null;
                if (pairingStatus !== 'connected') {
                    pairingStatus = 'error';
                    console.log('Timeout - parando refresh');
                }
            }
        }, 180000);
    });
});

app.get('/whatsapp/status', (req, res) => {
    let phone = null;
    let isRegistered = false;
    
    try {
        if (fs.existsSync(CREDS_PATH)) {
            const creds = JSON.parse(fs.readFileSync(CREDS_PATH, 'utf8'));
            isRegistered = creds.registered === true;
            if (isRegistered && creds.me && creds.me.id) {
                const match = creds.me.id.match(/^(\d+):/);
                if (match) phone = '+' + match[1];
            }
        }
    } catch(e) {}
    
    if (isRegistered && phone) {
        res.json({ status: 'connected', phone });
    } else if (lastQrDataUrl) {
        res.json({ status: 'waiting', qrImage: lastQrDataUrl, error: lastError });
    } else if (pairingStatus === 'error' || lastError) {
        res.json({ status: 'error', message: lastError || 'Falha. Clique para tentar novamente.' });
    } else {
        res.json({ status: 'waiting', qrImage: null });
    }
});

app.listen(3000, '0.0.0.0', () => console.log('Wizard running on port 3000'));
