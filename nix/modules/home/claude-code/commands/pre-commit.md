---
description: "Run pre-commit checks on modified TypeScript projects/workspaces in GitButler virtual branches including tests, linting, formatting, and type checking"
model: claude-opus-4-1-20250805
allowed-tools:
  - Bash(*)
  - Read
  - LS
  - Glob
  - Grep
  - Edit
  - Write
  - MultiEdit
---

# Pre-Commit Checks Command

Run pre-commit validation on modified TypeScript projects/workspaces in GitButler virtual branches. This command automatically detects your project and runs the appropriate checks on modified files only.

## Instructions

Simply run the pre-commit script which automatically:

1. **Detects your project** based on the current directory path
2. **Identifies the correct upstream branch** for your project
3. **Lists all modified files** since your branch started
4. **Runs the appropriate checks** for your project type
5. **Provides a summary** of what passed or failed

The script handles all three projects:
- **Farmers Cartel**: Uses NX affected commands with `origin/main`
- **Farmers Market**: Uses Make targets with `origin/master`  
- **Mandarina**: Uses yarn verify with `origin/main`

## Usage

1. **Execute the pre-commit script**:

```bash
/Users/giodamelio/.claude/commands/pre-commit.sh
```

The script will automatically handle project detection and run all checks.

2. **Check IDE Diagnostics**: After the script completes, check IDE diagnostics for any TypeScript errors/warnings on modified files.

Use the IDE tools that are built in to Claude Code. Print an error if it is not enabled.

## Success Criteria

✅ All linting passes
✅ All formatting checks pass  
✅ All type checking passes
✅ All tests pass
✅ No critical IDE diagnostics on modified files
✅ Clear reporting of which project/files were checked
✅ Proper error collection and reporting

Exit code 0 only if all checks pass, otherwise exit code 1 with detailed failure summary.
