---
command: provider
description: "Manage which AI providers Claude Octopus is allowed to dispatch to — persistent disable/enable with project + user scopes"
---

# Provider Control

Manage the set of AI providers Claude Octopus is allowed to dispatch to. Useful when:

- A provider isn't useful for your work (e.g., disable Copilot if you've found it doesn't add value)
- You want a project-scoped restriction (e.g., a client engagement that disallows certain external models)
- You want a session-scoped override (e.g., temporarily skip a provider that's having outages)

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes `/octo:provider` (with no args), `/octo:provider list`, or asks "what providers are enabled?", run:

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" provider list
```

Show the full output. The table includes per-provider status (`available` / `missing` / `disabled`) and source (which config file or env var disabled it, if applicable).

### Subcommands

```
/octo:provider                                  → equivalent to /octo:provider list
/octo:provider list                             → status table
/octo:provider disable <name> [--project]      → persistently disable
/octo:provider enable <name> [--project]       → re-enable
/octo:provider status <name>                   → detailed status for one provider
/octo:provider --help                          → usage
```

`--project` writes to `./.octopus/octo:providers.json` (commits with the repo, applies only when working in that project). Default scope is `--user` which writes to `~/.claude-octopus/config/octo:providers.json` (applies everywhere on your machine).

### Precedence

```
1. OCTO_ALLOWED_PROVIDERS env  (strict session allowlist — anything else treated as unavailable)
2. OCTO_DISABLED_PROVIDERS env (session denylist)
3. ./.octopus/octo:providers.json   (project scope, .disabled[])
4. ~/.claude-octopus/config/octo:providers.json (user scope, .disabled[])
```

Any source that disables a provider wins; env overrides persistent config.

### When NOT to use this command

- "Disable Claude" — Claude is the host runtime in Claude Code, not a dispatch target. Disabling it has no effect on workflows.
- One-shot exclusion of a provider for a single dispatch — pass the providers list explicitly to the dispatching skill/command instead.
- Disabling all providers — that defeats the multi-LLM value of Octopus. Use Claude-native `/review`, `/security-review`, etc. for single-LLM workflows.

### Examples

**Disable Copilot persistently** (you've found it doesn't add value):
```
/octo:provider disable copilot
```

**Disable Qwen for one project only** (the client doesn't allow it):
```
/octo:provider disable qwen --project
```

**Disable Gemini just for this session** (it's having an outage):
```
# Terminal:
export OCTO_DISABLED_PROVIDERS=gemini
# Then any /octo:* command will skip Gemini until the env var is unset
```

**Re-enable after a hiatus**:
```
/octo:provider enable copilot
```

### Post-execution

After any persistent change (`disable`/`enable`), run `/octo:provider list` to confirm the new state and show the user where the change took effect.

If the user disables a provider that the current dispatch pipeline was about to call (e.g., during a `/octo:debate`), surface the change but note that the in-flight call will complete as scheduled. Future calls will respect the new state.
