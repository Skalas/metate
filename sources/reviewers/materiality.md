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

**The present-tense test.** It runs in both directions, and both directions are your job:
- *On the code* — what problem that exists **today** does this solve? "Nothing, it is just in
  case" is overengineering: complexity paid now for a speculative benefit. Report it. (An
  architecture boundary is a problem that exists today — isolating one is not speculation.)
- *On your own finding* — same question. If the answer is "nothing, it is just in case", you are
  bikeshedding. Drop the finding.

**Budget.** At most **5** blocker/warning findings and **3** suggestions, most severe first. If
you had more, report the top ones and state the dropped count in the last finding's `rationale`.
The cap is the instrument: if everything is reported, nothing is prioritized.

**Ranking.** A finding that touches a `reviewFocus` invariant outranks one that does not. Within
a bucket, order by blast radius, not by how easy the fix looks.
