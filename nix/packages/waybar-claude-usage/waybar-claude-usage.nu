#!/usr/bin/env nu

def output-error [message: string] {
    {
        text: "Claude: --"
        tooltip: $"Error: ($message)"
        class: "error"
        percentage: 0
    } | to json --raw
}

def format-duration [seconds: int] {
    let hours = $seconds // 3600
    let mins = ($seconds mod 3600) // 60
    if $hours > 0 {
        $"($hours)h($mins)m"
    } else {
        $"($mins)m"
    }
}

def get-class [utilization: float] {
    if $utilization >= 80.0 {
        "critical"
    } else if $utilization >= 60.0 {
        "warning"
    } else {
        "normal"
    }
}

def get-token-from-omp []: nothing -> record<token: string, expires: int> {
    let db_path = $"($env.HOME)/.omp/agent/agent.db"
    if not ($db_path | path exists) {
        error make {msg: "OMP database not found"}
    }

    let result = (open $db_path
        | query db "SELECT data FROM auth_credentials WHERE provider='anthropic' AND credential_type='oauth' AND disabled=0 ORDER BY updated_at DESC LIMIT 1")

    if ($result | is-empty) {
        error make {msg: "No OAuth credentials in OMP database"}
    }

    let data = ($result | first | get data | from json)
    {token: $data.access, expires: $data.expires}
}

def get-token-from-claude-code []: nothing -> record<token: string, expires: int> {
    let creds_path = $"($env.HOME)/.claude/.credentials.json"
    if not ($creds_path | path exists) {
        error make {msg: "Claude Code credentials not found"}
    }

    let creds = (open $creds_path)
    if not ("claudeAiOauth" in $creds) {
        error make {msg: "No OAuth data in Claude Code credentials"}
    }

    let oauth = $creds.claudeAiOauth
    {token: $oauth.accessToken, expires: $oauth.expiresAt}
}

def get-token []: nothing -> record<token: string, expires: int> {
    try {
        get-token-from-omp
    } catch {
        get-token-from-claude-code
    }
}

def main [] {
    let creds = try {
        get-token
    } catch { |err|
        print (output-error $"No credentials: ($err.msg)")
        return
    }

    let now_ms = (date now | into int) // 1_000_000
    if $creds.expires < $now_ms {
        print (output-error "Token expired")
        return
    }

    let response = try {
        http get "https://api.anthropic.com/api/oauth/usage" --headers [
            "Authorization" $"Bearer ($creds.token)"
            "anthropic-beta" "oauth-2025-04-20"
            "User-Agent" "claude-code/2.1.29"
        ]
    } catch { |err|
        print (output-error $"API error: ($err.msg)")
        return
    }

    let five_hour = $response.five_hour.utilization
    let seven_day = $response.seven_day.utilization

    let reset_text = try {
        let reset_at = ($response.five_hour.resets_at | into datetime)
        let now = (date now)
        let diff_seconds = (($reset_at - $now) / 1sec) | into int
        if $diff_seconds > 0 {
            $" ⟳(format-duration $diff_seconds)"
        } else {
            ""
        }
    } catch {
        ""
    }

    let text = $"5h:($five_hour | into int)%($reset_text) 7d:($seven_day | into int)%"

    let tooltip_lines = [
        "Claude Usage"
        ""
        $"5-hour: ($five_hour)%"
        $"7-day: ($seven_day)%"
    ]

    let tooltip_lines = try {
        $tooltip_lines | append $"  Opus: ($response.seven_day_opus.utilization)%"
    } catch {
        $tooltip_lines
    }

    let tooltip_lines = try {
        $tooltip_lines | append $"  Sonnet: ($response.seven_day_sonnet.utilization)%"
    } catch {
        $tooltip_lines
    }

    let tooltip = ($tooltip_lines | str join "\n")
    let class = (get-class $five_hour)

    print ({
        text: $text
        tooltip: $tooltip
        class: $class
        percentage: ($five_hour | into int)
    } | to json --raw)
}
