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
📦 Gcloud-Scripts  
├── setup_vm.sh - Main automation script  
├── README.md # You are here  
├── README.ES.md  
└── terraform/ # Generated Terraform files  
├── backend.hcl  
├── main.tf  
├── variables.tf  
├── outputs.tf  
└── terraform.tfvar  
└── Readme.md

---

## ⚙️ Requirements
Before running:
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)
- [Terraform](https://developer.hashicorp.com/terraform/downloads)
- A Google Cloud project with billing enabled.

---

## 🚀 Usage
Clone and run the script:
```bash
git clone https://github.com/S4M73l09/Gcloud-Scripts.git
cd Gcloud-Scripts
chmod +x setup_vm.sh
./setup_vm.sh
```
The script will:

1: Your google email in Gcloud.  
2: Project ID, region and zone.    
3: Name prefix and VM size/type.  
4: Operating System (interactive menu).  
5: Confirmation for apply.  

🧠 What gets created

- A secure Service Account (terraform-sa)  
- A GCS bucket (for remote Terraform state)  
- Minimum permissions:  
    - SA --> *roles/storage.objectAdmin* in the status bucket  
    - User --> *roles/iam.serviceAccountTokenCreator* about the SA  
- Dedicated VPC (without auto-subnets), subnet, firewall and VM with public IP.  
- OS Login enabled on Linux for IAM audited SSH.  

🖥 ️ Choose Operating System  
During execution, you will see a menu like:  

* Ubuntu 22.04 LTS  
  *projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts*

* Debian 12  
  *projects/debian-cloud/global/images/family/debian-12*

* Windows Server 2022  
  *projects/windows-cloud/global/images/family/windows-2022*

* Windows Server 2019  
  *projects/windows-cloud/global/images/family/windows-2019*

The script automatically adjusts:

Firewall:

*--test* Mode.

Linux → Open SSH (22/tcp) and label SSH.

Windows → Open RDP (3389/tcp) and label RDP.

Disk: if you choose Windows and put less than 64 GB, go up to 64 GB (recommended for convenience).

Metadata: on Linux activate *enable-oslogin=TRUE.*

## 🔌 Connection to the VM

### 🔑Linux (Ubuntu / Debian)  
The script enables **OS Login**, so you can connect with:  
```bash
gcloud compute ssh <prefijo>-vm --zone <tu-zona>
```  
Or directly from the public IP:  
```bash
ssh <your_user>@<Public_IP>
```  
⚙️ **Requires your user to have the role *roles/compute.osLogin* or similar.**  

### Windows Server (2022/2019)
Once the VM is created, it generates secure credentials:  
```bash  
gcloud compute reset-windows-password <prefix>-vm --zone <your_zone> --user <admin>
```  
Connection RPD:  
```bash
<PUBLIC_IP>:3389
```

## ✅Test Mode --test  
The script also contains a test mode where you can test how it works and have these files saved in temporary branches.  
The script in *--test* mode shows precisely the temporary address where said files are displayed.  
```bash  
rm -r /tmp/tmp.*  
```  
This is responsible for deleting temporary folders created in general.  
If you want to clean it one by one, use the same command but adding the path of the temporary folder you want to delete.  

🧹 Clean up

To destroy Terraform resources:  
```bash
cd terraform
terraform destroy  
```

and optionally delete the bucket and Service Account:  
```bash  
**gcloud storage rm -r gs://<bucket-name>**  
**gcloud iam service-accounts delete terraform-sa@<project>.iam.gserviceaccount.com**  
```  

🔐 Security Highlights  
* No JSON keys: ephemeral identity by impersonation and local ADC.    
* State with versioning + lifecycle (purged from old versions).    
* OS Login on Linux → IAM controlled SSH access (auditable).    
* Minimum firewall: only open the port you need (22 or 3389).    
* In production, replace any temporary roles/editor with granular roles (Compute, Network, etc.).   


🧩 Future improvements  
* Changes the default machine type (e2-medium) in the script or in terraform.tfvars.    
* Add more image families (e.g. Ubuntu 24.04) by expanding the script menu.    
* Set allowed CIDRs (ssh_cidr_allow, rdp_cidr_allow) in terraform.tfvars.  

❓ FAQ   
Do I need GitHub Actions / OIDC?    
No. This repo is intended for local use. You can add CI/CD later if you wish.

Can I use another operating system?  
Yes, add new options in the script menu and its corresponding image.

Where is the state of Terraform?  
In the GCS bucket that creates the script (terraform/backend.hcl defines bucket and prefix).

<p align="center"> Made with ❤️ by <a href="https://github.com/S4M73l09">@S4M73l09</a> </p>
