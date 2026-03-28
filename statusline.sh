#!/usr/bin/env bash

# ~/.claude/statusline.sh

# Claude Code status line: project · model · agent · tokens · time

# Reads the JSON payload Claude Code pipes to stdin and renders a single-line
# status bar with ANSI colors.

# Requirements: bash ≥ 4.0, jq
#   macOS:  brew install bash jq
#   Linux:  apt install jq  |  dnf install jq

set -euo pipefail

# Layout constants
readonly BAR_WIDTH=12
readonly COL_PROJECT=24
readonly COL_MODEL=16
readonly COL_AGENT=10

# ANSI palette
readonly reset=$'\033[0m'
readonly bold=$'\033[1m'
readonly dim=$'\033[2m'
readonly fg_red=$'\033[31m'
readonly fg_green=$'\033[32m'
readonly fg_yellow=$'\033[33m'
readonly fg_blue=$'\033[34m'
readonly fg_magenta=$'\033[35m'
readonly fg_cyan=$'\033[36m'
readonly fg_white=$'\033[97m'
readonly fg_gray=$'\033[90m'

# Helpers

# truncate STR MAX_LEN -> STR trimmed with ellipsis
truncate() {
  local str="$1" max="$2"

  ((${#str} > max)) && str="${str:0:$((max - 1))}..."
  printf '%s' "$str"
}

# format_tokens N -> human-readable count: 96k, 1.2M, or raw integer
format_tokens() {
  local n=$1

  if ((n >= 1000000)); then
    printf '%d.%dM' $((n / 1000000)) $(((n % 1000000) / 100000))
  elif ((n >= 1000)); then
    printf '%dk' $((n / 1000))
  else
    printf '%d' "$n"
  fi
}

# format_elapsed SECONDS -> "4m 32s" or "1h 7m 18s"
format_elapsed() {
  local total=$1
  local h=$((total / 3600))
  local m=$(((total % 3600) / 60))
  local s=$((total % 60))

  if ((h > 0)); then
    printf '%dh %dm %02ds' "$h" "$m" "$s"
  else
    printf '%dm %02ds' "$m" "$s"
  fi
}

# parse_epoch ISO8601 -> Unix timestamp, or empty string on failure.
parse_epoch() {
  local ts="$1" epoch=""

  if command -v gdate &>/dev/null; then
    epoch=$(gdate -d "$ts" +%s 2>/dev/null) || true
  elif date -d "$ts" +%s &>/dev/null 2>&1; then
    epoch=$(date -d "$ts" +%s)
  else
    epoch=$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null) || true
  fi

  printf '%s' "$epoch"
}

# render_bar PCT -> ANSI-colored block progress bar (green -> yellow -> red)
render_bar() {
  local pct=$1
  local filled=$((pct * BAR_WIDTH / 100))
  local empty=$((BAR_WIDTH - filled))
  local color

  if ((pct < 50)); then
    color="$fg_green"
  elif ((pct < 75)); then
    color="$fg_yellow"
  else
    color="$fg_red"
  fi

  local bar="${color}" i

  for ((i = 0; i < filled; i++)); do bar+='█'; done

  bar+="${dim}${fg_gray}"

  for ((i = 0; i < empty; i++)); do bar+='░'; done

  printf '%s%s' "$bar" "$reset"
}

# Parse JSON — single jq invocation, tab-separated output
input=$(cat)

IFS=$'\t' read -r model ctx_pct in_tok out_tok cwd start_ts agent_name agent_type < <(
  jq -r '[
    .model.display_name                              // "unknown",
    (.context_window.used_percentage // 0 | floor | tostring),
    (.context_window.total_input_tokens  // 0 | tostring),
    (.context_window.total_output_tokens // 0 | tostring),
    .workspace.current_dir                           // "",
    .session.start_time                              // "",
    .agent.name                                      // "",
    .agent.type                                      // ""
  ] | join("\t")' <<<"$input"
)

# Derived: project name
project=$(truncate "$(basename "$cwd")" "$COL_PROJECT")

# Derived: short model name ("claude-sonnet-4-20250514" -> "sonnet-4")
short_model=$(truncate "$(sed -E 's/^claude-//; s/-[0-9]{8}$//' <<<"$model")" "$COL_MODEL")

# Derived: agent label + color
if [[ -n "$agent_name" ]]; then
  [[ "$agent_name" != "$agent_type" ]] && agent_raw="$agent_name" || agent_raw="$agent_type"

  agent_label=$(truncate "$agent_raw" "$COL_AGENT")

  case "$agent_type" in
  plan) agent_color="$fg_yellow" ;;
  explore) agent_color="$fg_cyan" ;;
  task) agent_color="$fg_magenta" ;;
  *) agent_color="$fg_white" ;;
  esac
else
  agent_label="main"
  agent_color="$fg_gray"
fi

# Derived: session elapsed time

session_time="--:--"

if [[ -n "$start_ts" ]]; then
  start_epoch=$(parse_epoch "$start_ts")

  if [[ -n "$start_epoch" ]]; then
    elapsed=$(($(date +%s) - start_epoch))
    elapsed=$((elapsed < 0 ? 0 : elapsed)) # guard against clock skew
    session_time=$(format_elapsed "$elapsed")
  fi
fi

# Derived: token display
token_display=$(format_tokens $((in_tok + out_tok)))

# Render
#   📁 my-project  │  🧠 sonnet-4  │  ⚡ main  │  ████░░░░░░░░  42%  96k tokens  │  ⏱️ 4m 32s
readonly sep="${fg_gray}│${reset}"

printf ' '
printf "${fg_blue}${bold}📁 %-*s${reset}" "$COL_PROJECT" "$project"
printf ' %s ' "$sep"
printf "${fg_cyan}🧠 %-*s${reset}" "$COL_MODEL" "$short_model"
printf ' %s ' "$sep"
printf "${agent_color}⚡ %-*s${reset}" "$COL_AGENT" "$agent_label"
printf ' %s ' "$sep"
printf '%s ' "$(render_bar "$ctx_pct")"
printf "${bold}%3d%%${reset}" "$ctx_pct"
printf " ${fg_gray}%s tokens${reset}" "$token_display"
printf ' %s ' "$sep"
printf "${fg_white}⏱️  %s${reset}" "$session_time"
printf '\n'
