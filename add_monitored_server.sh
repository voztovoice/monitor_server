#!/bin/bash
#
# Monitoring Server - Add Monitored Server
# Versión: 1.0
# 
# Instala Node Exporter en servidor remoto y lo añade a Prometheus
#

set -euo pipefail

#==========================================
# COLORES Y FUNCIONES
#==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

#==========================================
# VERIFICACIONES
#==========================================
[[ $EUID -ne 0 ]] && log_error "Este script debe ejecutarse como root"

CONFIG_FILE="/etc/monitoring/config.env"
[[ ! -f "$CONFIG_FILE" ]] && log_error "Config file no encontrado. Ejecuta monitoring_installer.sh primero"

source "$CONFIG_FILE"

NODE_EXPORTER_VERSION="1.7.0"

#==========================================
# BANNER
#==========================================
clear
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║       MONITORING - AÑADIR SERVIDOR AL MONITOREO           ║
║                                                           ║
║  Este script:                                             ║
║  1. Conectará al servidor remoto vía SSH                  ║
║  2. Instalará Node Exporter                               ║
║  3. Lo añadirá a Prometheus                               ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo ""

#==========================================
# SOLICITAR DATOS DEL SERVIDOR
#==========================================
log_info "Configuración del servidor a monitorear"
echo ""

read -p "Nombre/etiqueta del servidor (ej: email-server, vpn-server): " SERVER_NAME
SERVER_NAME=$(echo "$SERVER_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-_')
[[ -z "$SERVER_NAME" ]] && log_error "El nombre del servidor es obligatorio"

read -p "IP o hostname del servidor: " SERVER_IP
[[ -z "$SERVER_IP" ]] && log_error "La IP/hostname es obligatoria"

read -p "Puerto SSH [22]: " SSH_PORT
SSH_PORT=${SSH_PORT:-22}

read -p "Usuario SSH con sudo (ej: root): " SSH_USER
SSH_USER=${SSH_USER:-root}

echo ""
echo "Tipo de instalación:"
echo "1. Automática (requiere acceso SSH sin contraseña o con contraseña)"
echo "2. Manual (genera script para ejecutar en el servidor remoto)"
read -p "Selecciona opción [1]: " INSTALL_TYPE
INSTALL_TYPE=${INSTALL_TYPE:-1}

#==========================================
# RESUMEN
#==========================================
echo ""
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${BLUE}RESUMEN${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo "Nombre servidor:  $SERVER_NAME"
echo "IP/Hostname:      $SERVER_IP"
echo "Puerto SSH:       $SSH_PORT"
echo "Usuario SSH:      $SSH_USER"
echo "Tipo instalación: $([ "$INSTALL_TYPE" == "1" ] && echo "Automática" || echo "Manual")"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo ""
read -p "¿Continuar? (y/n): " confirm
[[ "$confirm" != "y" ]] && log_error "Operación cancelada"

#==========================================
# GENERAR SCRIPT DE INSTALACIÓN
#==========================================
INSTALL_SCRIPT="/tmp/install_node_exporter_${SERVER_NAME}.sh"

cat > "$INSTALL_SCRIPT" << 'EOSCRIPT'
#!/bin/bash
set -euo pipefail

NODE_EXPORTER_VERSION="1.7.0"

echo "[INFO] Instalando Node Exporter..."

# Crear usuario
if ! id node_exporter &>/dev/null; then
    useradd --no-create-home --shell /bin/false node_exporter
    echo "[INFO] Usuario node_exporter creado"
fi

# Descargar Node Exporter
cd /tmp
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar -xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
cd "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"

# Instalar binario
cp node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

# Crear servicio systemd
cat > /etc/systemd/system/node_exporter.service << 'EOSERVICE'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOSERVICE

# Configurar firewall (si existe nftables o firewalld)
if command -v nft &>/dev/null; then
    nft add rule inet filter input tcp dport 9100 accept 2>/dev/null || true
    nft list ruleset > /etc/sysconfig/nftables.conf 2>/dev/null || true
fi

if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-port=9100/tcp 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
fi

# Iniciar servicio
systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# Verificar
if systemctl is-active --quiet node_exporter; then
    echo "[INFO] ✓ Node Exporter instalado y corriendo"
    echo "[INFO] Métricas disponibles en: http://$(hostname -I | awk '{print $1}'):9100/metrics"
else
    echo "[ERROR] Node Exporter NO está corriendo"
    exit 1
fi

# Limpiar
cd /tmp
rm -rf node_exporter-*

echo "[INFO] Instalación completada"
EOSCRIPT

chmod +x "$INSTALL_SCRIPT"

#==========================================
# INSTALACIÓN
#==========================================
if [[ "$INSTALL_TYPE" == "1" ]]; then
    log_info "Instalando Node Exporter en $SERVER_IP..."
    
    # Probar conexión SSH
    if ! ssh -p "$SSH_PORT" -o ConnectTimeout=10 "$SSH_USER@$SERVER_IP" "echo 'OK'" &>/dev/null; then
        log_error "No se pudo conectar a $SERVER_IP vía SSH"
    fi
    
    # Copiar y ejecutar script
    scp -P "$SSH_PORT" "$INSTALL_SCRIPT" "$SSH_USER@$SERVER_IP:/tmp/install_node_exporter.sh"
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER_IP" "bash /tmp/install_node_exporter.sh"
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER_IP" "rm /tmp/install_node_exporter.sh"
    
    log_info "✓ Node Exporter instalado en $SERVER_IP"
    
else
    log_info "Script de instalación generado: $INSTALL_SCRIPT"
    log_warn "Copia y ejecuta este script en $SERVER_IP manualmente:"
    echo ""
    echo "  scp $INSTALL_SCRIPT $SSH_USER@$SERVER_IP:/tmp/"
    echo "  ssh $SSH_USER@$SERVER_IP 'bash /tmp/$(basename $INSTALL_SCRIPT)'"
    echo ""
    read -p "Presiona Enter cuando hayas ejecutado el script en el servidor remoto..."
fi

#==========================================
# AÑADIR A PROMETHEUS
#==========================================
log_info "Añadiendo $SERVER_NAME a Prometheus..."

# Backup de configuración
cp /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.backup.$(date +%s)

# Verificar si ya existe
if grep -q "job_name: '$SERVER_NAME'" /etc/prometheus/prometheus.yml; then
    log_warn "El servidor $SERVER_NAME ya existe en Prometheus"
    read -p "¿Deseas reemplazarlo? (y/n): " replace
    if [[ "$replace" == "y" ]]; then
        # Eliminar entrada existente
        sed -i "/job_name: '$SERVER_NAME'/,/^$/d" /etc/prometheus/prometheus.yml
    else
        log_error "Operación cancelada"
    fi
fi

# Añadir nueva entrada
cat >> /etc/prometheus/prometheus.yml << EOJOB

  # $SERVER_NAME
  - job_name: '$SERVER_NAME'
    static_configs:
      - targets: ['$SERVER_IP:9100']
        labels:
          instance: '$SERVER_NAME'
EOJOB

log_info "✓ Configuración añadida a Prometheus"

#==========================================
# RECARGAR PROMETHEUS
#==========================================
log_info "Recargando Prometheus..."
systemctl reload prometheus

if [[ $? -eq 0 ]]; then
    log_info "✓ Prometheus recargado correctamente"
else
    log_error "Error al recargar Prometheus"
fi

#==========================================
# VERIFICAR CONECTIVIDAD
#==========================================
log_info "Verificando conectividad con $SERVER_IP:9100..."

sleep 3

if curl -s "http://$SERVER_IP:9100/metrics" | grep -q "node_"; then
    log_info "✓ Node Exporter responde correctamente"
else
    log_warn "No se pudo conectar a Node Exporter en $SERVER_IP:9100"
    log_warn "Verifica el firewall del servidor remoto"
fi

#==========================================
# GUARDAR INFORMACIÓN
#==========================================
SERVERS_FILE="/etc/monitoring/monitored_servers.txt"

cat >> "$SERVERS_FILE" << EOSERVER
========================================
Servidor: $SERVER_NAME
IP: $SERVER_IP
Puerto SSH: $SSH_PORT
Añadido: $(date)
========================================
EOSERVER

#==========================================
# RESUMEN FINAL
#==========================================
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║          ✅  SERVIDOR AÑADIDO EXITOSAMENTE                 ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Servidor:         $SERVER_NAME"
echo "IP:               $SERVER_IP"
echo "Node Exporter:    http://$SERVER_IP:9100/metrics"
echo ""
echo "PRÓXIMOS PASOS:"
echo ""
echo "1. Verifica en Prometheus que el servidor aparece como UP:"
echo "   http://$DOMAIN:9090/targets"
echo ""
echo "2. En Grafana, el servidor ya aparecerá en los dashboards"
echo ""
echo "3. Configura alertas específicas para este servidor editando:"
echo "   /etc/prometheus/alerts.yml"
echo ""

rm -f "$INSTALL_SCRIPT"

exit 0
