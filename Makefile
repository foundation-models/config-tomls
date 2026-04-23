.PHONY: help decrypt-config check-sops-key encrypt-config-from-home

CONFIG_ENC_DIR := config/enc
CONFIG_ENC_GLOB := $(CONFIG_ENC_DIR)/*.enc.yaml
HOME_CONFIG := $(HOME)/.config
# Stems whose decrypted SOPS YAML is written as ~/.config/<stem>.toml (round-trip with encrypt-config-from-home).
DECRYPT_AS_TOML_STEMS := kube_config supabase
# Public age recipient from .sops.yaml (single source of truth for encrypt + check).
SOPS_AGE_RECIPIENT := $(shell sed -n 's/^[[:space:]]*age:[[:space:]]*\(age1[a-z0-9]*\).*/\1/p' .sops.yaml | head -1)

help: ## Show targets
	@grep -E '^[a-zA-Z0-9_.-]+:.*?##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-28s %s\n", $$1, $$2}'

check-sops-key: ## Verify SOPS_AGE_KEY / SOPS_AGE_KEY_FILE matches .sops.yaml recipient (needs age-keygen)
	@test -n "$(SOPS_AGE_RECIPIENT)" || (echo "Error: could not parse age recipient from .sops.yaml." >&2 && exit 1)
	@command -v age-keygen >/dev/null 2>&1 || (echo "Error: install age (e.g. brew install age) for check-sops-key." >&2 && exit 1)
	@if [ -n "$$SOPS_AGE_KEY_FILE" ] && [ -f "$$SOPS_AGE_KEY_FILE" ]; then \
		got=$$(age-keygen -y "$$SOPS_AGE_KEY_FILE" 2>/dev/null | tail -n1); \
	elif [ -n "$$SOPS_AGE_KEY" ]; then \
		tmp=$$(mktemp); printf '%s\n' "$$SOPS_AGE_KEY" > "$$tmp"; chmod 600 "$$tmp"; \
		got=$$(age-keygen -y "$$tmp" 2>/dev/null | tail -n1); rm -f "$$tmp"; \
	else echo "Error: set SOPS_AGE_KEY or SOPS_AGE_KEY_FILE." >&2 && exit 1; fi; \
	if [ "$$got" = "$(SOPS_AGE_RECIPIENT)" ]; then \
		echo "check-sops-key: OK (public recipient matches .sops.yaml)"; \
	else \
		echo "check-sops-key: FAILED — this private key's public recipient is:" >&2; \
		echo "  $$got" >&2; \
		echo "Expected (from .sops.yaml):" >&2; \
		echo "  $(SOPS_AGE_RECIPIENT)" >&2; \
		echo "Use the age identity that was used to encrypt this repo, or ask the repo owner for the matching key." >&2; \
		exit 1; \
	fi

decrypt-config: ## Decrypt config/enc/*.enc.yaml into ~/.config (SOPS_AGE_KEY or SOPS_AGE_KEY_FILE). kube_config -> .toml; others -> .yaml
	@command -v sops >/dev/null 2>&1 || (echo "Error: sops not on PATH." >&2 && exit 1)
	@test -n "$(wildcard $(CONFIG_ENC_GLOB))" || (echo "Error: no files matching $(CONFIG_ENC_GLOB)." >&2 && exit 1)
	@if [ -n "$$SOPS_AGE_KEY" ]; then :; \
	elif [ -n "$$SOPS_AGE_KEY_FILE" ] && [ -f "$$SOPS_AGE_KEY_FILE" ]; then :; \
	else echo "Error: set SOPS_AGE_KEY (age private key) or SOPS_AGE_KEY_FILE (path to key file)." >&2 && exit 1; fi
	@mkdir -p "$(HOME_CONFIG)"
	@set -e; for f in $(wildcard $(CONFIG_ENC_GLOB)); do \
		stem=$$(basename "$$f" .enc.yaml); \
		tmp=$$(mktemp); chmod 600 "$$tmp"; \
		sops -d "$$f" > "$$tmp"; \
		toml=0; for s in $(DECRYPT_AS_TOML_STEMS); do [ "$$stem" = "$$s" ] && toml=1 && break; done; \
		if [ "$$toml" = 1 ]; then \
			out="$$stem.toml"; \
			command -v uv >/dev/null 2>&1 || (echo "Error: need uv on PATH for YAML->TOML ($$stem)." >&2 && rm -f "$$tmp" && exit 1); \
			echo "decrypt: $$f -> $(HOME_CONFIG)/$$out (via YAML->TOML)"; \
			uv run --with pyyaml --with tomli-w python3 -c 'import sys, yaml, tomli_w; d = yaml.safe_load(sys.stdin.read()); sys.stdout.write(tomli_w.dumps(d))' < "$$tmp" > "$(HOME_CONFIG)/$$out.tmp" && \
			mv "$(HOME_CONFIG)/$$out.tmp" "$(HOME_CONFIG)/$$out" && \
			chmod 600 "$(HOME_CONFIG)/$$out"; \
			rm -f "$(HOME_CONFIG)/$$stem.yaml"; \
		else \
			out="$$stem.yaml"; \
			echo "decrypt: $$f -> $(HOME_CONFIG)/$$out"; \
			mv "$$tmp" "$(HOME_CONFIG)/$$out.tmp" && \
			mv "$(HOME_CONFIG)/$$out.tmp" "$(HOME_CONFIG)/$$out" && \
			chmod 600 "$(HOME_CONFIG)/$$out"; \
		fi; \
		rm -f "$$tmp"; \
	done
	@echo "Done: wrote under $(HOME_CONFIG)/"

# Re-encrypt after rotating age key: update .sops.yaml first, then run this from repo root.
encrypt-config-from-home: ## Re-encrypt config/enc/*.enc.yaml from $(HOME)/.config/<stem>.toml or .yaml (TOML needs uv + PyYAML)
	@test -n "$(SOPS_AGE_RECIPIENT)" || (echo "Error: could not parse age recipient from .sops.yaml." >&2 && exit 1)
	@command -v sops >/dev/null 2>&1 || (echo "Error: sops not on PATH." >&2 && exit 1)
	@test -n "$(wildcard $(CONFIG_ENC_GLOB))" || (echo "Error: no files matching $(CONFIG_ENC_GLOB)." >&2 && exit 1)
	@set -e; for enc in $(wildcard $(CONFIG_ENC_GLOB)); do \
		stem=$$(basename "$$enc" .enc.yaml); \
		ytoml="$(HOME_CONFIG)/$$stem.toml"; \
		yyaml="$(HOME_CONFIG)/$$stem.yaml"; \
		tmp=""; src=""; \
		if [ -f "$$ytoml" ]; then \
			command -v uv >/dev/null 2>&1 || (echo "Error: need uv on PATH to read $$ytoml (TOML -> YAML for SOPS)." >&2 && exit 1); \
			tmp=$$(mktemp); chmod 600 "$$tmp"; \
			uv run --with pyyaml python3 -c 'import pathlib, sys, tomllib, yaml; p = pathlib.Path(sys.argv[1]); d = tomllib.loads(p.read_text()); yaml.safe_dump(d, sys.stdout, default_flow_style=False, allow_unicode=True)' "$$ytoml" > "$$tmp"; \
			src="$$tmp"; \
		elif [ -f "$$yyaml" ]; then \
			src="$$yyaml"; \
		else \
			echo "Error: missing source $$ytoml or $$yyaml for $$enc" >&2; exit 1; \
		fi; \
		echo "encrypt: $$src -> $$enc (recipients from .sops.yaml for $$enc)"; \
		sops encrypt --filename-override "$$enc" --input-type yaml "$$src" --output "$$enc"; \
		if [ -n "$$tmp" ]; then rm -f "$$tmp"; fi; \
	done
	@echo "Done: updated $(CONFIG_ENC_GLOB)"
