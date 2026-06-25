#!/bin/bash

set -e

# Exit code tracking
EXIT_CODE=0
FAILED_CHECKS=()

# Function to add failed check
add_failed_check() {
    EXIT_CODE=1
    FAILED_CHECKS+=("$1|$2")
}

# Function to run command and track failure
run_check() {
    local check_name="$1"
    shift
    if ! "$@"; then
        # Join the command arguments as a single string
        local command_string="$*"
        add_failed_check "$check_name" "$command_string"
    fi
}

# Allow overriding affected projects
AFFECTED_PROJECTS="$1"

# Detect project and set configuration
PWD=$(pwd)
if [[ "$PWD" == *"farmers-cartel"* ]]; then
    PROJECT_NAME="🚜 Farmers Cartel (NX workspace)"
    UPSTREAM="origin/main"
    PROJECT_TYPE="cartel"
elif [[ "$PWD" == *"farmers-market"* ]]; then
    PROJECT_NAME="🌾 Farmers Market (Yarn workspaces + Make)"
    UPSTREAM="origin/master"
    PROJECT_TYPE="market"
elif [[ "$PWD" == *"mandarina"* ]]; then
    PROJECT_NAME="🍊 Mandarina (Yarn workspaces)"
    UPSTREAM="origin/master"
    PROJECT_TYPE="mandarina"
else
    echo "❌ Error: Not in a recognized project directory"
    echo "Expected one of: farmers-cartel, farmers-market, mandarina"
    exit 1
fi

echo "$PROJECT_NAME"
echo ""

# Run project-specific checks
case $PROJECT_TYPE in
    "cartel")
        # Load environment variables
        echo "📦 Loading environment..."
        set -a
        # shellcheck disable=SC1091
        source .env
        set +a

        if [[ -z "$AFFECTED_PROJECTS" ]]; then
          # Get affected projects using NX
          echo "🔍 Detecting affected projects..."
          AFFECTED_PROJECTS=$(yarn nx show projects --affected --base=$UPSTREAM --sep="," 2>/dev/null)
        fi

        if [[ -z "$AFFECTED_PROJECTS" ]]; then
            echo "✅ No affected projects found"
            exit 0
        fi

        # Count and display affected projects
        PROJECT_COUNT=$(echo "$AFFECTED_PROJECTS" | tr ',' '\n' | wc -l | xargs)
        echo "📁 Found $PROJECT_COUNT affected project(s):"
        printf "  "
        echo "$AFFECTED_PROJECTS" | sed -e 's/^/- /' -e $'s/,/\\\n  - /g'
        echo ""

        SHARED_NX_ARGS="--output-style=static --batch --parallel=10"

        echo "  🧹 Linting..."
        run_check "nx-lint" yarn nx "$SHARED_NX_ARGS" run-many -t lint -p "$AFFECTED_PROJECTS"
        echo ""

        echo "  🎨 Format checking..."
        run_check "nx-format:check" yarn nx "$SHARED_NX_ARGS" run-many -t check-format -p "$AFFECTED_PROJECTS"
        echo ""

        echo "  🔧 Type checking..."
        run_check "nx-check-types" yarn nx "$SHARED_NX_ARGS" run-many -t check-types "$AFFECTED_PROJECTS"
        echo ""

        echo "  🧪 Testing..."
        run_check "nx-test" yarn nx "$SHARED_NX_ARGS" run-many -t test "$AFFECTED_PROJECTS"
        echo ""

        ;;

    "market"|"mandarina")
        # Load environment variables
        echo "📦 Loading environment..."
        # shellcheck disable=SC1091
        [ -f .envrc ] && source .envrc
        set -a
        # shellcheck disable=SC1091
        [ -f .env ] && source .env
        set +a

        if [[ -z "$AFFECTED_PROJECTS" ]]; then
          # Get list of workspaces dynamically
          echo "🔍 Detecting affected projects..."

          echo "🔍 Getting workspace list..."
          AFFECTED_PROJECTS=$(yarn workspaces list --since="$UPSTREAM" --json | jq --raw-output0 '. | select(.name != null and .name != "") | .name' | tr '\0' ',')
          AFFECTED_PROJECTS="${AFFECTED_PROJECTS%,}"
        fi

        # Count and display affected projects
        PROJECT_COUNT=$(echo "$AFFECTED_PROJECTS" | tr ',' '\n' | wc -l | xargs)
        echo "📁 Found $PROJECT_COUNT affected project(s):"
        printf "  "
        echo "$AFFECTED_PROJECTS" | sed -e 's/^/- /' -e $'s/,/\\\n  - /g'
        echo ""

        # Get the list of include flags to put in the foreach command
        INCLUDE_FLAGS=$(echo "$AFFECTED_PROJECTS" | awk -v RS=',' '{print "--include \"" $1 "\""}' | xargs)

        echo "  🧹 Linting..."
        run_check "lint" yarn workspaces foreach --all "$INCLUDE_FLAGS" --parallel run lint
        echo ""

        echo "  🎨 Format checking..."
        run_check "check-format" yarn workspaces foreach --all "$INCLUDE_FLAGS" --parallel run check-format
        echo ""

        echo "  🔧 Type checking..."
        run_check "typecheck" yarn workspaces foreach --all "$INCLUDE_FLAGS" --parallel run typo-check
        echo ""

        echo "  🧪 Testing..."
        run_check "test" yarn workspaces foreach --all "$INCLUDE_FLAGS" --parallel run test
        echo ""

        ;;
esac

# Final Summary
echo ""
echo "📊 Pre-commit Summary:"
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✅ All checks passed! Ready to commit."
else
    echo "❌ Some checks failed:"
    for check in "${FAILED_CHECKS[@]}"; do
        IFS='|' read -r check_name command_to_run <<< "$check"
        printf "  • %-20s $ %s\n" "$check_name" "$command_to_run"
    done

    echo ""
    echo "🔧 Please fix the issues above before committing."
fi

exit $EXIT_CODE
