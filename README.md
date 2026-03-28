# statusline.sh

zero-bullshit statusline for claude code

📁 my-project  │ sonnet-4.6  │ ⚡ main  │ ████░░░░░░░░ 38%  │ 🧠 42% 96k  │ +1k -240  │ 💰 $0.84  │ ⏱ 14m32s

---

## what

a single bash script that reads json from stdin and renders a clean, colored status line.

no daemons  
no dependencies beyond `jq`  
no framework nonsense

just pipes + ansi

---

## features

- 📁 project (cwd basename, truncated)
- model name (truncated display name)
- ⚡ agent (only shown when an agent is active)
- █ 5-hour rate limit bar (green → yellow → red, hidden when unavailable)
- 🧠 context window % + token count (input + cache, k / M formatted)
- +N -N lines changed (hidden when zero)
- 💰 session cost (hidden when zero)
- ⏱ session elapsed time (hidden when zero)

all sections are conditional — absent data collapses cleanly, no placeholders

---

## requirements

- bash >= 4
- `jq`
```bash
# macos
brew install bash jq

# debian/ubuntu
apt install jq

# fedora
dnf install jq
```

---

## install
```bash
mkdir -p ~/.claude
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

---

## usage

claude code pipes a json payload into the script:
```bash
cat payload.json | ~/.claude/statusline.sh
```

or wire it into your claude config (depending on your setup).

---

## input contract (json)

expects fields like:
```json
{
  "model": { "display_name": "claude-sonnet-4-6" },
  "context_window": {
    "used_percentage": 42,
    "current_usage": {
      "input_tokens": 48000,
      "cache_creation_input_tokens": 12000,
      "cache_read_input_tokens": 36000
    }
  },
  "workspace": { "current_dir": "/path/to/project" },
  "agent": { "name": "main" },
  "rate_limits": {
    "five_hour": { "used_percentage": 38 }
  },
  "cost": {
    "total_cost_usd": 0.84,
    "total_duration_ms": 872000,
    "total_lines_added": 1024,
    "total_lines_removed": 240
  }
}
```

missing fields degrade gracefully.

---

## design notes

- **no `set -euo pipefail`** → a single jq or printf hiccup must not blank the entire status line; each section handles its own errors
- **single `jq` call** → minimal overhead
- **pipe delimiter** → tab-based IFS collapses consecutive empty fields; `|` is safe
- **conditional sections** → absent data hides the section entirely, no dead space
- **ansi only** → works everywhere (no tput, no ncurses)
- **defensive parsing** → survives partial / malformed payloads

---

## color semantics

| element      | color  |
| ------------ | ------ |
| project      | white  |
| model        | cyan   |
| agent        | white  |
| bar < 50%    | green  |
| bar < 75%    | yellow |
| bar ≥ 75%    | red    |
| lines added  | green  |
| lines removed| red    |
| cost         | gray   |
| elapsed      | gray   |

---

## license

do whatever you want.
