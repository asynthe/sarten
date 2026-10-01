variable "endpoint" {
  type    = string
  default = "https://192.168.1.135:8006/"
}

variable "node" {
  type    = string
  default = "sarten"
}

variable "datastore" {
  description = "Where guest disks go; registered by the storage role in ansible."
  type        = string
  default     = "local-btrfs"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "dns_servers" {
  type    = list(string)
  default = ["200.28.4.130", "200.28.1.130"]
}

variable "ssh_private_key" {
  description = "Key tofu uses for the few operations that go over ssh."
  type        = string
  default     = "~/git/auth/ssh/p1"
}

variable "guest_admin" {
  description = "Admin whose ssh keys, from the sops file, go into guests' root."
  type        = string
  default     = "asynthe"
}

variable "containers" {
  description = "LXC guests, keyed by hostname. See containers.tf for the shape."
  type = map(object({
    id       = number
    ip       = string
    template = string
    cores    = optional(number, 2)
    memory   = optional(number, 2048)
    disk     = optional(number, 16)
    tags     = optional(list(string), [])
    notes    = optional(string, "")
  }))
  default = {}
}
