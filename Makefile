.PHONY: help decrypt-config check-sops-key

CONFIG_ENC_DIR := config/enc
CONFIG_ENC_GLOB := $(CONFIG_ENC_DIR)/*.enc.yaml
HOME_CONFIG := $(HOME)/.config
# Must match .sops.yaml creation_rules age recipient (public).
SOPS_EXPECTED_AGE_RECIPIENT := age14a25mmmgcpdh9l2dg35325pjq024925zrzt5xhjs3a3n5p5u5pmsttuh45

help: ## Show targets
	@grep -E '^[a-zA-Z0-9_.-]+:.*?##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-28s %s\n", $$1, $$2}'

check-sops-key: ## Verify SOPS_AGE_KEY / SOPS_AGE_KEY_FILE matches .sops.yaml recipient (needs age-keygen)
	@command -v age-keygen >/dev/null 2>&1 || (echo "Error: install age (e.g. brew install age) for check-sops-key." >&2 && exit 1)
	@if [ -n "$$SOPS_AGE_KEY_FILE" ] && [ -f "$$SOPS_AGE_KEY_FILE" ]; then \
		got=$$(age-keygen -y "$$SOPS_AGE_KEY_FILE" 2>/dev/null | tail -n1); \
	elif [ -n "$$SOPS_AGE_KEY" ]; then \
		tmp=$$(mktemp); printf '%s\n' "$$SOPS_AGE_KEY" > "$$tmp"; chmod 600 "$$tmp"; \
		got=$$(age-keygen -y "$$tmp" 2>/dev/null | tail -n1); rm -f "$$tmp"; \
	else echo "Error: set SOPS_AGE_KEY or SOPS_AGE_KEY_FILE." >&2 && exit 1; fi; \
	if [ "$$got" = "$(SOPS_EXPECTED_AGE_RECIPIENT)" ]; then \
		echo "check-sops-key: OK (public recipient matches .sops.yaml)"; \
	else \
		echo "check-sops-key: FAILED — this private key's public recipient is:" >&2; \
		echo "  $$got" >&2; \
		echo "Expected (from .sops.yaml):" >&2; \
		echo "  $(SOPS_EXPECTED_AGE_RECIPIENT)" >&2; \
		echo "Use the age identity that was used to encrypt this repo, or ask the repo owner for the matching key." >&2; \
		exit 1; \
	fi

decrypt-config: ## Decrypt config/enc/*.enc.yaml into ~/.config (SOPS_AGE_KEY or SOPS_AGE_KEY_FILE). Run check-sops-key if decrypt fails.
	@command -v sops >/dev/null 2>&1 || (echo "Error: sops not on PATH." >&2 && exit 1)
	@test -n "$(wildcard $(CONFIG_ENC_GLOB))" || (echo "Error: no files matching $(CONFIG_ENC_GLOB)." >&2 && exit 1)
	@if [ -n "$$SOPS_AGE_KEY" ]; then :; \
	elif [ -n "$$SOPS_AGE_KEY_FILE" ] && [ -f "$$SOPS_AGE_KEY_FILE" ]; then :; \
	else echo "Error: set SOPS_AGE_KEY (age private key) or SOPS_AGE_KEY_FILE (path to key file)." >&2 && exit 1; fi
	@mkdir -p "$(HOME_CONFIG)"
	@set -e; for f in $(wildcard $(CONFIG_ENC_GLOB)); do \
		base=$$(basename "$$f"); \
		out=$${base%.enc.yaml}.yaml; \
		echo "decrypt: $$f -> $(HOME_CONFIG)/$$out"; \
		sops -d "$$f" > "$(HOME_CONFIG)/$$out.tmp" && \
		mv "$(HOME_CONFIG)/$$out.tmp" "$(HOME_CONFIG)/$$out" && \
		chmod 600 "$(HOME_CONFIG)/$$out"; \
	done
	@echo "Done: wrote under $(HOME_CONFIG)/"
