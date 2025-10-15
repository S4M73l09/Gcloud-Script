<#
.SYNOPSIS
  GCP VM Automation in PowerShell (Terraform + gcloud)
.DESCRIPTION
  Crea backend remoto (GCS), Service Account con impersonación,
  genera Terraform (VPC, subred, firewall y VM Linux/Windows) y despliega.
  Incluye -Test para simular sin tocar GCP (genera archivos en TEMP).
#>
# --- AUTO-EJECUCIÓN SEGURA ---
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @('Restricted','AllSigned')) {
    Write-Host "[!] Tu política actual es '$policy', que impide ejecutar scripts."
    Write-Host "Cambiando temporalmente a 'RemoteSigned'..."
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
        Write-Host "[✓] Política de ejecución actualizada a RemoteSigned." -ForegroundColor Green
    } catch {
        Write-Host "[x] No se pudo cambiar la política automáticamente. Intenta ejecutar como administrador." -ForegroundColor Red
        exit 1
    }
}

# Desbloquear el propio script (por si fue descargado de Internet)
$myPath = $MyInvocation.MyCommand.Definition
if (Test-Path $myPath) {
    try {
        Unblock-File -Path $myPath -ErrorAction Stop
        Write-Host "[✓] Script desbloqueado correctamente." -ForegroundColor Green
    } catch {
        Write-Host "[i] No fue necesario desbloquear el script (ya está permitido)."
    }
}
# --- FIN AUTO-EJECUCIÓN SEGURA ---

param(
  [switch]$Test
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ========== Helpers ==========
function Need($cmd) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "No encontrado en PATH: '$cmd'"
  }
}

function Prompt-Input([string]$Message, [string]$Default = "") {
  if ($Test) {
    switch -Wildcard ($Message) {
      "*correo*"        { return "tester@example.com" }
      "*proyecto*"      { return "test-project-123" }
      "*Región*"        { return "europe-southwest1" }
      "*Zona*"          { return "europe-southwest1-a" }
      "*Prefijo*"       { return "lab" }
      "*máquina*"       { return "e2-medium" }
      "*disco*"         { return "50" }
      default           { return $Default }
    }
  } else {
    if ($Default) { return Read-Host "$Message [$Default]" } else { return Read-Host $Message }
  }
}

function Confirm-Action([string]$Message) {
  if ($Test) { return $true }
  $ans = Read-Host "$Message (y/N)"
  return $ans -match '^[Yy]'
}

function New-RandHex([int]$bytes = 2) {
  $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
  $buf = New-Object byte[] ($bytes)
  $rng.GetBytes($buf)
  ($buf | ForEach-Object { $_.ToString("x2") }) -join ""
}

# ========== Modo Test ==========
if ($Test) {
  Write-Host "[TEST] Modo simulación: no se harán llamadas reales a GCP." -ForegroundColor Yellow
  $TempRoot = Join-Path $env:TEMP ("gcp-test-" + (New-RandHex 4))
  New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
  $TerraformDir = New-Item -ItemType Directory -Force -Path (Join-Path $TempRoot "terraform")
  Write-Host "[TEST] Archivos se escribirán en: $($TerraformDir.FullName)"
} else {
  Need "gcloud"
  Need "terraform"
}

# ========== Datos de entrada ==========
$email   = Prompt-Input "Introduce tu correo de Google:" ""
$project = Prompt-Input "ID del proyecto GCP:" (if (-not $Test) { (gcloud config get-value project 2>$null) } else { "test-project-123" })
$region  = Prompt-Input "Región (p.ej. europe-southwest1):" "europe-southwest1"
$zone    = Prompt-Input "Zona (p.ej. ${region}-a):" "$region-a"
$prefix  = Prompt-Input "Prefijo para los recursos:" "lab"
$machine = Prompt-Input "Tipo de máquina (e2-medium recomendado):" "e2-medium"
[int]$diskGB = [int](Prompt-Input "Tamaño del disco (GB):" "50")

# SO
$osOptions = @(
  "Ubuntu 22.04 LTS",
  "Debian 12",
  "Windows Server 2022",
  "Windows Server 2019"
)
if ($Test) {
  $osChoice = "Debian 12"
} else {
  Write-Host "`nElige sistema operativo:"
  1..$osOptions.Count | ForEach-Object { Write-Host "[$_] $($osOptions[$_-1])" }
  do {
    $idx = [int](Read-Host "Número (1-$($osOptions.Count))")
  } while ($idx -lt 1 -or $idx -gt $osOptions.Count)
  $osChoice = $osOptions[$idx-1]
}

# Imagen y ajustes según SO
$osType = "linux"
$image  = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
switch ($osChoice) {
  "Ubuntu 22.04 LTS"   { $osType="linux";   $image="projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts" }
  "Debian 12"          { $osType="linux";   $image="projects/debian-cloud/global/images/family/debian-12" }
  "Windows Server 2022"{ $osType="windows"; $image="projects/windows-cloud/global/images/family/windows-2022"; if ($diskGB -lt 64) { $diskGB=64 } }
  "Windows Server 2019"{ $osType="windows"; $image="projects/windows-cloud/global/images/family/windows-2019"; if ($diskGB -lt 64) { $diskGB=64 } }
}

# Identificadores
$rand     = New-RandHex 2
$bucket   = "tf-state-$project-$rand"
$saName   = "terraform-sa"
$saEmail  = "$saName@$project.iam.gserviceaccount.com"

Write-Host "`nResumen:" -ForegroundColor Cyan
Write-Host "  Proyecto: $project"
Write-Host "  Región:   $region"
Write-Host "  Zona:     $zone"
Write-Host "  SO:       $osChoice  (tipo: $osType)"
Write-Host "  Imagen:   $image"
Write-Host "  VM:       $machine  ($diskGB GB)"
Write-Host "  Bucket:   $bucket`n"

# ========== Login y preparación GCP (real) ==========
if (-not $Test) {
  # Login de cuenta
  $accounts = (gcloud auth list --format="value(account)") -split "`n"
  if (-not ($accounts -contains $email)) {
    Write-Host "[i] Iniciando sesión para $email ..."
    gcloud auth login $email | Out-Null
  }
  gcloud config set account $email    | Out-Null
  gcloud config set project $project  | Out-Null

  # ADC para Terraform (impersonación)
  $adc1 = Join-Path $env:APPDATA "gcloud\application_default_credentials.json"
  $adc2 = Join-Path $HOME ".config\gcloud\application_default_credentials.json"
  if (-not (Test-Path $adc1) -and -not (Test-Path $adc2)) {
    Write-Host "[i] Creando Application Default Credentials (ADC) ..."
    gcloud auth application-default login | Out-Null
  }

  # APIs necesarias
  Write-Host "[i] Habilitando APIs ..."
  gcloud services enable `
    compute.googleapis.com `
    iam.googleapis.com `
    cloudresourcemanager.googleapis.com `
    storage.googleapis.com `
    | Out-Null

  # Bucket backend
  Write-Host "[i] Creando bucket de estado: gs://$bucket"
  gcloud storage buckets create "gs://$bucket" --location=$region --uniform-bucket-level-access | Out-Null
  gcloud storage buckets update "gs://$bucket" --versioning | Out-Null
  $lifecycle = @'
{"rule":[{"action":{"type":"Delete"},"condition":{"isLive":false,"age":60}}]}
'@
  $tmpLifecycle = Join-Path $env:TEMP ("lifecycle-" + (New-RandHex 2) + ".json")
  $lifecycle | Out-File $tmpLifecycle -Encoding utf8
  gcloud storage buckets update "gs://$bucket" --lifecycle-file=$tmpLifecycle | Out-Null

  # Service Account + permisos
  if (-not (gcloud iam service-accounts describe $saEmail 2>$null)) {
    Write-Host "[i] Creando Service Account $saEmail"
    gcloud iam service-accounts create $saName --display-name "Terraform Service Account" | Out-Null
  } else {
    Write-Host "[i] SA ya existe: $saEmail"
  }

  Write-Host "[i] Concediendo a la SA acceso al bucket de estado..."
  gcloud storage buckets add-iam-policy-binding "gs://$bucket" `
    --member="serviceAccount:$saEmail" `
    --role="roles/storage.objectAdmin" | Out-Null

  Write-Host "[i] Concediendo impersonación a tu usuario ($email) sobre la SA..."
  gcloud iam service-accounts add-iam-policy-binding $saEmail `
    --member="user:$email" `
    --role="roles/iam.serviceAccountTokenCreator" | Out-Null
}

# ========== Generación de archivos Terraform ==========
$baseDir = if ($Test) { $TerraformDir.FullName } else { Join-Path $PSScriptRoot "terraform" }
New-Item -ItemType Directory -Force -Path $baseDir | Out-Null

$backend_hcl = @"
bucket  = "$bucket"
prefix  = "global/state"
impersonate_service_account = "$saEmail"
"@
$backend_hcl | Out-File (Join-Path $baseDir "backend.hcl") -Encoding utf8

$main_tf = @'
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
'@
$main_tf | Out-File (Join-Path $baseDir "main.tf") -Encoding utf8

$variables_tf = @'
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
'@
$variables_tf | Out-File (Join-Path $baseDir "variables.tf") -Encoding utf8

$outputs_tf = @'
output "state_bucket" { value = terraform.backend.gcs.bucket }
output "vm_ip"        { value = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip }
'@
$outputs_tf | Out-File (Join-Path $baseDir "outputs.tf") -Encoding utf8

$tfvars = @"
project_id     = "$project"
region         = "$region"
zone           = "$zone"
impersonate_sa = "$saEmail"

name_prefix    = "$prefix"
machine_type   = "$machine"
disk_gb        = $diskGB

os_type = "$osType"
image   = "$image"

ssh_cidr_allow = ["0.0.0.0/0"]
rdp_cidr_allow = ["0.0.0.0/0"]
"@
$tfvars | Out-File (Join-Path $baseDir "terraform.tfvars") -Encoding utf8

Write-Host "`n[✓] Terraform files generados en: $baseDir`n"

# ========== Terraform (init/plan/apply) ==========
if ($Test) {
  Write-Host "[TEST] Saltando ejecución de Terraform (simulación)."
Write-Host ('[TEST] Carpeta temporal: {0}' -f $TempRoot)
  return
}

Write-Host "Inicializando Terraform..."
terraform -chdir="$baseDir" init -reconfigure -backend-config="backend.hcl"

Write-Host "Planificando..."
terraform -chdir="$baseDir" plan

if (Confirm-Action "¿Aplicar ahora y crear VPC+Subnet+Firewall+VM?") {
  terraform -chdir="$baseDir" apply -auto-approve
  try {
    $ip = terraform -chdir="$baseDir" output -raw vm_ip
  } catch { $ip = "" }
  if ($osType -eq "windows") {
    Write-Host "`n[i] Para credenciales Windows:"
    Write-Host "    gcloud compute reset-windows-password ${prefix}-vm --zone $zone --user admin"
    if ($ip) { Write-Host "    Conéctate por RDP a: $ip`:3389" }
  } else {
    if ($ip) { Write-Host "`nSSH (OS Login):  gcloud compute ssh ${prefix}-vm --zone $zone" }
  }
} else {
Write-Host 'OK. No se aplicaron cambios.'
}


