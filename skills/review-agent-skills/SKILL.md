---
name: review-agent-skills
description: Review Agent Skill packages for routing, instruction quality, resource organization, tool and safety boundaries, testability, and maintainability. Use for SKILL.md or Skill repository reviews; not ordinary application-code review.
---

# Review Agent Skills

Review the requested Skill package against its repository instructions, current diff, and direct dependencies. Preserve the requested scope and do not publish comments or change files unless the user asks.

1. Identify the review target, baseline, changed Skill directories, applicable repository rules, and existing feedback.
2. Run the repository's deterministic checks when available, but keep their results separate from semantic judgment.
3. Read [Review Methodology](references/review-methodology.md) and inspect routing, instructions, resources, safety boundaries, failure handling, portability, tests, and metadata.
4. Read [Forward Testing](references/forward-testing.md) only when static inspection cannot establish important behavior or when the Skill is complex, risky, or uncertain.
5. Report actionable findings first. Include severity, file and line, evidence, impact, and the smallest safe correction. If there are no findings, say so explicitly and state residual validation limits.

Do not broaden the Skill's responsibility to solve adjacent problems. Do not weaken confirmation, credential, destructive-action, or data-integrity safeguards to make a check pass.

## Example

For `Review the changed payment-safety Skill`, compare the changed package with its baseline, run its validators, inspect the semantic dimensions, and place a finding like this before the validation summary:

```text
High — Missing confirmation before an external write
File: payment-safety Skill instruction, line 24
Evidence: The publish step executes immediately after preview.
Impact: A normal review request can mutate the remote system before required human confirmation.
Correction: Require explicit confirmation after preview and before publish.
```

## Error handling

If the baseline, referenced resource, required validator, or relevant external system is unavailable, continue only with the evidence that remains reliable. Label the missing verification and its impact as a residual risk; stop and ask for the missing input when proceeding would require guessing or crossing a safety boundary.
