# Global agent instructions

These apply across every repository and every agentic coding tool on this
machine (GitHub Copilot CLI, opencode, and anything else that reads a
global `AGENTS.md`/`CLAUDE.md`/`GEMINI.md`/`copilot-instructions.md`-style
file). Repo-specific instructions (e.g. this repo's own `AGENTS.md`) take
precedence for anything that conflicts - these are the baseline defaults
that hold everywhere else.

## Confirmation required

- **Let me review before committing.** Prepare/stage changes and show me
  what you intend to commit; don't run `git commit` on my behalf unless
  I've explicitly told you to just go ahead for this specific change.
- **Never push to a remote without my explicit confirmation first**,
  every time - a prior "yes" for one push does not carry over to the
  next one.
- **Never scan/search my entire disk, or large parts of it (especially
  my home directory), without asking first** - this applies doubly to
  anything that would *write*/modify files outside the current
  repository. Stay scoped to the current working directory and its
  children unless I've explicitly named another path.

## Persistent knowledge across sessions

- Use the shared **server-memory** MCP (the `memory` server) to store
  and recall knowledge that should persist across sessions/repos -
  durable facts, preferences, and context worth remembering later, not
  just this one conversation.
- Use the shared **Taskwarrior** MCP (the `taskwarrior` server) for
  anything that should become a tracked task. Always tag tasks you
  create with both `agent:<agent-name>` (which tool/agent created it -
  e.g. `agent:copilot`, `agent:opencode`) and `session:<session-id>`
  (an identifier for the current session/conversation), so tasks are
  traceable back to their origin.
- Tag a task `+attention` whenever it represents something that needs
  **my** (the human's) attention/decision/action - not just routine
  work an agent can pick up and finish on its own.
