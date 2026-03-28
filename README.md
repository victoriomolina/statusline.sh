# statusline.sh

zero-bullshit statusline for claude code

📁 my-project               │ 🧠 opus-4.6         │ ⚡ main       │ █████░░░░░░░  42% 96k tokens │ ⏱️  2h 13m 08s

---

## what

a single bash script that reads json from stdin and renders a clean, colored, fixed-width status line.

no daemons  
no dependencies beyond `jq`  
no framework nonsense  

just pipes + ansi

---

## features

- 📁 project (cwd basename, truncated)
- 🧠 model (normalized: `claude-sonnet-4-20250514` -> `sonnet-4`)
- ⚡ agent (color-coded by type)
- █ context usage bar (green → yellow → red)
- 🔢 token count (k / M formatted)
- ⏱ session elapsed time

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
````

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
  "model": { "display_name": "claude-sonnet-4-20250514" },
  "context_window": {
    "used_percentage": 42,
    "total_input_tokens": 48000,
    "total_output_tokens": 48000
  },
  "workspace": { "current_dir": "/path/to/project" },
  "session": { "start_time": "2026-01-01T12:00:00Z" },
  "agent": { "name": "main", "type": "task" }
}
```

missing fields degrade gracefully.

---

## design notes

* **single `jq` call** → minimal overhead
* **fixed column widths** → stable layout, no jitter
* **ansi only** → works everywhere (no tput, no ncurses)
* **defensive parsing** → survives partial / malformed payloads
* **no subshell spam** → tight loops, predictable latency

---

## color semantics

| element  | color      |
| -------- | ---------- |
| project  | blue       |
| model    | cyan       |
| agent    | type-based |
| bar <50% | green      |
| bar <75% | yellow     |
| bar ≥75% | red        |
| metadata | gray       |

agent types:

* `plan` → yellow
* `explore` → cyan
* `task` → magenta
* default → white

---

## license

do whatever you want.
