#!/usr/bin/env bash

# ~/.claude/statusline.sh

# Claude Code status line: project . model . agent . rate limit . context . diff . cost . time

# Reads the JSON payload Claude Code pipes to stdin and renders a single-line
# status bar with ANSI colors.

# Requirements: bash >= 4.0, jq
#   macOS:  brew install bash jq
#   Linux:  apt install jq  |  dnf install jq

# NOTE: Do NOT use `set -euo pipefail` here. A single jq or printf hiccup must
# not blank the entire status line. Each section handles its own errors.

# Layout constants
readonly BAR_WIDTH=12
readonly COL_PROJECT=14
readonly COL_MODEL=12
readonly COL_AGENT=10

# ANSI palette
readonly reset=$'\033[0m'
readonly bold=$'\033[1m'
readonly dim=$'\033[2m'
readonly fg_red=$'\033[31m'
readonly fg_green=$'\033[32m'
readonly fg_yellow=$'\033[33m'
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
  local n="${1:-0}"

  if ((n >= 1000000)); then
    printf '%d.%dM' $((n / 1000000)) $(((n % 1000000) / 100000))
  elif ((n >= 1000)); then
    printf '%dk' $((n / 1000))
  else
    printf '%d' "$n"
  fi
}

# format_elapsed MS -> "4m 32s" or "1h 07m"
format_elapsed() {
  local ms="${1:-0}"
  local total=$((ms / 1000))
  local h=$((total / 3600))
  local m=$(((total % 3600) / 60))
  local s=$((total % 60))

  if ((h > 0)); then
    printf '%dh%02dm' "$h" "$m"
  elif ((m > 0)); then
    printf '%dm%02ds' "$m" "$s"
  else
    printf '%ds' "$s"
  fi
}

# format_cost USD_FLOAT -> "$0.04", "$1.23", "$12"
format_cost() {
  awk -v v="$1" 'BEGIN {
    if (v >= 10)      printf "$%.0f",  v
    else if (v >= 1)  printf "$%.1f",  v
    else              printf "$%.2f",  v
  }'
}

# render_bar PCT -> ANSI-colored block progress bar (green -> yellow -> red)
render_bar() {
  local pct="${1:-0}"
  local capped=$((pct > 100 ? 100 : pct))
  local filled=$((capped * BAR_WIDTH / 100))
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

# Parse JSON -- single jq invocation, pipe-delimited output.
# Tab delimiter fails: bash `read` treats tab as IFS-whitespace and collapses
# consecutive instances, swallowing empty fields like absent agent_name.

input=$(cat)

readonly delim='|'

IFS="$delim" read -r \
  model \
  ctx_pct \
  ctx_input_tokens \
  ctx_cache_create \
  ctx_cache_read \
  cwd \
  agent_name \
  five_hour_pct \
  lines_added \
  lines_removed \
  cost_usd \
  duration_ms \
  <<< "$(echo "$input" | jq -r '[
    (.model.display_name // "unknown"),

    ((.context_window.used_percentage // 0) | floor | [., 0] | max | [., 100] | min),

    ((.context_window.current_usage.input_tokens // 0) | floor),
    ((.context_window.current_usage.cache_creation_input_tokens // 0) | floor),
    ((.context_window.current_usage.cache_read_input_tokens // 0) | floor),

    (.workspace.current_dir // .cwd // ""),

    (if (.agent | type) == "object"
        and (.agent.name | type) == "string"
        and (.agent.name | length) > 0
     then .agent.name
     else "" end),

    (.rate_limits.five_hour.used_percentage
     | if . != null and (type == "number") and . >= 0
       then (. | floor)
       else -1 end),

    ((.cost.total_lines_added   // 0) | floor),
    ((.cost.total_lines_removed // 0) | floor),

    (.cost.total_cost_usd
     | if . != null and (type == "number") and . > 0
       then .
       else -1 end),

    ((.cost.total_duration_ms // 0) | floor)

  ] | map(tostring) | join("|")' 2>/dev/null)" || true

# Fallback if jq failed entirely
model="${model:-unknown}"
ctx_pct="${ctx_pct:-0}"

# Derived: project name
project=$(truncate "$(basename "${cwd:-$PWD}")" "$COL_PROJECT")

# Derived: short model name
short_model=$(truncate "$model" "$COL_MODEL")

# Derived: agent label (only when an agent is active)
agent_label=""

if [[ -n "$agent_name" && "$agent_name" != "null" && ! "$agent_name" =~ ^[0-9]+$ ]]; then
  agent_label=$(truncate "$agent_name" "$COL_AGENT")
fi

# Derived: 5h rate-limit bar (hidden when unavailable)
bar_pct=""

if [[ "$five_hour_pct" =~ ^[0-9]+$ && "$five_hour_pct" -ge 0 ]]; then
  bar_pct=$((10#$five_hour_pct))
fi

# Derived: context token display (input + cache tokens from current_usage)
ctx_total_tokens=$(( ${ctx_input_tokens:-0} + ${ctx_cache_create:-0} + ${ctx_cache_read:-0} ))
token_display=""

if ((ctx_total_tokens > 0)); then
  token_display=$(format_tokens "$ctx_total_tokens")
fi

# Derived: lines changed (only when at least one side is non-zero)
diff_display=""

if [[ "${lines_added:-0}" != "0" || "${lines_removed:-0}" != "0" ]]; then
  diff_display=$(printf "${fg_green}+%s${reset} ${fg_red}-%s${reset}" \
    "$(format_tokens "${lines_added:-0}")" "$(format_tokens "${lines_removed:-0}")")
fi

# Derived: session cost (only when non-zero)
cost_display=""

if [[ "$cost_usd" =~ ^[0-9] && "$cost_usd" != "-1" ]]; then
  cost_display=$(format_cost "$cost_usd")
fi

# Derived: session elapsed time
session_time=""

if [[ "${duration_ms:-0}" =~ ^[0-9]+$ && "${duration_ms:-0}" != "0" ]]; then
  session_time=$(format_elapsed "$duration_ms")
fi

# Render
#   📁 project  │  model  │  ⚡ agent  │  ████ N%  │  🧠 ctx% tokens  │  +N -N  │  💰 $N  │  ⏱ elapsed

readonly sep="${fg_gray}│${reset}"

printf "${bold}${fg_white}📁 %s${reset}" "$project"

printf ' %s ' "$sep"
printf "${fg_cyan}%s${reset}" "$short_model"

if [[ -n "$agent_label" ]]; then
  printf ' %s ' "$sep"
  printf "${fg_white}⚡ %s${reset}" "$agent_label"
fi

if [[ -n "$bar_pct" ]]; then
  printf ' %s ' "$sep"
  printf '%s' "$(render_bar "$bar_pct")"
  printf " ${bold}%d%%${reset}" "$bar_pct"
fi

printf ' %s ' "$sep"

if [[ -n "$token_display" ]]; then
  printf "🧠 ${bold}%d%%${reset} ${fg_gray}%s${reset}" "$ctx_pct" "$token_display"
else
  printf "🧠 ${bold}%d%%${reset}" "$ctx_pct"
fi

if [[ -n "$diff_display" ]]; then
  printf ' %s ' "$sep"
  printf '%s' "$diff_display"
fi

if [[ -n "$cost_display" ]]; then
  printf ' %s ' "$sep"
  printf "${fg_gray}💰 ${bold}${fg_white}%s${reset}" "$cost_display"
fi

if [[ -n "$session_time" ]]; then
  printf ' %s ' "$sep"
  printf "${fg_gray}⏱ %s${reset}" "$session_time"
fi

printf '\n'
