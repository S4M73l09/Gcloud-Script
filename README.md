<h1 align="center">🚀 GCP Terraform VM Bootstrap</h1>

English-->[ES](README.ES.md)  
<p align="center">
  <b>Automated Google Cloud VM creation with Terraform + gcloud</b><br>
  <i>No JSON keys, no manual setup — just run one script.</i>
</p>

---

## 🌍 Overview
This repository allows you to create a **fully working GCP VM** with:
- Remote **Terraform backend** in Google Cloud Storage
- **Service Account** for Terraform (secure impersonation)
- Automatic **network, subnet, firewall and VM** creation

All through a single interactive script — no advanced GCP knowledge required.

---

## 📁 Repository structure  
```markdown
📦 Gcloud-Scripts  
├── setup_vm.sh  #Main automation script bash  
├── setup_vm.ps1 #Main automation script powershell  
├── setup_vm.cmd #Wrapper for script .ps1  
├── README.md # You are here  
├── README.ES.md  
└── terraform/ # Generated Terraform files  
    ├── Folder Powershell/bash  
    └── Readme.md  
```
---

## ⚙️ Requirements
Before running:
- Installation on Linux or Windows (Added to PATH) [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)  
- Installation on Linux or Windows (Added to PATH) [Terraform](https://developer.hashicorp.com/terraform/downloads)  
- A Google Cloud project with billing enabled.
- Project with billing enabled  
---

## 🚀 Usage
Clone and run the script:
```bash
git clone https://github.com/S4M73l09/Gcloud-Scripts.git
cd Gcloud-Scripts
chmod +x setup_vm.sh
./setup_vm.sh
```
Powershell:
```Powershell
git clone https://github.com/S4M73l09/Gcloud-Scripts.git
cd Gcloud-Scripts
./setup_vm.ps1 -test #to execute the test type  
./setup_vm.ps1 #Normal execution  
```
CMD:  
This repository is prepared so that you can run the script in Windows using CMD directly using a wrapper, you just have to run it and the wrapper will be in charge of launching the .ps1 script.

***setup_vm.cmd***  
***setup_vm.cmd -test***  *to execute the test type*  

### 🔧 Internal Workflow

1. Checks dependencies **(gcloud, terraform).**
2. Handles GCP login and ADC configuration.
3. Requests deployment details **(project, region, machine type, OS, etc.).**
4. Creates a remote bucket for Terraform state.
5. Creates and configures a Service Account.
6. Generates Terraform files in the chosen folder.
7. Runs terraform init, plan, and apply.
8. Displays the VM’s IP and connection instructions.
9. Outputs the full path to your Terraform folder.

🧠 What gets created

- A secure Service Account (terraform-sa)  
- A GCS bucket (for remote Terraform state)  
- Minimum permissions:  
    - SA --> *roles/storage.objectAdmin* in the status bucket  
    - User --> *roles/iam.serviceAccountTokenCreator* about the SA  
- Dedicated VPC (without auto-subnets), subnet, firewall and VM with public IP.  
- OS Login enabled on Linux for IAM audited SSH.  

🖥 ️ Choose Operating System  
During execution, you will be allowed to choose OS  

# 🚀 setup_vm.ps1 — Terraform Deployment Automator for GCP

This PowerShell script automates the entire virtual machine deployment lifecycle on **Google Cloud Platform (GCP)** using **Terraform**, with full environment control and support for both **interactive** and **CI/CD** execution.

---

## 🧩 Main Features

- **Automatic generation** of Terraform files (`backend.tf`, `providers.tf`, `network.tf`, `vm.tf`, `outputs.tf`).
- **Dual support**: 🐧 **Linux** and 🪟 **Windows Server**.
- **Interactive selection** if parameters are missing:
  - Operating System (Ubuntu, Debian, Windows Server 2019/2022)
  - Machine Type (predefined list or custom)
  - Minimum disk size (10 GB for Linux / 64 GB for Windows)
- **Separated environments by OS**:
  - Linux → `./Linux-terraform/`
  - Windows → `./Windows-terraform/`
- **Prefixed and isolated Terraform files**:
  - File names: `L...` or `W...`
  - Backend prefix in GCS: `env/linux` or `env/windows`
- **Clean test mode (`-Test`)**:
  - Creates a temporary working folder in `%TEMP%`
  - Validates APIs, bucket, and Service Account **without applying** infrastructure
  - Automatically deletes the temporary folder at the end
- **Compatible with PowerShell 5.1 and 7+**
- **CI/CD ready** (GitHub Actions, Azure DevOps, etc.)

---

## ⚙️ Usage Examples

### 🧪 1. Test Mode (validation only)
```powershell
pwsh ./setup_vm.ps1 -ProjectId "my-project" -Region "europe-west1" -Zone "europe-west1-b" -Test
```
### 🧭 2. Interactive Mode (no parameters)
```powershell
pwsh ./setup_vm.ps1
```  

👉 The script will display menus:

Select operating system:  
  [1] Ubuntu 22.04 LTS  
  [2] Debian 12  
  [3] Windows Server 2022  
  [4] Windows Server 2019  
Selection (1-4):  

Select machine type (or 'C' for custom):  
  [1] e2-micro  
  [2] e2-small  
  [3] e2-medium  
  ...  
Once selected, the script automatically generates and deploys the Terraform infrastructure.  

### ⚡ 3. Automated (CI/CD) Mode
```powershell
pwsh ./setup_vm.ps1 `
  -ProjectId "my-project" `
  -Region "europe-southwest1" `
  -Zone "europe-southwest1-a" `
  -OsType linux `
  -MachineType e2-medium `
  -OsDiskGb 20 `
  -AutoApprove
```  
💡 Perfect for GitHub Actions or Azure DevOps pipelines.  

### wrapper **setup_vm.cmd**  

In this repository, a .cmd wrapper is created that is responsible for calling the main script if we use CMD instead of Powershell, faster and without having to touch the console.

## 🗂️ Folder Structure (Environment Naming)

The script now creates **separate folders inside `./terraform/`** depending on the selected operating system and the custom environment name you provide.

- 🪟 **Windows** → `./terraform/PW-windows-<suffix>`
- 🐧 **Linux** → `./terraform/Linux-<suffix>`

### Example

If you run:
```powershell
pwsh ./setup_vm.ps1 -ProjectId "my-project" -Region "europe-west1" -Zone "europe-west1-b"
```
The script will prompt:  
**Enter environment name (suffix only, e.g. "prod", "web", "lab"):**  

Then, if you chose:  

 * OS → Windows Server 2022  

 * Suffix → prod  

It will create:
```markdown
terraform/
└── PW-windows-prod/
    ├── backend.tf
    ├── providers.tf
    ├── network.tf
    ├── vm.tf
    └── outputs.tf
```
If you chose Linux (Ubuntu or Debian) with suffix “monitoring”:  
```markdown
terraform/
└── Linux-monitoring/
    ├── backend.tf
    ├── providers.tf
    ├── network.tf
    ├── vm.tf
    └── outputs.tf
```  
Each environment folder is completely independent, allowing you to deploy multiple configurations (e.g., Linux + Windows) safely without file conflicts.

💡 The environment name suffix can also be passed directly as a parameter:

```powershell
pwsh ./setup_vm.ps1 -ProjectId "my-project" -Region "europe-west1" -Zone "europe-west1-b" -OsType linux -EnvNameSuffix "backend"
```  
This will skip the prompt and create:
```switf
terraform/Linux-backend/
```
# ⚙️ setup_vm.sh — GCP Infrastructure Automation with Bash + Terraform

🧭 Overview

This Bash script automates the deployment of virtual machines in Google Cloud Platform (GCP) using Terraform.
It’s a compact and portable version of your original PowerShell script — fully interactive, safe, and CI/CD-ready.

The script can run in interactive mode (prompting for inputs step-by-step) or non-interactive mode using CLI arguments **(--flags).**

### 🚀 Main Features
```markdown
|  #  | Feature                             | Description                                                                     | Status |
| :-: | :---------------------------------- | :------------------------------------------------------------------------------ | :----: |
|  1  | **Interactive Menu**                | Asks for inputs step-by-step when no arguments are provided.                    |    ✅   |
|  2  | **Multi-OS Support**                | Supports Ubuntu 22.04, Debian 12, Windows Server 2022 & 2019.                   |    ✅   |
|  3  | **Terraform Folder Creation**       | Generates organized subfolders inside `terraform/` based on OS type.            |    ✅   |
|  4  | **Custom Folder Names**             | Prompts you for a subfolder name (e.g. `demo`, `clientA`) or uses a timestamp.  |    ✅   |
|  5  | **`--no-prompt` Mode**              | Runs silently using defaults or provided flags (ideal for CI/CD).               |    ✅   |
|  6  | **`--test` Mode**                   | Simulates execution in `/tmp` with mock `gcloud` and `terraform` calls.         |    ✅   |
|  7  | **Automatic GCP Login**             | Runs `gcloud auth login` and `gcloud auth application-default login` if needed. |    ✅   |
|  8  | **Service Account & Remote Bucket** | Creates a remote bucket (`tf-state-*`) and a Service Account automatically.     |    ✅   |
|  9  | **Cross-Platform**                  | Works on Linux, WSL, and macOS (requires Bash ≥ 4).                             |    ✅   |
|  10 | **Final Summary**                   | Displays VM IP, connection commands, and Terraform folder path.                 |    ✅   |
```  
### 🧠 Interactive Flow (No Arguments)

If you run:
```bash
./setup_vm.sh
```  
The script starts in assistant mode, guiding you step-by-step:

1. Checks for gcloud and terraform installations.

2. Prompts for the basic information:
```less
GCP Project [my-project]:
Region [europe-southwest1]:
Zone [europe-southwest1-a]:
Prefix [lab]:
Machine type (vCPU/RAM) [e2-medium]:
Disk size (GB) [50]:
VPC [lab-vpc]:
Subnet [lab-subnet]:
```  

3. Then displays the colored OS selection menu:
```yaml
Choose OS:
  1) Ubuntu 22.04 LTS
  2) Debian 12
  3) Windows Server 2022
  4) Windows Server 2019
[default: 2] >
```
4. Prompts for the Terraform subfolder name:
```scss
🗂️  Subfolder name (e.g. demo, clientA) [2025-10-20_16-05]:
```  
5. Shows a full summary of your configuration.

6. Runs Terraform (init, plan, apply).

7. Displays the VM’s public IP and the exact folder where files were saved.

### 🗂️ Folder Structure

Depending on your OS and name, the script creates the following structure under **terraform/:**
```css
terraform/
├── bash-windows-clientA/
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
The folder name adjusts automatically based on OS and your chosen subfolder.  

## 🧩 Usage Examples

### 🟢 Interactive Mode
```bash
./setup_vm.sh
```  
Runs the full step-by-step interactive process.  

### ⚙️ Non-Interactive Mode
```bash
./setup_vm.sh \
  --no-prompt \
  --split-os \
  --project-id my-project \
  --region europe-southwest1 \
  --zone europe-southwest1-a \
  --name-prefix demo \
  --machine-type e2-standard-4 \
  --disk-gb 128 \
  --disk-type pd-ssd \
  --network demo-vpc \
  --subnetwork demo-subnet \
  --labels env=prod,owner=me \
  --run-id ci-test
```  
📁 Result:
```arduino
terraform/bash-linux-ci-test/
```  
## 🧪 Test Mode (Safe Simulation)
```bash
./setup_vm.sh --test --split-os --no-prompt \
  --project-id test-proj --region europe-southwest1 --zone europe-southwest1-a
```  
✅ Executes everything under **/tmp/.../work/terraform/**  
✅ Uses mock binaries for gcloud and terraform  
✅ Writes logs to **/tmp/.../logs/**  

## 🧾 Generated Terraform Files
```markdown
| File               | Description                                                 |
| :----------------- | :---------------------------------------------------------- |
| `backend.hcl`      | Configures remote GCS backend and Service Account.          |
| `main.tf`          | Defines network, subnet, firewall, VM, and labels.          |
| `variables.tf`     | Declares input variables (project, region, zone, OS, etc.). |
| `terraform.tfvars` | Stores the actual values from your run.                     |
```  
## ⚡ Available Arguments
```markdown
| Flag                        | Description                                           |
| :-------------------------- | :---------------------------------------------------- |
| `--project-id`              | GCP project ID                                        |
| `--region`, `--zone`        | Deployment region and zone                            |
| `--name-prefix`             | Resource name prefix                                  |
| `--machine-type`            | VM type (e.g., `e2-medium`, `e2-standard-4`)          |
| `--disk-gb`, `--disk-type`  | OS disk size and type (`pd-ssd`, `pd-balanced`, etc.) |
| `--network`, `--subnetwork` | Custom VPC and subnet names                           |
| `--labels`                  | Custom labels (`key=value,key2=value2`)               |
| `--split-os`                | Saves Linux and Windows configs in separate folders   |
| `--no-prompt`               | Runs silently with defaults or flags                  |
| `--run-id`                  | Manual suffix for Terraform folder                    |
| `--test`                    | Simulates execution without touching GCP              |
```  


## 🔌 Connection to the VM

#### 🔑Linux (Ubuntu / Debian)  
The script enables **OS Login**, so you can connect with:  
```bash
gcloud compute ssh <prefijo>-vm --zone <tu-zona>
```  
Or directly from the public IP:  
```bash
ssh <your_user>@<Public_IP>
```  
⚙️ **Requires your user to have the role *roles/compute.osLogin* or similar.**  

#### Windows Server (2022/2019)
Once the VM is created, it generates secure credentials:  
```bash  
gcloud compute reset-windows-password <prefix>-vm --zone <your_zone> --user <admin>
```  
Connection RPD:  
```bash
<PUBLIC_IP>:3389
```
### 💾 Example Final Output
```yaml
[i] Target folder: terraform/bash-windows-clientA
[✓] VM IP: 34.152.77.19
💾 Files saved in: terraform/bash-windows-clientA/
```  

## ✅Test Mode --test  
The script also contains a test mode where you can test how it works and have these files saved in temporary branches.  
The script in *--test* mode shows precisely the temporary address where said files are displayed.  

#### bash  
```bash  
rm -r /tmp/tmp.*  
```  
#### powershell  
```powershell
Remove-Item "$env:TEMP\iac-*" -Recurse -Force
```  
This is responsible for deleting temporary folders created in general.  
If you want to clean it one by one, use the same command but adding the path of the temporary folder you want to delete.  

Likewise, the script is programmed so that after finishing, it automatically deletes these folders.  

## 🧹 Clean up

To destroy Terraform resources:  
```bash
cd terraform
terraform destroy  
```  
and optionally delete the bucket and Service Account:  
```bash  
gcloud storage rm -r gs://<bucket-name>  
gcloud iam service-accounts delete terraform-sa@<project>.iam.gserviceaccount.com  
```  

## 🔐 Security Highlights  
* No JSON keys: ephemeral identity by impersonation and local ADC.    
* State with versioning + lifecycle (purged from old versions).    
* OS Login on Linux → IAM controlled SSH access (auditable).    
* Minimum firewall: only open the port you need (22 or 3389).    
* In production, replace any temporary roles/editor with granular roles (Compute, Network, etc.).   


## 🧩 Future improvements  
* Changes the default machine type (e2-medium) in the script or in terraform.tfvars.    
* Add more image families (e.g. Ubuntu 24.04) by expanding the script menu.    
* Set allowed CIDRs (ssh_cidr_allow, rdp_cidr_allow) in terraform.tfvars.  

## ❓ FAQ   
Do I need GitHub Actions / OIDC?    
No. This repo is intended for local use. You can add CI/CD later if you wish.

Can I use another operating system?  
Yes, add new options in the script menu and its corresponding image.

Where is the state of Terraform?  
In the GCS bucket that creates the script (terraform/backend.hcl defines bucket and prefix).

<p align="center"> Made with ❤️ by <a href="https://github.com/S4M73l09">@S4M73l09</a> </p>
