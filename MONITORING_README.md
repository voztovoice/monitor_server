# Sistema de Monitoreo - Prometheus + Grafana + Alertmanager

Sistema completo de monitoreo para infraestructura basado en Prometheus, Grafana y Alertmanager para AlmaLinux 10.

## Características

- **Prometheus** - Motor de métricas y monitoreo
- **Grafana** - Visualización de datos con dashboards
- **Alertmanager** - Gestión inteligente de alertas
- **Node Exporter** - Métricas del sistema operativo
- **Alertas predefinidas** - CPU, memoria, disco, servicios
- **Notificaciones múltiples** - Email, Slack, Telegram
- **Gestión simplificada** - Scripts interactivos para todo

## Componentes y Puertos

| Componente | Puerto | Descripción |
|------------|--------|-------------|
| Prometheus | 9090 | Consola web y API de métricas |
| Grafana | 3000 | Dashboards y visualización |
| Alertmanager | 9093 | Gestión de alertas |
| Node Exporter | 9100 | Métricas del sistema |

## Requisitos Previos

- AlmaLinux 10 recién instalado
- Acceso root
- Mínimo 2GB RAM, 2 CPU cores
- 20GB espacio en disco
- Puertos 9090, 3000, 9093, 9100 abiertos en firewall

## Instalación Rápida

### 1. Descargar scripts

```bash
wget https://tu-servidor.com/monitoring_installer.sh
wget https://tu-servidor.com/add_monitored_server.sh
wget https://tu-servidor.com/manage_alerts.sh

chmod +x *.sh
```

### 2. Ejecutar instalador

```bash
./monitoring_installer.sh
```

El instalador te preguntará:
- Dominio o IP para acceso
- Email para recibir alertas
- Contraseña de Grafana (o se genera automática)
- Configuración de Slack (opcional)
- Configuración de Telegram (opcional)

### 3. Acceder al sistema

Una vez instalado:

**Prometheus**: http://tu-servidor:9090
**Grafana**: http://tu-servidor:3000
- Usuario: `admin`
- Contraseña: La que configuraste en la instalación

## Configuración Post-Instalación

### Importar Dashboards en Grafana

1. Accede a Grafana (http://tu-servidor:3000)
2. Ve a **Dashboards → Import**
3. Importa estos dashboards populares por ID:

**Node Exporter Full** (ID: 1860)
- Dashboard completo para métricas del sistema
- CPU, memoria, disco, red, procesos

**Prometheus 2.0 Stats** (ID: 3662)
- Estadísticas del propio Prometheus
- Queries, targets, alertas

**Alertmanager** (ID: 9578)
- Estado de alertas y notificaciones

### Configurar Notificaciones

#### Email (Ya configurado)

El email se configuró durante la instalación. Para cambiar el destinatario:

```bash
nano /etc/alertmanager/alertmanager.yml
# Edita la sección email_configs
systemctl reload alertmanager
```

#### Slack

1. Crea un Incoming Webhook en Slack
2. Durante la instalación, proporciona la URL del webhook
3. O edita manualmente:

```bash
nano /etc/alertmanager/alertmanager.yml
```

Añade:
```yaml
- name: 'slack'
  slack_configs:
    - api_url: 'https://hooks.slack.com/services/TU_WEBHOOK'
      channel: '#alerts'
```

#### Telegram

1. Crea un bot con @BotFather en Telegram
2. Obtén el token del bot
3. Obtén tu chat_id enviando un mensaje al bot y consultando:
   ```
   https://api.telegram.org/botTOKEN/getUpdates
   ```
4. Configurado durante instalación o edita:

```bash
nano /etc/alertmanager/alertmanager.yml
```

## Añadir Servidores al Monitoreo

### Método Automático (Recomendado)

```bash
./add_monitored_server.sh
```

El script:
1. Se conectará al servidor remoto vía SSH
2. Instalará Node Exporter automáticamente
3. Lo añadirá a Prometheus
4. Verificará la conectividad

### Método Manual

Si no tienes acceso SSH automático:

1. Ejecuta el script y selecciona "Manual"
2. Copia el script generado al servidor remoto
3. Ejecútalo como root en el servidor remoto:

```bash
bash install_node_exporter.sh
```

4. Añade manualmente a Prometheus:

```bash
nano /etc/prometheus/prometheus.yml
```

Añade:
```yaml
  - job_name: 'mi-servidor'
    static_configs:
      - targets: ['IP_SERVIDOR:9100']
        labels:
          instance: 'mi-servidor'
```

```bash
systemctl reload prometheus
```

## Gestión de Alertas

### Script Interactivo

```bash
./manage_alerts.sh
```

Funciones disponibles:
- Ver alertas configuradas
- Ver alertas activas
- Añadir alerta personalizada
- Añadir alertas predefinidas
- Probar expresiones PromQL
- Editar archivo de alertas
- Ver logs de Alertmanager
- Restaurar backups

### Alertas Predefinidas Disponibles

1. **Servicio específico caído** - Detecta cuando un servicio systemd no está corriendo
2. **Puerto TCP no responde** - Verifica conectividad de puertos
3. **Disco creciendo rápidamente** - Predice cuando se llenará el disco
4. **Alto uso de inodes** - Alerta cuando quedan pocos inodes
5. **Muchos procesos zombie** - Detecta procesos zombie acumulados
6. **Swap en uso** - Alerta cuando se usa swap
7. **Reloj desincronizado** - Detecta problemas de NTP
8. **Reinicio reciente** - Notifica cuando un servidor se reinicia

### Alertas por Defecto

El sistema viene con estas alertas preconfiguradas:

- **InstanceDown**: Servidor no responde (>1min)
- **HighCPUUsage**: CPU >80% (>5min)
- **HighMemoryUsage**: Memoria disponible <10% (>5min)
- **DiskSpaceLow**: Disco <10% libre (>5min)
- **DiskSpaceCritical**: Disco <5% libre (>2min)
- **HighSystemLoad**: Load average alto (>10min)

## Dashboards Recomendados

### Para Servidores Linux

**Node Exporter Full** (ID: 1860)
```
Dashboards → Import → 1860 → Load → Prometheus → Import
```

**Node Exporter for Prometheus** (ID: 11074)
- Vista más simple y limpia

### Para Prometheus

**Prometheus 2.0 Stats** (ID: 3662)
- Métricas internas de Prometheus

### Para Aplicaciones Específicas

- **MySQL**: 7362
- **PostgreSQL**: 9628
- **Nginx**: 11199
- **Apache**: 3894
- **Docker**: 893
- **Redis**: 11835

## Ejemplos de Uso

### Verificar Estado de un Servidor

1. Abre Prometheus: http://tu-servidor:9090
2. Ve a **Status → Targets**
3. Verifica que el servidor aparezca como "UP"

### Consultar Métricas Manualmente

En Prometheus (Graph):

```promql
# CPU usage por servidor
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memoria disponible en GB
node_memory_MemAvailable_bytes / 1024 / 1024 / 1024

# Espacio en disco libre (porcentaje)
(node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100

# Número de procesos corriendo
node_processes_running

# Tráfico de red (bytes/segundo)
rate(node_network_receive_bytes_total[5m])
```

### Crear Alerta Personalizada

Ejemplo: Alertar cuando un directorio específico tiene más de 10000 archivos

```bash
./manage_alerts.sh
# Opción 3: Añadir alerta personalizada

Nombre: TooManyFilesInDir
Expresión: node_filesystem_files{mountpoint="/var/log"} > 10000
Durante: 5m
Severidad: warning
Resumen: Demasiados archivos en /var/log
Descripción: El directorio /var/log tiene más de 10000 archivos
```

## Monitoreo de Servicios Específicos

### Postfix (Email Server)

Añadir a Prometheus:

```yaml
  - job_name: 'postfix'
    static_configs:
      - targets: ['mail-server:9154']
```

Requiere: `postfix_exporter`

### Nginx/Apache

```yaml
  - job_name: 'nginx'
    static_configs:
      - targets: ['web-server:9113']
```

Requiere: `nginx-prometheus-exporter`

### MySQL/MariaDB

```yaml
  - job_name: 'mysql'
    static_configs:
      - targets: ['db-server:9104']
```

Requiere: `mysqld_exporter`

## Retención de Datos

Por defecto, Prometheus guarda métricas por **30 días**.

Para cambiar:

```bash
nano /etc/systemd/system/prometheus.service
```

Cambia `--storage.tsdb.retention.time=30d` por el valor deseado.

```bash
systemctl daemon-reload
systemctl restart prometheus
```

## Seguridad

### Autenticación Básica para Prometheus

```bash
dnf install -y httpd-tools
htpasswd -c /etc/prometheus/.htpasswd admin

nano /etc/systemd/system/prometheus.service
```

Añade:
```
--web.config.file=/etc/prometheus/web-config.yml
```

Crea `/etc/prometheus/web-config.yml`:
```yaml
basic_auth_users:
  admin: $2y$10$hash_generado_por_htpasswd
```

### Firewall Restrictivo

Si solo quieres acceso desde IPs específicas:

```bash
# Eliminar reglas permisivas
nft delete rule inet filter input tcp dport 9090 accept
nft delete rule inet filter input tcp dport 3000 accept

# Añadir reglas específicas
nft add rule inet filter input ip saddr TU_IP tcp dport 9090 accept
nft add rule inet filter input ip saddr TU_IP tcp dport 3000 accept

# Guardar
nft list ruleset > /etc/sysconfig/nftables.conf
```

### SSL/TLS con Nginx

Para acceso seguro vía HTTPS, instala Nginx como reverse proxy:

```bash
dnf install -y nginx certbot

# Configurar Nginx para Grafana
cat > /etc/nginx/conf.d/grafana.conf << 'EOF'
server {
    listen 443 ssl;
    server_name monitor.ejemplo.com;

    ssl_certificate /etc/letsencrypt/live/ejemplo.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ejemplo.com/privkey.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
    }
}
EOF

systemctl enable nginx
systemctl start nginx
```

## Mantenimiento

### Backup de Configuraciones

```bash
#!/bin/bash
# Script de backup
BACKUP_DIR="/backup/monitoring/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

cp -r /etc/prometheus $BACKUP_DIR/
cp -r /etc/alertmanager $BACKUP_DIR/
cp -r /etc/grafana $BACKUP_DIR/
tar -czf $BACKUP_DIR.tar.gz $BACKUP_DIR
rm -rf $BACKUP_DIR
```

### Verificar Salud del Sistema

```bash
# Estado de servicios
systemctl status prometheus alertmanager grafana-server node_exporter

# Verificar targets en Prometheus
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'

# Alertas activas
curl http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | {name: .labels.alertname, state: .state}'
```

### Actualizar Componentes

```bash
# Prometheus
PROMETHEUS_VERSION="2.49.0"
systemctl stop prometheus
wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
tar -xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
cp prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/
systemctl start prometheus

# Grafana
dnf update grafana
```

## Solución de Problemas

### Prometheus no inicia

```bash
# Ver logs
journalctl -u prometheus -n 50

# Verificar configuración
/usr/local/bin/promtool check config /etc/prometheus/prometheus.yml

# Verificar permisos
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
```

### Target aparece como DOWN

```bash
# Verificar conectividad
curl http://IP_SERVER:9100/metrics

# Verificar firewall en servidor remoto
nft list ruleset | grep 9100

# Ver detalles en Prometheus
http://tu-servidor:9090/targets
```

### Alertas no se envían

```bash
# Verificar logs de Alertmanager
journalctl -u alertmanager -f

# Probar configuración
/usr/local/bin/amtool check-config /etc/alertmanager/alertmanager.yml

# Ver estado de alertas
curl http://localhost:9093/api/v1/alerts
```

### Grafana no carga dashboards

```bash
# Reiniciar Grafana
systemctl restart grafana-server

# Verificar logs
journalctl -u grafana-server -f

# Verificar datasource
curl -u admin:PASSWORD http://localhost:3000/api/datasources
```

## Estructura de Archivos

```
/etc/monitoring/
├── config.env                    # Configuración del instalador
├── credentials/
│   └── access_info.txt          # Credenciales y URLs
└── monitored_servers.txt        # Lista de servidores monitoreados

/etc/prometheus/
├── prometheus.yml               # Configuración principal
├── alerts.yml                   # Definición de alertas
├── consoles/                    # Consolas web
└── console_libraries/           # Librerías de consolas

/var/lib/prometheus/             # Base de datos de métricas

/etc/alertmanager/
└── alertmanager.yml            # Configuración de alertas

/var/lib/alertmanager/          # Estado de Alertmanager

/etc/grafana/
└── grafana.ini                 # Configuración de Grafana

/var/lib/grafana/               # Dashboards y datos
```

## Métricas Importantes

### CPU
- `node_cpu_seconds_total` - Tiempo de CPU por modo
- `node_load1`, `node_load5`, `node_load15` - Load average

### Memoria
- `node_memory_MemTotal_bytes` - Total de RAM
- `node_memory_MemAvailable_bytes` - RAM disponible
- `node_memory_SwapTotal_bytes` - Total de swap

### Disco
- `node_filesystem_size_bytes` - Tamaño total
- `node_filesystem_avail_bytes` - Espacio disponible
- `node_disk_read_bytes_total` - Bytes leídos
- `node_disk_written_bytes_total` - Bytes escritos

### Red
- `node_network_receive_bytes_total` - Bytes recibidos
- `node_network_transmit_bytes_total` - Bytes enviados

### Sistema
- `node_boot_time_seconds` - Tiempo de arranque
- `node_processes_running` - Procesos corriendo
- `up` - Estado del target (1=up, 0=down)

## Recursos Adicionales

- [Documentación Prometheus](https://prometheus.io/docs/)
- [Documentación Grafana](https://grafana.com/docs/)
- [PromQL Tutorial](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Exporters y Integraciones](https://prometheus.io/docs/instrumenting/exporters/)

## Licencia

Este proyecto es software libre.

## Soporte

Para reportar problemas o solicitar funcionalidades, contacta al administrador del sistema.
