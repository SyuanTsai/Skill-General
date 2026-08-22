# Agent Skill Review Methodology

## Establish the review baseline

Confirm the requested Skill, comparison baseline, changed files, applicable repository instructions, and existing review feedback. Read the complete `SKILL.md`, its directly referenced resources, interface metadata, catalog entry, Skill-specific tests, and any scripts that implement user-visible behavior. Recheck the current head instead of assuming earlier feedback still applies, and avoid repeating an existing finding unless it remains unresolved.

## Deterministic checks

Run the repository's own contract tests and validators first when they exist. Typical checks include:

- valid frontmatter, stable lowercase kebab-case name, and an actionable description with clear trigger boundaries;
- resolvable one-level references and only necessary scripts, references, or assets;
- agreement among the Skill ID, directory, catalog metadata, and `agents/openai.yaml`;
- syntax, test naming, repository layout, and package-validation contracts;
- `skill-validator` and `skill-tools` results when those tools are available in the repository or CI.

Record the command and outcome. A passing deterministic validator does not prove that routing, scope, safety, fallback behavior, or instructions are semantically correct.

## Semantic review

Review the package as an agent would use it:

- **Routing:** The description states both capability and trigger conditions, distinguishes adjacent tasks, and avoids claiming unavailable tools or access.
- **Instructions:** Steps are executable, ordered only when order matters, and focused on outcomes rather than generic advice.
- **Progressive disclosure:** The entrypoint stays concise; optional detail is linked directly and loaded only for relevant variants.
- **Tools and safety:** Tool choices match the task, external writes require appropriate authority, secrets stay protected, and irreversible operations have explicit boundaries.
- **Scope and overlap:** The Skill has one coherent responsibility and does not duplicate or silently override repository-wide guardrails.
- **Failure handling:** Missing capabilities, inaccessible resources, partial results, and unsafe ambiguity lead to an explicit fallback or stop condition.
- **Portability and maintenance:** Assumptions about platforms, paths, shells, accounts, and repositories are declared or avoided.
- **Testability:** Important routing and workflow behavior has observable acceptance criteria and representative positive and negative cases.

Use [Forward Testing](forward-testing.md) when semantic behavior cannot be established confidently from static evidence.

## Severity

- **Critical:** A defect can expose credentials or sensitive data, authorize destructive behavior, cross an explicit trust boundary, or cause similarly severe and difficult-to-recover harm.
- **High:** The Skill is unusable or materially unsafe for a normal trigger, routes to the wrong capability, omits a required confirmation, or substantially conflicts with another Skill.
- **Medium:** The Skill is overly broad, unnecessarily loads large resources, handles important failures poorly, or creates a meaningful maintainability or portability risk.
- **Low:** A non-blocking naming, documentation, organization, or consistency issue that still has a concrete correction.

Do not inflate severity for style preferences. Tie severity to a plausible user or agent outcome.

## Findings and clean results

List findings before any summary. Each finding must contain:

1. severity and a concise title;
2. the file and exact line or tight line range;
3. direct evidence from the current package or a reproducible check;
4. the trigger and concrete impact;
5. the smallest safe correction, without implementing it unless requested.

When there are no findings, state `no findings` explicitly. Also report which deterministic checks and semantic areas were covered, plus residual risks such as unavailable tools, unexecuted forward tests, inaccessible external systems, or behavior that depends on an unstated consumer environment.
