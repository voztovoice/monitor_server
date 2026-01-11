#!/bin/bash
#
# Monitoring Server - Instalador Completo
# Versión: 1.0
# Compatible: AlmaLinux 10
# 
# Instala: Prometheus + Grafana + Alertmanager + Node Exporter
# Firewall: nftables
#
# Uso: ./monitoring_installer.sh
#

set -euo pipefail

#==========================================
# COLORES Y FUNCIONES DE LOG
#==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOGFILE="/var/log/monitoring_install.log"
exec > >(tee -a "$LOGFILE") 2>&1

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    exit 1
}

log_section() {
    echo ""
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
}

#==========================================
# VERIFICACIONES INICIALES
#==========================================
[[ $EUID -ne 0 ]] && log_error "Este script debe ejecutarse como root"

if [[ ! -f /etc/almalinux-release ]]; then
    log_warn "Este script está diseñado para AlmaLinux 10"
    read -p "¿Continuar de todas formas? (y/n): " continue_anyway
    [[ "$continue_anyway" != "y" ]] && exit 0
fi

#==========================================
# VERSIONES DE SOFTWARE
#==========================================
PROMETHEUS_VERSION="2.48.1"
ALERTMANAGER_VERSION="0.26.0"
NODE_EXPORTER_VERSION="1.7.0"
GRAFANA_VERSION="10.2.3"

#==========================================
# CONFIGURACIÓN GLOBAL
#==========================================
CONFIG_DIR="/etc/monitoring"
CONFIG_FILE="$CONFIG_DIR/config.env"
CRED_DIR="$CONFIG_DIR/credentials"

mkdir -p "$CONFIG_DIR"
mkdir -p "$CRED_DIR"
chmod 700 "$CONFIG_DIR"
chmod 700 "$CRED_DIR"

#==========================================
# BANNER
#==========================================
clear
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║       MONITORING SERVER - INSTALADOR COMPLETO             ║
║                                                           ║
║  Instalará:                                               ║
║  • Prometheus (Recolección de métricas)                   ║
║  • Grafana (Visualización)                                ║
║  • Alertmanager (Gestión de alertas)                      ║
║  • Node Exporter (Métricas del sistema)                   ║
║                                                           ║
║  Puertos:                                                 ║
║  • Prometheus: 9090                                       ║
║  • Grafana: 3000                                          ║
║  • Alertmanager: 9093                                     ║
║  • Node Exporter: 9100                                    ║
║                                                           ║
║  Compatible: AlmaLinux 10                                 ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo ""
read -p "Presione Enter para continuar..."

#==========================================
# RECOPILACIÓN DE CONFIGURACIÓN
#==========================================
log_section "CONFIGURACIÓN INICIAL"

# Dominio o IP
read -p "Dominio o IP para acceso (ej: monitor.ejemplo.com o IP): " DOMAIN
DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]' | xargs)
[[ -z "$DOMAIN" ]] && log_error "El dominio/IP es obligatorio"

# Email para alertas
read -p "Email para recibir alertas: " ALERT_EMAIL
[[ -z "$ALERT_EMAIL" ]] && log_error "El email para alertas es obligatorio"

# Detectar IP pública
log_info "Detectando IP pública..."
DETECTED_IP=$(curl -s -4 ifconfig.me || curl -s -4 icanhazip.com || echo "")
if [[ -n "$DETECTED_IP" ]]; then
    read -p "IP pública detectada: $DETECTED_IP - ¿Es correcta? (y/n) [y]: " ip_correct
    ip_correct=${ip_correct:-y}
    if [[ "$ip_correct" == "y" ]]; then
        PRIMARY_IP="$DETECTED_IP"
    else
        read -p "Introduce IP pública: " PRIMARY_IP
    fi
else
    read -p "IP pública del servidor: " PRIMARY_IP
fi
[[ -z "$PRIMARY_IP" ]] && log_error "La IP es obligatoria"

# Detectar interfaz de red
log_info "Detectando interfaz de red..."
DETECTED_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [[ -n "$DETECTED_INTERFACE" ]]; then
    echo ""
    echo "Interfaz detectada: $DETECTED_INTERFACE"
    ip addr show "$DETECTED_INTERFACE" | grep -E "inet |link/"
    echo ""
    read -p "¿Es correcta esta interfaz? (y/n) [y]: " interface_correct
    interface_correct=${interface_correct:-y}
    if [[ "$interface_correct" == "y" ]]; then
        INTERFACE="$DETECTED_INTERFACE"
    else
        echo "Interfaces disponibles:"
        ip link show | grep -E "^[0-9]+" | awk '{print $2}' | sed 's/://'
        read -p "Introduce nombre de interfaz: " INTERFACE
    fi
else
    echo "Interfaces disponibles:"
    ip link show | grep -E "^[0-9]+" | awk '{print $2}' | sed 's/://'
    read -p "Introduce nombre de interfaz: " INTERFACE
fi
[[ -z "$INTERFACE" ]] && log_error "La interfaz es obligatoria"

# Zona horaria
echo ""
echo "Zonas horarias comunes:"
echo "  America/Bogota"
echo "  America/Mexico_City"
echo "  America/New_York"
echo "  Europe/Madrid"
read -p "Zona horaria [America/Bogota]: " TIMEZONE
TIMEZONE=${TIMEZONE:-America/Bogota}

# Contraseña para Grafana
log_info "Generando contraseña para Grafana admin..."
GRAFANA_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-16)
echo ""
echo -e "${YELLOW}Contraseña Grafana admin:${NC} ${GREEN}$GRAFANA_PASSWORD${NC}"
echo ""
read -p "¿Aceptar esta contraseña? (y/n) [y]: " accept_password
accept_password=${accept_password:-y}

if [[ "$accept_password" != "y" ]]; then
    read -sp "Introduce tu propia contraseña: " GRAFANA_PASSWORD
    echo ""
    [[ -z "$GRAFANA_PASSWORD" ]] && log_error "La contraseña no puede estar vacía"
fi

# Slack webhook (opcional)
echo ""
read -p "¿Deseas configurar notificaciones por Slack? (y/n) [n]: " use_slack
use_slack=${use_slack:-n}

SLACK_WEBHOOK=""
if [[ "$use_slack" == "y" ]]; then
    read -p "Webhook URL de Slack: " SLACK_WEBHOOK
fi

# Telegram (opcional)
echo ""
read -p "¿Deseas configurar notificaciones por Telegram? (y/n) [n]: " use_telegram
use_telegram=${use_telegram:-n}

TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
if [[ "$use_telegram" == "y" ]]; then
    read -p "Bot Token de Telegram: " TELEGRAM_BOT_TOKEN
    read -p "Chat ID de Telegram: " TELEGRAM_CHAT_ID
fi

#==========================================
# RESUMEN DE CONFIGURACIÓN
#==========================================
log_section "RESUMEN DE CONFIGURACIÓN"

cat << EOSUMMARY
Dominio/IP:           $DOMAIN
IP pública:           $PRIMARY_IP
Interfaz de red:      $INTERFACE
Zona horaria:         $TIMEZONE
Email alertas:        $ALERT_EMAIL
Contraseña Grafana:   $GRAFANA_PASSWORD

URLs de acceso:
  - Prometheus:       http://$DOMAIN:9090
  - Grafana:          http://$DOMAIN:3000
  - Alertmanager:     http://$DOMAIN:9093

Notificaciones:
  - Email:            Sí
  - Slack:            $([ "$use_slack" == "y" ] && echo "Sí" || echo "No")
  - Telegram:         $([ "$use_telegram" == "y" ] && echo "Sí" || echo "No")

EOSUMMARY

echo ""
read -p "¿Toda la configuración es correcta? (y/n): " confirm_config
[[ "$confirm_config" != "y" ]] && log_error "Instalación cancelada por el usuario"

# Guardar configuración
cat > "$CONFIG_FILE" << EOCONFIG
# Monitoring Server Configuration
# Generado: $(date)

export DOMAIN="$DOMAIN"
export PRIMARY_IP="$PRIMARY_IP"
export INTERFACE="$INTERFACE"
export TIMEZONE="$TIMEZONE"
export ALERT_EMAIL="$ALERT_EMAIL"
export GRAFANA_PASSWORD="$GRAFANA_PASSWORD"
export SLACK_WEBHOOK="$SLACK_WEBHOOK"
export TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
export TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
EOCONFIG

chmod 600 "$CONFIG_FILE"
source "$CONFIG_FILE"

log_info "Configuración guardada en $CONFIG_FILE"

#==========================================
# FASE 1: SISTEMA BASE
#==========================================
log_section "FASE 1: SISTEMA BASE"

log_info "Actualizando sistema..."
dnf update -y

log_info "Instalando paquetes base..."
dnf install -y \
    wget curl tar \
    chrony nftables \
    policycoreutils-python-utils \
    openssl

log_info "Configurando zona horaria..."
timedatectl set-timezone "$TIMEZONE"

log_info "Configurando chrony (NTP)..."
systemctl enable chronyd
systemctl start chronyd

log_info "Configurando SELinux en modo permissive..."
setenforce 0 2>/dev/null || true
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

log_info "Configurando firewall (nftables)..."

# Detener firewalld
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true
systemctl mask firewalld 2>/dev/null || true

# Habilitar nftables
systemctl enable nftables

# Limpiar configuración
nft flush ruleset

# Crear tabla
nft add table inet filter

# Crear cadenas
nft add chain inet filter input { type filter hook input priority 0 \; policy drop \; }
nft add chain inet filter forward { type filter hook forward priority 0 \; policy drop \; }
nft add chain inet filter output { type filter hook output priority 0 \; policy accept \; }

# Loopback
nft add rule inet filter input iif lo accept
nft add rule inet filter input iif != lo ip daddr 127.0.0.0/8 reject

# Estados establecidos
nft add rule inet filter input ct state established,related accept

# SSH
nft add rule inet filter input tcp dport 22 accept

# Prometheus
nft add rule inet filter input tcp dport 9090 accept

# Grafana
nft add rule inet filter input tcp dport 3000 accept

# Alertmanager
nft add rule inet filter input tcp dport 9093 accept

# Node Exporter
nft add rule inet filter input tcp dport 9100 accept

# ICMP
nft add rule inet filter input ip protocol icmp icmp type echo-request accept
nft add rule inet filter input ip6 nexthdr icmpv6 accept

# Guardar
nft list ruleset > /etc/sysconfig/nftables.conf

# Iniciar
systemctl start nftables

log_info "Sistema base configurado correctamente"

#==========================================
# FASE 2: CREAR USUARIOS DEL SISTEMA
#==========================================
log_section "FASE 2: USUARIOS DEL SISTEMA"

log_info "Creando usuarios para servicios..."

# Usuario para Prometheus
if ! id prometheus &>/dev/null; then
    useradd --no-create-home --shell /bin/false prometheus
    log_info "✓ Usuario prometheus creado"
fi

# Usuario para Alertmanager
if ! id alertmanager &>/dev/null; then
    useradd --no-create-home --shell /bin/false alertmanager
    log_info "✓ Usuario alertmanager creado"
fi

# Usuario para Node Exporter
if ! id node_exporter &>/dev/null; then
    useradd --no-create-home --shell /bin/false node_exporter
    log_info "✓ Usuario node_exporter creado"
fi

#==========================================
# FASE 3: INSTALAR PROMETHEUS
#==========================================
log_section "FASE 3: PROMETHEUS"

log_info "Descargando Prometheus $PROMETHEUS_VERSION..."
cd /tmp
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

log_info "Extrayendo Prometheus..."
tar -xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
cd "prometheus-${PROMETHEUS_VERSION}.linux-amd64"

log_info "Instalando binarios de Prometheus..."
cp prometheus promtool /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

log_info "Creando directorios de Prometheus..."
mkdir -p /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /etc/prometheus /var/lib/prometheus

log_info "Copiando archivos de configuración..."
cp -r consoles console_libraries /etc/prometheus/
chown -R prometheus:prometheus /etc/prometheus/consoles /etc/prometheus/console_libraries

log_info "Creando configuración de Prometheus..."
cat > /etc/prometheus/prometheus.yml << EOPROM
# Prometheus Configuration
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'monitoring-server'

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093

# Load rules once and periodically evaluate them
rule_files:
  - "alerts.yml"

# Scrape configurations
scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          instance: 'prometheus-server'

  # Node Exporter (este servidor)
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          instance: 'monitoring-server'

  # Alertmanager
  - job_name: 'alertmanager'
    static_configs:
      - targets: ['localhost:9093']
        labels:
          instance: 'alertmanager'
EOPROM

chown prometheus:prometheus /etc/prometheus/prometheus.yml

log_info "Creando reglas de alertas..."
cat > /etc/prometheus/alerts.yml <<EOALERTS
groups:
  - name: system_alerts
    interval: 30s
    rules:
      # Instancia caída
      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Instancia {{ \$labels.instance }} caída"
          description: "{{ \$labels.instance }} del job {{ \$labels.job }} ha estado caída por más de 1 minuto."

      # CPU alta
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Uso alto de CPU en {{ \$labels.instance }}"
          description: "CPU en {{ \$labels.instance }} está en {{ \$value }}%"

      # Memoria alta
      - alert: HighMemoryUsage
        expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 < 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Memoria baja en {{ \$labels.instance }}"
          description: "Memoria disponible en {{ \$labels.instance }}: {{ \$value }}%"

      # Disco lleno
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Espacio en disco bajo en {{ \$labels.instance }}"
          description: "Espacio disponible en {{ \$labels.instance }}: {{ \$value }}%"

      # Disco crítico
      - alert: DiskSpaceCritical
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 5
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Espacio en disco CRÍTICO en {{ \$labels.instance }}"
          description: "Espacio disponible en {{ \$labels.instance }}: {{ \$value }}%"

      # Carga del sistema
      - alert: HighSystemLoad
        expr: node_load15 > 2
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Carga del sistema alta en {{ \$labels.instance }}"
          description: "Load average (15m) en {{ \$labels.instance }}: {{ \$value }}"
EOALERTS

chown prometheus:prometheus /etc/prometheus/alerts.yml

log_info "Creando servicio systemd para Prometheus..."
cat > /etc/systemd/system/prometheus.service << EOSERVICE
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file=/etc/prometheus/prometheus.yml \\
    --storage.tsdb.path=/var/lib/prometheus/ \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries \\
    --web.listen-address=0.0.0.0:9090 \\
    --storage.tsdb.retention.time=30d

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOSERVICE

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

log_info "✓ Prometheus instalado y corriendo"

#==========================================
# FASE 4: INSTALAR NODE EXPORTER
#==========================================
log_section "FASE 4: NODE EXPORTER"

log_info "Descargando Node Exporter $NODE_EXPORTER_VERSION..."
cd /tmp
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

log_info "Extrayendo Node Exporter..."
tar -xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
cd "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"

log_info "Instalando binario de Node Exporter..."
cp node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

log_info "Creando servicio systemd para Node Exporter..."
cat > /etc/systemd/system/node_exporter.service << EOSERVICE
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \\
    --web.listen-address=0.0.0.0:9100

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOSERVICE

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

log_info "✓ Node Exporter instalado y corriendo"

#==========================================
# FASE 5: INSTALAR ALERTMANAGER
#==========================================
log_section "FASE 5: ALERTMANAGER"

log_info "Descargando Alertmanager $ALERTMANAGER_VERSION..."
cd /tmp
wget -q "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"

log_info "Extrayendo Alertmanager..."
tar -xzf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
cd "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64"

log_info "Instalando binarios de Alertmanager..."
cp alertmanager amtool /usr/local/bin/
chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool

log_info "Creando directorios de Alertmanager..."
mkdir -p /etc/alertmanager /var/lib/alertmanager
chown alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager

log_info "Creando configuración de Alertmanager..."

# Configurar receptores según las opciones elegidas
RECEIVERS_CONFIG=""
ROUTE_RECEIVER="email"

# Email siempre está configurado
RECEIVERS_CONFIG+="  - name: 'email'
    email_configs:
      - to: '$ALERT_EMAIL'
        from: 'alertmanager@$DOMAIN'
        smarthost: 'localhost:25'
        require_tls: false
"

# Slack si está configurado
if [[ -n "$SLACK_WEBHOOK" ]]; then
    RECEIVERS_CONFIG+="
  - name: 'slack'
    slack_configs:
      - api_url: '$SLACK_WEBHOOK'
        channel: '#alerts'
        title: 'Alerta de Monitoreo'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ .Annotations.description }}\n{{ end }}'
"
    ROUTE_RECEIVER="email,slack"
fi

# Telegram si está configurado
if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
    RECEIVERS_CONFIG+="
  - name: 'telegram'
    telegram_configs:
      - bot_token: '$TELEGRAM_BOT_TOKEN'
        chat_id: $TELEGRAM_CHAT_ID
        parse_mode: 'HTML'
        message: '{{ range .Alerts }}<b>{{ .Labels.severity | toUpper }}</b>: {{ .Annotations.summary }}\n{{ .Annotations.description }}\n{{ end }}'
"
    if [[ "$ROUTE_RECEIVER" == "email" ]]; then
        ROUTE_RECEIVER="email,telegram"
    else
        ROUTE_RECEIVER="email,slack,telegram"
    fi
fi

cat > /etc/alertmanager/alertmanager.yml << EOALERT
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'instance']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'email'

receivers:
$RECEIVERS_CONFIG

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
EOALERT

chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml

log_info "Creando servicio systemd para Alertmanager..."
cat > /etc/systemd/system/alertmanager.service << EOSERVICE
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \\
    --config.file=/etc/alertmanager/alertmanager.yml \\
    --storage.path=/var/lib/alertmanager/ \\
    --web.listen-address=0.0.0.0:9093 \\
    --cluster.listen-address=""

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOSERVICE

systemctl daemon-reload
systemctl enable alertmanager
systemctl start alertmanager

log_info "✓ Alertmanager instalado y corriendo"

#==========================================
# FASE 6: INSTALAR GRAFANA
#==========================================
log_section "FASE 6: GRAFANA"

log_info "Añadiendo repositorio de Grafana..."
cat > /etc/yum.repos.d/grafana.repo << EOREPO
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOREPO

log_info "Instalando Grafana..."
dnf install -y grafana

log_info "Configurando Grafana..."
cat > /etc/grafana/grafana.ini << EOGRAFANA
[server]
protocol = http
http_addr = 0.0.0.0
http_port = 3000
domain = $DOMAIN
root_url = http://$DOMAIN:3000

[security]
admin_user = admin
admin_password = $GRAFANA_PASSWORD

[auth.anonymous]
enabled = false

[analytics]
reporting_enabled = false
check_for_updates = false

[log]
mode = console file
level = info

[alerting]
enabled = false
EOGRAFANA

log_info "Iniciando Grafana..."
systemctl enable grafana-server
systemctl start grafana-server

sleep 5

log_info "Configurando datasource de Prometheus en Grafana..."
curl -X POST -H "Content-Type: application/json" \
    -u admin:$GRAFANA_PASSWORD \
    http://localhost:3000/api/datasources \
    -d '{
      "name":"Prometheus",
      "type":"prometheus",
      "url":"http://localhost:9090",
      "access":"proxy",
      "isDefault":true
    }' 2>/dev/null || log_warn "No se pudo configurar datasource automáticamente (configurar manualmente)"

log_info "✓ Grafana instalado y corriendo"

#==========================================
# LIMPIAR ARCHIVOS TEMPORALES
#==========================================
log_section "LIMPIEZA"

log_info "Limpiando archivos temporales..."
cd /tmp
rm -rf prometheus-* alertmanager-* node_exporter-*

#==========================================
# VERIFICAR SERVICIOS
#==========================================
log_section "VERIFICACIÓN DE SERVICIOS"

SERVICES_OK=true

if systemctl is-active --quiet prometheus; then
    log_info "✓ Prometheus corriendo"
else
    log_error "✗ Prometheus NO está corriendo"
    SERVICES_OK=false
fi

if systemctl is-active --quiet node_exporter; then
    log_info "✓ Node Exporter corriendo"
else
    log_error "✗ Node Exporter NO está corriendo"
    SERVICES_OK=false
fi

if systemctl is-active --quiet alertmanager; then
    log_info "✓ Alertmanager corriendo"
else
    log_error "✗ Alertmanager NO está corriendo"
    SERVICES_OK=false
fi

if systemctl is-active --quiet grafana-server; then
    log_info "✓ Grafana corriendo"
else
    log_error "✗ Grafana NO está corriendo"
    SERVICES_OK=false
fi

if [ "$SERVICES_OK" = false ]; then
    log_error "Algunos servicios NO están corriendo correctamente"
fi

#==========================================
# GUARDAR INFORMACIÓN
#==========================================
log_section "GUARDANDO INFORMACIÓN"

cat > "$CRED_DIR/access_info.txt" << EOINFO
========================================
MONITORING SERVER - INFORMACIÓN DE ACCESO
========================================
Generado: $(date)

DOMINIO/IP: $DOMAIN

========================================
PROMETHEUS
========================================
URL: http://$DOMAIN:9090
Usuario: N/A (sin autenticación por defecto)

Endpoints útiles:
  - Targets: http://$DOMAIN:9090/targets
  - Alerts: http://$DOMAIN:9090/alerts
  - Graph: http://$DOMAIN:9090/graph

========================================
GRAFANA
========================================
URL: http://$DOMAIN:3000
Usuario: admin
Contraseña: $GRAFANA_PASSWORD

Datasource: Prometheus (ya configurado)

========================================
ALERTMANAGER
========================================
URL: http://$DOMAIN:9093
Usuario: N/A (sin autenticación por defecto)

Email alertas: $ALERT_EMAIL
$([ -n "$SLACK_WEBHOOK" ] && echo "Slack: Configurado")
$([ -n "$TELEGRAM_BOT_TOKEN" ] && echo "Telegram: Configurado")

========================================
NODE EXPORTER
========================================
URL: http://$DOMAIN:9100/metrics
Métricas del servidor de monitoreo

========================================
ARCHIVOS DE CONFIGURACIÓN
========================================
Prometheus: /etc/prometheus/prometheus.yml
Alertas: /etc/prometheus/alerts.yml
Alertmanager: /etc/alertmanager/alertmanager.yml
Grafana: /etc/grafana/grafana.ini

========================================
COMANDOS ÚTILES
========================================
# Ver estado de servicios
systemctl status prometheus
systemctl status alertmanager
systemctl status grafana-server
systemctl status node_exporter

# Ver logs
journalctl -u prometheus -f
journalctl -u alertmanager -f
journalctl -u grafana-server -f

# Recargar configuración
systemctl reload prometheus
systemctl reload alertmanager

========================================
EOINFO

chmod 600 "$CRED_DIR/access_info.txt"

log_info "Información guardada en $CRED_DIR/access_info.txt"

#==========================================
# RESUMEN FINAL
#==========================================
log_section "INSTALACIÓN COMPLETADA"

cat << EOFINAL

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        ✅  INSTALACIÓN COMPLETADA EXITOSAMENTE            ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

Sistema de monitoreo configurado:

  ✅ Prometheus (http://$DOMAIN:9090)
  ✅ Grafana (http://$DOMAIN:3000)
  ✅ Alertmanager (http://$DOMAIN:9093)
  ✅ Node Exporter (http://$DOMAIN:9100)

ACCESO A GRAFANA:
  URL: http://$DOMAIN:3000
  Usuario: admin
  Contraseña: $GRAFANA_PASSWORD

INFORMACIÓN COMPLETA:
  $CRED_DIR/access_info.txt

PRÓXIMOS PASOS:

1. Accede a Grafana: http://$DOMAIN:3000
2. Importa dashboards predefinidos (ID: 1860 para Node Exporter)
3. Añade servidores adicionales con add_monitored_server.sh
4. Configura alertas personalizadas

Log de instalación: $LOGFILE

EOFINAL

log_info "¡Sistema de monitoreo listo para usar!"

exit 0
