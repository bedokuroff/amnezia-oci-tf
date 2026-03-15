# ─────────────────────────────────────────────
# Outputs — printed after `terraform apply`
# ─────────────────────────────────────────────

output "instance_public_ip" {
  description = "Public IP address of the AmneziaVPN server. Use this in the AmneziaVPN app."
  value       = oci_core_instance.amnezia.public_ip
}

output "instance_id" {
  description = "OCID of the compute instance."
  value       = oci_core_instance.amnezia.id
}

output "ssh_command" {
  description = "SSH command to connect to the server manually."
  value       = "ssh ubuntu@${oci_core_instance.amnezia.public_ip}"
}

output "ubuntu_image_used" {
  description = "The Ubuntu image ID that was selected (verify it is x86-64, not aarch64)."
  value       = local.ubuntu_image_id
}

output "amnezia_connection_hint" {
  description = "What to enter in the AmneziaVPN app."
  value = {
    server_ip = oci_core_instance.amnezia.public_ip
    ssh_port  = 22
    username  = "ubuntu"
    auth      = "Use your SSH private key (matches the public key in terraform.tfvars)"
  }
}
