terraform {
  required_version = ">= 1.3.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

# ─────────────────────────────────────────────
# Provider
# ─────────────────────────────────────────────

# for provider configuration samples look inside terraform.tfvars.example,
# and uncomment  the configuration values -> variables mappings below
provider "oci" {
  # tenancy_ocid     = var.tenancy_ocid
  # user_ocid        = var.user_ocid
  # fingerprint      = var.fingerprint
  # private_key_path = pathexpand(var.private_key_path)
  # region           = var.region
  config_file_profile = var.oci_profile
  region              = var.region
}

# ─────────────────────────────────────────────
# Lookup: Latest Ubuntu 22.04 image (x86-64)
# AmneziaVPN requires Ubuntu 22.04/24.04 and
# explicitly does NOT support ARM — so we pin
# to x86_64 here.
# ─────────────────────────────────────────────

data "oci_core_images" "ubuntu_22_04" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"

  filter {
    name   = "display_name"
    values = [".*aarch64.*"]
    regex  = true
    # Invert: exclude ARM images
    # OCI provider doesn't support "not" filter, so we
    # pick the first result and verify in outputs.
  }
}

# Simpler alternative — directly filter x86_64 images
data "oci_core_images" "ubuntu_22_04_x86" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  # Pick the most recent image that is NOT aarch64
  ubuntu_image_id = [
    for img in data.oci_core_images.ubuntu_22_04_x86.images :
    img.id
    if !can(regex("aarch64", img.display_name))
  ][0]
}

# ─────────────────────────────────────────────
# Networking: VCN
# ─────────────────────────────────────────────

resource "oci_core_vcn" "main" {
  compartment_id = var.tenancy_ocid
  cidr_block     = var.vcn_cidr
  display_name   = "${var.prefix}-vcn"
  dns_label      = "${var.prefix}vcn"
}

# ─────────────────────────────────────────────
# Networking: Internet Gateway
# ─────────────────────────────────────────────

resource "oci_core_internet_gateway" "main" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-igw"
  enabled        = true
}

# ─────────────────────────────────────────────
# Networking: Route Table (send all traffic via IGW)
# ─────────────────────────────────────────────

resource "oci_core_route_table" "main" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

# ─────────────────────────────────────────────
# Networking: Security List
# Opens only what AmneziaVPN needs.
# ─────────────────────────────────────────────

resource "oci_core_security_list" "amnezia" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-security-list"

  # ── Ingress rules ──────────────────────────

  # SSH — required for AmneziaVPN to install itself
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "SSH"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # AmneziaWG (WireGuard-based, default protocol)
  ingress_security_rules {
    protocol    = "17" # UDP
    source      = "0.0.0.0/0"
    description = "AmneziaWG / WireGuard"
    udp_options {
      min = 51820
      max = 51820
    }
  }

  # OpenVPN over UDP
  ingress_security_rules {
    protocol    = "17" # UDP
    source      = "0.0.0.0/0"
    description = "OpenVPN UDP"
    udp_options {
      min = 1194
      max = 1194
    }
  }

  # OpenVPN over TCP (bypass port blocks)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "OpenVPN TCP"
    tcp_options {
      min = 1194
      max = 1194
    }
  }

  # HTTPS — used by some Amnezia protocols (e.g. XRay, VLESS)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "HTTPS TCP"
    tcp_options {
      min = 443
      max = 443
    }
  }

  ingress_security_rules {
    protocol    = "17" # UDP
    source      = "0.0.0.0/0"
    description = "HTTPS UDP (QUIC)"
    udp_options {
      min = 443
      max = 443
    }
  }

  # HTTP — optional fallback
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "HTTP TCP"
    tcp_options {
      min = 80
      max = 80
    }
  }

  # ICMP — allows ping, useful for debugging
  ingress_security_rules {
    protocol    = "1" # ICMP
    source      = "0.0.0.0/0"
    description = "ICMP ping"
    icmp_options {
      type = 3
      code = 4
    }
  }

  # ── Egress rules ───────────────────────────
  # Allow all outbound traffic

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Allow all outbound"
  }
}

# ─────────────────────────────────────────────
# Networking: Public Subnet
# ─────────────────────────────────────────────

resource "oci_core_subnet" "public" {
  compartment_id    = var.tenancy_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = var.subnet_cidr
  display_name      = "${var.prefix}-subnet"
  dns_label         = "${var.prefix}sub"
  route_table_id    = oci_core_route_table.main.id
  security_list_ids = [oci_core_security_list.amnezia.id]

  # Public subnet — no NAT gateway needed
  prohibit_public_ip_on_vnic = false
}

# ─────────────────────────────────────────────
# Compute: VM.Standard.E2.1.Micro (Free Tier)
# ─────────────────────────────────────────────

resource "oci_core_instance" "amnezia" {
  compartment_id      = var.tenancy_ocid
  availability_domain = var.availability_domain
  display_name        = "${var.prefix}-server"
  shape               = "VM.Standard.E2.1.Micro"

  source_details {
    source_type             = "image"
    source_id               = local.ubuntu_image_id
    boot_volume_size_in_gbs = 50 # Max free-tier boot volume
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    display_name     = "${var.prefix}-vnic"
    assign_public_ip = true
    hostname_label   = "${var.prefix}-server"
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)

    # cloud-init: ensure Docker is available (Amnezia uses Docker)
    # and that UFW won't block VPN ports on the OS level.
    user_data = base64encode(<<-EOF
      #!/bin/bash
      set -e

      # Update package lists
      apt-get update -y

      # Install Docker (Amnezia installs its services as containers)
      apt-get install -y ca-certificates curl gnupg
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) \
        signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
      apt-get update -y
      apt-get install -y docker-ce docker-ce-cli containerd.io

      # Allow ubuntu user to run Docker without sudo
      usermod -aG docker ubuntu

      # Disable UFW so OCI Security List is the sole firewall
      ufw disable || true

      echo "Bootstrap complete." > /var/log/amnezia-bootstrap.log
    EOF
    )
  }

  # Prevent accidental destroy of the instance
  # Comment this out when you want `terraform destroy` to work freely
  # lifecycle {
  #   prevent_destroy = true
  # }
}

# ─────────────────────────────────────────────
# (Optional) Reserved public IP
# Uncomment if you want a static IP that
# survives destroy + recreate cycles.
# ─────────────────────────────────────────────

# resource "oci_core_public_ip" "amnezia" {
#   compartment_id = var.tenancy_ocid
#   lifetime       = "RESERVED"
#   display_name   = "${var.prefix}-public-ip"
#   private_ip_id  = data.oci_core_private_ips.amnezia_vnic.private_ips[0].id
# }
#
# data "oci_core_vnic_attachments" "amnezia" {
#   compartment_id = var.tenancy_ocid
#   instance_id    = oci_core_instance.amnezia.id
# }
#
# data "oci_core_private_ips" "amnezia_vnic" {
#   vnic_id = data.oci_core_vnic_attachments.amnezia.vnic_attachments[0].vnic_id
# }
