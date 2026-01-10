#!/bin/bash
#
# Monitoring Server - Manage Alerts
# Versión: 1.0
# 
# Gestiona alertas de Prometheus de forma interactiva
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

ALERTS_FILE="/etc/prometheus/alerts.yml"
[[ ! -f "$ALERTS_FILE" ]] && log_error "Archivo de alertas no encontrado: $ALERTS_FILE"

CONFIG_FILE="/etc/monitoring/config.env"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

ALERTS_BACKUP="/etc/prometheus/alerts.yml.backup.$(date +%s)"

#==========================================
# FUNCIONES
#==========================================

backup_alerts() {
    cp "$ALERTS_FILE" "$ALERTS_BACKUP"
    log_info "Backup creado: $ALERTS_BACKUP"
}

reload_prometheus() {
    log_info "Recargando Prometheus..."
    systemctl reload prometheus
    
    if [[ $? -eq 0 ]]; then
        log_info "✓ Prometheus recargado correctamente"
    else
        log_error "Error al recargar Prometheus"
    fi
}

view_alerts() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}ALERTAS CONFIGURADAS${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════${NC}"
    echo ""
    
    # Mostrar alertas de forma legible
    grep -A 10 "alert:" "$ALERTS_FILE" | grep -E "alert:|expr:|for:|severity:|summary:|description:" | sed 's/^/  /'
    
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════${NC}"
    echo ""
}

view_active_alerts() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}ALERTAS ACTIVAS (EN PROMETHEUS)${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════${NC}"
    echo ""
    
    ALERTS_JSON=$(curl -s http://localhost:9090/api/v1/alerts)
    
    if echo "$ALERTS_JSON" | jq -e '.data.alerts | length > 0' &>/dev/null; then
        echo "$ALERTS_JSON" | jq -r '.data.alerts[] | "[\(.state)] \(.labels.alertname) - \(.annotations.summary)"'
    else
        echo "No hay alertas activas en este momento ✓"
    fi
    
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════${NC}"
    echo ""
}

add_alert() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}AÑADIR NUEVA ALERTA${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo ""
    
    read -p "Nombre de la alerta (sin espacios): " alert_name
    [[ -z "$alert_name" ]] && log_error "El nombre de la alerta es obligatorio"
    
    echo ""
    echo "Ejemplos de expresiones PromQL:"
    echo "  - CPU alta: 100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100) > 80"
    echo "  - Memoria baja: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 < 10"
    echo "  - Disco lleno: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 10"
    echo "  - Servicio caído: up{job=\"nombre_job\"} == 0"
    echo ""
    read -p "Expresión PromQL: " expr
    [[ -z "$expr" ]] && log_error "La expresión es obligatoria"
    
    echo ""
    echo "Duración (ejemplos: 1m, 5m, 10m, 1h)"
    read -p "Durante cuánto tiempo debe cumplirse [5m]: " duration
    duration=${duration:-5m}
    
    echo ""
    echo "Severidad: critical, warning, info"
    read -p "Severidad [warning]: " severity
    severity=${severity:-warning}
    
    read -p "Resumen de la alerta: " summary
    [[ -z "$summary" ]] && summary="Alerta: $alert_name"
    
    read -p "Descripción detallada: " description
    [[ -z "$description" ]] && description="$summary"
    
    echo ""
    echo -e "${YELLOW}Nueva alerta:${NC}"
    echo "  Nombre: $alert_name"
    echo "  Expresión: $expr"
    echo "  Durante: $duration"
    echo "  Severidad: $severity"
    echo "  Resumen: $summary"
    echo ""
    read -p "¿Añadir esta alerta? (y/n): " confirm
    
    if [[ "$confirm" == "y" ]]; then
        backup_alerts
        
        # Añadir nueva alerta al final del primer grupo
        cat >> "$ALERTS_FILE" << EOALERT

      # $alert_name
      - alert: $alert_name
        expr: $expr
        for: $duration
        labels:
          severity: $severity
        annotations:
          summary: "$summary"
          description: "$description"
EOALERT
        
        log_info "✓ Alerta añadida correctamente"
        reload_prometheus
    else
        log_warn "Operación cancelada"
    fi
}

add_predefined_alert() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}ALERTAS PREDEFINIDAS${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo ""
    
    echo "1. Servicio específico caído"
    echo "2. Puerto TCP no responde"
    echo "3. Disco creciendo rápidamente"
    echo "4. Alto uso de inodes"
    echo "5. Muchos procesos zombie"
    echo "6. Swap en uso"
    echo "7. Reloj del sistema desincronizado"
    echo "8. Reinicio reciente del sistema"
    echo "9. Volver"
    echo ""
    read -p "Selecciona una opción [1-9]: " option
    
    case $option in
        1)
            read -p "Nombre del servicio (ej: postfix, nginx): " service_name
            [[ -z "$service_name" ]] && return
            
            backup_alerts
            cat >> "$ALERTS_FILE" << EOALERT

      # Servicio $service_name caído
      - alert: ${service_name^}Down
        expr: node_systemd_unit_state{name="${service_name}.service",state="active"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Servicio ${service_name} caído en {{ \$labels.instance }}"
          description: "El servicio ${service_name} no está corriendo en {{ \$labels.instance }}"
EOALERT
            log_info "✓ Alerta añadida para servicio $service_name"
            reload_prometheus
            ;;
        2)
            read -p "Puerto TCP (ej: 25, 80, 443): " port
            [[ -z "$port" ]] && return
            read -p "Nombre descriptivo: " port_name
            [[ -z "$port_name" ]] && port_name="port_$port"
            
            backup_alerts
            cat >> "$ALERTS_FILE" << EOALERT

      # Puerto $port no responde
      - alert: Port${port}Down
        expr: probe_success{job="blackbox",instance="localhost:${port}"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Puerto $port ($port_name) no responde en {{ \$labels.instance }}"
          description: "No se puede conectar al puerto $port en {{ \$labels.instance }}"
EOALERT
            log_info "✓ Alerta añadida para puerto $port"
            log_warn "Necesitas configurar blackbox_exporter para que funcione"
            reload_prometheus
            ;;
        3)
            backup_alerts
            cat >> "$ALERTS_FILE" << EOALERT

      # Disco creciendo rápidamente
      - alert: DiskFillingUp
        expr: predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[1h], 4*3600) < 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disco llenándose rápidamente en {{ \$labels.instance }}"
          description: "Se predice que el disco estará lleno en menos de 4 horas en {{ \$labels.instance }}"
EOALERT
            log_info "✓ Alerta añadida para crecimiento rápido de disco"
            reload_prometheus
            ;;
        4)
            backup_alerts
            cat >> "$ALERTS_FILE" << EOALERT

      # Alto uso de inodes
      - alert: HighInodeUsage
        expr: (node_filesystem_files_free{mountpoint="/"} / node_filesystem_files{mountpoint="/"}) * 100 < 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Inodes casi agotados en {{ \$labels.instance }}"
          description: "Solo quedan {{ \$value }}% de inodes libres en {{ \$labels.instance }}"
EOALERT
            log_info "✓ Alerta añadida para uso de inodes"
            reload_prometheus
            ;;
        5)
            backup_alerts
            cat >> "$ALERTS_FILE" << EOALERT

      # Muchos procesos zombie
      - alert: TooManyZombieProcesses
        expr: node_processes_state{state="zombie"} > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Demasiados procesos zombie en {{ \$labels.instance }}"
          description: "Hay {{ \$value }} procesos zombie en {{ \$labels.instance }}"
EOALERT
            log_info "✓ Alerta añadida para procesos zombie"
            reload_prometheus
            ;;
        6)
            backup_alerts
            cat >> "$ALERTS_FILE" << EOALERT

      # Swap en uso
      - alert: SwapInUse
        expr: (node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes) / node_memory_SwapTotal_bytes * 100 > 50
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Swap en uso en {{ \$labels.instance }}"
          description: "Uso de swap: {{ \$value }}% en {{ \$labels.instance }}"
EOALERT
            log_info "✓ Alerta añadida para uso de swap"
            reload_prometheus
            ;;
        7)
            backup_alerts
            cat >> "$ALERTS_FILE" << EOALERT

      # Reloj desincronizado
      - alert: ClockSkew
        expr: abs(node_timex_offset_seconds) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Reloj del sistema desincronizado en {{ \$labels.instance }}"
          description: "Desviación del reloj: {{ \$value }}s en {{ \$labels.instance }}"
EOALERT
            log_info "✓ Alerta añadida para sincronización de reloj"
            reload_prometheus
            ;;
        8)
            backup_alerts
            cat >> "$ALERTS_FILE" << EOALERT

      # Reinicio reciente
      - alert: SystemReboot
        expr: node_boot_time_seconds > (time() - 600)
        for: 1m
        labels:
          severity: info
        annotations:
          summary: "Sistema reiniciado recientemente en {{ \$labels.instance }}"
          description: "El sistema {{ \$labels.instance }} se reinició hace menos de 10 minutos"
EOALERT
            log_info "✓ Alerta añadida para reinicios del sistema"
            reload_prometheus
            ;;
        9)
            return
            ;;
        *)
            log_warn "Opción inválida"
            ;;
    esac
}

test_alert() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}PROBAR EXPRESIÓN PROMQL${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo ""
    
    read -p "Expresión PromQL a probar: " expr
    [[ -z "$expr" ]] && return
    
    echo ""
    log_info "Ejecutando query en Prometheus..."
    
    RESULT=$(curl -s -G --data-urlencode "query=$expr" http://localhost:9090/api/v1/query)
    
    if echo "$RESULT" | jq -e '.status == "success"' &>/dev/null; then
        echo ""
        echo "Resultado:"
        echo "$RESULT" | jq -r '.data.result[] | "  [\(.metric.instance // "N/A")] \(.value[1])"'
        echo ""
    else
        log_error "Error en la query: $(echo "$RESULT" | jq -r '.error')"
    fi
}

edit_file() {
    echo ""
    log_warn "Abriendo editor de texto..."
    log_warn "Después de guardar, Prometheus se recargará automáticamente"
    echo ""
    read -p "Presiona Enter para continuar..."
    
    backup_alerts
    
    ${EDITOR:-nano} "$ALERTS_FILE"
    
    log_info "Archivo guardado"
    reload_prometheus
}

view_logs() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}LOGS DE ALERTMANAGER (ÚLTIMAS 50 LÍNEAS)${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════${NC}"
    echo ""
    
    journalctl -u alertmanager -n 50 --no-pager
    
    echo ""
}

restore_backup() {
    echo ""
    echo -e "${YELLOW}Backups disponibles:${NC}"
    echo ""
    
    BACKUPS=$(ls -1t /etc/prometheus/alerts.yml.backup.* 2>/dev/null || echo "")
    
    if [[ -z "$BACKUPS" ]]; then
        log_warn "No hay backups disponibles"
        return
    fi
    
    echo "$BACKUPS" | nl
    echo ""
    
    TOTAL_BACKUPS=$(echo "$BACKUPS" | wc -l)
    read -p "Número de backup a restaurar (1-$TOTAL_BACKUPS) [0 para cancelar]: " backup_num
    
    if [[ "$backup_num" == "0" || -z "$backup_num" ]]; then
        log_warn "Operación cancelada"
        return
    fi
    
    if ! [[ "$backup_num" =~ ^[0-9]+$ ]] || [[ "$backup_num" -lt 1 || "$backup_num" -gt "$TOTAL_BACKUPS" ]]; then
        log_error "Número de backup inválido"
    fi
    
    BACKUP_FILE=$(echo "$BACKUPS" | sed -n "${backup_num}p")
    
    echo ""
    echo -e "${YELLOW}Restaurar desde:${NC} $BACKUP_FILE"
    echo ""
    read -p "¿Confirmar restauración? (y/n): " confirm
    
    if [[ "$confirm" == "y" ]]; then
        cp "$ALERTS_FILE" "${ALERTS_FILE}.before_restore.$(date +%s)"
        cp "$BACKUP_FILE" "$ALERTS_FILE"
        
        log_info "✓ Backup restaurado correctamente"
        reload_prometheus
    else
        log_warn "Operación cancelada"
    fi
}

#==========================================
# MENÚ PRINCIPAL
#==========================================
clear
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        MONITORING SERVER - GESTIÓN DE ALERTAS             ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF

while true; do
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${BLUE}MENÚ PRINCIPAL${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo ""
    echo "1. Ver alertas configuradas"
    echo "2. Ver alertas activas en Prometheus"
    echo "3. Añadir alerta personalizada"
    echo "4. Añadir alerta predefinida"
    echo "5. Probar expresión PromQL"
    echo "6. Editar archivo de alertas manualmente"
    echo "7. Ver logs de Alertmanager"
    echo "8. Restaurar backup"
    echo "9. Salir"
    echo ""
    read -p "Selecciona una opción [1-9]: " option
    
    case $option in
        1)
            view_alerts
            ;;
        2)
            view_active_alerts
            ;;
        3)
            add_alert
            ;;
        4)
            add_predefined_alert
            ;;
        5)
            test_alert
            ;;
        6)
            edit_file
            ;;
        7)
            view_logs
            ;;
        8)
            restore_backup
            ;;
        9)
            log_info "Saliendo..."
            exit 0
            ;;
        *)
            log_warn "Opción inválida"
            ;;
    esac
done
