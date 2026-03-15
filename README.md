# AmneziaVPN on OCI Free Tier — Terraform

Provisions a **VM.Standard.E2.1.Micro** (Always Free) instance on Oracle Cloud
ready to run [AmneziaVPN](https://amnezia.org) in self-hosted mode.

## What gets created

| Resource | Details |
|---|---|
| VCN | `10.0.0.0/16` |
| Internet Gateway | Attached to VCN |
| Route Table | Default route → IGW |
| Security List | SSH 22, AmneziaWG 51820+35218/UDP, OpenVPN 1194 TCP+UDP, HTTPS 443 TCP+UDP, HTTP 80 |
| Public Subnet | `10.0.1.0/24` |
| Compute Instance | VM.Standard.E2.1.Micro · Ubuntu 22.04 x86-64 · 50 GB boot volume |

---

## Prerequisites

### 1. Terraform CLI

Install [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.3.

### 2. OCI CLI

**macOS**
```bash
brew install oci-cli
```

**Linux**
```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
exec -l $SHELL
```

**Windows (PowerShell as Admin)**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command `
  "iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.ps1'))"
```

Verify:
```bash
oci --version
```

### 3. Configure OCI CLI

Run the guided setup wizard — it generates your API key pair and config file:
```bash
oci setup config
```

You'll be prompted for:
- **User OCID** — OCI Console → top-right avatar → My Profile → copy OCID
- **Tenancy OCID** — top-right avatar → Tenancy: `<n>` → copy OCID
- **Region** — e.g. `eu-amsterdam-1`
- Accept defaults for key location and name
- Leave passphrase empty (simpler for Terraform)

Then upload your public key to OCI:
1. Console → My Profile → **API Keys** → **Add API Key**
2. Select **Paste a public key**
3. Paste the contents of `~/.oci/oci_api_key_public.pem`
4. Click **Add**

Verify the CLI works:
```bash
oci iam region list
```

### 4. SSH key pair

AmneziaVPN requires either a PEM-format RSA key or an ed25519 key. Generate an ed25519 key:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/amnezia_ed25519 -N ""
```

---

## Filling in terraform.tfvars

Copy the example and fill in your values:
```bash
cp terraform.tfvars.example terraform.tfvars
```

All values can be retrieved from the CLI:
```bash
# tenancy_ocid, user_ocid, fingerprint, private_key_path, region:
cat ~/.oci/config

# availability_domain:
oci iam availability-domain list \
  --query "data[*].name" --output table
```

> **Important:** use the absolute path for `private_key_path` — do not use `~`.
> Run `realpath ~/.oci/oci_api_key.pem` to get it.

---

## Checking and cleaning up existing OCI resources

OCI free tier has a limit of 2 VCNs. If your account already has one from the
initial setup, Terraform will fail with a `LimitExceeded` error. Check and clean
up existing resources before applying.

Set up a shell variable for convenience:
```bash
export T=$(grep tenancy ~/.oci/config | cut -d'=' -f2 | tr -d ' ')
```

### Check existing resources

```bash
# Instances
oci compute instance list --compartment-id $T \
  --query "data[*].{name:\"display-name\", id:id, status:\"lifecycle-state\"}" \
  --output table

# VCNs
oci network vcn list --compartment-id $T \
  --query "data[*].{name:\"display-name\", id:id}" --output table

# Subnets
oci network subnet list --compartment-id $T \
  --query "data[*].{name:\"display-name\", id:id}" --output table

# Internet Gateways
oci network internet-gateway list --compartment-id $T \
  --query "data[*].{name:\"display-name\", id:id}" --output table
```

### Delete in reverse dependency order

Resources must be deleted children-first. Replace `*_OCID` with actual values from the list commands above.

```bash
# 1. Terminate instances
oci compute instance terminate --instance-id INSTANCE_OCID --preserve-boot-volume false --force

# 2. Delete subnets
oci network subnet delete --subnet-id SUBNET_OCID --force

# 3. Clear route rules before deleting the internet gateway
oci network route-table update --rt-id RT_OCID --route-rules '[]' --force

# 4. Delete internet gateway
oci network internet-gateway delete --ig-id IGW_OCID --force

# 5. Delete VCN (cascades default route table, security list, DHCP options)
oci network vcn delete --vcn-id VCN_OCID --force
```

---

## Quick start

```bash
terraform init
terraform plan
terraform apply
```

After apply, note the outputs:
```
instance_public_ip = "x.x.x.x"
ssh_command        = "ssh ubuntu@x.x.x.x"
```

---

## Installing AmneziaVPN

1. Download the [AmneziaVPN client](https://amnezia.org/en/downloads)
2. Click **+** → **Self-hosted VPN**
3. Enter:
   - **IP**: `instance_public_ip` from Terraform output
   - **Port**: `22`
   - **Username**: `ubuntu`
   - **Auth**: your SSH private key (`~/.ssh/amnezia_ed25519`)
4. Choose **Automatic** install — AmneziaVPN installs Docker and configures itself

> Wait ~1 minute after `terraform apply` before connecting — the instance needs
> to finish booting.


---

## Teardown

```bash
terraform destroy
```

Removes all provisioned resources.

---

## Notes

- **Do not use VM.Standard.A1.Flex** — it is ARM/aarch64 and AmneziaVPN does not support ARM.
- **Do not use RSA keys in OpenSSH format** — AmneziaVPN only supports PEM-format RSA or ed25519 keys.
- UFW is disabled on the instance; the OCI Security List is the sole firewall.
- `terraform.tfvars` contains secrets — it is gitignored, never commit it.

## .gitignore

```
terraform.tfvars
.terraform/
*.tfstate
*.tfstate.backup
.terraform.lock.hcl
```

---

## Disclaimer

This project is an independent, community-maintained Terraform module. It is not affiliated with, endorsed by, or officially supported by:

- **AmneziaVPN** / the amnezia-vpn project
- **Oracle Corporation** or Oracle Cloud Infrastructure
- **HashiCorp** or the Terraform project

AmneziaVPN is licensed under [GPL-3.0](https://github.com/amnezia-vpn/amnezia-client/blob/dev/LICENSE). This Terraform module contains no AmneziaVPN source code and is published independently under the [MIT License](LICENSE).

This module is provided **as-is, without warranty of any kind**. You are solely responsible for any cloud costs, security configuration, and legal compliance in your jurisdiction. Always review the code before applying infrastructure changes to your account.
