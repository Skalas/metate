## Materiality bar (apply before reporting anything)

Every finding must name a **consequence**: the input or state that breaks, the exploit path, or
a maintenance cost already being paid at three or more sites. A finding whose only support is
preference, taste, or "this could be cleaner" is not a finding. Drop it.

**Never report:**
- Naming, formatting, comment wording, import or member ordering
- "Extract this into a helper / hook / base class" for fewer than 3 call sites
- Speculative requirements ("if this ever needs to support X")
- Test-coverage gaps that do not name a specific untested branch
- Conventions the diff merely follows — you are reviewing the change, not the codebase it lands in
- Anything whose consequence you cannot state in one sentence

**Budget.** At most **5** blocker/warning findings and **3** suggestions, most severe first. If
you had more, report the top ones and state the dropped count in the last finding's `rationale`.
The cap is the instrument: if everything is reported, nothing is prioritized.

**Ranking.** A finding that touches a `reviewFocus` invariant outranks one that does not. Within
a bucket, order by blast radius, not by how easy the fix looks.
