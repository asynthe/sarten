terraform {
  required_version = ">= 1.8"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.70"
    }
    sops = {
      source  = "carlpett/sops"
      version = ">= 1.0"
    }
  }
}

data "sops_file" "secrets" {
  source_file = "${path.module}/../ansible/group_vars/all.sops.yaml"
}

locals {
  secrets = yamldecode(data.sops_file.secrets.raw)
}

provider "proxmox" {
  endpoint  = var.endpoint
  api_token = data.sops_file.secrets.data["proxmox_api_token"]
  insecure  = true

  ssh {
    username    = "root"
    private_key = file(pathexpand(var.ssh_private_key))
  }
}
