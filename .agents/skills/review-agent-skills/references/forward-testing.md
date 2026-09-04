<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Forward Testing Agent Skills

Use forward testing when a complex or high-risk workflow cannot be validated confidently from static inspection, when routing boundaries are uncertain, or when the Skill depends on agent interpretation rather than a deterministic script.

## Design representative scenarios

- Include should-trigger requests that exercise the Skill's primary responsibility and important variants.
- Include should-not-trigger requests for adjacent capabilities and ordinary questions outside the Skill's scope.
- Include missing-tool, missing-access, unsafe-ambiguity, and partial-failure cases when relevant.
- State observable expectations for selected resources, tool choices, confirmation boundaries, produced artifacts, and completion or stop conditions.

Do not embed the intended answer or quote the decisive Skill instruction in the scenario. Test whether the package guides behavior from realistic user context.

## Execute safely

Use an isolated workspace or disposable fixtures. Do not perform real external writes, destructive actions, publish comments, or use sensitive credentials unless the user has explicitly authorized that exact operation. When an independent evaluator is authorized and available, give it the scenario and package under review without supplying the expected conclusion.

Capture the prompt, relevant environment assumptions, observed actions, outputs, errors, and evidence. Distinguish a product limitation or missing capability from a Skill defect.

## Interpret results

Compare observed behavior with the scenario's acceptance criteria. A single successful run is supporting evidence, not proof of universal correctness. Convert reproducible gaps into evidence-backed findings, make only the narrowest correction when implementation is requested, and rerun both the failing scenario and nearby negative cases.
