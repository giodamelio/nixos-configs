#!/usr/bin/env nu

# Find files that frequently change together with a target file by analyzing git commit history
#
# This script analyzes the git history to find files that are commonly modified
# in the same commits as your target file, which indicates logical coupling.
# Useful for understanding which files might need changes when modifying the target.
def main [
    target_file: string  # Path to the file you want to find related files for
    --limit (-l): int = 15  # Maximum number of related files to show (default: 15)
    --commits (-c): int = 0  # Number of recent commits to analyze (0 = unlimited, default: unlimited)
    --format (-f): string = "auto"  # Output format: json, table, or auto (default: auto - detects TTY)
] {
    let commit_hashes = (git log --pretty=format:%H -- $target_file | lines)

    # Apply commit limit only if specified (non-zero)
    let filtered_commits = if $commits > 0 {
        $commit_hashes | first $commits
    } else {
        $commit_hashes
    }

    let related_files = ($filtered_commits
        | each { |commit|  # For each commit that touched our target file
            git show --name-only --pretty=format: $commit
            | lines  # Split the file list into individual filenames
            | where ($it != "" and $it != $target_file)  # Filter out empty lines and the target file itself
        }
        | flatten  # Combine all file lists into a single list
        | histogram  # Count frequency of each file (built-in Nushell command)
        | sort-by count --reverse  # Sort by frequency, most common first
        | first $limit  # Show only the top N results
        | rename file frequency)  # Rename columns for clarity

    # Determine output format
    let output_format = if $format == "auto" {
        # If output is being piped or redirected, use JSON
        try {
            # let is_tty = (tty | complete | get exit_code) == 0
            let is_tty = (is-terminal --stdout)
            if $is_tty { "table" } else { "json" }
        } catch {
            "json"  # Default to JSON if we can't detect
        }
    } else {
        $format
    }

    # Output in determined format
    match $output_format {
        "json" => {
            {
                target_file: $target_file,
                total_commits_analyzed: ($filtered_commits | length),
                related_files: $related_files
            } | to json
        },
        "table" => {
            $related_files
        },
        _ => {
            error make {msg: "Invalid format. Use: json, table, or auto"}
        }
    }
}
