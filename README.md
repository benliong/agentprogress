# agentprogress

Real-time visibility into what your AI agents are doing — across every machine, in your menu bar.

Agents (Claude Code, Friday, OpenClaw, etc.) report their current task via a bash skill. Updates flow to a Cloudflare Worker and appear in a macOS menu bar app and CLI within ~10 seconds, from any machine.

---

## How it works

```
Agent (bash skill)
  → POST /update to Cloudflare Worker
    → stored in KV (keyed by token hash + hostname + agent)
      → macOS menu bar polls every 10s → shows all your agents
      → CLI: `progress show` / `progress history`

Local files (~/.progress/) written simultaneously → FSEvents → instant local update
```

**Token = user identity.** Each user generates one token, shared across all their machines. The Worker namespaces all data by `sha256(token)[0:12]` — no registration, no user management, complete isolation between users.

---

## Components

| Component | Location | Purpose |
|---|---|---|
| `Sources/ProgressCore` | Swift library | Models, file watching, remote polling, config |
| `Sources/ProgressMenuBar` | macOS app | Menu bar display, polls backend every 10s |
| `Sources/progress` | CLI | `show`, `history`, `watch`, `clear` |
| `worker/` | Cloudflare Worker | HTTP relay + KV storage |
| Skills | `~/.claude/skills/progress/` | Bash snippet agents invoke to report status |

---

## Quick Start

### 1. Deploy the Worker

```bash
cd worker
npm install
wrangler kv:namespace create PROGRESS_KV   # copy the returned ID into wrangler.toml
# Edit wrangler.toml: paste the KV namespace ID
wrangler deploy
# Note your Worker URL: https://progress-tracker.<subdomain>.workers.dev
```

### 2. Configure your machines

Add to `~/.zshrc` on **each machine** that runs agents (same token everywhere):

```bash
export PROGRESS_TOKEN="$(openssl rand -hex 16)"   # generate once, reuse on all machines
export PROGRESS_ENDPOINT="https://progress-tracker.<subdomain>.workers.dev"
```

Create `~/.progress/config.json` on machines running the **menu bar app** (shell env isn't inherited by Login Items):

```json
{
  "endpoint": "https://progress-tracker.<subdomain>.workers.dev",
  "token": "your-token-here"
}
```

### 3. Build and install

```bash
swift build -c release
# Install CLI
ln -sf $(pwd)/.build/release/progress ~/.local/bin/progress
# Launch menu bar app
open .build/release/ProgressMenuBar
```

### 4. Install the agent skill

Copy `skills/progress/SKILL.md` to wherever your agent loads skills from. For Claude Code:

```bash
cp skills/progress/SKILL.md ~/.claude/skills/progress/SKILL.md
```

The skill writes to `~/.progress/` locally **and** POSTs to the backend if `PROGRESS_TOKEN` + `PROGRESS_ENDPOINT` are set. If they're not set, it works in local-only mode silently.

---

## CLI Usage

```bash
progress           # show active agents
progress show      # same
progress history   # last 20 entries (merges local + remote)
progress history --last 50 --json  # JSONL output
progress watch     # live-tail (updates on file change)
progress clear     # clear all current-*.json files
```

---

## Architecture Details

### Token isolation

No server-side user management. The Worker derives `userId = sha256(token).slice(0, 12)` and prefixes all KV keys with it. Any token gets its own isolated namespace automatically. Two users sharing the same backend never see each other's data.

### KV schema

| Key | Value | TTL |
|---|---|---|
| `current:{userId}:{hostname}:{agent}` | ProgressEntry JSON | 4 hours (auto-expires stale sessions) |
| `history:{userId}` | JSONL blob, max 500 lines | None |

### Local + remote merge

The menu bar and CLI merge local file entries (via FSEvents, instant) with remote entries (polled every 10s). Local entries win for the same `agent+hostname` pair — they're written simultaneously with the remote push so are always at least as fresh.

### Stale session handling

- **Proper shutdown**: agent writes `status: done` or `idle` → filtered from actives immediately
- **Crash/timeout**: KV TTL of 4 hours auto-expires the entry; local files filtered after 2 hours

---

## Status Values

| Status | When |
|---|---|
| `working` | Actively writing code, running tools |
| `thinking` | Reasoning through a problem |
| `waiting` | Waiting for user input or external process |
| `done` | Task complete |
| `error` | Hit an error or blocker |
| `idle` | Session ending |

---

## Multi-user / Publishing the Skill

Each user deploys their own Worker (free Cloudflare tier: 100k req/day, well within personal use limits) and generates their own token. The skill file has no hardcoded values — it reads `PROGRESS_TOKEN` and `PROGRESS_ENDPOINT` from the environment. Users without these set get silent local-only mode.

---

## Requirements

- macOS 15+ (menu bar app)
- Swift 6.0+ (build)
- Node.js + Wrangler (worker deployment, one-time)
- Cloudflare account (free tier sufficient)
