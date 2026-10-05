<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# GitRef Handoff storage retirement

The GitRef Handoff storage capability is retired. This package does not provide a GitRef storage adapter. If trusted caller configuration explicitly selects GitRef for Handoff storage, report the source as unsupported and perform no source I/O. Do not infer GitRef from a `Source` field, fall back to another source, or automatically migrate data.

Retirement affects only this Skill's Handoff storage feature. Ordinary Git version control and repository work are unaffected. Existing refs, commits, and Handoff data are left untouched.

If the user explicitly requests recovery of an existing GitRef record, use a fixed compatible older release under the original authorization and in read-only mode. Any data recovery or export is a separate, specifically scoped request; this package does not provide an exporter or re-enable GitRef writes.
