# Phonevox Automações

Script bash para gerenciar automações do Phonevox com verificação de status automática via webhook.

## 📋 Características

- ✅ Instalação automatizada com systemd
- ✅ Timer para execução a cada 10 minutos
- ✅ Verificação de status via API REST
- ✅ Integração com PM2 para restart/stop automático
- ✅ Rotação de logs nativa (máx 10MB)
- ✅ Geração automática de comando curl para registro
- ✅ Validação de URLs com https:// automático
- ✅ Suporte a cores no terminal

## 🚀 Instalação

### 1. Download
```bash
curl -O https://seu-servidor/phonevox-automacoes.sh
chmod +x phonevox-automacoes.sh
```

### 2. Executar instalação (como root)
```bash
sudo bash phonevox-automacoes.sh install
```

### 3. Durante a instalação você precisará:
- **URL Base**: Digite a URL do seu servidor (ex: `https://auto-blocker.falevox.com.br`)
- **Type**: Escolha entre `opa`, `pabx` ou `did`
- **Code**: Código único para sua instalação (máx 255 caracteres)

### 4. Executar comando curl em rede permitida
O script gerará um comando curl que **DEVE ser executado apenas em uma máquina na rede permitida (VPN/Interna)**:

```bash
curl -L -X POST "https://auto-blocker.falevox.com.br/register" \
  -H "Content-Type: application/json" \
  -d '{"type":"opa","code":"seu-code"}'
```

Este comando retornará um `crypted_key` que você cola de volta no script.

### 5. Confirmação
Após colar a `crypted_key`, o script irá:
- Salvar a configuração
- Instalar o systemd service
- Ativar o timer (executa a cada 30 minutos)
- Executar verificação inicial de status

## 📖 Comandos

```bash
phonevox-automacoes install    # Configurar e instalar
phonevox-automacoes reconfig   # Regenerar crypted_key
phonevox-automacoes run        # Executar verificação de status
phonevox-automacoes status     # Exibir configuração completa
phonevox-automacoes logs       # Ver últimas 100 linhas do log
phonevox-automacoes start      # Iniciar service/timer
phonevox-automacoes stop       # Parar service/timer
phonevox-automacoes help       # Ver menu de ajuda
```

## ⚙️ Configuração

### Arquivos de configuração
```
/etc/phonevox/automacoes/
├── config              # TYPE e CODE
├── crypted_key         # Chave criptografada
├── urls                # URL_BASE e endpoints
└── last_response       # Último status HTTP
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
   GET /status?type={TYPE}&crypted_key={KEY}&last_status={STATUS}
   ```
3. **Script processa resposta**:
   - `HTTP 200` → Executa `pm2 restart all`
   - `HTTP 402` → Executa `pm2 stop all`
   - Outros → Ignora

4. **Salva último status** em `/etc/phonevox/automacoes/last_response`

## ⚠️ Requisitos

- **Bash** 4+
- **curl** (para requisições HTTP)
- **Python 3** (para URL encoding)
- **PM2** (opcional, para restart/stop automático)
- **root** (para instalar service systemd)

## 🔐 Segurança

- ⚠️ **IMPORTANTE**: A requisição de registro (`/register`) **DEVE ser executada APENAS em rede permitida (VPN/Interna)**
- Chave criptografada salva em `/etc/phonevox/automacoes/crypted_key` com permissões 600
- Todos os arquivos de configuração têm permissões restritivas (600/700)

## 📝 Exemplos de uso

### Instalar pela primeira vez
```bash
sudo bash phonevox-automacoes.sh install
```

### Regenerar chave (mesma URL)
```bash
sudo phonevox-automacoes reconfig
```

### Ver status atual
```bash
phonevox-automacoes status
```

### Ver logs em tempo real
```bash
phonevox-automacoes logs
```

### Parar temporariamente
```bash
sudo phonevox-automacoes stop
```

### Reiniciar
```bash
sudo phonevox-automacoes start
```

## 🐛 Troubleshooting

### PM2 não encontrado
Se PM2 não estiver instalado, o script apenas loga um aviso e continua executando. Para instalar PM2:
```bash
npm install -g pm2
```

### Erro ao executar curl
Verifique se:
- URL Base está correta (com `https://`)
- Você tem conexão com a internet
- O firewall permite requisições HTTPS

### Verificar logs
```bash
phonevox-automacoes logs
tail -f /var/log/phonevox-automacoes.log
```

### Verificar timer status
```bash
systemctl status phonevox-automacoes.timer
systemctl list-timers phonevox-automacoes.timer
```

### Executar verificação manual
```bash
sudo phonevox-automacoes run
```

## 📋 Variáveis de ambiente

Nenhuma variável de ambiente obrigatória. Tudo é configurado durante `install`.

## 🔄 Modificações após instalação

Caso você modifique o script:
1. **Apenas atualizar script**: O arquivo em `/usr/local/sbin/` será atualizado automaticamente ao rodar `install`
2. **Alterar URL/Type/Code**: Use `reconfig`
3. **Recarregar timer**: `systemctl daemon-reload && systemctl restart phonevox-automacoes.timer`

## 📄 Licença

Desenvolvido para Phonevox por Rafael Rizzo.

## 📞 Suporte
18 3256 8306