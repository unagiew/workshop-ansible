terraform {
  required_version = ">= 1.6.0"

  required_providers {
    multipass = {
      source  = "todoroff/multipass"
      version = "~> 1.7"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
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

  # Block until cloud-init has finished so that the SSH host keys (read by
  # multipass_file_download.host_key below) and python3 (needed by Ansible)
  # exist before any downstream resource runs.
  wait_for_cloud_init = true

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

# Fetch each VM's SSH host *public* key through Multipass (`multipass
# transfer`). This channel goes through the local multipassd daemon, not SSH,
# so it cannot be intercepted by an SSH man-in-the-middle. The host private
# key never leaves the VM and is never stored in Terraform state.
resource "multipass_file_download" "host_key" {
  for_each = multipass_instance.node

  instance       = each.value.name
  source         = "/etc/ssh/ssh_host_ed25519_key.pub"
  destination    = "${path.module}/.host_keys/${each.key}.ed25519.pub"
  create_parents = true
  overwrite      = true

  lifecycle {
    # A replaced VM has a new host key, so download it again.
    replace_triggered_by = [multipass_instance.node[each.key]]
  }
}

data "local_file" "host_key" {
  for_each = multipass_file_download.host_key

  filename = each.value.destination
}

locals {
  # "<type> <base64>" per node, with the "root@<host>" comment dropped. null
  # marks a file that does not look like an OpenSSH public key; the
  # precondition on local_file.ansible_known_hosts reports it.
  host_public_keys = {
    for name, key_file in data.local_file.host_key :
    name => try(join(" ", regex(local.ssh_public_key_regex, trimspace(key_file.content))), null)
  }
}

resource "local_file" "ansible_known_hosts" {
  filename        = "${path.module}/${var.ansible_known_hosts_path}"
  file_permission = "0644"

  content = join("", [
    for name, node in multipass_instance.node :
    "${node.ipv4[0]} ${local.host_public_keys[name]}\n"
  ])

  lifecycle {
    precondition {
      condition     = alltrue([for key in values(local.host_public_keys) : key != null])
      error_message = "One or more SSH host public keys downloaded to terraform/.host_keys/ are not valid OpenSSH public keys. Re-download them with: terraform apply -replace='multipass_file_download.host_key[\"<node>\"]'"
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

      # Absolute, because OpenSSH resolves UserKnownHostsFile relative to the
      # directory ansible is run from.
      known_hosts_path = abspath(local_file.ansible_known_hosts.filename)
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