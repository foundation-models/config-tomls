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
make check-sops-key   # optional: confirms your key matches .sops.yaml (needs: brew install age)
make decrypt-config   # writes ~/.config/kube_config.yaml, pi-production-kubeconfig.yaml, …
```

## Re-encrypt from `~/.config` (after rotating age key)

1. Put the new **public** `age1…` line in **`.sops.yaml`** (and update GitHub **`SOPS_AGE_KEY`** with the matching private key).
2. From the **repo root**, with plaintext under `~/.config/`:

| Encrypted file in repo | Plaintext source (first match wins) |
|------------------------|-------------------------------------|
| `config/enc/<stem>.enc.yaml` | `~/.config/<stem>.toml` **or** `~/.config/<stem>.yaml` |

Examples: `kube_config.enc.yaml` ← `kube_config.toml` or `kube_config.yaml`; `pi-production-kubeconfig.enc.yaml` ← `pi-production-kubeconfig.toml` or `.yaml`.

3. Run:

```bash
make encrypt-config-from-home   # needs: sops, uv + PyYAML if any source is .toml
```

The Makefile passes **`--filename-override`** to `sops encrypt` so **`.sops.yaml`** `path_regex` matches the repo path (`config/enc/*.enc.yaml`) even when the plaintext comes from `/tmp` (TOML→YAML) or from `~/.config` outside the repo. Then commit and push the updated `*.enc.yaml` files.

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
