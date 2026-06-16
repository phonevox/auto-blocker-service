# Phonevox Automações

Script bash para gerenciar automações do Phonevox com verificação de status automática via API REST.

## 📋 Características

- ✅ Instalação automatizada com systemd
- ✅ Timer para execução a cada 10 minutos
- ✅ Verificação de status via API REST
- ✅ Integração com PM2 (opa) ou Asterisk (pabx) para restart/stop automático
- ✅ Reutiliza configs existentes no `--install` sem pedir novamente
- ✅ Atualização via `--update` de qualquer diretório
- ✅ Rotação de logs nativa (máx 10MB)
- ✅ Suporte a cores no terminal

## 🚀 Instalação

### 1. Clonar o repositório (como root)
```bash
git clone https://github.com/phonevox/auto-blocker-opa.git
cd auto-blocker-opa
```

### 2. Executar instalação
```bash
sudo bash phonevox-automacoes.sh --install
```

### 3. Durante a instalação você precisará:
- **URL Base**: URL do servidor (ex: `https://auto-blocker.falevox.com.br`)
- **Type**: `opa` ou `pabx`
- **Key**: Código único para sua instalação (máx 255 caracteres)

> Se já existirem configs salvas em `/etc/phonevox/automacoes/`, o `--install` as reutiliza sem pedir novamente.

### 4. Executar comando curl em rede permitida
O script gerará um comando curl que **DEVE ser executado apenas em uma máquina na rede permitida (VPN/Interna)**:

**Linux/macOS:**
```bash
curl -L -X POST "https://auto-blocker.falevox.com.br/register" \
  -H "Content-Type: application/json" \
  -d '{"type":"opa","code":"seu-code"}'
```

**Windows (CMD):**
```cmd
curl -L -X POST "https://auto-blocker.falevox.com.br/register" -H "Content-Type: application/json" -d "{\"type\":\"opa\",\"code\":\"seu-code\"}"
```

Este comando retornará um `crypted_key` que você cola de volta no script.

### 5. Confirmação
Após colar a `crypted_key`, o script irá:
- Salvar a configuração
- Instalar o systemd service
- Ativar o timer (executa a cada 10 minutos)
- Executar verificação inicial de status

## 📖 Comandos

```bash
phonevox-automacoes --install       # Configurar e instalar (reutiliza configs se existirem)
phonevox-automacoes --reconfig      # Regenerar crypted_key
phonevox-automacoes --run           # Executar verificação de status
phonevox-automacoes --run --dry-run # Testar sem executar pm2/asterisk
phonevox-automacoes --status        # Exibir configuração completa
phonevox-automacoes --logs          # Ver últimas 100 linhas do log
phonevox-automacoes --update        # Git pull + atualiza script (funciona de qualquer diretório)
phonevox-automacoes --start         # Iniciar service/timer
phonevox-automacoes --stop          # Parar service/timer
phonevox-automacoes --remove        # Remove service, timer e binário (pergunta sobre configs)
phonevox-automacoes --fix-bin       # Copia script do repo para /usr/local/sbin (emergência)
phonevox-automacoes --help          # Ver menu de ajuda
```

## ⚙️ Configuração

### Arquivos de configuração
```
/etc/phonevox/automacoes/
├── config              # TYPE e CODE
├── crypted_key         # Chave criptografada
├── urls                # URL_BASE e endpoints
├── repo_path           # Caminho do repositório git (usado pelo --update)
└── last_response       # Último status HTTP (200 ou 402 apenas)
```

### Log
```
/var/log/phonevox-automacoes.log
```

Logs são rotacionados automaticamente quando atingem 10MB. Arquivos antigos ficam em:
```
/var/log/phonevox-automacoes.log.YYYYMMDD-HHMMSS.gz
```

## 🔄 Como funciona

1. **Timer executa a cada 10 minutos** (configurável em `/etc/systemd/system/phonevox-automacoes.timer`)
2. **Script verifica status** via GET request:
   ```
   GET /?type={TYPE}&crypted_key={KEY}&last_status={STATUS}
   ```
3. **Script processa resposta** (ação depende do `TYPE`):
   - `HTTP 200` + last_status = 200 → Sem ação (sistema OK)
   - `HTTP 200` + last_status ≠ 200 →
     - `opa` → `pm2 restart all`
     - `pabx` → `service asterisk restart`
   - `HTTP 402` →
     - `opa` → `pm2 stop all`
     - `pabx` → `service asterisk stop`
   - Qualquer outro código → Ignora, **não altera o last_status salvo**

4. **Salva último status** apenas para respostas 200 ou 402 — outros códigos (308, 404, 500, etc.) são ignorados sem sobrescrever o estado anterior

## ⚠️ Requisitos

- **Bash** 4+
- **curl**
- **git** (para `--update`)
- **Python 3** (para URL encoding)
- **PM2** (opcional, usado quando `TYPE=opa`)
- **Asterisk** (opcional, usado quando `TYPE=pabx`)
- **root** (para instalar service systemd)

## 🔐 Segurança

- ⚠️ **IMPORTANTE**: A requisição de registro (`/register`) **DEVE ser executada APENAS em rede permitida (VPN/Interna)**
- Chave criptografada salva com permissões 600
- Todos os arquivos de configuração têm permissões restritivas (600/700)

## 📝 Exemplos de uso

### Instalar pela primeira vez
```bash
cd auto-blocker-opa
sudo bash phonevox-automacoes.sh --install
```

### Reinstalar sem perder configurações
```bash
sudo phonevox-automacoes --install
# detecta configs existentes e pula os prompts
```

### Regenerar chave
```bash
sudo phonevox-automacoes --reconfig
```

### Atualizar script (de qualquer diretório)
```bash
sudo phonevox-automacoes --update
```

### Corrigir binário manualmente em emergência
```bash
sudo phonevox-automacoes --fix-bin
# encontra o repo automaticamente e copia para /usr/local/sbin
```

### Remover completamente
```bash
sudo phonevox-automacoes --remove
# pergunta se deseja remover configs também
```

### Ver logs em tempo real
```bash
tail -f /var/log/phonevox-automacoes.log
```

### Testar sem executar ações (dry-run)
```bash
sudo phonevox-automacoes --run --dry-run
```

## 🐛 Troubleshooting

### Binário desatualizado após git pull manual
```bash
sudo phonevox-automacoes --fix-bin
```

### PM2 não encontrado (TYPE=opa)
O script loga um aviso e continua. Para instalar:
```bash
npm install -g pm2
```

### Asterisk não responde (TYPE=pabx)
O script chama `service asterisk restart|stop`. Verifique manualmente:
```bash
service asterisk status
```

### Verificar timer
```bash
systemctl status phonevox-automacoes.timer
systemctl list-timers phonevox-automacoes.timer
```

### Executar verificação manual
```bash
sudo phonevox-automacoes --run
```

## 📋 Variáveis de ambiente

| Variável  | Padrão | Descrição                                     |
|-----------|--------|-----------------------------------------------|
| `DRY_RUN` | `0`    | Se `1`, simula ações sem executar pm2/asterisk |

```bash
DRY_RUN=1 sudo phonevox-automacoes --run
# equivalente a:
sudo phonevox-automacoes --run --dry-run
```

## 📄 Licença

Desenvolvido para Phonevox por Rafael Rizzo.

## 📞 Suporte
18 3256 8306
