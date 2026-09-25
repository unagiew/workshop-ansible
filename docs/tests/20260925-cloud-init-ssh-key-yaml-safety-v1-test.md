# QA Verification Report: Cloud-Init SSH Key YAML Safety v1

**Date**: 20260925
**Plan Document**: documents/cloud-init-ssh-key-yaml-safety-design.md
**Plan Version**: v1 (single revision, no version marker in the document)
**Status**: ⚠️ PASSED WITH AN OPEN RISK (design goal not fully met — see Issues Found)

## Test Summary

| Test Name | Type | Status | Notes |
|---|---|---|---|
| Implementation matches design (locals, check block, resource) | Static review | PASS | `terraform/main.tf` implements option 4b exactly as specified: regex-based `key_type`/`key_material` extraction, comment stripped, `yamlencode()` builds the whole cloud-init doc, `#cloud-config` prepended literally, `check "ssh_public_key_format"` block present |
| `cloud-init.yaml.tftpl` fully unreferenced in code | Static grep | PASS | Only hits in `terraform/main.tf` are an explanatory comment; all other hits are in `documents/` (design notes, workshop materials) — pre-existing and out of scope per task instructions |
| `terraform fmt -check -diff` | Tooling | PASS | Exit code 0, no diff |
| `terraform validate` | Tooling | PASS | Exit code 0, "Success! The configuration is valid." |
| Scenario A — valid key, no comment issues | Functional (plan) | PASS | `terraform plan` succeeds, exit 0, no check warning |
| Scenario B — key with YAML-unsafe comment | Functional (plan + console) | PASS | `terraform plan` succeeds, exit 0, no check warning. Verified via `terraform console` that `local.ssh_public_key` reduces to `"ssh-ed25519 AAAA..."` only (comment fully dropped) and the full `yamlencode(local.cloud_init_config)` output is valid, properly quoted YAML |
| Scenario C — malformed/invalid key file | Functional (plan, -detailed-exitcode, plan-file inspection) | **FAIL (design goal not met)** | See detailed findings below — the `check` block does not block `plan` or `apply` |
| No unrelated files touched | `git status` | PASS | Only `terraform/main.tf` (modified), `terraform/cloud-init.yaml.tftpl` (deleted), and the pre-existing untracked design note are present. `terraform.tfvars` and `*.tfstate*` unmodified (verified by timestamp/mtime and git status) |

## Coverage Analysis

Mapped against the design note's own "Validation & Test Plan" (§5, items 1–6):

- Item 1 (precondition rejects malformed key) — covered, and found to be **insufficient** (warning only, not a hard failure)
- Item 2 (comment with a colon accepted, dropped) — covered (Scenario B), PASS
- Item 3 (rendered YAML valid for a comment with every unsafe construct) — covered (Scenario B + `terraform console` inspection of `yamlencode()` output), PASS
- Item 4 (end-to-end `apply` + SSH auth check) — **not run**, per explicit task instruction not to run `terraform apply` against real infrastructure (the local state shows two real running `multipass_instance` resources, `ubuntu1`/`ubuntu2`) — out of scope for this QA pass, flagged as a deferred item
- Item 5 (regression: normal key with typical comment) — covered (Scenario A), PASS
- Item 6 (`fmt`/`validate` clean) — covered, PASS

Normal flows covered: 2/2 (valid key, unsafe-but-parseable comment)
Error flows covered: 1/1 scenario executed, but the *outcome* deviates from the design's stated goal (see below)
Boundary cases covered: empty file and non-key text file both tested, same result as the primary malformed case

## Plan Deviations

- **The design note's own goal is not met by the current implementation.** Design note §1 "Target State" explicitly states: "Invalid/malformed key file content ... is rejected at `terraform plan` time with a clear, actionable error message." The design note's own Implementation Plan step 2 and the `check` block satisfy the *message* half of this requirement but not the *rejection* half — Terraform `check` blocks are advisory only and never fail `plan`/`apply` on their own. This is not a bug introduced by the implementer; it is a known, called-out limitation in the design note's own risk framing (§3, "why a `check` block" section), but the note frames it as satisfying the goal when in fact it does not, under normal (non-CI-parsing) usage. This is a design-level gap, not an implementation defect — the implementer followed the design faithfully.
- No other deviations found; `main.tf` matches the design note's Implementation Plan step-by-step (regex extraction, comment stripping, `check` block wording referencing `var.ssh_public_key_path`, `yamlencode()` of the full document, literal `#cloud-config` prefix).

## Issues Found and Fixed

No code was modified during this QA pass (per the limited fix policy — the gap below is a design-level defect, not a "narrow fix," so no autonomous fix was applied).

### Issue: `check` block does not block `plan` or `apply` on a malformed key

**Root cause**: Terraform `check` blocks (available since 1.5) only ever produce a `Warning` diagnostic; they cannot fail `terraform plan` or `terraform apply`. This is a fundamental property of the `check` block feature, not a misconfiguration.

**Evidence** (using a temporary key file `not-a-valid-key` at a scratch path, `ssh_public_key_path` overridden via `-var`, never touching `terraform.tfvars`):

1. `terraform plan -var="ssh_public_key_path=<malformed file>"`:
   - Exit code: **0**
   - Output includes:
     ```
     ╷
     │ Warning: Check block assertion failed
     │
     │   on main.tf line 69, in check "ssh_public_key_format":
     │   69:     condition     = local.ssh_public_key_match != null
     │     ├────────────────
     │     │ local.ssh_public_key_match is null
     │
     │ The SSH public key at var.ssh_public_key_path ("...") does not look like a
     │ valid OpenSSH public key. Expected format: "<type> <base64> [comment]",
     │ e.g. "ssh-ed25519 AAAA... user@host". Check that the path points at a
     │ public key file (not a private key) and that it is not empty or corrupted.
     ╵
     ```
   - Plan summary still printed normally: `Plan: 3 to add, 0 to change, 3 to destroy.`
2. `terraform plan -detailed-exitcode -var="ssh_public_key_path=<malformed file>"`:
   - Exit code: **2** ("succeeded, non-empty diff")
   - This exit code is **not a signal of the check failure** — it is purely because the plan contains resource changes (which exist regardless of the key's validity, since `cloud_init` differs from the currently-applied state for unrelated reasons in this environment). A `-detailed-exitcode` run against a config with *no other pending changes* but an invalid key would still return **0**, silently passing in CI gates that treat only exit codes 0/2 as "success" and 1 as "failure." Exit code 1 (hard error) is never produced by a `check` block failure alone.
3. Saved a real plan file (`terraform plan -out=malformed.tfplan`) and inspected it with `terraform show -json`: `"errored": false`, with 3 resource changes queued for creation — i.e., **`terraform apply` on this plan file would proceed** and create `multipass_instance` resources whose `ssh_authorized_keys` entry is `[""]` (confirmed via `terraform console`: `local.ssh_public_key` evaluates to `""` when the regex match fails, since the ternary in `main.tf` line 32 falls back to an empty string rather than failing the plan). This produces syntactically valid YAML with a functionally broken (empty) authorized-key entry — exactly the "opaque, later-stage failure" scenario the design note set out to eliminate for malformed keys, and it is not eliminated.
4. Empty key file test produced identical behavior (warning only, `Plan: 3 to add, 0 to change, 3 to destroy.`, exit 0).

**Fix**: Not applied — this is a design-level defect (the design's chosen mechanism, `check`, structurally cannot deliver the stated goal of "rejected at `terraform plan` time"), which exceeds the QA agent's limited fix policy ("narrow status code or error mapping mistakes already implied by the plan" does not cover swapping the validation mechanism). Escalating per the recommendation below.

## Side Effects Verification

- `terraform.tfvars` byte-for-byte unmodified (verified via `git status --porcelain` showing no change and file mtime unchanged across the session).
- `terraform.tfstate` / `terraform.tfstate.backup` unmodified — both are gitignored and their mtimes (2026-09-14) predate this QA session; all `plan`/`console` invocations were read-only against the existing state of two real running `multipass_instance` resources (`ubuntu1`, `ubuntu2`). No `terraform apply` was run at any point.
- All temporary key files and plan files created under the session scratchpad directory were deleted at the end of the session; none were created inside the repository.
- Confirmed via `terraform plan` (Scenario A) that the `cloud_init` attribute forces resource replacement for the two existing real instances — this matches the design note's own risk table (Risk 1), which anticipates and accepts this as expected behavior for the fix to take effect, not a new regression introduced by this QA pass.
- `git status` at the end of the session shows exactly: `deleted: terraform/cloud-init.yaml.tftpl`, `modified: terraform/main.tf`, and the pre-existing untracked design note — no other files touched.

## Completion Declaration

- Static review (design-vs-implementation match), file-reference grep, `terraform fmt`, and `terraform validate` all **PASS**.
- Functional scenarios A (valid key) and B (unsafe comment) **PASS** — `yamlencode()` correctly eliminates the original YAML-injection bug for any comment content, and the comment-stripping defense-in-depth works as designed.
- Functional scenario C (malformed key) **does not meet the design note's stated acceptance goal**. The `check` block runs and emits the correct, actionable warning message, but it is advisory-only: `terraform plan` exits 0 (or 2 under `-detailed-exitcode`, for reasons unrelated to the check), and a saved plan for a malformed key shows `errored: false` with resource changes ready to apply. **`terraform apply` would proceed and create instances with a broken (empty) `ssh_authorized_keys` entry**, which is precisely the class of hard-to-diagnose, later-stage failure the design set out to prevent for malformed key input.
- **Recommendation**: Escalate. Replace or supplement the `check` block with a hard-blocking `precondition` in a `lifecycle` block on `multipass_instance.node` (e.g. `precondition { condition = local.ssh_public_key_match != null; error_message = "..." }`), which does fail `terraform plan`/`apply` with a real error (exit code 1) rather than a warning. The design note itself acknowledges (§3) that a `precondition` on the resource would be the harder-blocking alternative and only chose `check` for independence from resource apply ordering — but independence from apply ordering is not worth sacrificing the stated "fail fast" goal. If keeping the `check` block for its standalone-diagnostic value is desired, it should be kept in addition to, not instead of, a `precondition` that actually blocks `plan`/`apply`. This is a design-level change and should go back through `arch-planner` (or an addendum to the existing design note) before `plan-driven-coder` implements it, per this repo's `CLAUDE.md` workflow.
- End-to-end `apply` + SSH authentication check (design §5 item 4) was intentionally **not executed** in this QA pass per explicit task instructions (no `apply` against the real, running infrastructure) — this remains a deferred validation step for whenever `apply` is run deliberately (e.g., in a disposable environment).
