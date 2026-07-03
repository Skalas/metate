Convergence is anchored on **blockers** — the objective signal. Auto-fixed warnings/DESIGN are
attempted opportunistically each round but never by themselves force another round (subjective
findings would never converge).

**A round that applied fixes can never declare done.** "0 blockers" must come from a fan-out
round on the patched tree — any patch *requires* a following verify round. A green fast gate is
necessary, not sufficient: it proves the build, not the logic.

- **0 blockers and gate green** → ✅ done (`done`). Any unfixed (or implementer-declined)
  warning/DESIGN findings are reported, not looped on.
- **Blockers remain that autoFix won't route** → 🛑 STOP (`stop-blockers`). Hand back to the user.
- **Last patch left the fast gate red** → 🛑 STOP (`stop-gate`). Fix the gate before declaring done.
- **A reviewer lens failed** → 🛑 STOP (`stop-incomplete`). Re-run once the lens succeeds.
- **Blockers remain after round 3** → 🛑 STOP. Summarize survivors; hand back to the user.
- **Round 3 *applied* fixes that cleared the last blockers** → 🛑 STOP, not ✅: the cap leaves
  no round to verify that patch, and round 3 cannot self-certify. Hand back with the round-3
  diff flagged as unverified — the user runs a spot-check (or a manual round-4 fan-out) before
  declaring done.
