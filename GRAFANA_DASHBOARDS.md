# Guía de Dashboards para Grafana

Colección de dashboards recomendados para diferentes servicios y sistemas.

## Cómo Importar Dashboards

1. Accede a Grafana: http://tu-servidor:3000
2. Ve al menú lateral → **Dashboards**
3. Click en **New** → **Import**
4. Introduce el **ID del dashboard** (número)
5. Click en **Load**
6. Selecciona el datasource **Prometheus**
7. Click en **Import**

---

## Dashboards para Servidores Linux

### Node Exporter Full (ID: 1860) ⭐ RECOMENDADO

**Descripción**: Dashboard más completo para monitoreo de servidores Linux

**Métricas incluidas**:
- CPU: Uso general, uso por núcleo, contextos, interrupciones
- Memoria: RAM, Swap, Cache, Buffer
- Disco: Uso de espacio, I/O, latencia
- Red: Tráfico, errores, conexiones
- Sistema: Load average, uptime, procesos
- Filesystem: Inodes, montajes

**Ideal para**: Monitoreo general de servidores

---

### Node Exporter for Prometheus Dashboard (ID: 11074)

**Descripción**: Vista más limpia y moderna

**Métricas incluidas**:
- Estadísticas básicas del sistema
- Gráficos más grandes y legibles
- Panel de estado general

**Ideal para**: Dashboards en pantallas grandes o displays

---

### Node Exporter Server Metrics (ID: 405)

**Descripción**: Dashboard simple y directo

**Métricas incluidas**:
- CPU, RAM, Disco
- Red básica

**Ideal para**: Vista rápida de estado de múltiples servidores

---

## Dashboards para Prometheus

### Prometheus 2.0 Stats (ID: 3662) ⭐

**Descripción**: Estadísticas del propio Prometheus

**Métricas incluidas**:
- Queries ejecutadas
- Targets monitoreados
- Samples ingeridos
- Uso de recursos de Prometheus
- Alertas activas

**Ideal para**: Monitorear la salud de Prometheus

---

### Prometheus Blackbox Exporter (ID: 7587)

**Descripción**: Monitoreo de endpoints HTTP/TCP/ICMP

**Métricas incluidas**:
- Disponibilidad de servicios
- Tiempo de respuesta
- Certificados SSL

**Ideal para**: Monitoreo de sitios web y servicios

---

## Dashboards para Bases de Datos

### MySQL Overview (ID: 7362)

**Descripción**: Monitoreo completo de MySQL/MariaDB

**Métricas incluidas**:
- Queries por segundo
- Conexiones activas
- InnoDB métricas
- Slow queries
- Tamaño de tablas

**Ideal para**: Servidores de bases de datos MySQL

**Requiere**: mysqld_exporter instalado

---

### PostgreSQL Database (ID: 9628)

**Descripción**: Dashboard para PostgreSQL

**Métricas incluidas**:
- Transacciones
- Conexiones
- Locks
- Cache hit ratio
- Replicación

**Ideal para**: Servidores PostgreSQL

**Requiere**: postgres_exporter

---

### Redis Dashboard (ID: 11835)

**Descripción**: Monitoreo de Redis

**Métricas incluidas**:
- Memoria usada
- Operaciones por segundo
- Hit rate
- Clientes conectados

**Ideal para**: Servidores Redis

**Requiere**: redis_exporter

---

## Dashboards para Servidores Web

### NGINX (ID: 11199)

**Descripción**: Estadísticas de Nginx

**Métricas incluidas**:
- Requests por segundo
- Conexiones activas
- Tiempo de respuesta
- Códigos de estado HTTP

**Ideal para**: Servidores web Nginx

**Requiere**: nginx-prometheus-exporter

---

### Apache (ID: 3894)

**Descripción**: Monitoreo de Apache

**Métricas incluidas**:
- Workers activos
- Requests
- Bytes transferidos
- CPU de Apache

**Ideal para**: Servidores Apache

**Requiere**: apache_exporter

---

## Dashboards para Contenedores

### Docker Container & Host Metrics (ID: 893) ⭐

**Descripción**: Monitoreo de Docker y contenedores

**Métricas incluidas**:
- Contenedores corriendo
- CPU por contenedor
- Memoria por contenedor
- Red y disco
- Host metrics

**Ideal para**: Servidores con Docker

**Requiere**: cAdvisor

---

### Kubernetes Cluster Monitoring (ID: 7249)

**Descripción**: Dashboard para clusters K8s

**Métricas incluidas**:
- Pods, deployments, services
- Uso de recursos por namespace
- Estado de nodos

**Ideal para**: Clusters Kubernetes

---

## Dashboards para Servicios de Email

### Postfix (ID: 15033)

**Descripción**: Monitoreo de servidor Postfix

**Métricas incluidas**:
- Emails enviados/recibidos
- Cola de correos
- Bounces y rejects
- Tamaño de mensajes

**Ideal para**: Servidores de email Postfix

**Requiere**: postfix_exporter

---

## Dashboards para Alertmanager

### Alertmanager (ID: 9578)

**Descripción**: Estado de alertas

**Métricas incluidas**:
- Alertas activas
- Alertas por severidad
- Silenciados
- Notificaciones enviadas

**Ideal para**: Monitorear el sistema de alertas

---

## Dashboards para Almacenamiento

### MinIO Dashboard (ID: 13502)

**Descripción**: Monitoreo de MinIO

**Métricas incluidas**:
- Buckets
- Objetos almacenados
- Tráfico de red
- Operaciones

**Ideal para**: Servidores de almacenamiento MinIO

**Requiere**: MinIO metrics endpoint

---

## Dashboards Personalizados

### Crear Tu Propio Dashboard

1. En Grafana, ve a **Dashboards** → **New** → **New Dashboard**
2. Click en **Add visualization**
3. Selecciona **Prometheus** como datasource
4. Introduce una query PromQL

**Ejemplos de queries útiles**:

```promql
# CPU usage
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memoria disponible en %
(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# Disco usado en %
100 - ((node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100)

# Red - Bytes recibidos por segundo
rate(node_network_receive_bytes_total[5m])

# Procesos corriendo
node_processes_running

# Uptime en días
(time() - node_boot_time_seconds) / 86400
```

---

## Variables en Dashboards

Para crear dashboards dinámicos que funcionen con múltiples servidores:

1. En el dashboard, click en **Settings** (⚙️)
2. Ve a **Variables**
3. **Add variable**

**Ejemplo - Variable para seleccionar servidor**:
- Name: `instance`
- Type: `Query`
- Data source: `Prometheus`
- Query: `label_values(node_uname_info, instance)`

Luego en las queries usa: `{instance="$instance"}`

---

## Organización de Dashboards

### Crear Carpetas

1. **Dashboards** → **New folder**
2. Nombra las carpetas por categoría:
   - Servidores
   - Bases de Datos
   - Aplicaciones
   - Infraestructura

### Tags

Añade tags a cada dashboard para facilitar la búsqueda:
- `linux`
- `database`
- `web-server`
- `monitoring`

---

## Dashboards Recomendados por Tipo de Servidor

### Servidor de Email (Postfix + Dovecot)
- Node Exporter Full (1860)
- Postfix (15033)

### Servidor Web (Nginx)
- Node Exporter Full (1860)
- NGINX (11199)

### Servidor de Base de Datos (MySQL)
- Node Exporter Full (1860)
- MySQL Overview (7362)

### Servidor de Aplicaciones (Docker)
- Node Exporter Full (1860)
- Docker Container & Host Metrics (893)

### Servidor de Monitoreo (Prometheus)
- Node Exporter Full (1860)
- Prometheus 2.0 Stats (3662)
- Alertmanager (9578)

---

## Exportar y Compartir Dashboards

### Exportar Dashboard

1. Abre el dashboard
2. Click en **Share** (icono de compartir)
3. Tab **Export**
4. **Save to file** → Descarga JSON

### Importar Dashboard Exportado

1. **Dashboards** → **Import**
2. **Upload JSON file**
3. Selecciona el archivo
4. Click **Import**

---

## Consejos de Rendimiento

### Optimizar Queries

- Usa `rate()` en lugar de `irate()` para queries largas
- Limita el rango temporal: `[5m]` en lugar de `[1h]`
- Usa `instance` labels para filtrar

### Reducir Carga

- No uses intervalos muy pequeños (< 15s)
- Limita el número de panels por dashboard (< 20)
- Usa variables para reutilizar queries

### Refrescar Dashboards

- Para dashboards en tiempo real: 10s - 30s
- Para dashboards generales: 1m - 5m
- Para dashboards históricos: 5m - 15m

---

## Alertas desde Dashboards

Puedes crear alertas directamente desde panels de Grafana:

1. Edita un panel
2. Tab **Alert**
3. **Create alert rule from this panel**
4. Configura condiciones
5. **Save**

---

## Recursos Adicionales

- **Grafana Dashboard Gallery**: https://grafana.com/grafana/dashboards/
- **Buscar por datasource**: Filtra por "Prometheus"
- **Comunidad**: https://community.grafana.com/

---

## Dashboards Populares por Categoría

### Top 10 Dashboards Más Usados

1. **Node Exporter Full** (1860) - 1M+ descargas
2. **Docker Container & Host Metrics** (893)
3. **Kubernetes Cluster** (7249)
4. **Prometheus Stats** (3662)
5. **MySQL Overview** (7362)
6. **NGINX** (11199)
7. **PostgreSQL** (9628)
8. **Redis** (11835)
9. **Blackbox Exporter** (7587)
10. **Apache** (3894)

---

¡Explora la galería de Grafana para encontrar más dashboards específicos para tus necesidades!
