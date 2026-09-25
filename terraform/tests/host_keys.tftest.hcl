# Plan/apply the configuration against mocked providers so that no VM is
# created and no local file is written. Verifies how the downloaded SSH host
# public keys are turned into known_hosts entries and inventory SSH options.

mock_provider "multipass" {}
mock_provider "local" {}

variables {
  nodes = {
    ubuntu1 = { cpus = 1, memory = "1G", disk = "5G" }
    ubuntu2 = { cpus = 1, memory = "1G", disk = "5G" }
  }
  ssh_public_key_path  = "tests/fixtures/user_key.pub"
  ssh_private_key_path = "/tmp/unused_private_key"
}

override_resource {
  target = multipass_instance.node["ubuntu1"]
  values = { ipv4 = ["192.0.2.11"] }
}

override_resource {
  target = multipass_instance.node["ubuntu2"]
  values = { ipv4 = ["192.0.2.12"] }
}

override_data {
  target = data.local_file.host_key["ubuntu1"]
  values = { content = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHostKeyOne root@ubuntu1\n" }
}

override_data {
  target = data.local_file.host_key["ubuntu2"]
  values = { content = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHostKeyTwo root@ubuntu2\n" }
}

run "known_hosts_has_one_pinned_key_per_node" {
  command = apply

  assert {
    condition = local_file.ansible_known_hosts.content == join("", [
      "192.0.2.11 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHostKeyOne\n",
      "192.0.2.12 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHostKeyTwo\n",
    ])
    error_message = "known_hosts must contain exactly one '<ip> <type> <base64>' line per node, without the key comment."
  }

  assert {
    condition     = multipass_file_download.host_key["ubuntu1"].source == "/etc/ssh/ssh_host_ed25519_key.pub"
    error_message = "Only the public ed25519 host key must be downloaded from the VM."
  }
}

run "inventory_enforces_strict_host_key_checking" {
  command = apply

  assert {
    condition     = strcontains(local_file.ansible_inventory.content, "-o StrictHostKeyChecking=yes")
    error_message = "Inventory must enable StrictHostKeyChecking=yes."
  }

  assert {
    condition = strcontains(
      local_file.ansible_inventory.content,
      "-o UserKnownHostsFile=\"${abspath(local_file.ansible_known_hosts.filename)}\""
    )
    error_message = "Inventory must point UserKnownHostsFile at the absolute path of the generated known_hosts."
  }

  assert {
    condition     = startswith(abspath(local_file.ansible_known_hosts.filename), "/")
    error_message = "UserKnownHostsFile path must be absolute."
  }
}

run "malformed_host_key_fails_precondition" {
  command = plan

  override_data {
    target = data.local_file.host_key["ubuntu2"]
    values = { content = "-----BEGIN OPENSSH PRIVATE KEY-----\n" }
  }

  expect_failures = [local_file.ansible_known_hosts]
}
