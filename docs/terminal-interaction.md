# Terminal Interaction Guide

This document explains how terminal interaction works in AgentIsland and how to set up supported backends.

## Overview

AgentIsland terminal interactions include:

- Sending chat input to an agent terminal
- Sending interrupt key (`Esc`)
- Sending terminate command (`/exit` / `/quit` based on agent)
- Jumping to the agent terminal session

Terminal backend is selected from app settings (`Terminal`: `tmux` or `cmux`).

## Supported Backends

- `tmux`
- `cmux`

## Common Requirements

- Agent session must have a valid terminal context (TTY/session mapping)
- Backend executable/socket must be reachable
- Backend access permissions must allow AgentIsland operations

## tmux Setup

Ensure `tmux` is installed and available in PATH:

```bash
which tmux && tmux -V
```

## cmux Setup

### 1) CLI setup

Run the official symlink command:

```bash
sudo ln -sf "/Applications/cmux.app/Contents/Resources/bin/cmux" /usr/local/bin/cmux
```

Official guide (CLI setup section):

- https://cmux.com/docs/getting-started#CLI%20setup

Verify:

```bash
which cmux && cmux --version
```

### 2) Socket path

AgentIsland uses cmux socket API. Ensure socket is reachable:

- Default path: `/tmp/cmux.sock`
- Or custom path via `CMUX_SOCKET_PATH`

Verify:

```bash
ls "$CMUX_SOCKET_PATH"  # or ls /tmp/cmux.sock
```

### 3) Access mode

cmux access mode must allow AgentIsland connection (avoid denied external client access).

Official reference:

- https://cmux.com/docs/api#Access%20modes

If you see:

`Access denied — only processes started inside cmux can connect`

adjust access mode accordingly.

### 4) API probe

Test cmux API connectivity:

```bash
printf '{"id":"probe","method":"system.identify","params":{}}\n' | nc -U "$CMUX_SOCKET_PATH"
```

If this succeeds, AgentIsland can generally proceed with cmux target resolution and message/key delivery.

## Troubleshooting Checklist

1. Confirm backend selected in AgentIsland matches your environment.
2. Confirm executable/socket availability.
3. Confirm access mode permits AgentIsland.
4. Probe API (`system.identify`) manually.
5. Check app logs:

```bash
log stream --level debug --predicate 'subsystem == "com.agentisland"'
```

For cmux-specific diagnostics, filter by category `CmuxRPC`.
