# SSH Remote Sessions — Internals

Detailed implementation notes for the SSH remote session system. See [AGENTS.md](AGENTS.md) for the high-level overview.

## Host Model

`~/.mterm/ssh_hosts` is the **single source of truth** for the REMOTE sidebar. One hostname per line. `~/.ssh/config` is never auto-loaded or modified — it's only parsed for suggestions in the Add Host palette.

- `loadSshHosts()` reads `~/.mterm/ssh_hosts`
- `saveSshHosts()` writes all hosts back
- `loadSshSuggestions()` parses `~/.ssh/config`, filters out already-added hosts
- `bridge_add_ssh_host()` appends to the list + saves
- `bridge_remove_ssh_host()` kills active sessions for the host, removes from list + saves

## SSH Probe

Discovers remote tmux sessions by running:
```
ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new HOST "tmux list-sessions -F '#{session_name}'"
```

**Critical**: The format string MUST be single-quoted in the remote command string. SSH concatenates args and passes them to the remote shell. Without quotes, `#` is treated as a bash comment, making `tmux list-sessions -F` fail (no format arg → non-zero exit → 0 sessions returned). This was a real bug that caused all probes to return 0 sessions.

### Probe triggers
- First click on a disconnected host → probe in background thread
- Expanding a collapsed connected host → re-probe
- After `bridge_create_ssh_shell()` → re-probe (without changing status to `.connecting`)
- After `bridge_kill_remote_session()` → re-probe

### Probe resilience
- If a re-probe fails on an already-connected host, the existing session list is preserved (not wiped to 0)
- Re-probes after session creation do NOT set `host.status = .connecting` — this would hide the expanded view while probing
- `g_ssh_probe_thread` guards against concurrent probes

## Session Naming

| Action | Local tmux session name | Remote tmux session |
|--------|------------------------|---------------------|
| `+ New Session` | `ssh_HOST-N` | Auto-named, has `destroy-unattached on` |
| Click remote session | `ssh_HOST/SESSION` | Pre-existing session `SESSION` |

`bridge_is_ssh_session()` checks `ssh_` prefix. `isSshSessionForHost()` matches `ssh_HOST/` or `ssh_HOST-`.

SSH sessions are **hidden from SESSIONS** and shown under their host in **REMOTE**.

## Session Lifecycle

### Creating (+ New Session)
```
local: tmux new-session -d -s ssh_HOST-N ssh HOST -t "tmux new-session \; set-option destroy-unattached on"
```
- `destroy-unattached on` ensures the remote session auto-destroys when SSH disconnects
- From empty state: uses `startPtyAttach()` (NOT `startPty()` which creates an unwanted local session)

### Attaching (click remote session)
```
local: tmux new-session -d -s ssh_HOST/SESSION ssh HOST -t "tmux attach-session -t SESSION"
```

### Killing (× button)

**Active local SSH sessions** (`bridge_kill_session`):
1. If name contains `/` (attached session): SSH to remote, run `tmux kill-session -t SESSION`
2. Kill local tmux session
3. Re-probe the host to refresh sidebar

**Remote unattached sessions** (`bridge_kill_remote_session`):
1. SSH to remote, run `tmux kill-session -t SESSION`
2. Re-probe the host to refresh sidebar

**New sessions** (created via `+ New Session`):
- Have `destroy-unattached on` — remote session auto-destroys when local session is killed (SSH drops)

### Host removal (× on host)
1. Kill all local SSH sessions matching `ssh_HOST/` or `ssh_HOST-`
2. Remove from `~/.mterm/ssh_hosts`
3. Sync state

## FFI Functions

| Bridge function | Purpose |
|----------------|---------|
| `bridge_toggle_ssh_host(idx)` | Connect (probe) / expand+re-probe / collapse |
| `bridge_select_ssh_session(host, sess)` | Attach to a remote tmux session |
| `bridge_create_ssh_shell(host)` | Create new remote session via SSH |
| `bridge_kill_remote_session(host, sess)` | Kill a remote session via SSH + re-probe |
| `bridge_remove_ssh_host(idx)` | Remove host, kill its sessions |
| `bridge_load_ssh_suggestions()` | Load `~/.ssh/config` hosts for Add Host palette |
| `bridge_get_ssh_suggestion_count/name/name_len()` | Read suggestion list |
| `bridge_get_ssh_host_count/name/name_len/status/expanded()` | Read host list |
| `bridge_get_ssh_session_count/name/name_len()` | Read probe results |
| `bridge_get_ssh_active_count/session_idx/display/display_len()` | Read active local SSH sessions |
| `bridge_is_ssh_session(idx)` | Check if session has `ssh_` prefix |
