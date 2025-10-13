<h1 align="center">🚀 GCP Terraform VM Bootstrap</h1>

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
├── setup_local_vm.sh # Main automation script  
├── README.md # You are here  
└── terraform/ # Generated Terraform files  
├── backend.hcl  
├── main.tf  
├── variables.tf  
├── outputs.tf  
└── terraform.tfvar  

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

The script will:

1: Ask for your Google account email.

2: Log in automatically to gcloud.

3: Ask for Project ID, region, zone, and VM type.

4: Create a remote Terraform backend (bucket + Service Account).

5: Generate Terraform configuration files in terraform/.

6: Run terraform init, plan and ask if you want to apply.

🧠 What gets created

- A secure Service Account (terraform-sa)

- A GCS bucket (for remote Terraform state)

- One VPC + subnet

- A firewall rule allowing SSH

- A Debian-based VM with OS Login enabled

🧹 Clean up

When you’re done:

**cd terraform**
**terraform destroy**


and optionally delete the bucket and Service Account:

**gcloud storage rm -r gs://<bucket-name>**
**gcloud iam service-accounts delete terraform-sa@<project>.iam.gserviceaccount.com**

🛡️ Security Highlights

- No static JSON keys: uses short-lived impersonation tokens.

- Remote state stored securely in GCS (versioned + lifecycle).

- OS Login for SSH auditing.

- Optional CMEK (Customer Managed Encryption Key) ready.


🧩 Future improvements

- Add optional GitHub Actions workflow for CI/CD (OIDC auth).

- Include CMEK encryption support for the state bucket.

- Parameterize for multiple environments (dev, stage, prod).
```
<p align="center"> Made with ❤️ by <a href="https://github.com/S4M73l09">@S4M73l09</a> </p>
