# Plan de trabajo en Azure

Guía paso a paso para ejecutar el laboratorio en Azure con el código de este repositorio. Cada paso indica la opción **Portal** (como dice el enunciado) y la opción **CLI** (scripts de `azure/`, para Azure Cloud Shell).

## 0. Antes de empezar

| Qué | Cómo |
|---|---|
| Subir los cambios a GitHub | `git add -A && git commit -m "..." && git push`. Las VMs clonan el repo y cloud-init descarga `scripts/setup-vm.sh` desde la rama `main`. |
| Herramientas locales | `cd tools && npm install` (instala newman). Las pruebas **siempre** se corren desde su PC, nunca desde la VM. |
| Llave SSH | Ya existe `~/.ssh/id_ed25519.pub`. En el portal pegue su contenido; en Cloud Shell use `--generate-ssh-keys` (por defecto) o `SSH_KEY=~/.ssh/id.pub`. |
| Cloud Shell (opcional) | Portal → icono `>_` → Bash. Suba la carpeta `azure/` o clone el repo allí. |

### Diferencias con el enunciado (2019) que debe tener en cuenta

- **Ubuntu 18.04 ya no tiene soporte.** Use **Ubuntu Server 24.04 LTS**. Las versiones actuales de Node no corren en 18.04.
- **Los SKU Basic de Load Balancer e IP pública se retiraron (30-sep-2025).** Use **Standard** en todo (las imágenes del lab ya muestran Standard).
- **Standard es "cerrado por defecto"**: sin la regla del NSG para el puerto 3000, el balanceador no entrega tráfico aunque el health probe esté bien.
- **Región**: Azure for Students restringe regiones por política. Si aparece `RequestDisallowedByPolicy`, cambie de región. Para la parte 2 la región debe tener **zonas de disponibilidad** (por ejemplo East US 2 o Central US).
- **Cuota**: B1ls usa 1 vCPU y B2ms 2. Cuatro VMs B1ls más una B2ms caben en la cuota típica, pero **borre la parte 1 antes de la parte 2**.
- Los comandos del README `npm FibinacciApp.js`, `source /home/vm1/.bashrc` y nvm `v0.34.0` están desactualizados; `scripts/setup-vm.sh` los reemplaza.

---

## Parte 1 – Escalabilidad vertical

### 1.1 Crear la VM (pasos 1–2)

**Portal:** Virtual machines → Create.
- Resource group: `SCALABILITY_LAB` (nuevo)
- Name: `VERTICAL-SCALABILITY`
- Image: Ubuntu Server 24.04 LTS
- Size: `Standard_B1ls`
- Username: `scalability_lab`
- Auth: SSH public key

**CLI:** `./azure/part1-vertical.sh create`

📸 **Para la pregunta 1:** abra el resource group y tome captura de **todos** los recursos que se crearon junto con la VM: VM, disco del SO, NIC, IP pública, NSG y VNet.

### 1.2 Abrir el puerto 3000 (paso 6)

**Portal:** VM → Networking → *Add inbound port rule*: Destination port `3000`, TCP, Allow, prioridad 1010, nombre `Port_3000`.
**CLI:** el comando `create` ya lo hace.

### 1.3 Instalar la app (pasos 3–5)

```bash
ssh scalability_lab@<IP_VM>
curl -fsSL https://raw.githubusercontent.com/juanesgl/ARSW_LOAD-BALANCING_AZURE/main/scripts/setup-vm.sh | bash
```

El script instala nvm y Node LTS, clona el repo, ejecuta `npm install`, arranca la app con `forever` y deja una entrada `@reboot` para que se levante sola tras el resize.

Para la pregunta 3, demuestre primero el problema: ejecute `node FibonacciApp.js` a mano, cierre el ssh y observe que deja de responder. Después use `forever`.

Verifique en el navegador `http://<IP_VM>:3000/fibonacci/6`; la respuesta debe ser `The answer is 8`.

### 1.4 Medir tiempos con B1ls (paso 7)

```bash
cd tools
node measure-times.js <IP_VM>:3000 B1ls
```

Genera `reports/times-B1ls.md` con la tabla de los 10 valores. Si el profesor exige la consola del navegador, abra `http://<IP_VM>:3000/` y en la consola (F12) ejecute:

```js
for (const n of [1000000,1010000,1020000,1030000,1040000,1050000,1060000,1070000,1080000,1090000]) {
  const t = performance.now(); await fetch(`/fibonacci/${n}`);
  console.log(n, Math.round(performance.now() - t), 'ms');
}
```

### 1.5 CPU (paso 8)

VM → Monitoring → **Metrics** → métrica `Percentage CPU`, agregación **Max**, últimos 30 min. Espere unos 5 min a que aparezcan los datos. 📸 Captura para la pregunta 5.

### 1.6 Carga concurrente con B1ls (paso 9)

```bash
node load-test.js part1 <IP_VM> 2 10 B1ls-2x
```

Equivale a los dos `newman run ... -n 10 &` del enunciado. Revise el resumen en `reports/B1ls-2x/summary.md`: tiempos, éxitos, fallos y errores (por ejemplo `ECONNRESET` o `ETIMEDOUT`). 📸 Captura de la salida y de la CPU para la pregunta 6.

Si prefiere los comandos originales:

```bash
cd FibonacciApp/postman/part1   # antes ponga la IP en VM1 del environment
newman run ARSW_LOAD-BALANCING_AZURE.postman_collection.json -e "[ARSW_LOAD-BALANCING_AZURE].postman_environment.json" -n 10 &
newman run ARSW_LOAD-BALANCING_AZURE.postman_collection.json -e "[ARSW_LOAD-BALANCING_AZURE].postman_environment.json" -n 10
```

### 1.7 Escalar a B2ms y repetir (pasos 10–11)

**Portal:** VM → Size → `B2ms` → Resize. **CLI:** `./azure/part1-vertical.sh scale-up`.

⚠️ El resize **reinicia la VM** (pregunta 9); la IP pública estática se conserva. Compruebe que la app volvió a levantar con `curl http://<IP_VM>:3000/` y, si no responde, ejecute `forever start` por ssh.

Luego repita:

```bash
node measure-times.js <IP_VM>:3000 B2ms
node load-test.js part1 <IP_VM> 2 10 B2ms-2x
node load-test.js part1 <IP_VM> 4 10 B2ms-4x     # pregunta 11
```

📸 CPU de nuevo.

> **Qué esperar (para las preguntas 8, 10 y 12):** Node.js ejecuta la función en **un solo hilo**. B2ms tiene 2 vCPU, pero la app solo usa una, así que el tiempo por petición casi no mejora y las peticiones concurrentes siguen haciendo fila. La CPU total baja (aproximadamente un núcleo de dos, alrededor del 50 %) porque hay más capacidad ociosa, no porque la app sea más rápida. B1ls además es *burstable*: con créditos agotados queda limitado a una fracción del núcleo.

### 1.8 Volver a B1ls y limpiar (paso 13)

`./azure/part1-vertical.sh scale-down`. Cuando tenga todas las evidencias, borre el grupo con `./azure/cleanup.sh` (o desde el portal, *Delete resource group*) antes de la parte 2.

---

## Parte 2 – Escalabilidad horizontal

Use los mismos nombres de las imágenes de `images/part2`.

### 2.1 Infraestructura de red

**CLI (todo junto):** `./azure/part2-horizontal.sh infra`

**Portal, en este orden:**

| # | Recurso | Configuración |
|---|---|---|
| 1 | Load balancer | `SCALABILITY_LAB_LOAD_BALANCER`, Public, **SKU Standard**, IP nueva `SCALABILITY_LAB_LOAD_BALANCER_IP`, zone-redundant |
| 2 | Backend pool | `SCALABILITY_LAB_BACKEND_POOL`, asociado a la VNet (vacío por ahora) |
| 3 | Health probe | `SCALABILITY_LAB_HEALTH_PROBE`, TCP, puerto `3000`, intervalo 5 s |
| 4 | LB rule | `SCALABILITY_LAB_LOAD_BALANCING_RULE`, IPv4, TCP, frontend **80** → backend **3000**, probe anterior, session persistence **None**, floating IP desactivada |
| 5 | Virtual network | `SCALABILITY_LAB_VIRTUAL_NETWORK`, `10.1.0.0/16`; subnet `SCALABILITY_LAB_SUBNET` `10.1.0.0/24` |

En el portal actual el asistente del LB pide crear el backend pool, el probe y la regla en sus pestañas. Si no existe la VNet todavía, cree primero la VNet (paso 5) y luego el LB.

### 2.2 Nodos VM1, VM2 y VM3

**CLI:** `./azure/part2-horizontal.sh vms`. Crea las tres VMs en las zonas 1, 2 y 3, cada una con IP Standard zone-redundant, el NSG compartido `LOAD_BALANCER_NSG` (22 y 3000) y dentro del backend pool. **cloud-init instala y arranca la app sola** (unos 3–5 min después de crearse). Con `MANUAL_SETUP=1` la omite para hacerlo a mano.

**Portal (por cada VM *i*):**
- *Basics*: name `VMi`, Availability zone `i`, Ubuntu 24.04, `B1ls`, usuario `vmi`, SSH key.
- *Networking*: VNet y subnet del paso 2.1, IP pública nueva (Standard, zone-redundant).
- *NIC NSG*: **Advanced** → crear `LOAD_BALANCER_NSG` con la inbound rule `Port_3000` (prioridad 1010) solo en VM1; en VM2 y VM3 seleccione el existente.
- *Load balancing*: Azure load balancer → `SCALABILITY_LAB_LOAD_BALANCER` → pool `SCALABILITY_LAB_BACKEND_POOL`.
- Después: `ssh vmi@<IP_VMi>` y ejecute el mismo `curl ... setup-vm.sh | bash` del paso 1.3.

Verifique con `./azure/part2-horizontal.sh status` y en el portal: LB → *Backend pools*, donde las 3 VMs deben estar en estado sano.

### 2.3 Probar el balanceador (punto 1)

```bash
IP_LB=$(./azure/part2-horizontal.sh ip)     # o LB → Frontend IP configuration
curl -i http://$IP_LB/
curl -i http://$IP_LB/fibonacci/1
```

La cabecera **`X-Served-By`** indica qué VM respondió; repita varias veces y verá cómo se reparte la carga.

### 2.4 Pruebas de carga e informe comparativo (punto 2)

```bash
cd tools
node measure-times.js <IP_LB> LB-3vms
node load-test.js part2 <IP_LB> 2 10 LB-3vms-2x
```

Compare con `reports/B1ls-2x` y `reports/B2ms-2x` en tiempos de respuesta, tasa de éxito y costo. En la columna **Nodo** de `times-LB-3vms.md` se ve la distribución.

**Costos de referencia** (East US, pago por uso; confirme en la [calculadora de precios](https://azure.microsoft.com/es-es/pricing/calculator/)):

| Recurso | Precio aproximado |
|---|---|
| B1ls | ≈ USD 0.0052/h (≈ 3.8/mes) |
| B2ms | ≈ USD 0.083/h (≈ 60/mes) |
| Standard LB | ≈ USD 0.025/h por las primeras 5 reglas (≈ 18/mes) + 0.005/GB procesado |
| IP pública Standard | ≈ USD 0.005/h (≈ 3.6/mes) cada una |

### 2.5 Cuarta VM y 4 ejecuciones paralelas (punto 3)

```bash
./azure/part2-horizontal.sh vm 4             # o por portal: VM4, zona 1
node load-test.js part2 <IP_LB> 4 10 LB-4vms-4x
```

📸 Métricas `Percentage CPU` de **las 4 VMs en una misma gráfica**: Monitor → Metrics → scope con las 4 VMs → *Split by* recurso.

> **Qué esperar:** la regla sin persistencia de sesión reparte las conexiones por hash de 5 tuplas, así que cada VM atiende una fracción de las peticiones con su propio hilo de Node. Hay menos cola por nodo, por eso hay menos timeouts y resets y la tasa de éxito sube. Si un nodo cae, el health probe lo saca del pool.

### 2.6 Diagrama de despliegue y cierre

- Diagrama: Internet → IP pública del LB (80) → Load Balancer Standard (regla 80→3000, probe TCP:3000) → backend pool → VM1/VM2/VM3/VM4 (zonas 1/2/3/1, subnet 10.1.0.0/24, NSG con 22 y 3000) → nodo Node.js + `forever` + FibonacciApp:3000.
- **Al terminar:** `./azure/cleanup.sh`, para que no se consuma el crédito. Verifique en el portal que el resource group desapareció.

---

## Checklist de evidencias

- [ ] Captura de los recursos creados con la VM (P1·Q1)
- [ ] Tablas de tiempos B1ls y B2ms (`reports/times-*.md`) (P1·Q4)
- [ ] CPU B1ls y B2ms (P1·Q5)
- [ ] Resumen newman B1ls 2x, B2ms 2x y B2ms 4x (P1·Q6, Q11)
- [ ] Tabla de tiempos y resumen newman con el LB y 3 VMs (P2·punto 2)
- [ ] Resumen newman con 4 VMs y 4 ejecuciones + CPU de las 4 VMs (P2·punto 3)
- [ ] Diagrama de despliegue
- [ ] Resource group eliminado
