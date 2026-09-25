terraform {
  required_version = ">= 1.6.0"

  required_providers {
    multipass = {
      source  = "todoroff/multipass"
      version = "~> 1.7"
    }
  }
}

locals {
  ssh_public_key_raw = trimspace(
    file(pathexpand(var.ssh_public_key_path))
  )

  # Matches "<type> <base64>" at the start of an OpenSSH public key line,
  # covering the standard key types plus FIDO2/U2F "sk-" variants. Anything
  # after the base64 field (the free-form comment) is intentionally ignored.
  ssh_public_key_regex = "^(ssh-[a-z0-9-]+|ecdsa-sha2-[a-z0-9-]+|sk-[a-z0-9-]+@openssh\\.com) +([A-Za-z0-9+/=]+)"

  # try() avoids a hard crash here so the check block below can report a
  # clear, actionable error instead of a raw regex failure.
  ssh_public_key_match = try(regex(local.ssh_public_key_regex, local.ssh_public_key_raw), null)

  # Reconstruct the key as "<type> <base64>" only, dropping the comment.
  # OpenSSH ignores the comment for authentication, and it is the primary
  # source of unpredictable, user-edited content, so it is intentionally not
  # carried into the rendered cloud-init document. yamlencode() below would
  # already safely escape any comment content, but stripping it removes the
  # highest-risk portion of the string as defense in depth.
  ssh_public_key = local.ssh_public_key_match == null ? "" : "${local.ssh_public_key_match[0]} ${local.ssh_public_key_match[1]}"

  # Cloud-init document for each node, built as an HCL structure so that
  # yamlencode() produces well-formed YAML regardless of the content of
  # ssh_public_key. This replaces the former cloud-init.yaml.tftpl.
  cloud_init_config = {
    users = [
      "default",
      {
        name        = "ansible"
        gecos       = "Ansible user"
        shell       = "/bin/bash"
        groups      = ["sudo"]
        sudo        = ["ALL=(ALL) NOPASSWD:ALL"]
        lock_passwd = true
        ssh_authorized_keys = [
          local.ssh_public_key
        ]
      }
    ]

    ssh_pwauth   = false
    disable_root = true

    packages = [
      "python3",
      "python3-apt"
    ]
  }
}

resource "multipass_instance" "node" {
  for_each = var.nodes

  name   = each.key
  image  = var.vm_image
  cpus   = each.value.cpus
  memory = each.value.memory
  disk   = each.value.disk

  # #cloud-config is prepended literally since yamlencode() only emits the
  # YAML body, not the leading marker cloud-init requires.
  cloud_init = "#cloud-config\n${yamlencode(local.cloud_init_config)}"

  lifecycle {
    precondition {
      # Validates that the file at var.ssh_public_key_path actually contains
      # an OpenSSH public key, since yamlencode() only guarantees
      # syntactically valid YAML, not syntactically valid key content (e.g. a
      # typo'd path pointing at a private key or an empty file). Unlike a
      # `check` block (advisory-only: prints a warning but lets plan/apply
      # succeed), a lifecycle precondition hard-fails plan/apply, which is
      # required here since a passing apply with an empty
      # ssh_authorized_keys entry would silently create an unreachable VM.
      condition     = local.ssh_public_key_match != null
      error_message = "The SSH public key at var.ssh_public_key_path (\"${var.ssh_public_key_path}\") does not look like a valid OpenSSH public key. Expected format: \"<type> <base64> [comment]\", e.g. \"ssh-ed25519 AAAA... user@host\". Check that the path points at a public key file (not a private key) and that it is not empty or corrupted."
    }
  }
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/${var.ansible_inventory_path}"

  content = templatefile(
    "${path.module}/inventory.ini.tpl",
    {
      nodes = {
        for name, node in multipass_instance.node :
        name => node.ipv4[0]
      }

      ssh_private_key_path = var.ssh_private_key_path
    }
  )
}

output "nodes" {
  value = {
    for name, node in multipass_instance.node :
    name => {
      ipv4  = node.ipv4
      state = node.state
    }
  }
}

output "inventory_file" {
  value = local_file.ansible_inventory.filename
}