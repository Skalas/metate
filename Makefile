SHELL := bash
SCRIPTS := install.sh skills/metate-review/bootstrap.sh bin/metate sources/render.sh
CODEX_REVIEW := skills/metate-review/codex-review.sh
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
	@for f in $(SCRIPTS) $(CODEX_REVIEW); do bash -n "$$f" && echo "  ✓ syntax $$f"; done
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SCRIPTS) $(CODEX_REVIEW) skills/metate-review/lib/yaml.sh \
			skills/metate-review/lib/profile.sh skills/metate-review/lib/captures.sh \
			skills/metate-review/lib/trusted-review-text.sh \
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
	@PROFILE_ROOT=$$(pwd); absent=$$(mktemp); \
		printf '%s\n' 'fastGate: "make check"' > "$$absent"; \
		export PROFILE_ROOT PROFILE="$$absent"; \
		. skills/metate-review/lib/profile.sh \
		&& . skills/metate-review/lib/captures.sh \
		&& [ "$$(count_open_captures)" = "0" ] \
		&& echo "  ✓ absent signalsFile → 0 open captures (not an error)" \
		|| { echo "  ✗ absent signalsFile should yield 0 open captures"; rm -f "$$absent"; exit 1; }; \
		rm -f "$$absent"
	@PROFILE_ROOT=$$(pwd); sig=$$(mktemp); prof=$$(mktemp); \
		echo '[]' > "$$sig"; printf 'signalsFile: %s\n' "$$sig" > "$$prof"; \
		export PROFILE_ROOT PROFILE="$$prof"; \
		. skills/metate-review/lib/profile.sh \
		&& . skills/metate-review/lib/captures.sh \
		&& [ "$$(count_open_captures)" = "0" ] \
		&& echo "  ✓ empty capture log → 0 open captures" \
		|| { echo "  ✗ empty capture log should yield 0 open captures"; rm -f "$$sig" "$$prof"; exit 1; }; \
		rm -f "$$sig" "$$prof"
	@legacy=$$(mktemp); \
		printf '%s\n' 'discover:' '  signals:' '    captures: false' > "$$legacy"; \
		export PROFILE="$$legacy"; \
		bash -ec '. skills/metate-review/lib/profile.sh; [ "$$(prof_discover_toggle captures)" = "false" ]' \
		&& echo "  ✓ legacy discover.signals alias reads captures toggle" \
		|| { echo "  ✗ legacy discover.signals alias failed"; rm -f "$$legacy"; exit 1; }; \
		rm -f "$$legacy"
	@! grep -qE 'git show HEAD:' skills/metate-review/lib/trusted-review-text.sh \
		&& echo "  ✓ trusted-review-text never loads branch HEAD for in-diff prompts"
	@bash -ec '\
		bundle=$$(mktemp -d); \
		gate_rel=skills/metate-review/generated/__gate-trusted-test.txt; \
		mkdir -p "$$bundle/generated" skills/metate-review/generated; \
		echo TRUSTED_BUNDLED_ONLY > "$$bundle/generated/__gate-trusted-test.txt"; \
		echo MALICIOUS_WORKING_TREE > "$$gate_rel"; \
		export ROOT="$$(pwd)" BASE_BRANCH=main METATE_TRUSTED_SKILL_ROOT="$$bundle"; \
		die() { echo "✗ $$*" >&2; exit 1; }; \
		. skills/metate-review/lib/trusted-review-text.sh; \
		out=$$(trusted_review_text "$$gate_rel"); \
		rm -f "$$gate_rel"; rm -rf "$$bundle"; \
		[ "$$out" = TRUSTED_BUNDLED_ONLY ]' \
		&& echo "  ✓ trusted-review-text loads bundled copy for new-in-diff prompts" \
		|| { echo "  ✗ trusted-review-text should prefer bundled install over working tree"; exit 1; }
