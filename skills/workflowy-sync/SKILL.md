---
name: workflowy-sync
description: Sync with Workflowy to receive tasks, report progress, ask questions, and poll for new work
argument-hint: "<node-id>"
---

# Workflowy Sync Skill

You are operating in a collaborative workflow where Workflowy serves as the shared task board between you and the user. The user manages tasks in Workflowy's UI, and you execute them here.

## Invocation

The user will invoke this skill with a Workflowy node ID:
```
/workflowy-sync abc12345-uuid-here
```

The provided ID (`$ARGUMENTS`) is your root node. All tasks and communication happen under this node.

## First-Run Setup

On first invocation in a project, check if the project's `.claude/settings.json` has hooks configured for `workflowy-sync`. Look for `PermissionRequest` and `PostToolUse` hook entries referencing `workflowy-sync`.

If not configured, ask the user:

> Workflowy-sync can notify your Workflowy task tree when Claude Code is awaiting permission. This requires adding two hooks to this project's `.claude/settings.json`. Would you like to enable permission notifications?

If the user agrees, add the following to `.claude/settings.json` (create the file if needed):
```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/skills/workflowy-sync/hooks/permission-alert.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/skills/workflowy-sync/hooks/permission-resolved.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```
Merge these entries into existing settings — do not overwrite other hooks or settings.

**After installing hooks, tell the user they need to restart Claude Code for the hooks to take effect.** Display a message like:

> Hooks have been installed. Please restart Claude Code for the permission notifications to take effect. After restarting, re-invoke `/workflowy-sync <node-id>` to continue.

Then stop and wait for the user to restart — do not proceed with task processing until the next invocation.

If the user declines, skip this and proceed normally. The skill works without hooks; the user just won't see permission notifications in Workflowy.

## Core Workflow

### 1. Fetch the Task Tree

First, fetch the root node and its descendants:
```
Use mcp__workflowy__workflowy_get with:
- id: $ARGUMENTS
- depth: -1 (fetch all descendants)
```

### 2. Identify Tasks

Tasks are identified by their **layout_mode**:
- Nodes with `layout_mode: "todo"` are actionable tasks
- Completed todos should be skipped (they have a `completed` property)
- **Non-todo nodes are never tasks** — they are context, details, or drafts. The user promotes a node to todo when it's ready for you to work on. Never act on plain bullet nodes as tasks, even if they look actionable.
- Non-todo children of a task are **context/details** for that task
- Todo children of a task are **subtasks** that should be completed before the parent

### 3. Check if Tasks Are Ready

Before starting a todo task, check if it appears unfinished (e.g. trailing ellipsis, sentence fragments, empty name, or it was just created with no context children yet). If it looks unfinished:
1. Wait 5 seconds, then refetch the tree and check again
2. If still unfinished, wait 5 more seconds and refetch again
3. If still unfinished after the third check, ask the user (via `#question:`) whether the task is ready

### 4. Process Tasks (Depth-First)

Work through ready tasks recursively, depth-first:
1. If a task has incomplete todo subtasks, complete those first
2. Non-todo children provide context about what the task means
3. Look for any `#question:` nodes that now have sibling responses (user answers)

### 5. When Starting a Task

Before beginning work on a task:

1. Save the root node and task ID for permission hooks:
```bash
~/.claude/skills/workflowy-sync/scripts/workflowy-set-task.sh <task-id> <root-id>
```
Pass both arguments when the skill is first invoked. For subsequent tasks, pass only the task ID:
```bash
~/.claude/skills/workflowy-sync/scripts/workflowy-set-task.sh <task-id>
```

2. Create a status node:
```
Use mcp__workflowy__workflowy_create to add a child node:
- parent_id: <task-id>
- name: "<b>started working on this</b>"
- position: "bottom"
```

Save this status node's ID - you'll update it when done.

### 6. During Task Execution

Execute the task using all your normal Claude Code capabilities:
- Read/write files
- Run commands
- Search the codebase
- Make edits
- etc.

**Permission notifications are automatic.** A hook posts `<b>⏳ awaiting permission:</b>` to Workflowy whenever Claude Code requests permission. No manual action needed.

**If you have questions**, create a structured question with options:

1. Create the question node:
```
Use mcp__workflowy__workflowy_create:
- parent_id: <task-id>
- name: "<b>#question:</b> Your question here?"
- position: "bottom"
```

2. Add child nodes for each possible option:
```
Use mcp__workflowy__workflowy_create (for each option):
- parent_id: <question-node-id>
- name: "Option description"
- position: "bottom"
```

The user will respond by either:
- Adding a child under one of the options (e.g., "this one", "yes", etc.)
- Adding a new sibling to the options (a custom answer not in your list)

### 7. When Completing a Task

After successfully completing a task:

1. Update your status node:
```
Use mcp__workflowy__workflowy_update:
- id: <status-node-id>
- name: "<b>completed:</b> <brief description of what was done>"
```

2. Mark the task itself as complete:
```
Use mcp__workflowy__workflowy_complete:
- id: <task-id>
```

### 8. Refetch and Continue (MANDATORY LOOP)

**You MUST loop continuously.** After completing a task, immediately refetch the entire tree and look for the next task. Never stop after completing a single task.

```
Use mcp__workflowy__workflowy_get with:
- id: $ARGUMENTS
- depth: -1
```

This allows you to:
- Discover new tasks the user added
- Find answers to your questions (new nodes added near your `#question:` nodes)
- See updated context or changed requirements

**Then go back to step 2** (Identify Tasks) and repeat. Step 3 will handle any tasks still being written. This is a continuous loop — you keep working until there are no incomplete tasks, then you poll.

### 9. Polling When Idle

If no incomplete tasks remain:
1. Inform the user you've completed all visible tasks
2. Wait and poll for new work using exponential backoff:
   - First poll: 10 seconds
   - Then: 20, 40, 80, 160 seconds (cap at 5 minutes)
3. Reset backoff when new tasks are found

To wait, use Bash with `sleep`:
```bash
sleep 10
```

Then refetch the tree and check for new tasks. **Never exit the loop — always continue polling.**

## Question Format

Questions are structured with options as children:

```
<b>#question:</b> Which authentication method should we use?
├── JWT tokens (stateless, good for APIs)
├── Session cookies (simpler, good for web apps)
└── OAuth (if we need third-party login)
```

The user can respond in several ways:
- **Select an option** by adding a child under it (e.g., "this one", "yes")
- **Narrow the options** by deleting or marking as complete the options they don't want
- **Expand an answer** by adding children under an option with more detail or context
- **Provide a custom answer** by adding a new sibling to the options

The user responds by adding a child under their chosen option:
```
<b>#question:</b> Which authentication method should we use?
├── JWT tokens (stateless, good for APIs)
│   └── this one
├── Session cookies (simpler, good for web apps)
└── OAuth (if we need third-party login)
```

Or by adding a custom answer as a new child of the question:
```
<b>#question:</b> Which authentication method should we use?
├── JWT tokens (stateless, good for APIs)
├── Session cookies (simpler, good for web apps)
├── OAuth (if we need third-party login)
└── Actually, let's use Passkeys instead
```

## Detecting and Processing Answers

When you refetch the tree, look for answers in your question nodes:

1. **Option selected**: One of your option nodes now has a child (e.g., "this one", "yes", "👍")
   - The parent of that child is the chosen option
2. **Options removed**: Some of your original options were deleted or marked complete — the remaining options are what the user wants
3. **Option expanded**: An option node now has children with additional detail or context from the user
4. **Custom answer**: A new child of the question node that wasn't one of your original options
   - This is the user providing an alternative
5. **Inline edit**: The question or an option node was edited by the user

**After processing an answer**, mark the question node as complete:
```
Use mcp__workflowy__workflowy_complete:
- id: <question-node-id>
```

This signals to the user that you've seen and acted on their response.

## Error Handling

If a task cannot be completed:
1. Update your status node to explain what went wrong:
   ```
   "<b>blocked:</b> <explanation of the issue>"
   ```
2. Add a `<b>#question:</b>` if you need user input to proceed
3. Move on to other tasks
4. Do NOT mark the task as complete

## Example Session

```
Root Node (provided ID)
├── [todo] Add user authentication
│   ├── Use JWT tokens
│   └── **started working on this**
├── [todo] Fix the login bug
│   ├── [done] **#question:** Which login endpoint?
│   │   ├── /api/login
│   │   │   └── this one
│   │   └── /auth/login
│   └── **started working on this**
├── [todo] Choose database
│   └── **#question:** Which database should we use?
│       ├── PostgreSQL (recommended for relational data)
│       ├── MongoDB (if we need flexible schemas)
│       └── Let's use SQLite for now, we can migrate later
└── [todo] Update README
```

In this example:
- "Add user authentication" is in progress (bold status node)
- "Fix the login bug" had a question with options - user selected `/api/login` by adding "this one" under it
- "Choose database" has an unanswered question with options, plus a custom answer from the user
- "Update README" is pending

## Communicating Plans

When reporting a plan or progress back to the user, **use Workflowy's note and nested list structure**. Create hierarchical breakdowns with parent nodes for phases/categories and child nodes for specific steps. This leverages Workflowy's strengths and makes plans easy for the user to reorganize, annotate, and respond to.

## Important Notes

- Always work depth-first (complete subtasks before parent tasks)
- Never mark a task complete if you added unanswered questions
- Keep status updates concise but informative
- The user may add tasks at any level - always refetch to see the full picture
- If the Workflowy MCP tools fail, inform the user and retry after a delay

<!-- TODO: Rename this skill from "workflowy-sync" to "workflowy-driver" -->
