---
title: "Improve builder/switch to support SSH Agent Forwarding"
labels: ["enhancement", "deployment"]
assignees: ["lamtt77"]
---

**Current Behavior:**
The `make builder/switch` command fails to deploy to the target host (`NIXHOST`) via the remote builder (`BUILDER_HOST`) unless the private key matching the target's `SSHUSER` is physically present on the builder.

**Desired Behavior:**
The deployment process should utilize SSH Agent Forwarding (`-A`). This allows the builder to authenticate with the target using the credentials loaded in the local user's SSH agent, eliminating the need to store private keys on the builder.

**Context:**
- Command: `make builder/switch NIXHOST=avon NIXUSER=nixos SSHUSER=nixos SECRETS=yes NIXADDR=192.168.1.18`
- Deployment path: Local -> Builder -> Target
- `SSH_OPTIONS` currently includes `-A`, but it appears insufficient or ineffective in the current environment.

**Proposed Solution:**
1.  Verify `SSH_AUTH_SOCK` is present in the local environment before starting.
2.  Ensure `SSH_AUTH_SOCK` is correctly forwarded and accessible in the builder's shell environment during the `nix copy` operation.
