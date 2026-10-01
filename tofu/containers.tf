resource "proxmox_virtual_environment_container" "ct" {
  for_each = var.containers

  node_name     = var.node
  vm_id         = each.value.id
  unprivileged  = true
  start_on_boot = true
  tags          = each.value.tags
  description   = each.value.notes

  initialization {
    hostname = each.key

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = each.value.ip == "dhcp" ? null : var.gateway
      }
    }

    user_account {
      keys = local.secrets.ssh_keys[var.guest_admin]
    }
  }

  operating_system {
    template_file_id = each.value.template
    type             = "debian"
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.datastore
    size         = each.value.disk
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge
  }

  features {
    nesting = true
  }

  lifecycle {
    ignore_changes = [mount_point, features]
  }
}
