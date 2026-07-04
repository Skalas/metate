SHELL := bash
SCRIPTS := install.sh skills/metate-review/bootstrap.sh sources/render.sh
RENDER_SCRIPT := sources/render.sh
RENDERED := skills/metate-review/cursor-rule.mdc \
	skills/metate-review/codex-rule.md \
	skills/metate-review/cursor-agents/metate-correctness-reviewer.md \
	skills/metate-review/cursor-agents/metate-security-reviewer.md \
	skills/metate-review/cursor-agents/metate-elegance-reviewer.md \
	skills/metate-review/generated/prompt-clause.md \
	skills/metate-review/generated/lens-prompts/correctness.txt \
	skills/metate-review/generated/lens-prompts/security.txt \
	skills/metate-review/generated/lens-prompts/elegance.txt

.PHONY: verify check lint test render render-check help
.DEFAULT_GOAL := help

help: ## list targets
	@grep -hE '^[a-z]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/' | sort

check: lint ## fast loop (run each review round)

verify: lint test render-check ## full gate (mirrors CI; run before shipping)

render: ## regenerate harness artifacts from sources/
	bash $(RENDER_SCRIPT)

render-check: ## fail if rendered artifacts drift from sources/ (does not rewrite the tree)
	@fail=0; \
	for f in $(RENDERED); do \
	  [ -f "$$f" ] || { echo "  ✗ missing rendered artifact $$f"; fail=1; }; \
	done; \
	[ "$$fail" -eq 0 ] || exit 1; \
	tmp=$$(mktemp -d); \
	RENDER_OUT_ROOT="$$tmp" bash $(RENDER_SCRIPT) >/dev/null; \
	for f in $(RENDERED); do \
	  diff -q "$$f" "$$tmp/$$f" >/dev/null || { \
	    echo "  ✗ $$f drifted from sources/ — run make render"; fail=1; }; \
	done; \
	rm -rf "$$tmp"; \
	[ "$$fail" -eq 0 ] && echo "  ✓ rendered harness artifacts match sources/"

lint: ## bash -n on every script + shellcheck when available
	@for f in $(SCRIPTS); do bash -n "$$f" && echo "  ✓ syntax $$f"; done
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SCRIPTS) skills/metate-review/lib/yaml.sh \
			&& echo "  ✓ shellcheck"; \
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
	@val=$$(bash -c 'source skills/metate-review/lib/yaml.sh; yaml_nested_scalar skills/metate-review/profile.template.yml reviewer backend'); \
		[ "$$val" = claude ] \
		&& echo "  ✓ yaml.sh reads nested profile keys" \
		|| { echo "  ✗ yaml.sh nested read on profile.template.yml failed"; exit 1; }
