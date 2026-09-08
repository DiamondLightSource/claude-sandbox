---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Unless the user specifies a destination, save to `.claude/handoffs/` in the workspace, creating the directory if needed, with a unique timestamped filename. This ignored directory persists across sandbox sessions and is accessible to both Claude Code and Codex; `/tmp` is private to each sandbox session. Give the user the resulting path so the next agent can read it. For a different checkout or machine, the user must transfer the file explicitly.

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
