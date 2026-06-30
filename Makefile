SHELL := bash
SCRIPTS := install.sh skills/metate-review/bootstrap.sh bin/metate skills/metate-review/codex-review.sh

.PHONY: verify check lint test help
.DEFAULT_GOAL := help

help: ## list targets
	@grep -hE '^[a-z]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/' | sort

check: lint ## fast loop (run each review round)

verify: lint test ## full gate (mirrors CI; run before shipping)

lint: ## bash -n on every script + shellcheck when available
	@for f in $(SCRIPTS); do bash -n "$$f" && echo "  ✓ syntax $$f"; done
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SCRIPTS) && echo "  ✓ shellcheck"; \
	else echo "  – shellcheck not installed, skipped"; fi

test: ## metadata + installer sanity
	@python3 -m json.tool .claude-plugin/plugin.json >/dev/null && echo "  ✓ plugin.json is valid JSON"
	@for s in skills/*/SKILL.md; do \
		grep -q '^name:' "$$s"      || { echo "  ✗ $$s missing name:"; exit 1; }; \
		grep -q '^description:' "$$s" || { echo "  ✗ $$s missing description:"; exit 1; }; \
	done; echo "  ✓ every SKILL.md has name + description"
	@out=$$(bash install.sh --help); echo "$$out" | grep -q 'install.sh' \
		&& ! echo "$$out" | grep -q 'fetching metate' \
		&& echo "  ✓ local --help works and does not clone"
	@m=$$(awk -f skills/metate-review/reconcile-profile.awk .metate/profile.yml skills/metate-review/profile.template.yml 2>/dev/null); \
		[ "$$m" = "$$(cat .metate/profile.yml)" ] \
		&& echo "  ✓ reconcile is a no-op on an up-to-date profile" \
		|| { echo "  ✗ reconcile not idempotent on current profile"; exit 1; }
	@partial=$$(mktemp); err=$$(mktemp); \
		grep -v '^issueLedger:' .metate/profile.yml > "$$partial"; \
		out=$$(awk -f skills/metate-review/reconcile-profile.awk "$$partial" skills/metate-review/profile.template.yml 2>"$$err"); \
		grep -q '+ issueLedger' "$$err" \
		&& echo "$$out" | grep -q '^issueLedger:' \
		&& echo "$$out" | grep -q '^fastGate:' \
		&& echo "  ✓ reconcile inserts a missing key and keeps existing ones" \
		|| { echo "  ✗ reconcile failed to insert a missing key"; rm -f "$$partial" "$$err"; exit 1; }; \
		rm -f "$$partial" "$$err"
