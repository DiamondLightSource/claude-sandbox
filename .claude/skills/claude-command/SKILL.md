---
name: claude-command
description: Run a workspace command defined in .claude/commands when the user names that command or asks to list the available workspace commands. Supports verify-sandbox, memo, toolbox, toolbox-update, and future command files.
---

Locate the repository root and read `.claude/commands/<name>.md` in full.
Follow that file as the source of the workflow; do not maintain copied command
bodies here. Treat any remaining user text as the command's arguments. If no
command was named, list available command filenames and their descriptions.
If a named command is absent, report that instead of inventing a workflow.

Resolve project paths from the repository root. Use the current agent's
available tools for the requested operations. Claude-specific frontmatter
does not configure Codex tools, permissions, or model selection. Preserve
literal shell and awk variables when executing snippets.

In Codex, apply these compatibility rules:

- `toolbox`: enumerate current workspace commands and skill frontmatter instead
  of reproducing its cached Claude-global listing. Report only discoverable
  workspace entries; show skills as `$name` and commands as
  `$claude-command name`.
- `toolbox-update`: refresh the workspace copy only when `~/.claude` is
  unavailable. Mark that global scope as unavailable, not empty. Preserve the
  actual frontmatter and instruction paragraph when replacing the listing;
  the command's quoted delimiter may differ from the current file. State the
  scope refreshed. Do not create a replacement private Claude home directory.
- `memo`: use the shared `.claude/MEMORY.md` required by the project guidance.

For any other unavailable agent-specific capability, explain the limitation
and complete the independent steps that remain possible. Report the command's
actual result, including failures and skipped phases.
