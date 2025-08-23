---
description: "Load a previously saved plan and context to continue work"
argument-hint: "<plan-name>"
model: claude-opus-4-1-20250805
allowed-tools:
  - Read
  - LS
  - Glob
  - Grep
  - Search
  - Bash(ls:*)
  - Bash(cat:*)
  - Bash(git status:*)
  - Bash(git log:*)
  - Bash(pwd:*)
  - Bash(echo:*)
  - Bash(head:*)
  - Bash(tail:*)
  - Bash(wc:*)
  - Bash(grep:*)
  - Bash(which:*)
  - ListMcpResourcesTool
  - ReadMcpResourceTool
  - mcp__linear__get_issue
  - mcp__linear__list_issues
  - mcp__notion__fetch
  - mcp__notion__search
  - mcp__postgres__list_schemas
  - mcp__postgres__list_objects
  - mcp__postgres__get_object_details
  - mcp__obsidian__obsidian_get_file_contents
  - mcp__obsidian__obsidian_list_files_in_vault
  - mcp__allpepper-memory-bank__list_projects
  - mcp__allpepper-memory-bank__memory_bank_read
---

# Load Plan Command

Load a previously saved plan and context for continuation of work. This command will read the plan file and provide you with all the necessary context to continue where you left off.

## Instructions

1. **Read the Plan File**: Follow this exact sequence:
 - **Option A**: If $ARGUMENTS contains a full file path, use Read tool directly on that path
 - **Option B**: If $ARGUMENTS is just a filename (with or without .md extension), try to read `tmp/plans/$ARGUMENTS.md` directly using Read tool
 - **Option C**: If the direct read fails or $ARGUMENTS appears to be a search term, use `Grep(pattern: "$ARGUMENTS", path: "tmp/plans", output_mode: "files_with_matches")` to find plans containing that term
 - **If multiple matches**: List the matches and ask the user which specific plan to load
 - **If no matches**: Inform user no plans found and suggest available plans using `Glob(pattern: "tmp/plans/*.md")`

2. **Parse and Understand Context**: After reading the plan, analyze:
   - The current state of the project
   - What was being worked on
   - What the next steps should be
   - Any important technical decisions or context

3. **Verify Current State**: After successfully reading a plan, check if anything has changed since the plan was saved:
   - Use `git status --porcelain` to check for changes
   - Use `git log --oneline -n 5` to see recent commits
   - DO NOT run file existence checks (ls, cat) if you already successfully read the plan

4. **Re-establish MCP Context**: If the plan mentions:
   - Linear ticket IDs - fetch the latest ticket status
   - Notion pages - verify access and current state
   - Database contexts - reconnect and verify schemas
   - Memory bank entries - check for relevant saved context

5. **Present Summary**: Provide a clear summary of:
   - What you understand about the current task
   - What has been accomplished
   - What the immediate next steps are
   - Any potential issues or changes since the plan was saved

6. **Ask for Confirmation**: Before proceeding, confirm with the user:
   - Is the context accurate?
   - Are there any updates to the plan?
   - Should we proceed with the next steps as outlined?

## Potential Commands (Use As Needed)

```bash
# Get current git status to compare with saved state (step 3)
git status --porcelain

# Get recent commits to see if anything new happened (step 3)
git log --oneline -n 5

# Check current working directory if needed
pwd

# List available plans if user needs to see options
ls tmp/plans/
```

Load the specified plan and help the user continue their work seamlessly from where they left off.