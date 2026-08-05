# NXD pure projection

`nxd/` converts normalized LAMT data into canonical NXD configuration. It must
not invent topology, rediscover hosts, or hard-code infrastructure addresses.

## Sources of truth

| Domain | Owner |
| --- | --- |
| Host / deploy target metadata | `hosts/*/meta.nix` via `infra/default.nix` |
| Management addresses | `infra/site.nix` → `site.hosts` |
| PVE cluster / node topology | `infra/site.nix` → `site.clusters` |
| PBS service policy | `infra/site.nix` → `site.pbs` |
| Shared OS/HM options | `modules/shared/options.nix` (`user`, `lamt.binaryCache`) |

## Files

- `default.nix` — small composition root and canonical operation sets.
- `pve.nix`, `pbs.nix`, and `headscale.nix` — pure domain projections from
  `infra`. Deployment targets are attached by `flake/hosts.nix` from
  `infra.deploymentTargetResources`.
- `pve-root-ca.pem` / `pbs-root-ca.pem` — trust material referenced by provider
  projection only.
