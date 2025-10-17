#Requires -Version 5.1
<#
.SYNOPSIS
  Automatiza backend GCS, Service Account (impersonación) y Terraform (VPC, subnet, firewall, VM).

.DESCRIPTION
  - Crea bucket GCS para estado (UBA + versioning + lifecycle)
  - Crea Service Account y concede permisos mínimos + impersonación para tu usuario
  - Genera configuración Terraform (VPC/Subred/Firewall + VM Linux/Windows)
  - Ejecuta terraform init/plan y, si confirmas, apply
  - Usa -Test para generar ficheros sin tocar GCP
#>

param(
  [switch]$Test
)

# --- Seguridad y comportamiento ---
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Fuerza Python embebido y el launcher .cmd de gcloud
$env:CLOUDSDK_PYTHON = Join-Path $env:LOCALAPPDATA 'Google\Cloud SDK\google-cloud-sdk\platform\bundledpython\python.exe'
$GcloudCmd = Join-Path $env:LOCALAPPDATA 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd'
if (-not (Test-Path $GcloudCmd)) { throw "gcloud.cmd no encontrado: $GcloudCmd" }

# Alias para que cualquier 'gcloud ...' use SIEMPRE el .cmd (y no gcloud.ps1)
Set-Alias -Name gcloud -Value $GcloudCmd -Scope Process -Force

# ---------- Seguridad y utilidades ----------
Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Need([string]$cmd) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "No encontrado en PATH: '$cmd'"
  }
}

function Prompt-Input([string]$Message, [string]$Default = "") {
  if ($Test) {
    switch -Wildcard ($Message) {
      "*correo*"   { return "tester@example.com" }
      "*proyecto*" { return "test-project-123" }
      "*Región*"   { return "europe-southwest1" }
      "*Zona*"     { return "europe-southwest1-a" }
      "*Prefijo*"  { return "lab" }
      "*máquina*"  { return "e2-medium" }
      "*disco*"    { return "50" }
      default      { return $Default }
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

function New-RandHex([int]$bytes = 2) { -join ((1..$bytes) | ForEach-Object { "{0:x2}" -f (Get-Random -Min 0 -Max 256) }) }

function Write-TextUtf8($Path, [string[]]$Lines) {
  $nl = "`r`n"
  ($Lines -join $nl) | Set-Content -Path $Path -Encoding utf8
}

# ---------- Dependencias ----------
Need gcloud
Need gsutil
Need terraform

# ---------- Inputs ----------
$email   = Prompt-Input "Introduce tu correo de Google (para gcloud):"
$defProj = (gcloud config get-value project 2>$null)
$project = Prompt-Input "ID del proyecto GCP (o vacío para el activo):" $defProj
if (-not $project) { $project = Prompt-Input "ID de proyecto GCP:" "test-project-123" }
$region  = Prompt-Input "Región (p.ej. europe-southwest1):" "europe-southwest1"
$zone    = Prompt-Input "Zona (p.ej. ${region}-a):" "$($region)-a"
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
  Write-Host ""
  Write-Host "Elige sistema operativo:" -ForegroundColor Cyan
  for ($i=0; $i -lt $osOptions.Count; $i++) { Write-Host ("[{0}] {1}" -f ($i+1), $osOptions[$i]) }
  do { $idx = [int](Read-Host ("Número (1-{0})" -f $osOptions.Count)) } while ($idx -lt 1 -or $idx -gt $osOptions.Count)
  $osChoice = $osOptions[$idx-1]
}

# Imagen y ajustes según SO
$osType = "linux"
$image  = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
switch ($osChoice) {
  "Ubuntu 22.04 LTS"    { $osType="linux";   $image="projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts" }
  "Debian 12"           { $osType="linux";   $image="projects/debian-cloud/global/images/family/debian-12" }
  "Windows Server 2022" { $osType="windows"; $image="projects/windows-cloud/global/images/family/windows-2022"; if ($diskGB -lt 64) { $diskGB=64 } }
  "Windows Server 2019" { $osType="windows"; $image="projects/windows-cloud/global/images/family/windows-2019"; if ($diskGB -lt 64) { $diskGB=64 } }
}

# Identificadores y paths
$rand     = New-RandHex 2
$bucket   = ("tf-state-{0}-{1}" -f $project, $rand).ToLower()
$saName   = "$prefix-tf-sa"
$saEmail  = "$saName@$project.iam.gserviceaccount.com"

# Carpeta Terraform
if ($Test) {
  $TempRoot    = Join-Path $env:TEMP ("gcp-test-" + (New-RandHex 4))
  New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
  $TerraformDir = New-Item -ItemType Directory -Force -Path (Join-Path $TempRoot "terraform")
}
$baseDir = if ($Test) { $TerraformDir.FullName } else { Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "terraform" }

Write-Host ""
Write-Host "Resumen:" -ForegroundColor Yellow
Write-Host ("  Proyecto: {0}" -f $project)
Write-Host ("  Región:   {0}" -f $region)
Write-Host ("  Zona:     {0}" -f $zone)
Write-Host ("  SO:       {0} (tipo: {1})" -f $osChoice, $osType)
Write-Host ("  Imagen:   {0}" -f $image)
Write-Host ("  SA:       {0}" -f $saEmail)
Write-Host ("  Bucket:   gs://{0}" -f $bucket)
Write-Host ""

# ---------- Preparación GCP (si no es Test) ----------
if (-not $Test) {
  # Sesión y proyecto
  $accounts = (gcloud auth list --format="value(account)") -split "`n"
  if (-not ($accounts -contains $email)) {
    Write-Host ("[i] Iniciando sesión para {0} ..." -f $email)
    gcloud auth login $email | Out-Null
  }
  gcloud config set account $email   | Out-Null
  gcloud config set project $project | Out-Null

  # ADC para Terraform (si falta)
  $adc1 = Join-Path $env:APPDATA "gcloud\application_default_credentials.json"
  $adc2 = Join-Path $HOME ".config\gcloud\application_default_credentials.json"
  if (-not (Test-Path $adc1) -and -not (Test-Path $adc2)) {
    Write-Host "[i] Creando Application Default Credentials (ADC) ..."
    gcloud auth application-default login | Out-Null
  }

  # APIs
  Write-Host "[i] Habilitando APIs (puede tardar)..."
  gcloud services enable `
    compute.googleapis.com `
    iam.googleapis.com `
    cloudresourcemanager.googleapis.com `
    storage.googleapis.com `
    | Out-Null

  # Bucket backend (UBA + versioning + lifecycle)
  Write-Host ("[i] Creando bucket: gs://{0}" -f $bucket)
  gcloud storage buckets create ("gs://{0}" -f $bucket) --location=$region --uniform-bucket-level-access | Out-Null
  gcloud storage buckets update ("gs://{0}" -f $bucket) --versioning | Out-Null

  $tmpLifecycle = Join-Path $env:TEMP ("lifecycle-" + (New-RandHex 2) + ".json")
  $lcLines = @(
    '{'
    '  "rule": ['
    '    {'
    '      "action": { "type": "Delete" },'
    '      "condition": { "isLive": false, "age": 60 }'
    '    }'
    '  ]'
    '}'
  )
  Write-TextUtf8 $tmpLifecycle $lcLines
  gcloud storage buckets update ("gs://{0}" -f $bucket) --lifecycle-file=$tmpLifecycle | Out-Null
  Remove-Item $tmpLifecycle -Force -ErrorAction SilentlyContinue

  # Service Account
  Write-Host ("[i] Creando Service Account {0} ..." -f $saEmail)
  gcloud iam service-accounts create $saName --display-name "Terraform Service Account" | Out-Null

  # Permiso bucket para SA
  Write-Host "[i] Concediendo acceso al bucket a la SA..."
  gcloud storage buckets add-iam-policy-binding ("gs://{0}" -f $bucket) `
    --member=("serviceAccount:{0}" -f $saEmail) `
    --role="roles/storage.objectAdmin" | Out-Null

  # Impersonación: tu usuario -> SA
  Write-Host "[i] Concediendo impersonación a tu usuario sobre la SA..."
  gcloud iam service-accounts add-iam-policy-binding $saEmail `
    --member=("user:{0}" -f $email) `
    --role="roles/iam.serviceAccountTokenCreator" | Out-Null
}

# ---------- Generación de archivos Terraform ----------
New-Item -ItemType Directory -Force -Path $baseDir | Out-Null

# backend.hcl
Write-TextUtf8 (Join-Path $baseDir "backend.hcl") @(
  ('bucket  = "{0}"' -f $bucket)
  'prefix  = "global/state"'
  ('impersonate_service_account = "{0}"' -f $saEmail)
)

# main.tf
Write-TextUtf8 (Join-Path $baseDir "main.tf") @(
  'terraform {'
  '  required_version = ">= 1.5.0"'
  '  backend "gcs" {}'
  '  required_providers {'
  '    google = { source = "hashicorp/google", version = "~> 5.43" }'
  '    random = { source = "hashicorp/random", version = "~> 3.6" }'
  '  }'
  '}'
  ''
  'provider "google" {'
  '  project                     = var.project_id'
  '  region                      = var.region'
  '  impersonate_service_account = var.impersonate_sa'
  '}'
  ''
  'resource "random_id" "suffix" {'
  '  byte_length = 2'
  '}'
  ''
  'resource "google_compute_network" "vpc" {'
  '  name                    = "${var.name_prefix}-vpc-${random_id.suffix.hex}"'
  '  auto_create_subnetworks = false'
  '}'
  ''
  'resource "google_compute_subnetwork" "subnet" {'
  '  name          = "${var.name_prefix}-subnet"'
  '  ip_cidr_range = var.subnet_cidr'
  '  region        = var.region'
  '  network       = google_compute_network.vpc.id'
  '}'
  ''
  'resource "google_compute_firewall" "allow_ssh" {'
  '  count    = var.os_type == "linux" ? 1 : 0'
  '  name     = "${var.name_prefix}-allow-ssh"'
  '  network  = google_compute_network.vpc.name'
  '  priority = 1000'
  '  allow { protocol = "tcp" ports = ["22"] }'
  '  source_ranges = var.ssh_cidr_allow'
  '  target_tags   = ["ssh"]'
  '}'
  ''
  'resource "google_compute_firewall" "allow_rdp" {'
  '  count    = var.os_type == "windows" ? 1 : 0'
  '  name     = "${var.name_prefix}-allow-rdp"'
  '  network  = google_compute_network.vpc.name'
  '  priority = 1000'
  '  allow { protocol = "tcp" ports = ["3389"] }'
  '  source_ranges = var.rdp_cidr_allow'
  '  target_tags   = ["rdp"]'
  '}'
  ''
  'resource "google_compute_instance" "vm" {'
  '  name         = "${var.name_prefix}-vm"'
  '  machine_type = var.machine_type'
  '  zone         = var.zone'
  ''
  '  boot_disk {'
  '    initialize_params {'
  '      image = var.image'
  '      size  = var.disk_gb'
  '    }'
  '  }'
  ''
  '  network_interface {'
  '    subnetwork = google_compute_subnetwork.subnet.id'
  '    access_config {}'
  '  }'
  ''
  '  metadata = var.os_type == "linux" ? { enable-oslogin = "TRUE" } : {}'
  ''
  '  tags = var.os_type == "linux" ? ["ssh"] : ["rdp"]'
  '}'
  ''
  'output "vm_ip" {'
  '  value = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip'
  '}'
)

# variables.tf
Write-TextUtf8 (Join-Path $baseDir "variables.tf") @(
  'variable "project_id"      { type = string }'
  'variable "region"          { type = string }'
  'variable "zone"            { type = string }'
  'variable "impersonate_sa"  { type = string }'
  'variable "name_prefix"     { type = string  default = "lab" }'
  'variable "subnet_cidr"     { type = string  default = "10.10.0.0/24" }'
  'variable "os_type"         { type = string  description = "linux | windows" }'
  'variable "image"           { type = string  description = "GCE image or family URL" }'
  'variable "ssh_cidr_allow"  { type = list(string) default = ["0.0.0.0/0"] }'
  'variable "rdp_cidr_allow"  { type = list(string) default = ["0.0.0.0/0"] }'
  'variable "machine_type"    { type = string  default = "e2-medium" }'
  'variable "disk_gb"         { type = number  default = 50 }'
)

# outputs.tf
Write-TextUtf8 (Join-Path $baseDir "outputs.tf") @(
  'output "vm_ip" { value = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip }'
)

# terraform.tfvars
Write-TextUtf8 (Join-Path $baseDir "terraform.tfvars") @(
  ('project_id     = "{0}"' -f $project)
  ('region         = "{0}"' -f $region)
  ('zone           = "{0}"' -f $zone)
  ('impersonate_sa = "{0}"' -f $saEmail)
  ''
  ('name_prefix    = "{0}"' -f $prefix)
  ('machine_type   = "{0}"' -f $machine)
  ('disk_gb        = {0}' -f $diskGB)
  ('os_type        = "{0}"' -f $osType)
  ('image          = "{0}"' -f $image)
  ''
  'ssh_cidr_allow = ["0.0.0.0/0"]'
  'rdp_cidr_allow = ["0.0.0.0/0"]'
)

# ---------- Terraform (init/plan/apply) ----------
if ($Test) {
  Write-Host "[TEST] Generados ficheros en: $baseDir" -ForegroundColor Green
  return
}

Write-Host "Inicializando Terraform..." -ForegroundColor Cyan
terraform -chdir="$baseDir" init -reconfigure -backend-config="backend.hcl"

Write-Host "Planificando..." -ForegroundColor Cyan
terraform -chdir="$baseDir" plan

if (Confirm-Action "¿Aplicar ahora (crear VPC+Subnet+Firewall+VM)?") {
  terraform -chdir="$baseDir" apply -auto-approve
  try { $ip = terraform -chdir="$baseDir" output -raw vm_ip } catch { $ip = "" }

  if ($osType -eq "windows") {
    Write-Host ""
    Write-Host "[i] Credenciales Windows:" -ForegroundColor Yellow
    Write-Host ("    gcloud compute reset-windows-password {0}-vm --zone {1} --user admin" -f $prefix, $zone)
    if ($ip) { Write-Host ("    Conéctate por RDP a: {0}:3389" -f $ip) }
  } else {
    if ($ip) {
      Write-Host ""
      Write-Host ("SSH (OS Login): gcloud compute ssh {0}-vm --zone {1}" -f $prefix, $zone) -ForegroundColor Yellow
    }
  }
} else {
  Write-Host "OK. No se aplicaron cambios." -ForegroundColor Yellow
}



