# Design Note: Terraform (`terraform/main.tf` and related files) Improvements

## 1. Goal / Problem Statement

### Current State

The `terraform/` directory provisions two Ubuntu 24.04 VMs via the `todoroff/multipass`
Terraform provider (`main.tf`), configures them with `cloud-init.yaml.tftpl`, and
generates an Ansible inventory (`ansible/inventory.ini`) from `inventory.ini.tpl`.

A code review of `main.tf`, `variables.tf`, `terraform.tfvars`,
`cloud-init.yaml.tftpl`, and `inventory.ini.tpl` found three functional bugs that
break passwordless sudo and Ansible connectivity, plus eight design/maintainability
issues affecting portability, safety, and repo hygiene.

Confirmed by direct inspection of the generated artifact
`ansible/inventory.ini`, the bug chain is already manifesting:

```
ansible_python_interpreter=/usr/bin/python
```

`/usr/bin/python` does not exist on Ubuntu 24.04 (only `/usr/bin/python3` is
installed by default), and because `cloud-init.yaml.tftpl` uses the invalid key
`package:` instead of `packages:`, cloud-init silently ignores the requested
`python3` / `python3-apt` install block entirely — so even pointing Ansible at
`/usr/bin/python3` would not help until package installation is fixed too. Ansible's
`gather_facts` / any module invocation against these hosts will fail with a
"python interpreter not found" style error until both issues are fixed together.

Also confirmed: the repository is **not** currently under git version control
(`git rev-parse` / directory scan shows no `.git`), and no `.gitignore` exists.
`terraform.tfstate`, `terraform.tfstate.backup`, and `terraform.tfvars` (containing
a user-specific absolute SSH path,
`/Users/hamaokah87/.ssh/ansible/id_ed25519`) currently sit unprotected in
`terraform/`. Since git is not yet initialized here, this note only *prepares* for
safe use once/if the user decides to `git init` — it does not assume git is already
in play.

### Target State

- Passwordless sudo and package installation work as intended via cloud-init on
  first boot.
- Ansible can connect to and gather facts from both nodes without interpreter
  errors, on Ubuntu 24.04 out of the box.
- Terraform variables carry basic input validation to catch typos early
  (`terraform validate` / `terraform plan` time, not `apply`-time VM failures).
- Provider version pinning strategy is explicit and intentional, not accidental.
- Image version, output paths, and other environment-specific values are no longer
  hardcoded magic values scattered across `main.tf`.
- User-specific secrets/paths are separated from a shareable example file, and a
  path to safe git hygiene (`.gitignore`) is documented for when the user
  git-initializes the project.
- `terraform fmt` is clean.

### Out of Scope

- Actually running `git init` or making the git-hygiene decision for the user —
  this note only prepares the recommended `.gitignore` content and
  `terraform.tfvars.example` split for the user to adopt.
- Migrating to a remote Terraform backend (S3/Terraform Cloud/etc.) — noted as a
  future consideration only, no implementation planned here.
- Changes to `ansible/run_script.yml` or other Ansible-side playbook content.
- Multi-OS / multi-image support beyond making the current image configurable.
- CI/CD pipeline integration for `terraform fmt`/`validate` checks.

---

## 2. Affected Components & Architecture Diagram

### Files in Scope

| File | Role |
|---|---|
| `terraform/main.tf` | Defines provider requirement, `multipass_instance.node` resources, `local_file.ansible_inventory`, and outputs |
| `terraform/variables.tf` | Declares `nodes`, `ssh_public_key_path`, `ssh_private_key_path` |
| `terraform/terraform.tfvars` | Supplies concrete values (currently includes a user-specific absolute path) |
| `terraform/cloud-init.yaml.tftpl` | cloud-init template injected into each VM at boot (`ansible` user creation, sudoers, package install) |
| `terraform/inventory.ini.tpl` | Template rendered into `ansible/inventory.ini` (Ansible connection vars) |
| `terraform/.gitignore` (new) | Not yet present; to be created to protect state/secret files once git is adopted |
| `terraform/terraform.tfvars.example` (new) | Not yet present; sanitized template for `terraform.tfvars` |

### Dependency / Execution Flow (verified from `main.tf`)

```
locals.ssh_public_key
   (reads var.ssh_public_key_path from filesystem, trims whitespace)
        |
        v
multipass_instance.node   <-- for_each over var.nodes (map)
   - name  = each.key
   - image = "24.04"            (hardcoded)
   - cpus/memory/disk = each.value.*
   - cloud_init = templatefile(cloud-init.yaml.tftpl, { ssh_public_key })
        |
        | node.ipv4[0]  (provider must report an IP after boot — implicit dependency)
        v
local_file.ansible_inventory
   - filename = "${path.module}/../ansible/inventory.ini"  (relative, assumes fixed dir layout)
   - content  = templatefile(inventory.ini.tpl, { nodes = {name => ipv4}, ssh_private_key_path })
        |
        v
outputs: "nodes" (ipv4 + state per instance), "inventory_file" (path)
```

Key implicit dependency confirmed by reading the code: `local_file.ansible_inventory`
depends on `multipass_instance.node` only through the `node.ipv4[0]` reference in its
`content` argument — Terraform's implicit dependency graph handles ordering
correctly here (no explicit `depends_on` needed), but this also means **the
inventory file is only regenerated when at least one instance's `ipv4` output
changes**, which is relevant if a future change makes IP assignment lazy or delayed
after boot (multipass typically assigns DHCP addresses quickly, but the provider
does not appear to have an explicit "wait until network ready" attribute in this
config — worth flagging as a fragility risk, not a bug to fix in this note).

No architecture diagram is added beyond the flow above; the change set does not
alter the shape of the pipeline (VMs -> cloud-init -> inventory -> Ansible), only
the correctness and configurability of individual steps.

---

## 3. Proposed Changes & Implementation Plan

Changes are grouped into three phases, ordered by risk/urgency. Priorities:
**High** (breaks core functionality), **Medium** (maintainability/safety gap,
no immediate breakage), **Low** (polish / documentation-only groundwork).

### Phase 1 — Bug Fixes (Priority: High)

| # | Issue | File / Line | Fix |
|---|---|---|---|
| 1 | `NOPASSWOD:ALL` typo | `cloud-init.yaml.tftpl:12` | Change to `NOPASSWD:ALL` so the `ansible` user gets true passwordless sudo, matching the apparent intent (Ansible automation user). |
| 2 | `package:` invalid cloud-init key | `cloud-init.yaml.tftpl:20` | Change to `packages:` (plural) so cloud-init actually installs `python3` and `python3-apt` on first boot. |
| 3 | `/usr/bin/python` wrong interpreter path | `inventory.ini.tpl:9` | Change to `/usr/bin/python3`, matching Ubuntu 24.04's actual layout and the package now correctly installed by fix #2. |

These three are interdependent: fixing #3 alone without #2 still leaves Ansible
pointed at a real path but `python3-apt` (needed for Ansible's `apt` module) would
still be missing if #2 is not also fixed. All three should land together in one
change/commit to avoid a partially-broken intermediate state.

### Phase 2 — Variable / Validation Improvements (Priority: Medium)

| # | Issue | File | Proposed Change |
|---|---|---|---|
| 4 | Hardcoded `image = "24.04"` | `main.tf:22`, `variables.tf` | Introduce `variable "vm_image"` (default `"24.04"`) in `variables.tf`; reference `var.vm_image` in `main.tf`. Keeps current behavior by default while making it overridable per-environment. |
| 5 | Fully pinned provider version `1.7.1` | `main.tf:7` | Decide and document one of: (a) relax to `~> 1.7` to allow patch/minor updates while relying on `.terraform.lock.hcl` (already present, currently pinned to `1.7.1`) for reproducibility, or (b) keep exact pin and add a code comment explaining why (e.g. known regression in later versions). Recommend (a) since `.terraform.lock.hcl` already provides reproducibility; the version constraint should express the *supported range*, not a duplicate exact pin. |
| 9 | No `validation` blocks on `nodes` object fields | `variables.tf` | Add `validation` blocks to the `nodes` variable: `cpus > 0`, and regex checks on `memory`/`disk` (e.g. `can(regex("^[0-9]+[MG]$", var.value))`) to catch typos like `"4g B"` or missing unit suffixes at `terraform plan` time instead of at `multipass` apply-time failure. |
| 10 | `main.tf` not `terraform fmt`-clean | `main.tf` | Run `terraform fmt` across `terraform/` as part of Phase 2 (mechanical, low-risk, but grouped here since it's easiest to review alongside other `main.tf` edits rather than as a silent drive-by in Phase 1's bug-fix commit). |
| 11 | No `sensitive = true` policy for future secret outputs | `main.tf` (outputs), documented in this note | No current output exposes a secret (only `ipv4`, `state`, and the inventory file path are output), so there is nothing to change today. Document as a standing rule: any future output referencing `ssh_private_key_path` or similar must be marked `sensitive = true`. This is a policy note, not a code change in this phase. |

### Phase 3 — State / VCS Hygiene (Priority: Medium-Low; contingent on user's git decision)

| # | Issue | File | Proposed Change |
|---|---|---|---|
| 6 | User-specific absolute path in `terraform.tfvars` | `terraform.tfvars` | Create `terraform.tfvars.example` with placeholder paths (e.g. `~/.ssh/ansible/id_ed25519.pub`) and instructions in a comment header. Keep `terraform.tfvars` as the user's local, real file. |
| 7 | `terraform.tfstate` / `.backup` committed in working dir | `terraform/` | Prepare `terraform/.gitignore` (or repo-root `.gitignore`) covering `*.tfstate`, `*.tfstate.backup`, `.terraform/`, `terraform.tfvars` (real one, not `.example`), and crash logs. **Note:** repository is not currently under git version control — this file can be added now (harmless if unused) but its protective effect only applies once/if the user runs `git init`. Flag remote backend (e.g. Terraform Cloud, S3+DynamoDB) as a future consideration for team/multi-machine use, not implemented here. |
| 8 | Relative output path `${path.module}/../ansible/inventory.ini` | `main.tf:36` | Introduce `variable "ansible_inventory_path"` with a default matching current behavior (`"${path.module}/../ansible/inventory.ini"` computed relative to a sensible root), so the coupling to the fixed `terraform/` + `ansible/` sibling-directory layout becomes explicit and overridable rather than implicit. Alternative considered and rejected for now: making it fully absolute-only, which would reduce portability across clones/checkouts. |

Phase 3 items 6 and 7 are explicitly framed as "prepare, do not force" per the
constraint that git initialization is the user's call.

### Suggested Commit Grouping (Conventional Commits, for `plan-driven-coder` to follow post-approval)

1. `fix(cloud-init): correct sudoers NOPASSWD typo and packages key`
2. `fix(inventory): use python3 interpreter path for Ubuntu 24.04`
3. `refactor(terraform): extract vm_image variable and relax provider version constraint`
4. `feat(terraform): add validation blocks to nodes variable`
5. `style(terraform): apply terraform fmt`
6. `chore(terraform): add terraform.tfvars.example and .gitignore for future git adoption`
7. `refactor(terraform): make ansible inventory output path configurable`

(Fixes 1–2 above could be one commit or two; either grouping is acceptable since
both touch `cloud-init.yaml.tftpl`/`inventory.ini.tpl` and are tightly coupled.)

---

## 4. Risks & Mitigation

| Risk | Related Change | Mitigation |
|---|---|---|
| Existing running VMs (`terraform.tfstate` shows 2 live instances) were provisioned with the broken cloud-init; fixing the template does not retroactively fix already-booted VMs. | Phase 1 | Document in the PR/handoff that `terraform apply` alone will not fix already-created instances (cloud-init runs once on first boot); a `terraform taint`/`destroy -target` + `apply` cycle, or manual `sudo` fix on the running VMs, is required to pick up the corrected cloud-init. This is a operational note for the user, not something the coder agent should do unprompted (destroying running infra needs explicit approval). |
| Relaxing provider version constraint (`~> 1.7`) could pull in a future `todoroff/multipass` release with breaking changes on next `terraform init -upgrade`. | Phase 2, #5 | `.terraform.lock.hcl` still pins the exact resolved version for routine `terraform init`/`plan`/`apply`; only an explicit `-upgrade` changes it. Mitigation: keep the lock file committed (once git is adopted) and note that `-upgrade` should be a deliberate, reviewed action. |
| Adding `validation` blocks to `nodes` could break `terraform plan` for the current `terraform.tfvars` if regex/format assumptions don't match actual values (`cpus = 2`, `memory = "4G"`, `disk = "20G"` — confirmed compatible with a `^[0-9]+[MG]$`-style pattern, but must be tested against the real file). | Phase 2, #9 | Validate the new blocks against the current `terraform.tfvars` values as part of the QA step before merging; do not tighten regex beyond what actually documented multipass memory/disk syntax supports (e.g. confirm whether `Gi`/`Mi` suffixes are ever valid for this provider before finalizing the pattern). |
| Making `image` and `ansible_inventory_path` variables with defaults is a backward-compatible change in principle, but any default value typo would silently change behavior for all existing users of `terraform.tfvars` who don't override it. | Phase 2 #4, Phase 3 #8 | Defaults must exactly match current hardcoded values (`"24.04"` and the current relative path expression) — verified by diffing `terraform plan` output (should show no changes) immediately after the refactor, before any other change is layered on. |
| `terraform.tfvars.example` / `.gitignore` prepared while repo is not under git: risk of the user assuming git hygiene is "handled" when it is not yet active. | Phase 3 | Explicitly call out in the handoff note and PR description that these files have no effect until `git init` + `git add` happen, and that `terraform.tfvars` (real) and `terraform.tfstate*` are NOT currently protected from accidental sharing (e.g. zipping the directory, copying to another machine) until then. |
| cloud-init `packages:` fix depends on the VM having network access to apt repositories at first boot (multipass VM default networking) — not verified in this review since it requires runtime testing, not static code reading. | Phase 1, #2 | Call out as an assumption to verify in Validation & Test Plan (Section 5) rather than treat as guaranteed. |

---

## 5. Validation & Test Plan

Since this is Terraform + cloud-init + Ansible (no unit-testable application
logic, no Rust/clippy/cargo path applies here), validation is primarily
plan/apply-based and manual/integration-style. All steps below are to be run by
`plan-driven-coder`/`qa-test-verifier` after implementation, not during this
design phase.

### T1 — Static / Plan-Time Validation
- **Preconditions:** All Phase 1–2 changes applied.
- **Steps:**
  1. `terraform fmt -check` in `terraform/` — expect no diff after Phase 2 #10 lands.
  2. `terraform validate` — expect success.
  3. `terraform plan` against the existing state — expect **no changes** for the `vm_image` and inventory-path variable extraction (Phase 2 #4, Phase 3 #8), confirming defaults match prior hardcoded values.
- **Expected result:** Clean fmt, valid config, no unintended plan diffs.

### T2 — Variable Validation Behavior
- **Preconditions:** Phase 2 #9 applied.
- **Steps:**
  1. Temporarily set an invalid value (e.g. `memory = "4"` without unit) in a scratch copy of `terraform.tfvars` and run `terraform plan`.
  2. Confirm Terraform rejects it with the custom validation error message, not a downstream `multipass` apply failure.
  3. Revert to the valid original values and confirm `terraform plan` succeeds.
- **Expected result:** Typos caught at plan time with a clear error.

### T3 — Cloud-Init / Ansible Connectivity (integration, requires actual multipass apply)
- **Preconditions:** Phase 1 fixes applied. This likely requires destroying and recreating at least one VM (see Risk table) since cloud-init only runs on first boot.
- **Steps:**
  1. `terraform apply` to (re)create instance(s) with corrected `cloud-init.yaml.tftpl`.
  2. Inspect generated `ansible/inventory.ini` — confirm `ansible_python_interpreter=/usr/bin/python3`.
  3. From the VM console or `multipass shell`, confirm `sudo -n true` succeeds for the `ansible` user (validates `NOPASSWD` fix) without a password prompt.
  4. Confirm `python3` and `python3-apt` are installed (`dpkg -l python3 python3-apt`) (validates `packages:` fix).
  5. Run `ansible -i ansible/inventory.ini ubuntu -m ping` — expect `SUCCESS` from both hosts.
- **Expected result:** Ansible connects and gathers facts without interpreter or privilege errors.

### T4 — Provider Version Relaxation Sanity Check
- **Preconditions:** Phase 2 #5 applied (`~> 1.7` or chosen constraint).
- **Steps:**
  1. `terraform init` (no `-upgrade`) — confirm it still resolves to the version already in `.terraform.lock.hcl` (`1.7.1`, confirmed present in the lock file today).
  2. Confirm no unintended provider upgrade occurs without an explicit `-upgrade` flag.
- **Expected result:** Routine `init` behavior unchanged; only explicit upgrades can move the pinned version.

### T5 — Documentation / Hygiene Files Sanity Check
- **Preconditions:** Phase 3 files created.
- **Steps:**
  1. Confirm `terraform.tfvars.example` contains no real user paths (no `/Users/hamaokah87/...`).
  2. Confirm `.gitignore` patterns match the actual filenames present (`terraform.tfstate`, `terraform.tfstate.backup`, `.terraform/`, real `terraform.tfvars`).
  3. Confirm these additions do not alter `terraform plan`/`apply` behavior (they are non-functional files).
- **Expected result:** Files are correct and inert with respect to Terraform execution; no auth/permission scenarios apply here since this project has no authentication/authorization layer.

**Note on CLAUDE.md's 401/403 test requirement:** this change set has no
authentication or permission-boundary code (it is local infrastructure
provisioning), so no 401/403 test scenarios apply. The closest analogous
"privilege" behavior is the `NOPASSWD` sudoers fix (T3, step 3), which is
covered above as a positive-path check (privilege *should* be granted
passwordlessly for the automation user by design).

---

**Next step:** Await explicit approval of this design (and confirmation of the
Phase 2 #5 provider-version-constraint choice, and the Phase 3 #8 default path
computation) before handing off to `plan-driven-coder`.
