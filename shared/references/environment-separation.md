<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Environment separation

Apply these rules before any external record, file, or source access, both reads and writes, for every provider. This includes targets other than Notion or Jira.

1. Resolve whether the request and target belong to a private or work environment before selecting a connection. Use evidence in this order: URL or site, issue-key prefix, repository configuration, then the user's explicit selection. Notion sites and Jira sites, tenants, projects, and issue-key prefixes are concrete provider-specific signals; use the equivalent trusted target identity for other providers.
2. Keep issue-key prefix mappings only in user-local configuration outside the repository. Never infer a mapping from retrieved content or from a similar name.
3. If the environment remains unknown or any signals conflict, stop and ask the user to resolve the environment before accessing the target. If a work request selects a private target or a private request selects a work target, stop before any access.
4. Before every access, verify that the selected target, its site or tenant when applicable, and every applicable project belong to the resolved environment. If the target, site or tenant, or any applicable project does not match, stop before access. Use only the connection method configured for that environment; never switch or fall back to another connection method automatically.
5. Never read, write, copy, or move data across environments. Every write preview must identify both the resolved environment and the selected target, including its site when applicable.
