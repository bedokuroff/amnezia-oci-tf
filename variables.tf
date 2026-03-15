# ─────────────────────────────────────────────
# OCI Authentication
# ─────────────────────────────────────────────

variable "tenancy_ocid" {
  description = "OCID of your OCI tenancy. Found in: Profile → Tenancy."
  type        = string
}

variable "user_ocid" {
  description = "OCID of the OCI user running Terraform. Found in: Profile → My Profile."
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the API signing key. Found in: Profile → API Keys."
  type        = string
}

variable "private_key_path" {
  description = "Path to your OCI API private key file (PEM format)."
  type        = string
  default     = "~/.oci/oci_api_key.pem"
}

variable "region" {
  description = "OCI region to deploy into (e.g. eu-amsterdam-1, us-ashburn-1)."
  type        = string
}

variable "oci_profile" {
  description = "OCI profile name, from oci cli configuration"
  type        = string
  default     = "DEFAULT"
}

# ─────────────────────────────────────────────
# Instance
# ─────────────────────────────────────────────

variable "availability_domain" {
  description = "Availability domain name. Run: oci iam availability-domain list"
  type        = string
  # Example: "Uocm:EU-AMSTERDAM-1-AD-1"
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key. AmneziaVPN uses SSH to install itself on the server."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# ─────────────────────────────────────────────
# Networking
# ─────────────────────────────────────────────

variable "vcn_cidr" {
  description = "CIDR block for the VCN."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

# ─────────────────────────────────────────────
# Tagging
# ─────────────────────────────────────────────

variable "prefix" {
  description = "Prefix used in resource names."
  type        = string
  default     = "amnezia"
}
