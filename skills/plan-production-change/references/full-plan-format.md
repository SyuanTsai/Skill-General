<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Full plan format

Use this template when the plan-production-change workflow selects the full format. Translate the headings into the user's language and omit optional operational entries that do not apply.

```markdown
# Plan: <feature or problem>

## 1. Objective and scope
- Expected outcome:
- Acceptance criteria:
- Deliverables:
- Out of scope:
- Assumptions / dependencies:
- Open decisions:

## 2. Planned changes

### 2.1 <change item>
- Target files / symbols:
- Current behavior or convention:
- Change:
- Reason:
- Impact or risk:

## 3. Test scenarios

### 3.1 <scenario>
- Related change:
- Test level:
- Given:
- When:
- Then:
- TDD: Red <failing test> → Green <minimum production change> → Refactor <cleanup while tests pass>; when exempt, give the reason and alternative validation.

## 4. Delivery and validation
- Validation commands or checks and expected results:
- Smoke / regression coverage:
- Rollout or migration:
- Rollback or recovery:
- Monitoring and success signals:

## 5. Risks and unresolved items
- Risk and mitigation:
- Unresolved or blocking item:
```
