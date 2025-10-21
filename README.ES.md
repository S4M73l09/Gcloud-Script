<h1 align="center">🚀 GCP Terraform VM Bootstrap</h1>

Español --> [EN](README.md)  
<p align="center">
   <b>Automatizacion de creacion de VM con Terraform + gcloud</b><br>
   <i>Sin llaves JSON, sin pasos manuales — Solo correr un Script.</i>
</p>

---

## 🌍Descripcion general  
Este repositorio le permite crear una máquina virtual GCP **completamente funcional** con:  
- **Backend Remoto de Terraform** para el storage de Google Cloud
- Eleccion de **VM**   
- **Service Account** para Terraform (Impersonacion)
- Creacion automatica de **Red, subnet, firewall y VM**

Todo a traves de un Script interactivo — No requiere pasos avanzados.

---

## 📁Estructura de repositorio  
```markdown
📦 Gcloud-Scripts  
├── setup_vm.sh  # Script de Automatizacion bash  
├── setup_vm.ps1 # Script de Automatizacion Powershell  
├── setup_vm.cmd # Wrapper para script .ps1   
├── README.md  
├── README.ES.md # Estas aqui  
└── terraform/ # Archivos de terraform generados  
    ├── Carpeta Powershell/bash
    └── Readme.md
```  

## ⚙️Requerimientos  
Antes de ejecutarlo:
- Instalacion en Linux o Windows (Añadido al PATH) [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)  
- Instalacion en Linux o Windows (Añadido al PAth) [Terraform](https://developer.hashicorp.com/terraform/downloads)  
- Un proyecto de Google Cloud disponible.  
- Proyecto con facturacion habilitada.
---

## 🚀Uso  
Clona y ejecuta el script:
```bash
git clone https://github.com/S4M73l09/Gcloud-Scripts.git
cd Gcloud-Scripts
chmod +x setup_vm.sh
./setup_vm.sh
```  
En Powershell:  
```powershell
git clone https://github.com/S4M73l09/Gcloud-Scripts.git
cd Gcloud-Scripts
./setup_vm.ps1 -test #Para ejecutar el tipo Test
./setup_vm.ps1 #Ejecucion normal
```  
CMD:  
Este repositorio esta preparado para lanzar el script en windows usando CMD directamente desde su propio Wrapper, solo tienes que ejecutarlo y el Wrapper se encargara de todo lo que haga el script .ps1.  

***setup_vm.cmd***
***setup_vm.cmd -test*** *Para ejecutar el modo test*

 ### 🔧 Flujo interno  

1. Comprueba dependencias **(gcloud, terraform).**
2. Gestiona el inicio de sesión en GCP y las credenciales ADC.
3. Solicita los detalles del despliegue **(proyecto, región, tipo de máquina, SO, etc.).**
4. Crea un bucket remoto para el estado de Terraform.
5. Crea y configura una Service Account.
6. Genera los archivos Terraform en la carpeta seleccionada.
7. Ejecuta terraform init, plan y apply.
8. Muestra la IP de la VM y los comandos de conexión.
9. Muestra la ruta completa de la carpeta Terraform generada.

🧠 Que creara:

- Una Service Account necesaria por seguridad para Terraform (terraform-sa).  
- Una bucket o vault para guardar dicho Backend (para su estado remoto).  
- Permisos minimos:  
    - SA --> *roles/storage.objectAdmin* en el bucket de Estado.
    - Tu usuario --> *roles/iam.serviceAccountTokenCreator* sobre la SA (Impersonacion)
- VPC dedicada (sin auto-subnets), subred, firewall y VM con IP pública.  
- OS Login activado en Linux para SSH auditado por IAM.

🖥️ Elegir Sistema Operativo

Durante la ejecución, te permitira elegir la maquina.

# 🚀 setup_vm.ps1 — Automatizador de despliegues Terraform en GCP

Este script PowerShell automatiza el ciclo completo de despliegue de una máquina virtual en **Google Cloud Platform (GCP)** usando **Terraform**, con control total del entorno y soporte para ejecución **interactiva o CI/CD**.

---

## 🧩 Características principales

- **Generación automática** de archivos Terraform (`backend.tf`, `providers.tf`, `network.tf`, `vm.tf`, `outputs.tf`).
- **Soporte dual**: 🐧 **Linux** y 🪟 **Windows Server**.
- **Selección interactiva** si faltan parámetros:
  - Sistema operativo (Ubuntu, Debian, Windows Server 2019/2022).
  - Tipo de máquina (lista o personalizado).
  - Tamaño de disco mínimo (10 GB Linux / 64 GB Windows).
- **Separación por sistema operativo**:
  - Linux → `./Linux-terraform/`
  - Windows → `./Windows-terraform/`
- **Prefijos y rutas diferenciadas**:
  - Archivos `.tf`: `L...` o `W...`
  - Backend remoto: `env/linux` o `env/windows`
- **Modo test limpio (`-Test`)**:
  - Crea entorno temporal en `%TEMP%`
  - Valida APIs, bucket y Service Account sin aplicar infraestructura
  - Elimina la carpeta temporal al finalizar
- **Compatible con PowerShell 5.1 y 7+**
- **Listo para CI/CD** (GitHub Actions, Azure DevOps, etc.)

---

## ⚙️ Ejemplos de uso

### 🧪 1. Modo test (solo validaciones)
```powershell
pwsh ./setup_vm.ps1 -ProjectId "mi-proyecto" -Region "europe-west1" -Zone "europe-west1-b" -Test
```  
### 🧭 2. Modo interactivo (sin parámetros)  
```powershell  
pwsh ./setup_vm.ps1  
```  
👉 El script mostrará menús:

Elige sistema operativo:  
  [1] Ubuntu 22.04 LTS  
  [2] Debian 12  
  [3] Windows Server 2022  
  [4] Windows Server 2019  
Selección (1-4):

Elige tipo de máquina (o 'C' para personalizado):  
  [1] e2-micro  
  [2] e2-small  
  [3] e2-medium  
  ...  

### ⚡ 3. Ejecución automatizada (CI/CD)  
```powershell
pwsh ./setup_vm.ps1 `
  -ProjectId "mi-proyecto" `
  -Region "europe-southwest1" `
  -Zone "europe-southwest1-a" `
  -OsType linux `
  -MachineType e2-medium `
  -OsDiskGb 20 `
  -AutoApprove
```  
### Wrapper **setup_vm.cmd**

En este repositorio esta creado un wrapper .cmd que se encarga de llamar al script principal si usamos CMD en vez de Powershell, mas rapido y sin necesidad de tocar consola.

## 🗂️ Estructura de carpetas (nombres de entorno)

El script ahora crea **carpetas separadas dentro de `./terraform/`** dependiendo del sistema operativo elegido y del nombre personalizado de entorno que proporciones.

- 🪟 **Windows** → `./terraform/PW-windows-<sufijo>`
- 🐧 **Linux** → `./terraform/Linux-<sufijo>`

### Ejemplo

Si ejecutas:
```powershell
pwsh ./setup_vm.ps1 -ProjectId "mi-proyecto" -Region "europe-west1" -Zone "europe-west1-b"
```  
El script mostrará:  
```java
Introduce el nombre del entorno (solo el sufijo, p. ej. "prod", "web", "lab"):
```  
Luego, si eliges:  

 * Sistema operativo → Windows Server 2022  

 * Sufijo → prod  

Creará:  
```markdown
terraform/
└── PW-windows-prod/
    ├── backend.tf
    ├── providers.tf
    ├── network.tf
    ├── vm.tf
    └── outputs.tf
```  
Si eliges Linux (Ubuntu o Debian) con el sufijo “monitoring”:  
```markdown
terraform/
└── Linux-monitoring/
    ├── backend.tf
    ├── providers.tf
    ├── network.tf
    ├── vm.tf
    └── outputs.tf
```  
Cada carpeta de entorno es totalmente independiente, permitiendo desplegar múltiples configuraciones (por ejemplo, Linux y Windows) sin conflictos de archivos.  

💡 También puedes pasar el sufijo directamente como parámetro:  
```powershell
pwsh ./setup_vm.ps1 -ProjectId "mi-proyecto" -Region "europe-west1" -Zone "europe-west1-b" -OsType linux -EnvNameSuffix "backend"
```  
Esto saltará la pregunta interactiva y creará:  
```swift
terraform/Linux-backend/
```  
# ⚙️ setup_vm.sh — Automatización de Infraestructura GCP con Bash + Terraform

🧭 Descripción general

Este script Bash automatiza la creación de máquinas virtuales en Google Cloud Platform (GCP) utilizando Terraform.
Reproduce todas las capacidades de la versión PowerShell original, pero de forma más compacta, portable y 100% interactiva.

Permite configurar proyectos, regiones, redes, discos, etiquetas y sistemas operativos (Windows o Linux) mediante un menú paso a paso, o bien, en modo no interactivo mediante argumentos *(--flags).*

### 🚀 Características principales
```markdown
|  Nº | Característica           | Descripción                                   | Estado |
| :-: | :----------------------- | :-------------------------------------------- | :----: |
|  1  | **Menú interactivo**     | Pide datos paso a paso si no hay argumentos.  |    ✅   |
|  2  | **Multi-SO**             | Ubuntu, Debian, Windows 2022 y 2019.          |    ✅   |
|  3  | **Carpetas Terraform**   | Crea subcarpetas en `terraform/` según el SO. |    ✅   |
|  4  | **Nombre personalizado** | Permite nombrar o usar timestamp automático.  |    ✅   |
|  5  | **Modo `--no-prompt`**   | Ejecución sin preguntas, ideal CI/CD.         |    ✅   |
|  6  | **Modo `--test`**        | Simula todo en `/tmp` sin tocar GCP.          |    ✅   |
|  7  | **Login automático GCP** | Ejecuta `gcloud auth login` si es necesario.  |    ✅   |
|  8  | **SA + bucket remoto**   | Crea Service Account y bucket `tf-state`.     |    ✅   |
|  9  | **Multi-plataforma**     | Funciona en Linux, WSL y macOS.               |    ✅   |
|  10 | **Resumen final**        | Muestra IP y carpeta generada al finalizar.   |    ✅   |

```  

### 🧠 Flujo interactivo (sin argumentos)

Si ejecutas:
```bash
./setup_vm.sh
```  
El script inicia en modo asistente:

1. Comprueba gcloud y terraform.

2. Te pide la información base:
```less
Proyecto GCP [mi-proyecto]:
Región [europe-southwest1]:
Zona [europe-southwest1-a]:
Prefijo [lab]:
Tipo de máquina (vCPU/RAM) [e2-medium]:
Disco OS (GB) [50]:
VPC [lab-vpc]:
Subred [lab-subnet]:
```  

3. Muestra el menú de selección de sistema operativo:
```yaml
Elige SO:
  1) Ubuntu 22.04 LTS
  2) Debian 12
  3) Windows Server 2022
  4) Windows Server 2019
[por defecto: 2] >
```  
4. Pregunta el nombre de la carpeta Terraform:
```less
🗂️  Nombre de la subcarpeta (ej: miinfra, demo, clienteX) [2025-10-20_16-05]:
```  
5. Muestra un resumen de todos los parámetros elegidos.

6. Ejecuta Terraform (init, plan, apply) y muestra la IP de la VM creada.

7. Indica la ruta exacta donde se guardaron los archivos.

### 🗂️ Estructura generada

Según tus elecciones, el script crea dentro de tu carpeta **terraform/:**
```css
terraform/
├── bash-windows-clienteA/
│   ├── backend.hcl
│   ├── main.tf
│   ├── variables.tf
│   └── terraform.tfvars
└── bash-linux-demo/
    ├── backend.hcl
    ├── main.tf
    ├── variables.tf
    └── terraform.tfvars
```  
El nombre de la carpeta cambia automáticamente según el SO y el nombre elegido.  

## 🧩 Ejemplos de uso  

### 💬 Modo interactivo (por defecto)  
```bash
./setup_vm.sh
```
El script irá preguntando los datos paso a paso y creará la VM al final.

## ⚙️ Modo no interactivo (flags)
```bash
./setup_vm.sh \
  --no-prompt \
  --split-os \
  --project-id mi-proyecto \
  --region europe-southwest1 \
  --zone europe-southwest1-a \
  --name-prefix demo \
  --machine-type e2-standard-4 \
  --disk-gb 128 \
  --disk-type pd-ssd \
  --network demo-vpc \
  --subnetwork demo-subnet \
  --labels env=dev,owner=yo \
  --run-id prod-release
```  
📁 Resultado:
```arduino
terraform/bash-linux-prod-release/
```
## 🧪 Modo prueba (sin tocar GCP)
```bash
./setup_vm.sh --test --split-os --no-prompt \
  --project-id test-proj --region europe-southwest1 --zone europe-southwest1-a
```
✅ Ejecuta todo en **/tmp/.../work/terraform/**  
✅ Usa mocks de gcloud y terraform  
✅ Guarda logs en **/tmp/.../logs/**  

## 🧾 Archivos generados por Terraform
```markdown
| Archivo            | Descripción                                         |
| :----------------- | :-------------------------------------------------- |
| `backend.hcl`      | Configuración del backend remoto (bucket GCS + SA). |
| `main.tf`          | Recursos principales: red, subred, firewall y VM.   |
| `variables.tf`     | Variables definidas (project, region, zone, etc.).  |
| `terraform.tfvars` | Valores reales obtenidos del script.                |
```
## ⚡ Argumentos disponibles
```markdown
| Flag                        | Descripción                                             |
| :-------------------------- | :------------------------------------------------------ |
| `--project-id`              | ID del proyecto GCP                                     |
| `--region`, `--zone`        | Región y zona del despliegue                            |
| `--name-prefix`             | Prefijo base de los recursos                            |
| `--machine-type`            | Tipo de máquina (`e2-medium`, `e2-standard-4`, etc.)    |
| `--disk-gb`, `--disk-type`  | Tamaño y tipo de disco (`pd-ssd`, `pd-balanced`, etc.)  |
| `--network`, `--subnetwork` | Nombres personalizados de red y subred                  |
| `--labels`                  | Etiquetas (`key=value,key2=value2`)                     |
| `--split-os`                | Guarda Linux y Windows en carpetas separadas            |
| `--no-prompt`               | No hace preguntas, usa valores por defecto              |
| `--run-id`                  | Sufijo manual para la carpeta Terraform                 |
| `--test`                    | Simula toda la ejecución sin crear infraestructura real |
```  

## 🔌 Conexión a la VM

#### 🔑 Linux (Ubuntu / Debian)
El script habilita **OS Login**, así que puedes conectarte con:  
```bash  
gcloud compute ssh <prefijo>-vm --zone <tu-zona>
```
O directamente desde la ip publica:  
```bash
ssh <tu_usuario>@<IP_PUBLICA>
```
⚙️ **Requiere que tu usuario tenga el rol *roles/compute.osLogin* o similar.**  

#### Windows Server (2022/2019)  
Una vez creada la VM, genera credenciales seguras:  
```bash
gcloud compute reset-windows-password <prefijo>-vm --zone <tu-zona> --user <admin>
```  
Conectate por RPD:  
```bash
<IP_PUBLICA>:3389
```
### 💾 Ejemplo de resultado final
```yaml
[i] Carpeta destino: terraform/bash-windows-clienteA
[✓] VM IP: 34.152.77.19
💾 Archivos guardados en: terraform/bash-windows-clienteA/
```

## ✅Modo prueba --test  
El script contiene tambien un modo de test donde puedes probar su funcionamiento y que dichos archivos se guarden en ramas temporales.  
El script en modo de *--test* muestra justamente la direccion temporal donde se muestra dichos archivos.  

#### bash
```bash  
rm -r /tmp/tmp.*  
```  
#### powershell  
```powershell  
Remove-Item "$env:TEMP\\iac-*" -Recurse -Force
```  
Esto se encarga de borrar las carpetas temporales creadas en general.  
Si quieres limpiarla una por una, usa el mismo comando pero añadiendo la ruta de la carpeta temporal que quieres borrar.  

Igualmente el script esta programado para que despues de finalizar, este borre dichas carpetas de manera automatica.  

## 🧹 Limpieza  
Para destruir los recursos de Terraform:  
```bash
cd terraform
terraform destroy
```  
Para destruir o eliminar el Bucket y el Service Account:
```bash
gcloud storage rm -r gs://<bucket-del-estado>
gcloud iam service-accounts delete terraform-sa@<project>.iam.gserviceaccount.com
```

## 🔐 Seguridad (mejores prácticas)  
* Sin claves JSON: identidad efímera por impersonación y ADC local.  
* State con versionado + lifecycle (purgado de versiones antiguas).  
* OS Login en Linux → acceso SSH controlado por IAM (auditable).  
* Firewall mínimo: solo abre el puerto que necesitas (22 o 3389).  
* En producción, sustituye cualquier roles/editor temporal por roles granulares (Compute, Network, etc.).  

## 🧩 Personalización rápida  
* Cambia el tipo de máquina por defecto (e2-medium) en el script o en terraform.tfvars.  
* Añade más familias de imágenes (ej. Ubuntu 24.04) ampliando el menú del script.  
* Ajusta CIDR permitidos (ssh_cidr_allow, rdp_cidr_allow) en terraform.tfvars.  

## ❓ FAQ  
¿Necesito GitHub Actions / OIDC?  
No. Este repo está pensado para uso local. Más adelante puedes añadir CI/CD si lo deseas.

¿Puedo usar otro sistema operativo?  
Sí, añade nuevas opciones en el menú del script y su image correspondiente.

¿Dónde está el estado de Terraform?  
En el bucket GCS que crea el script (terraform/backend.hcl define bucket y prefix).

<p align="center"> Hecho ❤️ por <a href="https://github.com/S4M73l09">@S4M73l09</a> </p>