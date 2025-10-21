#!/usr/bin/env bash
set -euo pipefail

# ==== Utils ====
die(){ echo "ERROR: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Falta $1"; }
ask(){ local v="$1" q="$2" d="${3:-}"; [[ -n "${!v:-}" ]] || { read -rp "$q [${d}]: " _; printf -v "$v" "${_:-$d}"; }; }
yesno(){ read -rp "$1 [y/N]: " _; [[ "$_" =~ ^[Yy]$ ]]; }

# ==== Colors ====
if [[ -t 1 ]]; then
  BOLD="\033[1m"; DIM="\033[2m"; UL="\033[4m"; RESET="\033[0m"
  C1="\033[38;5;117m"; C2="\033[38;5;149m"; C3="\033[38;5;216m"; C4="\033[38;5;203m"; BLUE="\033[34m"
else
  BOLD=""; DIM=""; UL=""; RESET=""; C1=""; C2=""; C3=""; C4=""; BLUE=""
fi

# ==== Flags ====
TEST=0 NO_PROMPT=false SPLIT_OS=false
PROJECT_ID="" REGION="" ZONE="" NAME_PREFIX="" MACHINE_TYPE="" DISK_GB="" DISK_TYPE="pd-balanced"
NETWORK_NAME="" SUBNET_NAME="" LABELS="" RUN_ID=""
while [[ $# -gt 0 ]]; do case "$1" in
  --test) TEST=1; shift ;;
  --no-prompt) NO_PROMPT=true; shift ;;
  --split-os) SPLIT_OS=true; shift ;;
  --project-id) PROJECT_ID="$2"; shift 2 ;;
  --region) REGION="$2"; shift 2 ;;
  --zone) ZONE="$2"; shift 2 ;;
  --name-prefix) NAME_PREFIX="$2"; shift 2 ;;
  --machine-type) MACHINE_TYPE="$2"; shift 2 ;;     # vCPU/RAM (ej: e2-medium)
  --disk-gb) DISK_GB="$2"; shift 2 ;;               # almacenamiento (GB)
  --disk-type) DISK_TYPE="$2"; shift 2 ;;           # pd-balanced|pd-ssd|pd-standard
  --network) NETWORK_NAME="$2"; shift 2 ;;
  --subnetwork) SUBNET_NAME="$2"; shift 2 ;;
  --labels) LABELS="$2"; shift 2 ;;                 # k=v,k2=v2
  --run-id) RUN_ID="$2"; shift 2 ;;                 # sufijo manual de carpeta
  -h|--help) cat <<'H'; exit 0
setup_vm.sh [--test] [--no-prompt] [--split-os]
  --project-id ID --region R --zone Z --name-prefix N
  --machine-type TYPE --disk-gb N --disk-type TYPE
  --network VPC --subnetwork SUB --labels k=v,k2=v2
  [--run-id TEXTO]   # si se indica, sustituye al nombre interactivo/timestamp
H
  ;;
  *) die "Flag desconocido: $1";;
esac; done

# ==== Test mode (mocks + trabajo en /tmp para NO tocar repo) ====
if (( TEST )); then
  TMP="$(mktemp -d)"; export LOGDIR="$TMP/logs"; mkdir -p "$LOGDIR"
  PATH="$TMP:$PATH"
  printf '#!/usr/bin/env bash\necho gcloud "$@" >>"%s"\n' "$LOGDIR/gcloud.log" >"$TMP/gcloud"
  printf '#!/usr/bin/env bash\necho terraform "$@" >>"%s"\n' "$LOGDIR/terraform.log" >"$TMP/terraform"
  chmod +x "$TMP/gcloud" "$TMP/terraform"
  echo "[TEST] activo. Logs en $LOGDIR"
  # Trabajar en un directorio temporal:
  WORKDIR="$TMP/work"; mkdir -p "$WORKDIR"; pushd "$WORKDIR" >/dev/null
fi

# ==== Requisitos (solo real) ====
if (( ! TEST )); then need gcloud; need terraform; fi

# ==== Login + ADC ====
ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"
if [[ -z "$ACCOUNT" ]]; then
  (( NO_PROMPT )) || echo "[i] Autenticando en gcloud…"
  gcloud auth login ${NO_PROMPT:+--no-launch-browser} >/dev/null
fi
[[ -f "$HOME/.config/gcloud/application_default_credentials.json" ]] || \
  gcloud auth application-default login ${NO_PROMPT:+--no-launch-browser} >/dev/null

# ==== Entradas (pregunta solo si faltan y no --no-prompt) ====
defproj="$(gcloud config get-value project 2>/dev/null || true)"
if [[ "$NO_PROMPT" != true ]]; then
  ask PROJECT_ID "Proyecto GCP" "${PROJECT_ID:-$defproj}"
  ask REGION "Región" "${REGION:-europe-southwest1}"
  ask ZONE "Zona" "${ZONE:-${REGION:-europe-southwest1}-a}"
  ask NAME_PREFIX "Prefijo" "${NAME_PREFIX:-lab}"
  ask MACHINE_TYPE "Tipo de máquina (vCPU/RAM)" "${MACHINE_TYPE:-e2-medium}"
  ask DISK_GB "Disco OS (GB)" "${DISK_GB:-50}"
  ask NETWORK_NAME "VPC" "${NETWORK_NAME:-${NAME_PREFIX:-lab}-vpc}"
  ask SUBNET_NAME "Subred" "${SUBNET_NAME:-${NAME_PREFIX:-lab}-subnet}"
else
  PROJECT_ID="${PROJECT_ID:-$defproj}"; REGION="${REGION:-europe-southwest1}"
  ZONE="${ZONE:-${REGION}-a}"; NAME_PREFIX="${NAME_PREFIX:-lab}"
  MACHINE_TYPE="${MACHINE_TYPE:-e2-medium}"; DISK_GB="${DISK_GB:-50}"
  NETWORK_NAME="${NETWORK_NAME:-${NAME_PREFIX}-vpc}"
  SUBNET_NAME="${SUBNET_NAME:-${NAME_PREFIX}-subnet}"
fi
[[ -n "$PROJECT_ID" ]] || die "PROJECT_ID requerido"
gcloud config set project "$PROJECT_ID" >/dev/null

# ==== SO/Imagen (menú con colores + Win2019) ====
choose_os(){
  local preset="${1:-}"
  [[ -n "$preset" ]] && { echo "$preset"; return; }
  if [[ "$NO_PROMPT" == true ]]; then echo "Debian 12"; return; }
  echo -e "${BOLD}Elige SO:${RESET}"
  echo -e "  ${C1}1) Ubuntu 22.04 LTS${RESET}"
  echo -e "  ${C2}2) Debian 12${RESET}"
  echo -e "  ${C3}3) Windows Server 2022${RESET}"
  echo -e "  ${C4}4) Windows Server 2019${RESET}"
  read -rp "$(echo -e "${DIM}[por defecto: 2]${RESET} > ")" n
  case "${n:-2}" in
    1) echo "Ubuntu 22.04 LTS" ;;
    2) echo "Debian 12" ;;
    3) echo "Windows Server 2022" ;;
    4) echo "Windows Server 2019" ;;
    *) echo "Debian 12" ;;
  esac
}
OS_CHOICE="$(choose_os "${OS_CHOICE:-}")"

case "$OS_CHOICE" in
  Ubuntu*)  OS_TYPE="linux";   IMAGE="projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts" ;;
  Debian*)  OS_TYPE="linux";   IMAGE="projects/debian-cloud/global/images/family/debian-12" ;;
  "Windows Server 2022") OS_TYPE="windows"; IMAGE="projects/windows-cloud/global/images/family/windows-2022" ;;
  "Windows Server 2019") OS_TYPE="windows"; IMAGE="projects/windows-cloud/global/images/family/windows-2019" ;;
  *) die "SO inválido" ;;
esac
(( DISK_GB < 64 && OS_TYPE == "windows" )) && DISK_GB=64   # mínimo recomendado

# ==== Bucket/SA/Backend (conciso) ====
RAND="$(head -c4 </dev/urandom | od -An -tx1 | tr -d ' \n')"
BUCKET="tf-state-${PROJECT_ID}-${RAND}"

echo "[i] Habilitando APIs…"
gcloud --quiet services enable compute.googleapis.com iam.googleapis.com cloudresourcemanager.googleapis.com storage.googleapis.com
echo "[i] Creando bucket gs://${BUCKET}…"
gcloud storage buckets create "gs://${BUCKET}" --location="$REGION" --uniform-bucket-level-access
gcloud storage buckets update "gs://${BUCKET}" --versioning
printf '{"rule":[{"action":{"type":"Delete"},"condition":{"isLive":false,"age":60}}]}\n' >/tmp/lc.json
gcloud storage buckets update "gs://${BUCKET}" --lifecycle-file=/tmp/lc.json

SA="terraform-sa@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud iam service-accounts describe "$SA" >/dev/null 2>&1 || gcloud iam service-accounts create terraform-sa --display-name="Terraform SA"
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" --member="serviceAccount:${SA}" --role="roles/storage.objectAdmin" >/dev/null
USER_EMAIL="$(gcloud config get-value account)"
gcloud iam service-accounts add-iam-policy-binding "$SA" --member="user:${USER_EMAIL}" --role="roles/iam.serviceAccountTokenCreator" >/dev/null

# ==== Carpeta Terraform dentro del repo (nombre interactivo / --run-id / timestamp) ====
BASE_TF_DIR="terraform"       # carpeta raíz de Terraform en tu repo
TS="$(date +%Y-%m-%d_%H-%M)"  # timestamp de respaldo

if [[ -n "$RUN_ID" ]]; then
  SUF="$RUN_ID"
elif [[ "$NO_PROMPT" == true ]]; then
  SUF="$TS"
else
  read -rp "🗂️  Nombre de la subcarpeta (ej: miinfra, demo, clienteX) [${TS}]: " INPUT_NAME
  SUF="${INPUT_NAME:-$TS}"
fi

if [[ "$SPLIT_OS" == true ]]; then
  if [[ "$OS_TYPE" == "windows" ]]; then
    TF_DIR="${BASE_TF_DIR}/bash-windows-${SUF}"
  else
    TF_DIR="${BASE_TF_DIR}/bash-linux-${SUF}"
  fi
else
  TF_DIR="${BASE_TF_DIR}/bash-terraform-${SUF}"
fi

echo -e "[i] Carpeta destino: ${BLUE}${UL}${TF_DIR}${RESET}"

# ==== Labels HCL (1-liner) ====
labels_hcl="{}"; [[ -n "$LABELS" ]] && labels_hcl="{ $(echo "$LABELS" | tr ',' '\n' | awk -F= '{printf "%s = \"%s\" ",$1,$2}') }"

# ==== Archivos Terraform (4 ficheros, minimal) ====
mkdir -p "$TF_DIR"
cat >"$TF_DIR/backend.hcl" <<EOF
bucket="${BUCKET}"
prefix="global/state"
impersonate_service_account="${SA}"
EOF

cat >"$TF_DIR/main.tf"<<'EOF'
terraform {
  required_providers { google = { source="hashicorp/google", version="~> 5.43" } }
  backend "gcs" {}
}
provider "google" {
  project = var.project_id
  region  = var.region
  impersonate_service_account = var.impersonate_sa
}
resource "google_compute_network" "vpc" { name=var.vpc_name auto_create_subnetworks=false }
resource "google_compute_subnetwork" "sub" { name=var.subnet_name ip_cidr_range=var.subnet_cidr region=var.region network=google_compute_network.vpc.id }
resource "google_compute_firewall" "ssh" { count=var.os_type=="linux"?1:0 name="${var.name_prefix}-allow-ssh" network=google_compute_network.vpc.name allow{protocol="tcp" ports=["22"]} source_ranges=var.ssh_cidr target_tags=["ssh"] }
resource "google_compute_firewall" "rdp" { count=var.os_type=="windows"?1:0 name="${var.name_prefix}-allow-rdp" network=google_compute_network.vpc.name allow{protocol="tcp" ports=["3389"]} source_ranges=var.rdp_cidr target_tags=["rdp"] }
resource "google_compute_instance" "vm" {
  name="${var.name_prefix}-vm"; machine_type=var.machine_type; zone=var.zone
  boot_disk { initialize_params { image=var.image size=var.disk_gb type=var.disk_type } }
  network_interface { subnetwork=google_compute_subnetwork.sub.id  access_config {} }
  metadata = var.os_type=="linux" ? { enable-oslogin="TRUE" } : {}
  tags   = var.os_type=="linux" ? ["ssh"] : ["rdp"]
  labels = var.labels
}
output "vm_ip" { value = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip }
EOF

cat >"$TF_DIR/variables.tf"<<'EOF'
variable "project_id"{type=string} variable "region"{type=string} variable "zone"{type=string}
variable "impersonate_sa"{type=string} variable "name_prefix"{type=string}
variable "vpc_name"{type=string} variable "subnet_name"{type=string} variable "subnet_cidr"{type=string,default="10.10.0.0/24"}
variable "ssh_cidr"{type=list(string),default=["0.0.0.0/0"]} variable "rdp_cidr"{type=list(string),default=["0.0.0.0/0"]}
variable "os_type"{type=string} variable "image"{type=string} variable "machine_type"{type=string,default="e2-medium"}
variable "disk_gb"{type=number,default=50} variable "disk_type"{type=string,default="pd-balanced"} variable "labels"{type=map(string),default={}}
EOF

cat >"$TF_DIR/terraform.tfvars"<<EOF
project_id="${PROJECT_ID}" region="${REGION}" zone="${ZONE}" impersonate_sa="${SA}"
name_prefix="${NAME_PREFIX}" vpc_name="${NETWORK_NAME}" subnet_name="${SUBNET_NAME}"
os_type="${OS_TYPE}" image="${IMAGE}" machine_type="${MACHINE_TYPE}" disk_gb=${DISK_GB} disk_type="${DISK_TYPE}" labels=${labels_hcl}
EOF

# ==== Terraform run ====
pushd "$TF_DIR" >/dev/null
terraform init -reconfigure -backend-config=backend.hcl
terraform plan
APPLY=true
if [[ "$NO_PROMPT" != true ]]; then
  if yesno "¿Aplicar ahora?"; then APPLY=true; else APPLY=false; fi
fi
if $APPLY; then
  terraform apply -auto-approve
  VM_IP="$(terraform output -raw vm_ip || true)"
  echo -e "[${BOLD}✓${RESET}] VM IP: $VM_IP"
  if [[ "$OS_TYPE" == "windows" ]]; then
    echo "Credenciales: gcloud compute reset-windows-password ${NAME_PREFIX}-vm --zone ${ZONE} --user admin"
  else
    echo "SSH: gcloud compute ssh ${NAME_PREFIX}-vm --zone ${ZONE}"
  fi
else
  echo "Plan listo. No se aplicó."
fi
popd >/dev/null

# ==== Mensaje final de carpeta destino ====
echo -e "💾 Archivos guardados en: ${BLUE}${UL}${TF_DIR}${RESET}"

# ==== Salida del modo test (volver del workdir temporal) ====
if (( TEST )); then
  popd >/dev/null || true
  echo "[TEST] Archivos temporales en: $WORKDIR"
  echo "[TEST] Logs: $LOGDIR/gcloud.log | $LOGDIR/terraform.log"
fi
