SHELL := bash
SCRIPTS := install.sh skills/metate-review/bootstrap.sh sources/render.sh tests/contracts/validate.sh
RENDER_SCRIPT := sources/render.sh
BUDGET := tests/contracts/prose-budget.txt
RENDERED := skills/metate-review/cursor-rule.mdc \
	skills/metate-review/codex-rule.md \
	skills/metate-review/cursor-agents/metate-correctness-reviewer.md \
	skills/metate-review/cursor-agents/metate-security-reviewer.md \
	skills/metate-review/cursor-agents/metate-elegance-reviewer.md \
	skills/metate-review/generated/prompt-clause.md \
	skills/metate-review/generated/lens-prompts/correctness.txt \
	skills/metate-review/generated/lens-prompts/security.txt \
	skills/metate-review/generated/lens-prompts/elegance.txt

.PHONY: verify check lint test render render-check drift budget help
.DEFAULT_GOAL := help

help: ## list targets
	@grep -hE '^[a-z]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/' | sort

check: lint ## fast loop (run each review round)

verify: lint test render-check budget ## full gate (mirrors CI; run before shipping)

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

budget: ## fail when a SKILL.md grows past its recorded line cap
	@fail=0; \
	while read -r file cap; do \
	  case "$$file" in ''|\#*) continue ;; esac; \
	  [ -f "$$file" ] || { echo "  ✗ budget: $$file listed but missing"; fail=1; continue; }; \
	  n=$$(wc -l < "$$file" | tr -d ' '); \
	  if [ "$$n" -gt "$$cap" ]; then \
	    echo "  ✗ $$file: $$n lines > cap $$cap — remove prose, or raise the cap in $(BUDGET) explicitly"; \
	    fail=1; \
	  fi; \
	done < $(BUDGET); \
	for f in skills/*/SKILL.md; do \
	  grep -q "^$$f " $(BUDGET) || { echo "  ✗ $$f has no cap in $(BUDGET)"; fail=1; }; \
	done; \
	[ "$$fail" -eq 0 ] || exit 1; \
	echo "  ✓ every SKILL.md within its prose budget"

drift: ## warn when the copies harnesses actually load are stale (never fails the build)
	@stale=0; \
	for pair in \
	  ".cursor/agents/metate-correctness-reviewer.md:skills/metate-review/cursor-agents/metate-correctness-reviewer.md" \
	  ".cursor/agents/metate-security-reviewer.md:skills/metate-review/cursor-agents/metate-security-reviewer.md" \
	  ".cursor/agents/metate-elegance-reviewer.md:skills/metate-review/cursor-agents/metate-elegance-reviewer.md" \
	  ".cursor/rules/codebase-memory.mdc:skills/metate-review/cursor-rule.mdc" \
	; do \
	  dst=$${pair%%:*}; src=$${pair#*:}; \
	  [ -f "$$dst" ] || continue; \
	  diff -q "$$src" "$$dst" >/dev/null 2>&1 || { \
	    echo "  ! stale: $$dst differs from $$src"; stale=1; }; \
	done; \
	for root in "$$HOME/.claude/skills" "$$HOME/.agents/skills"; do \
	  [ -d "$$root" ] || continue; \
	  for s in skills/*/SKILL.md; do \
	    d="$$root/$$(basename $$(dirname $$s))/SKILL.md"; \
	    [ -f "$$d" ] || continue; \
	    diff -q "$$s" "$$d" >/dev/null 2>&1 || { echo "  ! stale: $$d"; stale=1; }; \
	  done; \
	done; \
	if [ "$$stale" -eq 0 ]; then echo "  ✓ installed harness copies match the repo"; \
	else echo "  → run: bash install.sh --update --user && metate-init --update"; fi

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
	@bash tests/contracts/validate.sh
