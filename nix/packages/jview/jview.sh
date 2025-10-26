#!/usr/bin/env bash

# jview - A convenient wrapper for viewing journalctl logs
# Usage: jview <unit_name>

set -euo pipefail

# Check if unit name was provided
if [ $# -eq 0 ]; then
    echo "Usage: jview <unit_name>"
    echo "Example: jview nginx"
    echo "         jview ssh"
    exit 1
fi

UNIT_NAME="$1"
PAGER="${PAGER:-less}"

# Set LESS options to handle colors properly if using less
if [[ "$PAGER" == *"less"* ]]; then
    export LESS="${LESS:--R}"
fi

# Function to check if a systemd unit exists
unit_exists() {
    local unit="$1"
    local type="$2"

    if [ "$type" = "system" ]; then
        systemctl list-unit-files --all --no-legend | grep -q "^${unit}\.service\|^${unit}\.timer\|^${unit}\.socket" 2>/dev/null
    else
        systemctl --user list-unit-files --all --no-legend | grep -q "^${unit}\.service\|^${unit}\.timer\|^${unit}\.socket" 2>/dev/null
    fi
}

# Function to find similar unit names
find_similar_units() {
    local search="$1"
    local matches=()

    # Search for system units containing the search term
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            matches+=("$line (system)")
        fi
    done < <(systemctl list-unit-files --all --no-legend | awk '{print $1}' | grep -i "$search" | head -10)

    # Search for user units containing the search term
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            matches+=("$line (user)")
        fi
    done < <(systemctl --user list-unit-files --all --no-legend 2>/dev/null | awk '{print $1}' | grep -i "$search" | head -10)

    # Also search for partial matches at the beginning
    if [ ${#matches[@]} -eq 0 ]; then
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                matches+=("$line (system)")
            fi
        done < <(systemctl list-unit-files --all --no-legend | awk '{print $1}' | grep "^${search}" | head -10)

        while IFS= read -r line; do
            if [ -n "$line" ]; then
                matches+=("$line (user)")
            fi
        done < <(systemctl --user list-unit-files --all --no-legend 2>/dev/null | awk '{print $1}' | grep "^${search}" | head -10)
    fi

    if [ ${#matches[@]} -gt 0 ]; then
        echo "Unit '${UNIT_NAME}' not found. Did you mean one of these?"
        echo ""
        printf '%s\n' "${matches[@]}" | sort -u
        return 0
    else
        return 1
    fi
}

# Function to view logs with appropriate permissions
view_logs() {
    local unit="$1"
    local type="$2"

    if [ "$type" = "system" ]; then
        # Check if we need sudo
        if journalctl -u "$unit" -n 1 >/dev/null 2>&1; then
            # We can read without sudo
            SYSTEMD_COLORS=1 journalctl --output=short-precise --all -u "$unit" -f | $PAGER
        else
            # We need sudo
            echo "Requesting sudo privileges to view system logs..."
            sudo SYSTEMD_COLORS=1 journalctl --output=short-precise --all -u "$unit" -f | $PAGER
        fi
    else
        # User unit logs don't need sudo
        SYSTEMD_COLORS=1 journalctl --output=short-precise --all --user -u "$unit" -f | $PAGER
    fi
}

# Main logic

# First, check if it's a full unit name with extension
if [[ "$UNIT_NAME" == *.service ]] || [[ "$UNIT_NAME" == *.timer ]] || [[ "$UNIT_NAME" == *.socket ]]; then
    # Check system units first
    if unit_exists "${UNIT_NAME%.*}" "system"; then
        view_logs "$UNIT_NAME" "system"
        exit 0
    elif unit_exists "${UNIT_NAME%.*}" "user"; then
        view_logs "$UNIT_NAME" "user"
        exit 0
    fi
else
    # No extension provided, try common extensions
    for ext in service timer socket; do
        # Check system units first (preference)
        if unit_exists "$UNIT_NAME" "system"; then
            view_logs "${UNIT_NAME}.${ext}" "system"
            exit 0
        fi
    done

    # Check user units if not found in system
    for ext in service timer socket; do
        if unit_exists "$UNIT_NAME" "user"; then
            view_logs "${UNIT_NAME}.${ext}" "user"
            exit 0
        fi
    done
fi

# Unit not found, try to find similar ones
if find_similar_units "$UNIT_NAME"; then
    exit 1
else
    echo "No unit found matching '${UNIT_NAME}' and no similar units found."
    exit 1
fi
