# Design Note: Pin VM SSH Host Keys via a Trusted Out-of-Band Channel

## 1. Goal / Problem Statement

### Current State

- Each Multipass VM generates a random SSH host key at first boot
  (cloud-init default).
- `terraform/inventory.ini.tpl` sets no SSH host key options, so OpenSSH
  falls back to `~/.ssh/known_hosts` with `StrictHostKeyChecking=ask`.
- Result:
  - First `ansible` run: the `yes/no/[fingerprint]` prompt appears. With
    several hosts in parallel, the prompts overlap and the run fails or
    hangs.
  - After `terraform destroy` / `apply`, Multipass often reuses the same
    IP with a new host key. Ansible then fails with
    `REMOTE HOST IDENTIFICATION HAS CHANGED`, and the user has to clean up
    `~/.ssh/known_hosts` by hand.
- The workshop materials (003 §9.6, 004 §13) tell attendees to type `yes`.
  Review item #10 in `review_004_ansible.md` flags this as a source of
  confusion.

### Rejected Alternatives

- **`StrictHostKeyChecking=no` / `host_key_checking = False`**: turns off
  host verification completely. This is a poor practice to teach.
- **Generate host keys in Terraform (`tls_private_key`) and inject them via
  cloud-init**: the host private keys would be stored in plaintext in
  `terraform.tfstate` and in the cloud-init user-data. That is acceptable
  for local state only; it is a real exposure once state moves to a remote
  backend (S3/GCS) or the pattern is reused on a cloud provider (user-data
  is readable via the metadata service). Ephemeral resources cannot help,
  because `multipass_instance.cloud_init` is not a write-only attribute.

### Target State

- Host keys are still generated inside each VM. **No private key leaves the
  VM**, and Terraform state holds only public keys.
- Terraform retrieves each VM's ed25519 host **public** key through
  Multipass (`multipass transfer`, via the `todoroff/multipass` provider's
  `multipass_file_download` resource). This channel goes through the local
  `multipassd` daemon, not SSH, so it cannot be intercepted by an SSH
  man-in-the-middle.
- Terraform writes a project-local `ansible/known_hosts` with
  `<ip> ssh-ed25519 <base64>` lines.
- Ansible connects with `StrictHostKeyChecking=yes` against that file only:
  - there is no prompt on first connection;
  - recreating a VM needs no manual cleanup;
  - a host presenting an unexpected key is rejected;
  - `~/.ssh/known_hosts` is never read or modified.
- The same pattern carries over to cloud VMs: replace `multipass transfer`
  with an authenticated provider API, such as AWS console output or GCP
  guest attributes.

## 2. Affected Components

| File | Change |
|---|---|
| `terraform/main.tf` | `wait_for_cloud_init = true`; per-node `multipass_file_download` for `/etc/ssh/ssh_host_ed25519_key.pub`; `data "local_file"` to read it; `local_file` for `known_hosts`; pass the path to the inventory template; declare `hashicorp/local` in `required_providers` |
| `terraform/variables.tf` | New `ansible_known_hosts_path` (default `../ansible/known_hosts`) |
| `terraform/inventory.ini.tpl` | Add `ansible_ssh_common_args` with `StrictHostKeyChecking=yes` and `UserKnownHostsFile` |
| `terraform/.terraform.lock.hcl` | Refreshed only if the explicit `hashicorp/local` constraint changes the selection (expected: no change, 2.9.0) |
| `terraform/tests/host_keys.tftest.hcl` | New `terraform test` with mocked providers |
| `.gitignore` | Ignore `ansible/known_hosts` and `terraform/.host_keys/` |
| `documents/workshop_materials/003_*.md`, `004_*.md`, `README.md` | Sync embedded code and remove the "type `yes`" instructions (via `doc-writer`) |

```
multipass_instance.node[n]  (wait_for_cloud_init = true)
   │  multipassd (trusted local channel, not SSH)
   ▼
multipass_file_download.host_key[n] ─► terraform/.host_keys/<n>.ed25519.pub
   ▼
data.local_file.host_key[n] ─► regex "<type> <base64>" (precondition-validated)
   ▼
local_file.ansible_known_hosts ─► ansible/known_hosts: "<ipv4> ssh-ed25519 AAAA..."
   ▼
inventory.ini: ansible_ssh_common_args='-o StrictHostKeyChecking=yes -o UserKnownHostsFile="<abs path>"'
```

## 3. Proposed Changes & Implementation Plan

1. **Wait for cloud-init** on `multipass_instance.node`:
   `wait_for_cloud_init = true`. This guarantees that the host keys exist,
   and that `python3` is installed, before downstream resources run.
2. **Download the public host key**:
   ```hcl
   resource "multipass_file_download" "host_key" {
     for_each       = multipass_instance.node
     instance       = each.value.name
     source         = "/etc/ssh/ssh_host_ed25519_key.pub"
     destination    = "${path.module}/.host_keys/${each.key}.ed25519.pub"
     create_parents = true
     overwrite      = true

     lifecycle {
       replace_triggered_by = [multipass_instance.node[each.key].id]
     }
   }
   ```
   `replace_triggered_by` re-downloads the key whenever the VM is replaced.
   The instance `id` may equal its name, which stays the same across a
   replacement, so the final choice of trigger attribute will be confirmed
   during implementation.
3. **Read and validate**:
   ```hcl
   data "local_file" "host_key" {
     for_each   = multipass_file_download.host_key
     filename   = each.value.destination
   }
   ```
   Extract `<type> <base64>` with the existing
   `local.ssh_public_key_regex` and drop the `root@host` comment. A
   `lifecycle.precondition` on `local_file.ansible_known_hosts` fails the
   apply with a clear message if any key does not match.
4. **known_hosts**:
   ```hcl
   resource "local_file" "ansible_known_hosts" {
     filename        = "${path.module}/${var.ansible_known_hosts_path}"
     file_permission = "0644"
     content = join("", [
       for name, node in multipass_instance.node :
       "${node.ipv4[0]} ${local.host_public_keys[name]}\n"
     ])
   }
   ```
5. **Inventory**: pass
   `known_hosts_path = abspath(local_file.ansible_known_hosts.filename)`.
   The path must be absolute because OpenSSH resolves `UserKnownHostsFile`
   relative to the current directory:
   ```ini
   ansible_ssh_common_args='-o StrictHostKeyChecking=yes -o UserKnownHostsFile="${known_hosts_path}"'
   ```
6. **`.gitignore`**: add `ansible/known_hosts` and `terraform/.host_keys/`.
7. **Docs** (`doc-writer`):
   - sync the embedded `main.tf`, template, and inventory examples in 003;
   - add a short section explaining the host-key flow and why keys are not
     generated by Terraform (state and user-data exposure);
   - replace the "type `yes`" notes in 003 §9.6 and 004 §13. The manual
     `ssh` example becomes
     `ssh -i ... -o UserKnownHostsFile=ansible/known_hosts ansible@<ip>`;
   - address review item #10.

## 4. Risks & Mitigation

| Risk | Mitigation |
|---|---|
| `multipass_file_download` may contact the VM during refresh, so plan or destroy could fail while a VM is stopped | Verify during implementation (stop a VM, run `plan` and `destroy`). If it fails, fall back to `data "local_command"` or `terraform_data` + `local-exec` and report the deviation before continuing. |
| `wait_for_cloud_init` or the new dependency chain forces the existing VMs to be replaced | Acceptable for disposable VMs. Check with `terraform plan` first, and confirm with the user before `apply`. |
| `data.local_file` fails at plan time if the cached `.pub` file was deleted by hand | Recover with `terraform apply -replace='multipass_file_download.host_key["<n>"]'`. Document this in the troubleshooting section. |
| The image does not produce an ed25519 host key | Ubuntu 24.04 generates one by default. The precondition fails loudly if it is missing. |
| `wait_for_cloud_init` makes `apply` slower | This is intended, since Ansible also needs `python3` from cloud-init. |

## 5. Validation & Test Plan

Automated:
- `terraform fmt -check -recursive` and `terraform validate`.
- `terraform test` (`terraform/tests/host_keys.tftest.hcl`, with
  `mock_provider` for `multipass` and `local`, and `override_data` for the
  key files) asserts that:
  - `known_hosts` has exactly one `<ip> ssh-ed25519 <base64>` line per
    node, with the comment stripped;
  - the inventory contains `StrictHostKeyChecking=yes` and an absolute
    `UserKnownHostsFile` path;
  - a malformed key file makes the precondition fail
    (`expect_failures`).

Manual, on real VMs (after user confirmation):
1. `terraform apply`, then `ansible all -i ansible/inventory.ini -m ansible.builtin.ping`
   succeeds with no prompt, and `~/.ssh/known_hosts` is unchanged.
2. `multipass exec ubuntu1 -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`
   matches `ssh-keygen -lf ansible/known_hosts`.
3. `terraform.tfstate` contains no `PRIVATE KEY` string.
4. Negative case: corrupt one entry in `ansible/known_hosts`. Ansible must
   fail with `Host key verification failed` / `UNREACHABLE`.
5. Recreate case: `terraform apply -replace='multipass_instance.node["ubuntu1"]'`
   (the IP may be reused). Ping must succeed again with no manual cleanup.
6. Stopped-VM case: `multipass stop ubuntu2`, then `terraform plan`
   succeeds (see Risks).
