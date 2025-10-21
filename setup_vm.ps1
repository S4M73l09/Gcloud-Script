#Requires -Version 5.1
<#
  setup_vm.ps1 — Refactor limpio (con prefijo de archivos según sistema operativo)
  ---------------------------------------------------------------
  - Si se usa -Test → crea los ficheros Terraform en una carpeta temporal (%TEMP%) y la elimina al finalizar.
  - Si se ejecuta en modo real → guarda los ficheros en ./terraform.
  - Carpetas separadas dentro ./terraform según SO (Linux-<sufijo> o PW-windows-<sufijo>).
  - El wrapper se encarga del PATH y autenticación.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false, ConfirmImpact = 'Medium')]
param(
  [Parameter(Mandatory)][string]$ProjectId,
  [Parameter(Mandatory)][string]$Region,
  [Parameter(Mandatory)][string]$Zone,
  [string]$StateBucketName = "tfstate-$([guid]::NewGuid().ToString('N').Substring(0,8))",
  [string]$StatePrefix = 'env/default',
  [ValidateSet('linux','windows')][string]$OsType = 'linux',
  [string]$Prefix = 'demo',
  [string]$MachineType = 'e2-medium',
  [string]$ImageFamily = 'debian-12',
  [string]$ImageProject = 'debian-cloud',
  [int]$OsDiskGb,
  [string]$VpcCidr = '10.10.0.0/16',
  [string]$SubnetCidr = '10.10.10.0/24',
  [string[]]$OpenTcp = @('22','80','443','3389'),
  [string]$SaName = 'tf-runner',
  [string]$SaDisplay = 'Terraform Runner',
  [string]$EnvNameSuffix,
  [switch]$AutoApprove,
  [int]$TfParallelism = 10,
  [switch]$Test
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

function Write-Log { param([ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level, [string]$Message)
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  $line = "[$ts][$Level] $Message"
  if ($Level -eq 'ERROR') { Write-Error $Message -ErrorAction Continue } else { Write-Host $line }
}

$script:Gcloud = $env:GCLOUD_CLI ?? 'gcloud'
$script:Terraform = $env:TERRAFORM_CLI ?? 'terraform'

function Invoke-Gcloud { param([string[]]$Args, [switch]$Json)
  Write-Log DEBUG ("gcloud " + ($Args -join ' '))
  if ($Json) { (& $script:Gcloud @Args --format=json) | ConvertFrom-Json } else { & $script:Gcloud @Args }
  if ($LASTEXITCODE -ne 0) { throw "gcloud error ($LASTEXITCODE)" }
}
function Invoke-Terraform { param([string[]]$Args)
  Write-Log DEBUG ("terraform " + ($Args -join ' '))
  & $script:Terraform @Args
  if ($LASTEXITCODE -ne 0) { throw "terraform error ($LASTEXITCODE)" }
}

# --- Utilidades interacción (solo si faltan parámetros) ---
function Ask($prompt, $default='') {
  $v = Read-Host -Prompt $prompt
  if ([string]::IsNullOrWhiteSpace($v)) { return $default } else { return $v }
}
function Select-Os {
  Write-Host "`nElige sistema operativo:" -ForegroundColor Cyan
  $opts = @(
    @{name='Ubuntu 22.04 LTS'; type='linux';   family='ubuntu-2204-lts'; project='ubuntu-os-cloud'; minDisk=10},
    @{name='Debian 12';        type='linux';   family='debian-12';       project='debian-cloud';   minDisk=10},
    @{name='Windows Server 2022'; type='windows'; family='windows-2022'; project='windows-cloud';  minDisk=64},
    @{name='Windows Server 2019'; type='windows'; family='windows-2019'; project='windows-cloud';  minDisk=64}
  )
  for ($i=0; $i -lt $opts.Count; $i++) { Write-Host ("  [$($i+1)] $($opts[$i].name)") }
  $k = Ask 'Selección (1-4)' '1'
  if (-not ($k -as [int]) -or [int]$k -lt 1 -or [int]$k -gt $opts.Count) { throw 'Selección de SO inválida' }
  return $opts[[int]$k - 1]
}
function Select-MachineType {
  Write-Host "`nElige tipo de máquina (o 'C' para personalizado):" -ForegroundColor Cyan
  $types = @('e2-micro','e2-small','e2-medium','e2-standard-2','n2-standard-2','n2d-standard-2','t2d-standard-2','c3-standard-4')
  for ($i=0; $i -lt $types.Count; $i++) { Write-Host ("  [$($i+1)] $($types[$i])") }
  $sel = Ask 'Selección (1-8/C)' '3'
  if ($sel -match '^[Cc]$') { return Ask 'Introduce el tipo (p.ej. e2-standard-4)' 'e2-medium' }
  if (-not ($sel -as [int]) -or [int]$sel -lt 1 -or [int]$sel -gt $types.Count) { throw 'Selección de tipo inválida' }
  return $types[[int]$sel - 1]
}

function Ensure-ProjectContext {
  Invoke-Gcloud -Args @('config','set','project',$ProjectId) | Out-Null
  Invoke-Gcloud -Args @('config','set','compute/region',$Region) | Out-Null
  Invoke-Gcloud -Args @('config','set','compute/zone',$Zone) | Out-Null
}

function Enable-RequiredApis {
  $apis = @('compute.googleapis.com','iam.googleapis.com','cloudresourcemanager.googleapis.com','oslogin.googleapis.com','storage.googleapis.com')
  foreach ($api in $apis) {
    Write-Log INFO "Habilitando API: $api"
    Invoke-Gcloud -Args @('services','enable',$api,'--project',$ProjectId) | Out-Null
  }
}

function Ensure-StateBucket {
  $b = Invoke-Gcloud -Args @('storage','buckets','list','--project',$ProjectId,'--filter',"name:$StateBucketName") -Json -ErrorAction SilentlyContinue
  if (-not $b) {
    Invoke-Gcloud -Args @('storage','buckets','create',"gs://$StateBucketName",'--project',$ProjectId,'--uniform-bucket-level-access') | Out-Null
    Invoke-Gcloud -Args @('storage','buckets','update',"gs://$StateBucketName",'--versioning') | Out-Null
    $policy = '{"rule":[{"action":{"type":"Delete"},"condition":{"isLive":false,"age":30}}]}'
    $tmp = New-TemporaryFile
    $policy | Out-File -FilePath $tmp -Encoding utf8
    Invoke-Gcloud -Args @('storage','buckets','set-lifecycle',"gs://$StateBucketName",'--lifecycle-file',$tmp) | Out-Null
    Remove-Item $tmp -Force
  } else { Write-Log INFO "Bucket ya existe: gs://$StateBucketName" }
}

function Ensure-ServiceAccount {
  $saEmail = "$SaName@$ProjectId.iam.gserviceaccount.com"
  $exists = Invoke-Gcloud -Args @('iam','service-accounts','list','--project',$ProjectId,'--filter',"email:$saEmail") -Json
  if (-not $exists) {
    Invoke-Gcloud -Args @('iam','service-accounts','create',$SaName,'--display-name',$SaDisplay,'--project',$ProjectId) | Out-Null
  }
  foreach ($r in @('roles/compute.admin','roles/iam.serviceAccountUser','roles/storage.admin')) {
    Invoke-Gcloud -Args @('projects','add-iam-policy-binding',$ProjectId,'--member',"serviceAccount:$saEmail",'--role',$r,'--quiet') | Out-Null
  }
  return $saEmail
}

function Ensure-TfScaffold {
  if (-not (Test-Path -LiteralPath $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir | Out-Null }
  # Files without L/W prefixes; differentiation is by folder (PW-windows-<suffix> or Linux-<suffix>)
  
  $backendTf = @"
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = { source = "hashicorp/google", version = ">= 5.30" }
  }
  backend "gcs" {
    bucket = "$StateBucketName"
    prefix = "$StatePrefix"
  }
}
"@

  $providersTf = @"
provider "google" {
  project = "$ProjectId"
  region  = "$Region"
  zone    = "$Zone"
}
"@

  $networkTf = @"
resource "google_compute_network" "vpc" {
  name                    = "${Prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${Prefix}-subnet"
  ip_cidr_range = "$SubnetCidr"
  region        = "$Region"
  network       = google_compute_network.vpc.id
}

resource "google_compute_firewall" "allow" {
  name    = "${Prefix}-allow"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = [${OpenTcp | ForEach-Object { '"' + $_ + '"' } -join ', '}]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${Prefix}"]
}
"@

  $vmTf = @"
resource "google_compute_instance" "vm" {
  name         = "${Prefix}-vm"
  machine_type = "$MachineType"
  zone         = "$Zone"
  tags         = ["${Prefix}"]

  boot_disk {
    initialize_params {
      image = "$ImageProject/$ImageFamily"
      ${if ($OsDiskGb -gt 0) { "size = $OsDiskGb" } else { '' }}
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {}
  }

  metadata = ${if ($OsType -eq 'linux') { '{
    enable-oslogin = "TRUE"
  }' } else { '{}' }}
}
"@

  $outputsTf = @'
output "vm_ip" {
  value = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}
'@

  Set-Content -Path (Join-Path $WorkDir 'backend.tf')   -Value $backendTf   -Encoding utf8
  Set-Content -Path (Join-Path $WorkDir 'providers.tf') -Value $providersTf -Encoding utf8
  Set-Content -Path (Join-Path $WorkDir 'network.tf')   -Value $networkTf   -Encoding utf8
  Set-Content -Path (Join-Path $WorkDir 'vm.tf')        -Value $vmTf        -Encoding utf8
  Set-Content -Path (Join-Path $WorkDir 'outputs.tf')   -Value $outputsTf   -Encoding utf8
}
"@

  $providersTf = @"
provider "google" {
  project = "$ProjectId"
  region  = "$Region"
  zone    = "$Zone"
}
"@

  $networkTf = @"
resource "google_compute_network" "vpc" {
  name                    = "${Prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${Prefix}-subnet"
  ip_cidr_range = "$SubnetCidr"
  region        = "$Region"
  network       = google_compute_network.vpc.id
}

resource "google_compute_firewall" "allow" {
  name    = "${Prefix}-allow"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = [${OpenTcp | ForEach-Object { '"' + $_ + '"' } -join ', '}]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${Prefix}"]
}
"@

  $vmTf = @"
resource "google_compute_instance" "vm" {
  name         = "${Prefix}-vm"
  machine_type = "$MachineType"
  zone         = "$Zone"
  tags         = ["${Prefix}"]

  boot_disk {
    initialize_params {
      image = "$ImageProject/$ImageFamily"
      ${if ($OsDiskGb -gt 0) { "size = $OsDiskGb" } else { '' }}
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {}
  }

  metadata = ${if ($OsType -eq 'linux') { '{
    enable-oslogin = "TRUE"
  }' } else { '{}' }}
}
"@

  $outputsTf = @'
output "vm_ip" {
  value = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}
'@

  Set-Content -Path (Join-Path $WorkDir ("${prefix}backend.tf"))   -Value $backendTf   -Encoding utf8
  Set-Content -Path (Join-Path $WorkDir ("${prefix}providers.tf")) -Value $providersTf -Encoding utf8
  Set-Content -Path (Join-Path $WorkDir ("${prefix}network.tf"))   -Value $networkTf   -Encoding utf8
  Set-Content -Path (Join-Path $WorkDir ("${prefix}vm.tf"))        -Value $vmTf        -Encoding utf8
  Set-Content -Path (Join-Path $WorkDir ("${prefix}outputs.tf"))   -Value $outputsTf   -Encoding utf8
}

# --- Terraform pipeline ---
function Run-Terraform {
  Push-Location $WorkDir
  try {
  # === Captura interactiva si faltan parámetros clave (SO, imagen, tipo y disco) ===
  if (-not $PSBoundParameters.ContainsKey('OsType') -or -not $PSBoundParameters.ContainsKey('ImageFamily') -or -not $PSBoundParameters.ContainsKey('ImageProject') -or -not $PSBoundParameters.ContainsKey('OsDiskGb')) {
    $os = Select-Os
    $OsType       = $os.type
    $ImageFamily  = $os.family
    $ImageProject = $os.project
    if (-not $PSBoundParameters.ContainsKey('OsDiskGb') -or $OsDiskGb -le 0) { $OsDiskGb = [int]$os.minDisk }
  }
  if (-not $PSBoundParameters.ContainsKey('MachineType')) { $MachineType = Select-MachineType }
  if (-not $PSBoundParameters.ContainsKey('StatePrefix') -or $StatePrefix -eq 'env/default') { $StatePrefix = ($OsType -eq 'windows') ? 'env/windows' : 'env/linux' }

  # === Selección de carpeta de trabajo (después de decidir SO) ===
  if ($Test) {
    $WorkDir = Join-Path $env:TEMP ("iac-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    Write-Log INFO "Modo -Test: usando carpeta temporal $WorkDir"
  } else {
    # Base ./terraform and a fixed OS prefix; only the suffix is user-provided
    $base = Join-Path (Resolve-Path '.').Path 'terraform'
    if (-not (Test-Path -LiteralPath $base)) { New-Item -ItemType Directory -Path $base -Force | Out-Null }
    if (-not $PSBoundParameters.ContainsKey('EnvNameSuffix') -or [string]::IsNullOrWhiteSpace($EnvNameSuffix)) {
      $EnvNameSuffix = Ask 'Nombre del entorno (solo sufijo, p.ej. "prod", "web", "lab")' 'default'
    }
    $fixedPrefix = ($OsType -eq 'windows') ? 'PW-windows-' : 'Linux-'
    $dirName = $fixedPrefix + $EnvNameSuffix
    $WorkDir = Join-Path $base $dirName
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    Write-Log INFO ("Modo real: carpeta ./terraform/{0}" -f $dirName)
  }
  }

    Invoke-Terraform -Args @('init','-upgrade')
    Invoke-Terraform -Args @('validate')
    Invoke-Terraform -Args @('plan','-out=.tfplan','-parallelism',$TfParallelism)
    if ($AutoApprove) {
      if ($PSCmdlet.ShouldProcess('infra','terraform apply')) {
        Invoke-Terraform -Args @('apply','-parallelism',$TfParallelism,'-auto-approve')
      }
    } else {
      Write-Host ""; $ans = Read-Host "¿Aplicar cambios? (y/N)"
      if ($ans -match '^(y|yes|s|si)$') {
        if ($PSCmdlet.ShouldProcess('infra','terraform apply')) {
          Invoke-Terraform -Args @('apply','-parallelism',$TfParallelism)
        }
      } else {
        Write-Log WARN 'OK. No se aplicaron cambios.'
      }
    }
  }
  finally { Pop-Location }
}

# --- Mostrar resultados de Terraform (solo entorno real) ---
function Show-Outputs {
  if ($Test) { return }
  try {
    Push-Location $WorkDir
    $ip = (& $script:Terraform output -raw vm_ip 2>$null)
  } catch { $ip = $null } finally { Pop-Location }

  if ($OsType -eq 'windows') {
    Write-Host ""
    Write-Host "[i] Credenciales Windows:" -ForegroundColor Yellow
    Write-Host ("    gcloud compute reset-windows-password {0}-vm --zone {1} --user admin" -f $Prefix, $Zone)
    if ($ip) { Write-Host ("    Conéctate por RDP a: {0}:3389" -f $ip) }
  } else {
    if ($ip) {
      Write-Host ""
      Write-Host ("SSH (OS Login): gcloud compute ssh {0}-vm --zone {1}" -f $Prefix, $Zone) -ForegroundColor Yellow
    }
  }
}

try {
  if ($Test) {
    $WorkDir = Join-Path $env:TEMP ("iac-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    Write-Log INFO "Modo -Test: usando carpeta temporal $WorkDir"
  } else {
    $dirName = if ($OsType -eq 'windows') { 'Windows-terraform' } else { 'Linux-terraform' }
    $WorkDir = Join-Path (Resolve-Path '.').Path $dirName
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    Write-Log INFO ("Modo real: carpeta ./{0}" -f $dirName)
  }

  Ensure-ProjectContext
  if ($Test) { Write-Log INFO 'Modo -Test: solo validaciones de API y contexto.' }
  Enable-RequiredApis
  Ensure-StateBucket
  $sa = Ensure-ServiceAccount

  if ($Test) {
    Write-Log INFO "Test OK — Project=$ProjectId, Zone=$Zone, SA=$sa, Bucket=gs://$StateBucketName"
    return
  }

  Ensure-TfScaffold
Write-Log INFO 'Terraform scaffold creado.'
Run-Terraform
Show-Outputs
  Write-Log INFO 'Finalizado sin errores.'
}
catch { Write-Log ERROR $_.Exception.Message; throw }
finally {
  if ($Test -and (Test-Path -LiteralPath $WorkDir)) {
    try { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction Stop; Write-Log INFO "Carpeta temporal eliminada: $WorkDir" } catch { Write-Log WARN "No se pudo borrar $WorkDir: $($_.Exception.Message)" }
  }
}

