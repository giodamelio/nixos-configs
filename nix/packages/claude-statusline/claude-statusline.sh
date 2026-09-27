# shellcheck shell=bash
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // empty')

# Share rate_limits with the bars over NATS KV. Only publish after a new API
# response (total_api_duration_ms moved), so an idle session re-rendering can't
# keep stale numbers alive past the bucket TTL.
publish_usage() {
    local session_id api_ms payload state_dir state_file last_ms
    session_id=$(echo "$input" | jq -r '.session_id // empty')
    api_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // empty')
    payload=$(echo "$input" | jq -c '
        def window: if . then {util: .used_percentage, resetsAt: .resets_at} else null end;
        .rate_limits // {}
        | select(.five_hour)
        | {source: "statusline", writtenAt: (now | floor), fiveHour: (.five_hour | window), sevenDay: (.seven_day | window)}')
    if [ -z "$session_id" ] || [ -z "$api_ms" ] || [ -z "$payload" ]; then
        return
    fi

    state_dir="$HOME/.cache/claude/statusline-usage"
    state_file="$state_dir/$session_id"
    mkdir -p "$state_dir"
    if [ -f "$state_file" ]; then
        read -r last_ms <"$state_file"
        if [ "$api_ms" = "$last_ms" ] || [ $(($(date +%s) - $(stat -c %Y "$state_file"))) -lt 30 ]; then
            return
        fi
    fi
    echo "$api_ms" >"$state_file"

    # Backgrounded with stdout closed so the statusline never waits on NATS.
    nats --server "$CLAUDE_USAGE_NATS_URL" --timeout 2s kv put claude-usage current "$payload" \
        >/dev/null 2>"$state_dir/last-put-error" &
}
publish_usage

if [ -n "$cwd" ]; then
    path_flag=(-p "$cwd")
else
    path_flag=()
fi

modules=(
    directory
    nix_shell
    nodejs python rust golang lua ruby java c
    dart elixir elm haskell kotlin perl php scala swift zig
    deno bun dotnet erlang gleam nim ocaml typst
)

# Claude Code metrics (first so they aren't cut off on narrow terminals)
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
five_hr=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hr_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')

parts=""
if [ -n "$model" ]; then
    parts+="\e[38;5;75m${model}\e[0m"
fi
cc=""
if [ -n "$ctx_pct" ]; then cc+="${ctx_pct%.*}%"; fi
if [ -n "$five_hr" ]; then
    reset_str=""
    if [ -n "$five_hr_reset" ]; then
        now=$(date +%s)
        diff=$((five_hr_reset - now))
        if [ "$diff" -gt 0 ] 2>/dev/null; then
            h=$((diff / 3600))
            m=$(((diff % 3600) / 60))
            if [ "$h" -gt 0 ]; then
                reset_str=" ${h}h${m}m"
            else
                reset_str=" ${m}m"
            fi
        fi
    fi
    cc+=" q:${five_hr%.*}%${reset_str}"
fi
if [ -n "$cost" ]; then
    cost_cents=$(printf '%.2f' "$cost")
    cc+=" \$${cost_cents}"
fi
if [ -n "$cc" ]; then
    parts+=" \e[38;5;209m✦ ${cc}\e[0m"
fi

# Custom jj status (can't use starship module for custom modules)
jj_seg=""
if [ -n "$cwd" ]; then
    cd "$cwd" || true
fi
if jj --ignore-working-copy root &>/dev/null; then
    jj_info=$(jj log 2>/dev/null --no-graph --ignore-working-copy --color=always --revisions @ --template 'surround("(", ")", separate(" ", bookmarks.join(", "), change_id.shortest(), commit_id.shortest(), if(conflict, "x"), if(empty, "(empty)", "*")))') || true
    if [ -n "$jj_info" ]; then
        jj_seg=" \e[38;5;75m󱗆\e[0m $jj_info"
    fi
fi

# Built-in starship modules (jj segment slots in just before nix_shell)
for mod in "${modules[@]}"; do
    if [ "$mod" = "nix_shell" ]; then
        parts+="$jj_seg"
    fi
    out=$(starship module "$mod" "${path_flag[@]}" 2>/dev/null) || true
    if [ -n "$out" ]; then
        parts+=" $out"
    fi
done

echo -ne "$parts" | sed 's/^[[:space:]]*//'
