---
description: "Save comprehensive context and plan for future continuation of work"
model: claude-opus-4-1-20250805
allowed-tools:
  - Read
  - LS
  - Glob
  - Grep
  - Write
  - Bash(mkdir:*)
  - Bash(git status:*)
  - Bash(git log:*)
  - Bash(find:*)
  - Bash(ls:*)
  - Bash(pwd:*)
  - Bash(cat:*)
  - Bash(head:*)
  - Bash(tail:*)
  - Bash(wc:*)
  - Bash(grep:*)
  - Bash(which:*)
  - Bash(echo:*)
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
  - mcp__allpepper-memory-bank__memory_bank_write
  - mcp__sequential-thinking__sequentialthinking
---

# Save Plan Command

You are tasked with saving the current context and plan for future continuation. Create a comprehensive plan file that includes all necessary context for a future Claude Code session.

## Instructions

1. **Use Extended Thinking**: Before creating the plan, think deeply about the current state of the work:
   - What has been accomplished so far?
   - What are the next steps?
   - What challenges or considerations are important?
   - What context would be most valuable for continuing this work?

2. **Generate Plan Name and Create File**: 
   - First, analyze the current context to generate an appropriate plan filename
   - If working on a Linear ticket, start with the ticket ID (e.g., "ENG-1394-")
   - Add a descriptive name based on the current task using kebab-case
   - Save the plan to `tmp/plans/{generated-name}.md` relative to the project root

3. **Include the following sections in the plan**:

### Project Context
- Current working directory and project structure
- Git status and recent commits
- Main technologies/frameworks used

### Current Task Overview
- What is the main objective?
- What problem are we solving?
- Current progress status

### MCP Server Context
- List available MCP servers and their capabilities
- If working with Linear issues, include ticket ID and key details
- If working with Notion pages, include page URLs
- If working with databases, include current tables being worked with, as well as primary id's for future queries
- Any other MCP server context that's relevant

### File Inventory
Create a detailed inventory of relevant files:
- File path and purpose
- Current state (modified, new, etc.)
- What specific parts we're working on
- Any important functions/classes/components
- Dependencies and relationships

### Technical Context
- Current implementation approach
- Key decisions made and rationale
- Any constraints or requirements
- Testing strategy being used

### Next Steps Plan
- Immediate next actions (prioritized)
- Potential challenges to watch for
- Success criteria
- Any blocked items or dependencies

### Memory Bank Instructions
- Save key technical decisions and patterns to memory bank
- Include any reusable code snippets or configurations
- Document any hard-won insights or debugging discoveries
- Note any project-specific conventions discovered

### Continuation Instructions
Provide specific instructions for the next Claude Code session:
- What tools to use first
- Key files to examine
- Commands to run for verification
- How to pick up where we left off

## Commands to Execute

```bash
# Ensure the plans directory exists
mkdir -p tmp/plans

# Get current git status
git status --porcelain

# Get recent commits
git log --oneline -n 5

# Get current working directory structure
find . -type f -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.md" -o -name "*.json" -o -name "*.sql" | head -20
```

Think deeply about the current context and create a comprehensive plan that will allow seamless continuation of the work in a future session. The plan should be so detailed that no previous context is needed to understand where we are and what needs to be done next.
