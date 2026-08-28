variable "nodes" {
  description = "Worker node multipass VM settings"
  type = map(object({
    cpus   = number
    memory = string
    disk   = string
  }))

  validation {
    condition     = alltrue([for n in values(var.nodes) : n.cpus > 0])
    error_message = "Each node's cpus must be greater than 0."
  }

  validation {
    condition     = alltrue([for n in values(var.nodes) : can(regex("^[0-9]+[MG]$", n.memory))])
    error_message = "Each node's memory must match the pattern <number><M|G>, e.g. \"4G\"."
  }

  validation {
    condition     = alltrue([for n in values(var.nodes) : can(regex("^[0-9]+[MG]$", n.disk))])
    error_message = "Each node's disk must match the pattern <number><M|G>, e.g. \"20G\"."
  }
}

variable "ssh_public_key_path" {
  description = "SSH public key for Ansible connection"
  type        = string
  default = "value"
}

variable "ssh_private_key_path" {
  description = "SSH private key for Ansible connection"
  type        = string
  default = "value"
}

variable "vm_image" {
  description = "Multipass image to use for provisioned nodes"
  type        = string
  default     = "24.04"
}

variable "ansible_inventory_path" {
  description = "Output path for the generated Ansible inventory file"
  type        = string
  default     = "../ansible/inventory.ini"
}