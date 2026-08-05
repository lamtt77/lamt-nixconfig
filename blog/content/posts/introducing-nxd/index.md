---
title: "Introducing NXD: Declarative Infrastructure Reconciliation for Nix-Authored State"
date: 2026-08-04T00:00:00Z
draft: false
description: "NixOS makes one machine reproducible. NXD does the same for everything underneath it: hypervisors, private networking, and backups, planned as one dependency graph and applied only against a plan you approved."
tags: ["NixOS", "Nix", "Infrastructure as Code", "Proxmox", "Rust", "DevOps", "Tailscale", "Headscale", "Reconciliation"]
---

NixOS solved the operating system. It did not solve what the operating system runs on.

If you use NixOS, you know the feeling: your machines are described completely in code, rebuildable from scratch, rollback-able in one command. Then you look one layer down — at the hypervisor hosting those machines, the private network connecting them, the server holding their backups — and none of it is described anywhere. It was configured by clicking, and the only record is what you remember.

That was my situation. Perfect reproducibility above the hypervisor, none below it. And the boundary between the two is exactly where my outages came from.

**NXD** is the tool I built to remove that boundary: one Nix-authored description of the whole environment, planned as a single dependency graph, applied only against a plan you approved.

It runs production infrastructure today, including the server this page is served from. It is pre-release and under active development — the [project site](https://nxd.lamhub.com/) and [technical manual](https://nxd.lamhub.com/manual/) have the full picture if you would rather start there.

> **New to Nix?** A few terms below: a **closure** is a fully built system plus everything it depends on. **Evaluating** is working out *what* to build; **realizing** is actually building it. The **Nix store** is where results live, in paths named by a hash of their inputs.

## The pipeline

<ol class="nxd-pipeline">
<li class="nxd-stage">
<h3 class="nxd-stage-title">Evaluate <code>evalConfiguration</code></h3>
<p>Nix modules become a canonical JSON specification. <span class="nxd-stage-note">Offline: no endpoint is contacted and no secret is decrypted, so planning cannot be influenced by the state it plans against.</span></p>
</li>
<li class="nxd-stage">
<h3 class="nxd-stage-title">Plan <code>nxd plan</code></h3>
<p>A dependency-ordered graph across every provider, each action risk-classified. <span class="nxd-stage-note">The plan is persisted to disk and hashed, which turns it into an artifact with an identity.</span></p>
</li>
<li class="nxd-stage">
<h3 class="nxd-stage-title">Approve <code>sha256:4592a2f3…</code></h3>
<p>Applying requires approval of that exact digest. <span class="nxd-stage-note">If anything changed since planning, the digest stops matching and the apply refuses.</span></p>
</li>
<li class="nxd-stage">
<h3 class="nxd-stage-title">Apply and verify <code>nxd verify</code></h3>
<p>Typed Rust providers mutate, then live state is re-read. <span class="nxd-stage-note">Success means <code>desiredSystemPath == activeSystemPath</code>, not a zero exit code.</span></p>
</li>
</ol>

Four properties make this different from a shell script with extra steps.

**Evaluation is offline.** Working out what to do never contacts your infrastructure and never decrypts a secret. A plan cannot be corrupted by the state of the thing it is planning against.

**Plans are artifacts with identities.** A plan is written to disk and hashed. Your approval binds to that hash. If anything changes between reviewing and applying, the hash stops matching and the apply refuses. There is no window where you approve one thing and execute another.

**Risk is visible before you approve.** Every action is classified — from <span class="nxd-risk nxd-risk-read">ReadOnly</span> through <span class="nxd-risk nxd-risk-service">ServiceImpacting</span> to <span class="nxd-risk nxd-risk-identity">IdentityCritical</span>, which touches cryptographic identity like host keys and node registrations. Destructive work is listed first, naming exactly what it touches.

**Verification is empirical.** Success is not "the command exited 0." It is re-reading live state and asserting the machine is running the system you reviewed.

## Ordering across providers is the point

The reason this is one graph rather than four tools is that the dependencies genuinely cross tool boundaries. Bringing up a new host:

1. **Identity** — resolve the host's encrypted SSH key material and pin the expected host key.
2. **Network** — issue an authentication key for the private network. This has to happen *before* the machine boots, because the machine uses it on first start.
3. **Hypervisor** — Proxmox creates the virtual machine, attaches networking, seeds first-boot configuration.
4. **Operating system** — build the reviewed NixOS system, transfer it, activate it.
5. **Verify** — confirm the running system and network membership match what was declared.

Step 2 before step 3 is not a convention someone wrote in a runbook. It is an edge in a graph, and the scheduler enforces it.

<figure class="nxd-figure">
<svg viewBox="0 0 720 290" role="img" aria-labelledby="dag-title dag-desc" xmlns="http://www.w3.org/2000/svg">
<title id="dag-title">One action graph spanning four providers</title>
<desc id="dag-desc">Four horizontal provider lanes — Identity, Headscale, Proxmox VE and Nix — with five ordered actions connected by dependency edges that cross between lanes: resolve host key, mint preauth key, create guest, activate closure, and verify.</desc>
<defs>
<marker id="dag-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
<path d="M 0 0 L 10 5 L 0 10 z" fill="currentColor"/>
</marker>
</defs>
<g font-family="ui-sans-serif, system-ui, -apple-system, sans-serif">
<g opacity="0.6">
<rect x="0" y="14"  width="720" height="56" rx="10" fill="currentColor" opacity="0.035"/>
<rect x="0" y="84"  width="720" height="56" rx="10" fill="currentColor" opacity="0.06"/>
<rect x="0" y="154" width="720" height="56" rx="10" fill="currentColor" opacity="0.035"/>
<rect x="0" y="224" width="720" height="56" rx="10" fill="currentColor" opacity="0.06"/>
</g>
<g font-size="11" font-weight="700" letter-spacing="0.06em" fill="currentColor" opacity="0.55">
<text x="10" y="46">IDENTITY</text>
<text x="10" y="116">HEADSCALE</text>
<text x="10" y="186">PROXMOX VE</text>
<text x="10" y="256">NIX</text>
</g>
<g fill="none" stroke-width="2" stroke-linecap="round" color="#8b93a7" opacity="0.85">
<path d="M 268 42 C 300 42 300 112 316 112" stroke="currentColor" marker-end="url(#dag-arrow)"/>
<path d="M 452 112 C 484 112 484 182 500 182" stroke="#7c3aed" marker-end="url(#dag-arrow)" stroke-dasharray="0"/>
<path d="M 570 200 C 570 216 300 210 218 222 L 218 230" stroke="currentColor" marker-end="url(#dag-arrow)"/>
<path d="M 300 252 L 356 252" stroke="currentColor" marker-end="url(#dag-arrow)"/>
</g>
<g font-size="12.5" font-weight="600">
<rect x="104" y="24" width="164" height="36" rx="9" fill="#4f46e5"/>
<text x="186" y="47" text-anchor="middle" fill="#ffffff">1 · resolve host key</text>
<rect x="316" y="94" width="136" height="36" rx="9" fill="#7c3aed"/>
<text x="384" y="117" text-anchor="middle" fill="#ffffff">2 · mint key</text>
<rect x="500" y="164" width="140" height="36" rx="9" fill="#b45309"/>
<text x="570" y="187" text-anchor="middle" fill="#ffffff">3 · create guest</text>
<rect x="136" y="234" width="164" height="36" rx="9" fill="#047857"/>
<text x="218" y="257" text-anchor="middle" fill="#ffffff">4 · activate closure</text>
<rect x="356" y="234" width="120" height="36" rx="9" fill="#047857" opacity="0.82"/>
<text x="416" y="257" text-anchor="middle" fill="#ffffff">5 · verify</text>
</g>
<g font-size="10.5" fill="#7c3aed" font-weight="600">
<text x="496" y="152">must precede</text>
</g>
</g>
</svg>
<figcaption class="nxd-figcaption">The key must exist before the guest that consumes it boots. Because the dependency is an edge in one graph rather than a step in a runbook, the scheduler enforces it — no ordering lives in an operator's head.</figcaption>
</figure>

## Everything that can run at once, does

A dependency graph tells you what must wait. It also tells you what does not.

NXD starts each action as soon as its dependencies have finished successfully and no other action holds a lock on the same resource. It does not run in fixed stages, so a quick task on one host is never blocked by a slow build on an unrelated one.

This matters most on **mixed fleets**, since real environments are rarely uniform. A Proxmox virtual machine, a cloud server, a Windows WSL distribution, and an Apple Silicon laptop share no dependencies with each other, so all four are updated in parallel while the ordering that does matter is still enforced. Concurrency is capped with `--parallel`.

## Only evaluating what you asked for

Nix evaluation is the expensive part of any deployment tool, and the naive approach — evaluate the whole environment, then filter — gets slower with every host you add.

NXD selects first, then evaluates. Planning one machine evaluates that machine, its providers, and its secrets. It does not evaluate the other twenty hosts to discover they were not selected, and it does not walk unrelated dependency trees to prove they are irrelevant.

The practical result: planning stays roughly as fast on a large environment as a small one, because the work is proportional to what you selected rather than what exists.

## Providers are plugins, in any language

The eight providers NXD ships with are compiled in, but that is a packaging choice, not an architectural one. Providers talk to the engine over a **versioned gRPC protocol**, so one adapter presents an external process through exactly the same interface as a built-in.

Three things follow:

**Providers can live in your own repository.** A provider specific to your infrastructure does not need to be upstreamed, or exist in NXD at all. It is an executable NXD is configured to load — and the plan binds its exact content digest, so the thing that was reviewed is the thing that runs.

**They can be written in any language.** The protocol is the contract, not the implementation. Rust is right for something long-lived and hot; Python or TypeScript is right for a first version you want working this afternoon.

**Not everything deserves a provider.** Some work is real but too irregular to model as a reconciled resource. `nxd exec` runs a reviewed command through the same verified transport and target identity a provider would use — so one-off and runbook-style work still goes through pinned host keys and the configured target, rather than a hand-typed `ssh` outside the system.

The point is that a provider is not a privileged insider. It is any process that speaks the protocol, and that protocol will be published and versioned as a public contract rather than left as an internal detail.

## Your private network, your control plane

Most teams reach for Tailscale, and it is genuinely excellent. But the coordination server — the thing that decides which machines exist, what they are named, and which may talk to which — runs in someone else's account.

NXD manages a **self-hosted control plane** for your tailnet. Same protocol, same clients, same connectivity. The difference is that node identity, authentication keys, and access rules are declared in your Nix configuration, applied by the same graph that builds your machines, and stored in your infrastructure.

That turns network membership into a normal part of provisioning. A machine gets its authentication key issued, joins, and is verified as part of coming up — with no console visit and no third party holding the roster.

## Secrets never touch the Nix store

The Nix store is world-readable. Any secret passed into a build is published to every user on that machine and permanently baked into a hash.

So NXD does not put secrets in builds. Configuration carries **binding references** — a name pointing at an encrypted value — and nothing else. At apply time, those are resolved with SOPS/age directly into memory, or into files readable only by root when a program genuinely needs a path.

Git holds ciphertext. The store holds references. Plaintext exists only in the process that needs it, for as long as it needs it.

Transport is held to the same standard. Every provider shares one SSH layer that enforces exact host key pinning and reuses connections by default. That started as a correctness decision and turned into a performance one — before it was shared, twelve modules across four providers opened SSH connections, and exactly one of them reused anything. Everything else paid a full handshake per command.

## Building on machines that cannot build

Small servers cannot always build their own operating system. Evaluation alone can want more memory than the machine has, and the result is an out-of-memory kill partway through.

NXD decides where each build happens, per machine:

- **On a builder** — a capable machine compiles, and only the finished result ships.
- **On the orchestrator** — your workstation builds, when it can produce that machine's system.
- **On the target** — when it is the most capable machine available.
- **Evaluate here, realize there** — the orchestrator does the memory-hungry evaluation, and the target assembles the result into its own store.

That last strategy is what makes 1 GB machines routine rather than a fight. The server this blog runs on has 1 GB of memory; it never has to hold a build plan.

## Rebuilding from nothing

The real test is not a routine update. It is the day a hypervisor is gone and you are standing in front of bare hardware.

Three paths, ordered by how much still survives:

**A machine you cannot boot from media.** `--intent convert` takes it over in place: kexec boots a new kernel from the running system and the host comes back as NixOS. The server this page is served from is a DigitalOcean droplet created from an Ubuntu image, converted this way — no install media, no console.

**Bare hardware, network alive.** **PXE boot**: power on, fetch reviewed installer media, install with the answer file and first-boot configuration already declared.

**Nothing left running.** A **cold recovery USB** carries the installer assets *and* the service that serves them, so a laptop becomes the temporary infrastructure that rebuilds a hypervisor.

That last one is where production recovery usually goes wrong, and the reason is the network. Real networks are segmented — VLANs, tagged trunks, a router handing out addresses on a management segment — and the equipment providing all that may be exactly what you are rebuilding. Standing up a second DHCP server on a live VLAN is also a good way to break what still works. So the image runs **isolated**, scoped to its own interface and address range: one cable between laptop and machine, with the switch taken out of the picture rather than fought with during an outage.

Two things matter more than the mechanics. The bootstrap service is bounded — one reviewed operation, cleanup on success, failure, or timeout. And recovery is **not a separate engine**: same plan, approve, apply, verify cycle, same identity checks. It never skips host key verification because an endpoint is unreachable, which is exactly when weakened checks would hurt most.

## What it looks like

```bash
# Inspect the graph before anything moves
nxd plan web-01 --source ".#nxdConfigurations.prod"

# Apply a system update to a live host
nxd switch web-01 --source ".#nxdConfigurations.prod"

# Machine-readable, for CI and coding agents
nxd plan web-01 --source ".#nxdConfigurations.prod" --format json
```

```
evaluating selected target outputs...
evaluated selected target outputs in 4s
approval required for switch plan .nxd/plans/switch-4592a2f32894.plan.json
plan digest: sha256:4592a2f32894b465309c87f2052ab9b97ee19799898d1cfc5ec5b69cb446a3ea  (3 actions, 1 target)

PLAN ACTIONS:
  1. deployment-target/web-01      build -> nixos-rebuild switch    [ServiceImpacting]
  2. secret/hosts/web-01/ssh-host  stage SOPS decrypted key         [IdentityCritical]
  3. deployment-target/web-01      verify active system closure     [ReadOnly]

✓ [web-01] build placement configured=auto builder=deploy@utils
✓ [web-01] realized closure /nix/store/jpz7lcmwjzjymdr38kxh428rwa2arr04-nixos-system-web-01
✓ [web-01] active system verified: desiredSystemPath == activeSystemPath (delta +0)
```

## Why it might belong in your stack

**If you operate infrastructure:** one description instead of three that drift apart. You see the risk class of every change before authorizing it, and the layer underneath your machines stops being the undocumented part.

**If you point coding agents at your infrastructure:** every surface is structured. JSON output on plan and verify, typed provider contracts, explicit postconditions. An agent can inspect real state, propose a plan, and get empirical confirmation that it converged — instead of pattern-matching shell output and guessing. And because applying requires approval bound to a specific plan hash, an agent that gets it wrong produces a refused apply, not a broken cluster.

## Get involved

NXD is open source and moving fast. Issues, ideas, and early adopters all welcome.

- **[Star or watch the repository on GitHub](https://github.com/lamtt77/nxd)** — the source is being prepared for its first public release
- **[Technical manual](https://nxd.lamhub.com/manual/)** — architecture, safety model, CLI reference
- **[Project site](https://nxd.lamhub.com/)**
- **[lamt-nixconfig](https://github.com/lamtt77/lamt-nixconfig)** — a real consumer repository, if you would rather read configuration than prose

If you have felt the gap between a reproducible operating system and an unreproducible everything-else, that is the gap this was built to close. I would genuinely like to hear how it holds up against infrastructure that is not mine.
