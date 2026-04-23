# config-tomls

Team TOML-style configs, stored **encrypted** in git (SOPS + age).

## Layout

| Path | Purpose |
|------|---------|
| `config/enc/*.enc.yaml` | SOPS-encrypted files (safe to commit). |
| `config/enc/pi-production-kubeconfig.enc.yaml` | Encrypted DOKS admin kubeconfig (`pi-production`). |
| `.sops.yaml` | SOPS rules (age **public** recipient only). |

Plaintext originals (for example `~/.config/kube_config.toml`) stay on your machine and are listed in `config/enc/.gitignore` if copied beside ciphertext.

## Decrypt / edit (local)

Requires the age **private** key (same material as GitHub secret `SOPS_AGE_KEY`):

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"   # or SOPS_AGE_KEY with inline key
sops -d config/enc/kube_config.enc.yaml
```

To restore the pi-production kubeconfig to a local file (then `chmod 600` it):

`sops -d config/enc/pi-production-kubeconfig.enc.yaml > ~/.config/pi-production-kubeconfig.yaml`

Edit in place:

```bash
sops config/enc/kube_config.enc.yaml
```

## Round-trip to TOML

SOPS operates on this file as **YAML** (structured encryption). To match `~/.config/kube_config.toml`, convert after decrypt (example with Python + PyYAML + tomllib).

## CI

Provide `SOPS_AGE_KEY` as a repository secret (the **age private** key that matches `.sops.yaml`).

Workflow **pi-production k8s smoke** (`.github/workflows/pi-production-k8s-smoke.yml`): `workflow_dispatch` → decrypts `config/enc/pi-production-kubeconfig.enc.yaml` → `kubectl get namespaces`. Requires `SOPS_AGE_KEY` and outbound access from GitHub runners to the DOKS API.
