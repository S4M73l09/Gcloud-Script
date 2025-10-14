#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Flags de utilidad (fmt/lint/hooks/help/test)
# ============================================================
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: falta '$1' en PATH"; exit 1; }; }

ensure_tools() {
  local missing=0
  for t in shellcheck shfmt; do
    if ! command -v "$t" >/dev/null 2>&1; then
      echo "[!] No encontrado: $t"; missing=1
    fi
  done
  if [[ $missing -eq 1 ]]; then
    cat <<'EOS'

Para instalar rápidamente:

  # Ubuntu / Debian
  sudo apt update && sudo apt install -y shellcheck
  # shfmt (Linux amd64):
  curl -sSL https://github.com/mvdan/sh/releases/latest/download/shfmt_linux_amd64 \
    | sudo tee /usr/local/bin/shfmt >/dev/null
  sudo chmod +x /usr/local/bin/shfmt

  # macOS (Homebrew)
  brew install shellcheck shfmt

  # Arch
  sudo pacman -S shellcheck shfmt

EOS
    exit 1
  fi
}

fmt_sh() { ensure_tools; echo "[i] Formateo (shfmt)…"; shfmt -w -s -i 2 .; echo "[✓] Formato OK"; }
lint_sh() {
  ensure_tools
  echo "[i] Lint (shellcheck)…"
  mapfile -t files < <(git ls-files '*.sh' 2>/dev/null || find . -type f -name '*.sh')
  [[ ${#files[@]} -gt 0 ]] && shellcheck -e SC1091 "${files[@]}"
  echo "[✓] Lint OK"
}
install_git_hook() {
  if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[!] No estás en un repo git."; exit 1
  fi
  mkdir -p .git/hooks
  cat > .git/hooks/pre-commit <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
echo "[pre-commit] shfmt…"
if command -v shfmt >/dev/null 2>&1; then
  shfmt -w -s -i 2 .
  git add -A
else
  echo "[pre-commit] aviso: shfmt no instalado"
fi
echo "[pre-commit] shellcheck…"
if command -v shellcheck >/dev/null 2>&1; then
  files=$(git diff --cached --name-only --diff-filter=ACMR | grep -E '\.sh$' || true)
  [[ -n "$files" ]] && shellcheck -e SC1091 $files
else
  echo "[pre-commit] aviso: shellcheck no instalado"
fi
echo "[pre-commit] OK"
HOOK
  chmod +x .git/hooks/pre-commit
  echo "[✓] Hook pre-commit instalado"
}
usage() {
  cat <<'USAGE'
Uso:
  ./setup_vm.sh                 # modo real (interactivo)
  ./setup_vm.sh --test          # modo pruebas (mocks; no toca GCP; usa /tmp)
  ./setup_vm.sh --fmt           # formatea scripts .sh
  ./setup_vm.sh --lint          # lint de scripts .sh
  ./setup_vm.sh --install-hooks # instala hook pre-commit (fmt+lint)
  ./setup_vm.sh -h|--help

USAGE
}

# Dispatcher de flags rápidos (antes de todo lo demás)
case "${1:-}" in
  --fmt) fmt_sh; exit 0 ;;
  --lint) lint_sh; exit 0 ;;
  --install-hooks) install_git_hook; exit 0 ;;
  -h|--help) usage; exit 0 ;;
  --test) ;; # se gestiona más abajo
  *) ;;
esac

# ============================================================
# TEST MODE ( --test )  —— NO toca GCP real, usa mocks y /tmp
# ============================================================
TEST_MODE=0
if [[ "${1:-}" == "--test" ]]; then
  TEST_MODE=1
  shift || true
fi

if [[ "$TEST_MODE" -eq 1 ]]; then
  TEST_TMPDIR="$(mktemp -d)"
  FAKEBIN="$TEST_TMPDIR/fakebin"
  LOGDIR="$TEST_TMPDIR/logs"
  WORKDIR="$TEST_TMPDIR/work"
  mkdir -p "$FAKEBIN" "$LOGDIR" "$WORKDIR"
  export FAKEBIN LOGDIR

  # Defaults automáticos para respuestas
  export TEST_EMAIL="${TEST_EMAIL:-tester@example.com}"
  export TEST_PROJECT="${TEST_PROJECT:-test-project-123}"
  export TEST_REGION="${TEST_REGION:-europe-southwest1}"
  export TEST_ZONE="${TEST_ZONE:-europe-southwest1-a}"
  export TEST_NAME="${TEST_NAME:-lab}"
  export TEST_MACHINE="${TEST_MACHINE:-e2-medium}"
  export TEST_DISK="${TEST_DISK:-20}"
  export TEST_OSCHOICE="${TEST_OSCHOICE:-Debian 12}"

  # Inyecta mocks en PATH
  export PATH="$FAKEBIN:$PATH"

  # Mock gcloud
  cat > "$FAKEBIN/gcloud" <<'BASH'
#!/usr/bin/env bash
echo "gcloud $*" >> "$LOGDIR/gcloud.log"
case "$1 $2" in
  "auth list") echo "${TEST_EMAIL:-}"; exit 0 ;;
  "auth login") exit 0 ;;
  "auth application-default") exit 0 ;;
  "config get-value")
    [[ "$3" == "project" ]] && { echo "${TEST_PROJECT:-test-project-123}"; exit 0; }
    [[ "$3" == "account" ]] && { echo "${TEST_EMAIL:-tester@example.com}"; exit 0; }
    exit 0 ;;
  "config set") exit 0 ;;
  "services enable"*) exit 0 ;;
  "storage buckets describe"*) exit 0 ;;
  "storage buckets create"*) exit 0 ;;
  "storage buckets update"*) exit 0 ;;
  "storage buckets add-iam-policy-binding"*) exit 0 ;;
  "iam service-accounts describe"*) exit 1 ;; # fuerza creación
  "iam service-accounts create"*) exit 0 ;;
  "iam service-accounts add-iam-policy-binding"*) exit 0 ;;
  "compute reset-windows-password"*) echo "username: admin password: FakeP@ssw0rd" >> "$LOGDIR/gcloud.log"; exit 0 ;;
  *) exit 0 ;;
esac
BASH
  chmod +x "$FAKEBIN/gcloud"

  # Mock terraform
  cat > "$FAKEBIN/terraform" <<'BASH'
#!/usr/bin/env bash
echo "terraform $*" >> "$LOGDIR/terraform.log"
case "$1" in
  init) echo "Terraform has been successfully initialized!"; exit 0 ;;
  plan) echo "No changes. Infrastructure is up-to-date."; exit 0 ;;
  apply)
    mkdir -p .terraform
    echo '{"version":4}' > terraform.tfstate
    echo "Apply complete! (simulado)"; exit 0 ;;
  output)
    [[ "${2:-}" == "-raw" ]] && { echo "34.34.34.34"; exit 0; }
    echo "vm_ip = 34.34.34.34"; exit 0 ;;
  *) exit 0 ;;
esac
BASH
  chmod +x "$FAKEBIN/terraform"

  # Sobrescribe UI (auto-responde)
  prompt_box() {
    local title="$1" text="$2" default="${3:-}"
    case "$text" in
      *correo*|*Google*) echo "${TEST_EMAIL}";;
      *ID*proyecto*|*Project*ID*) echo "${TEST_PROJECT}";;
      *Región*|*Region*) echo "${TEST_REGION}";;
      *Zona*|*Zone*) echo "${TEST_ZONE}";;
      *Prefijo*|*Nombre*) echo "${TEST_NAME}";;
      *Máquina*|*Machine*) echo "${TEST_MACHINE}";;
      *Disco*|*GB*) echo "${TEST_DISK}";;
      *) echo "${default}";;
    esac
  }
  confirm_box() { return 0; }   # siempre "Sí" en test
  menu_box() { echo "${TEST_OSCHOICE}"; }

  echo "[TEST] Modo prueba activo"
  echo "[TEST] Carpeta temporal de trabajo: $WORKDIR"
  echo "[TEST] Logs: $LOGDIR/gcloud.log | $LOGDIR/terraform.log"

  # **Muy importante**: trabajar en un directorio temporal para NO tocar el repo
  pushd "$WORKDIR" >/dev/null
else
  # =========================
  # UI helpers (modo real)
  # =========================
  prompt_box() {
    local title="$1" text="$2" default="${3:-}"
    if command -v whiptail >/dev/null 2>&1; then
      whiptail --title "$title" --inputbox "$text" 10 70 "$default" 3>&1 1>&2 2>&3 || { echo "Cancelado."; exit 1; }
    elif command -v dialog >/dev/null 2>&1; then
      dialog --stdout --inputbox "$text" 10 70 "$default" || { echo "Cancelado."; exit 1; }
    elif command -v zenity >/dev/null 2>&1; then
      zenity --entry --title="$title" --text="$text" --entry-text="$default" || { echo "Cancelado."; exit 1; }
    else
      read -rp "$text " REPLY; echo "$REPLY"
    fi
  }
  confirm_box() {
    local msg="$1"
    if command -v whiptail >/dev/null 2>&1; then
      whiptail --title "Confirmación" --yesno "$msg" 8 70
    elif command -v dialog >/dev/null 2>&1; then
      dialog --yesno "$msg" 8 70
    elif command -v zenity >/dev/null 2>&1; then
      zenity --question --text="$msg"
    else
      read -rp "$msg [y/N]: " ans; [[ "$ans" =~ ^[Yy]$ ]]
    fi
  }
  menu_box() {
    local title="$1"; shift
    local text="$1"; shift
    local opts=("$@")
    if command -v whiptail >/dev/null 2>&1; then
      local items=(); for o in "${opts[@]}"; do items+=("$o" ""); done
      whiptail --title "$title" --menu "$text" 15 70 8 "${items[@]}" 3>&1 1>&2 2>&3
    elif command -v dialog >/dev/null 2>&1; then
      local items=(); for o in "${opts[@]}"; do items+=("$o" ""); done
      dialog --stdout --menu "$text" 15 70 8 "${items[@]}"
    elif command -v zenity >/dev/null 2>&1; then
      zenity --list --title="$title" --text="$text" --column="Opción" "${opts[@]}"
    else
      echo "Elige una opción:"; select opt in "${opts[@]}"; do echo "$opt"; break; done
    fi
  }

  # Asegura trabajar en la carpeta del script (para generar ./terraform en el repo)
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$SCRIPT_DIR"
fi

# ============================================================
# Requisitos (modo real)
# ============================================================
if [[ "$TEST_MODE" -eq 0 ]]; then
  command -v gcloud >/dev/null || { echo "ERROR: instala Google Cloud SDK (gcloud)"; exit 1; }
  command -v terraform >/dev/null || { echo "ERROR: instala Terraform"; exit 1; }
fi

require_gcloud_login() {
  local EMAIL
  EMAIL=$(prompt_box "gcloud login" "Introduce tu correo de Google:")
  [[ -z "$EMAIL" ]] && { echo "Correo vacío."; exit 1; }

  if gcloud auth list --format="value(account)" 2>/dev/null | grep -Fxq "$EMAIL"; then
    echo "[i] Ya autenticado como $EMAIL. Seleccionando cuenta..."
    gcloud config set account "$EMAIL" >/dev/null
  else
    echo "[i] Iniciando sesión para $EMAIL ..."
    if command -v xdg-open >/dev/null 2>&1 || command -v wslview >/dev/null 2>&1; then
      gcloud auth login "$EMAIL"
    else
      gcloud auth login "$EMAIL" --no-launch-browser
    fi
  fi

  # ADC (para impersonación de SA con Terraform)
  if [[ ! -f "${HOME}/.config/gcloud/application_default_credentials.json" ]]; then
    echo "[i] Configurando Application Default Credentials (ADC) para Terraform..."
    if command -v xdg-open >/dev/null 2>&1 || command -v wslview >/dev/null 2>&1; then
      gcloud auth application-default login
    else
      gcloud auth application-default login --no-launch-browser
    fi
  fi
  echo "[✓] gcloud y ADC listos."
}

# ============================================================
# Flujo principal
# ============================================================
require_gcloud_login

PROJECT_ID=$(prompt_box "Proyecto" "ID del proyecto GCP (p.ej. mi-proyecto-123):" "$(gcloud config get-value project 2>/dev/null || true)")
[[ -z "${PROJECT_ID}" ]] && { echo "PROJECT_ID requerido"; exit 1; }
gcloud config set project "$PROJECT_ID" >/dev/null

REGION=$(prompt_box "Región" "Región (p.ej. europe-southwest1):" "europe-southwest1")
ZONE=$(prompt_box "Zona" "Zona (p.ej. europe-southwest1-a):" "${REGION}-a")
NAME_PREFIX=$(prompt_box "Nombre" "Prefijo para recursos (vpc/vm/etc):" "lab")
MACHINE_TYPE=$(prompt_box "Máquina" "Tipo de máquina (e2-medium recomendado):" "e2-medium")
DISK_GB=$(prompt_box "Disco" "Tamaño disco OS en GB:" "50")

OS_CHOICE=$(menu_box "Sistema Operativo" "Elige la imagen de la VM:" \
"Ubuntu 22.04 LTS" "Debian 12" "Windows Server 2022" "Windows Server 2019")
[[ -z "${OS_CHOICE}" ]] && { echo "Debes elegir un SO."; exit 1; }

OS_TYPE="linux"
IMAGE="projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
case "$OS_CHOICE" in
  "Ubuntu 22.04 LTS") OS_TYPE="linux"; IMAGE="projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts" ;;
  "Debian 12")        OS_TYPE="linux"; IMAGE="projects/debian-cloud/global/images/family/debian-12" ;;
  "Windows Server 2022") OS_TYPE="windows"; IMAGE="projects/windows-cloud/global/images/family/windows-2022" ;;
  "Windows Server 2019") OS_TYPE="windows"; IMAGE="projects/windows-cloud/global/images/family/windows-2019" ;;
  *) echo "Selección no válida"; exit 1 ;;
esac
if [[ "$OS_TYPE" == "windows" && "$DISK_GB" -lt 64 ]]; then DISK_GB=64; fi

# Nombre de bucket único
RAND=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')
BUCKET_NAME="tf-state-${PROJECT_ID}-${RAND}"

echo
echo "Resumen:"
echo "  Proyecto:   $PROJECT_ID"
echo "  Región:     $REGION"
echo "  Zona:       $ZONE"
echo "  Bucket:     $BUCKET_NAME"
echo "  Prefijo:    $NAME_PREFIX"
echo "  SO:         $OS_CHOICE  (tipo: $OS_TYPE)"
echo "  Imagen:     $IMAGE"
echo "  VM:         $MACHINE_TYPE, ${DISK_GB}GB"
echo

echo "[i] Habilitando APIs..."
gcloud --quiet services enable \
  compute.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  storage.googleapis.com

echo "[i] Creando bucket de estado: gs://${BUCKET_NAME}"
gcloud storage buckets create "gs://${BUCKET_NAME}" --location="${REGION}" --uniform-bucket-level-access
gcloud storage buckets update "gs://${BUCKET_NAME}" --versioning
cat > /tmp/lifecycle.json <<'JSON'
{"rule":[{"action":{"type":"Delete"},"condition":{"isLive":false,"age":60}}]}
JSON
gcloud storage buckets update "gs://${BUCKET_NAME}" --lifecycle-file=/tmp/lifecycle.json

SA_NAME="terraform-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
if ! gcloud iam service-accounts describe "${SA_EMAIL}" >/dev/null 2>&1; then
  echo "[i] Creando Service Account ${SA_EMAIL}"
  gcloud iam service-accounts create "$SA_NAME" --display-name="Terraform Service Account"
else
  echo "[i] SA ya existe: ${SA_EMAIL}"
fi

echo "[i] Concediendo a la SA acceso al bucket de estado..."
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectAdmin" >/dev/null

USER_EMAIL="$(gcloud config get-value account)"
echo "[i] Permitimos que ${USER_EMAIL} impersonate la SA..."
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --member="user:${USER_EMAIL}" \
  --role="roles/iam.serviceAccountTokenCreator" >/dev/null

# Generación de ficheros Terraform en la carpeta actual (WORKDIR si --test)
mkdir -p terraform

cat > terraform/backend.hcl <<EOF
bucket  = "${BUCKET_NAME}"
prefix  = "global/state"
impersonate_service_account = "${SA_EMAIL}"
EOF

cat > terraform/main.tf <<'EOF'
terraform {
  required_version = ">= 1.5.0"
  backend "gcs" {}
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.43" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "google" {
  project                     = var.project_id
  region                      = var.region
  impersonate_service_account = var.impersonate_sa
}

resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.name_prefix}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
}

resource "google_compute_firewall" "allow_ssh" {
  count   = var.os_type == "linux" ? 1 : 0
  name    = "${var.name_prefix}-allow-ssh"
  network = google_compute_network.vpc.name
  allow { protocol = "tcp"; ports = ["22"] }
  source_ranges = var.ssh_cidr_allow
  target_tags   = ["ssh"]
}

resource "google_compute_firewall" "allow_rdp" {
  count   = var.os_type == "windows" ? 1 : 0
  name    = "${var.name_prefix}-allow-rdp"
  network = google_compute_network.vpc.name
  allow { protocol = "tcp"; ports = ["3389"] }
  source_ranges = var.rdp_cidr_allow
  target_tags   = ["rdp"]
}

resource "google_compute_instance" "vm" {
  name         = "${var.name_prefix}-vm"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.disk_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {}
  }

  metadata = var.os_type == "linux" ? { enable-oslogin = "TRUE" } : {}

  tags = var.os_type == "linux" ? ["ssh"] : ["rdp"]
}

output "vm_ip" {
  value = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}
EOF

cat > terraform/variables.tf <<'EOF'
variable "project_id"      { type = string }
variable "region"          { type = string }
variable "zone"            { type = string }
variable "impersonate_sa"  { type = string }
variable "name_prefix"     { type = string  default = "lab" }
variable "subnet_cidr"     { type = string  default = "10.10.0.0/24" }
variable "os_type"         { type = string  description = "linux | windows" }
variable "image"           { type = string  description = "GCE image or family URL" }
variable "ssh_cidr_allow"  { type = list(string) default = ["0.0.0.0/0"] }
variable "rdp_cidr_allow"  { type = list(string) default = ["0.0.0.0/0"] }
variable "machine_type"    { type = string  default = "e2-medium" }
variable "disk_gb"         { type = number  default = 50 }
EOF

cat > terraform/outputs.tf <<'EOF'
output "state_bucket" { value = terraform.backend.gcs.bucket }
output "vm_ip"        { value = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip }
EOF

cat > terraform/terraform.tfvars <<EOF
project_id     = "${PROJECT_ID}"
region         = "${REGION}"
zone           = "${ZONE}"
impersonate_sa = "${SA_EMAIL}"

name_prefix    = "${NAME_PREFIX}"
machine_type   = "${MACHINE_TYPE}"
disk_gb        = ${DISK_GB}

os_type = "${OS_TYPE}"
image   = "${IMAGE}"

ssh_cidr_allow = ["0.0.0.0/0"]
rdp_cidr_allow = ["0.0.0.0/0"]
EOF

# Init + Plan + (Apply opcional)
pushd terraform >/dev/null
echo "[i] Inicializando Terraform con backend remoto..."
terraform init -reconfigure -backend-config=backend.hcl

echo
echo "================ PLAN ================"
terraform plan || { echo "Plan falló"; exit 1; }

echo
if confirm_box "¿Aplicar ahora (crear VPC+Subnet+Firewall+VM)?"; then
  terraform apply -auto-approve
  echo
  echo "[✓] IP pública:"
  VM_IP=$(terraform output -raw vm_ip || true)
  echo "  $VM_IP"

  if [[ "$OS_TYPE" == "windows" ]]; then
    WIN_USER="admin"
    echo "[i] Para credenciales Windows:"
    echo "    gcloud compute reset-windows-password ${NAME_PREFIX}-vm --zone ${ZONE} --user ${WIN_USER}"
    echo "    Conéctate por RDP a: ${VM_IP}:3389"
  else
    echo "SSH (OS Login): gcloud compute ssh ${NAME_PREFIX}-vm --zone ${ZONE}"
  fi
else
  echo "OK. No se aplicaron cambios."
fi
popd >/dev/null

# Si estábamos en TEST_MODE, volvemos y mostramos rutas
if [[ "$TEST_MODE" -eq 1 ]]; then
  popd >/dev/null  # salir de $WORKDIR
  echo
  echo "[TEST] Finalizado."
  echo "[TEST] Archivos generados en: $WORKDIR/terraform"
  echo "[TEST] Logs:"
  echo "       $LOGDIR/gcloud.log"
  echo "       $LOGDIR/terraform.log"
fi

