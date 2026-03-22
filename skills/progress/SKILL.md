---
name: progress
description: Report current agent activity to ~/.progress/ so Ben can see what's happening in real-time.
user-invocable: false
allowed-tools:
  - Bash
---

# Progress Reporter

Call this skill whenever you start a significant new task, switch focus, or complete a milestone. Write to `~/.progress/` so the menu bar app and CLI can display your current activity.

## When to invoke

- Starting a new task or subtask
- Switching to a different area of work
- Completing a task (status: done)
- Blocked or waiting (status: waiting)
- Thinking through a problem (status: thinking)
- On error (status: error)

## How to write

Use a single Bash call with `printf`. Never use `jq`. Always end with `|| true` so a write failure never blocks you.

```bash
# Gather context
_AGENT="claude-code"
_HOSTNAME=$(uname -n | tr '[:upper:]' '[:lower:]' | sed 's/\.local$//' | sed 's/[^a-z0-9]/-/g')
_SESSION_FILE="/tmp/.progress-session-${_AGENT}-${_HOSTNAME}"
[[ -f "$_SESSION_FILE" ]] || printf '%s-%s\n' "$_HOSTNAME" "$(date -u +%Y%m%dT%H%M%SZ)" > "$_SESSION_FILE"
_PROGRESS_SESSION=$(cat "$_SESSION_FILE")
_PROGRESS_PROJECT=$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null || basename "$(pwd)")
_PROGRESS_PROJECT_PATH=$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || pwd)
_PROGRESS_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
mkdir -p ~/.progress

# Write current-{agent}-{hostname}.json (overwrite)
printf '{"version":1,"agent":"%s","hostname":"%s","project":"%s","projectPath":"%s","task":"%s","status":"%s","detail":"%s","startedAt":"%s","updatedAt":"%s","sessionId":"%s"}\n' \
  "$_AGENT" "$_HOSTNAME" "$_PROGRESS_PROJECT" "$_PROGRESS_PROJECT_PATH" \
  "TASK_HERE" "STATUS_HERE" "DETAIL_HERE" \
  "$_PROGRESS_TS" "$_PROGRESS_TS" "$_PROGRESS_SESSION" \
  > ~/.progress/current-${_AGENT}-${_HOSTNAME}.json || true

# Append to history.jsonl
printf '{"version":1,"agent":"%s","hostname":"%s","project":"%s","projectPath":"%s","task":"%s","status":"%s","detail":"%s","startedAt":"%s","updatedAt":"%s","sessionId":"%s"}\n' \
  "$_AGENT" "$_HOSTNAME" "$_PROGRESS_PROJECT" "$_PROGRESS_PROJECT_PATH" \
  "TASK_HERE" "STATUS_HERE" "DETAIL_HERE" \
  "$_PROGRESS_TS" "$_PROGRESS_TS" "$_PROGRESS_SESSION" \
  >> ~/.progress/history-${_HOSTNAME}.jsonl || true

# Push to remote backend (fire-and-forget, skipped if token/endpoint not set)
if [[ -n "${PROGRESS_TOKEN:-}" && -n "${PROGRESS_ENDPOINT:-}" ]]; then
  curl -sf -X POST "${PROGRESS_ENDPOINT}/update" \
    -H "Authorization: Bearer ${PROGRESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"version\":1,\"agent\":\"${_AGENT}\",\"hostname\":\"${_HOSTNAME}\",\"project\":\"${_PROGRESS_PROJECT}\",\"projectPath\":\"${_PROGRESS_PROJECT_PATH}\",\"task\":\"TASK_HERE\",\"status\":\"STATUS_HERE\",\"detail\":\"DETAIL_HERE\",\"startedAt\":\"${_PROGRESS_TS}\",\"updatedAt\":\"${_PROGRESS_TS}\",\"sessionId\":\"${_PROGRESS_SESSION}\"}" \
    --max-time 3 --retry 0 -o /dev/null 2>/dev/null || true
fi
```

## Status values

| Status     | When to use                                 |
|------------|---------------------------------------------|
| `working`  | Actively writing code, files, running tools |
| `thinking` | Reasoning through a problem, planning       |
| `waiting`  | Waiting for user input or external process  |
| `done`     | Task complete                               |
| `error`    | Hit an error or blocker                     |
| `idle`     | Session ending or no active task            |

## Guidelines

- **task**: Short verb phrase describing what you're doing right now. Max ~60 chars. Examples: "Writing ProgressStore.swift", "Running tests", "Fixing compilation errors"
- **detail**: Optional. Extra context, error message, or filename. Empty string if none.
- **startedAt**: Set once when the task begins; keep it stable across updates to the same task.
- **updatedAt**: Always set to current time.
- Escape any double-quotes in task/detail with `\"`.
- Never block on this write. The `|| true` guard is mandatory.
- Session ID is stable for the lifetime of the boot (stored in `/tmp/`). Resets on reboot.
