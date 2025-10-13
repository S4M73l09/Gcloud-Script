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
📦 Gcloud-Scripts  
├── setup_vm.sh # Script de Automatizacion  
├── README.md  
├── README.ES.md # Estas aqui
└── terraform/ # Archivos de terraform generados  
├── backend.hcl  
├── main.tf  
├── variables.tf  
├── outputs.tf  
└── terraform.tfvar  
└── Readme.md

## ⚙️Requerimientos  
Antes de ejecutarlo:
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)  
- [Terraform](https://developer.hashicorp.com/terraform/downloads)
- Un proyecto de Google Cloud disponible.  

---

## 🚀Uso  
Clona y ejecuta el script:
```bash
git clone https://github.com/S4M73l09/Gcloud-Scripts.git
cd Gcloud-Scripts
chmod +x setup_vm.sh
./setup_vm.sh
```
El Script comenzara a:

1: Correo para login en gcloud.  
2: Project ID, región y zona.  
3: Prefijo de nombres y tamaño/tipo de VM.  
4: Sistema Operativo (menú interactivo).  
5: Confirmación para apply.  

🧠 Que creara:

- Una Service Account necesaria por seguridad para Terraform (terraform-sa).  
- Una bucket o vault para guardar dicho Backend (para su estado remoto).  
- Permisos minimos:  
    - SA --> *roles/storage.objectAdmin* en el bucket de Estado.
    - Tu usuario --> *roles/iam.serviceAccountTokenCreator* sobre la SA (Impersonacion)
- VPC dedicada (sin auto-subnets), subred, firewall y VM con IP pública.  
- OS Login activado en Linux para SSH auditado por IAM.

🖥️ Elegir Sistema Operativo

Durante la ejecución, verás un menú como:

* Ubuntu 22.04 LTS  
  *projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts*

* Debian 12  
  *projects/debian-cloud/global/images/family/debian-12*

* Windows Server 2022
  *projects/windows-cloud/global/images/family/windows-2022*

* Windows Server 2019
  *projects/windows-cloud/global/images/family/windows-2019*

El script ajusta automáticamente:

Firewall:

Linux → abre SSH (22/tcp) y etiqueta ssh.

Windows → abre RDP (3389/tcp) y etiqueta rdp.

Disco: si eliges Windows y pones menos de 64 GB, sube a 64 GB (recomendado por comodidad).

Metadatos: en Linux activa enable-oslogin=TRUE.

## 🔌 Conexión a la VM

### 🔑 Linux (Ubuntu / Debian)
El script habilita **OS Login**, así que puedes conectarte con:  
```bash  
gcloud compute ssh <prefijo>-vm --zone <tu-zona>
```
O directamente desde la ip publica:  
```bash
ssh <tu_usuario>@<IP_PUBLICA>
```
⚙️ **Requiere que tu usuario tenga el rol *roles/compute.osLogin* o similar.**  

### Windows Server (2022/2019)  
Una vez creada la VM, genera credenciales seguras:  
```bash
gcloud compute reset-windows-password <prefijo>-vm --zone <tu-zona> --user <admin>
```  
Conectate por RPD:  
```bash
<IP_PUBLICA>:3389
```
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

🔐 Seguridad (mejores prácticas)  
* Sin claves JSON: identidad efímera por impersonación y ADC local.  
* State con versionado + lifecycle (purgado de versiones antiguas).  
* OS Login en Linux → acceso SSH controlado por IAM (auditable).  
* Firewall mínimo: solo abre el puerto que necesitas (22 o 3389).  
* En producción, sustituye cualquier roles/editor temporal por roles granulares (Compute, Network, etc.).  

🧩 Personalización rápida  
* Cambia el tipo de máquina por defecto (e2-medium) en el script o en terraform.tfvars.  
* Añade más familias de imágenes (ej. Ubuntu 24.04) ampliando el menú del script.  
* Ajusta CIDR permitidos (ssh_cidr_allow, rdp_cidr_allow) en terraform.tfvars.  

❓ FAQ  
¿Necesito GitHub Actions / OIDC?  
No. Este repo está pensado para uso local. Más adelante puedes añadir CI/CD si lo deseas.

¿Puedo usar otro sistema operativo?  
Sí, añade nuevas opciones en el menú del script y su image correspondiente.

¿Dónde está el estado de Terraform?  
En el bucket GCS que crea el script (terraform/backend.hcl define bucket y prefix).

<p align="center"> Hecho ❤️ por <a href="https://github.com/S4M73l09">@S4M73l09</a> </p>