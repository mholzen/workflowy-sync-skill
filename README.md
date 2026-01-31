# workflowy-sync-skill

A [Claude Code](https://claude.com/claude-code) skill that turns Workflowy into a shared task board between you and Claude. You manage tasks in Workflowy's UI, and Claude executes them — reporting progress, asking questions, and polling for new work, all within your Workflowy tree.

## Prerequisites

This skill requires the **Workflowy MCP server** to be configured in Claude Code. Install it first:

- [mholzen/workflowy](https://github.com/mholzen/workflowy) — follow the installation and MCP configuration instructions in that repo.

## Install

```bash
npx workflowy-sync-skill
```

This copies the skill files into `~/.claude/skills/workflowy-sync/`.

## Usage

Inside a Claude Code session:

```
/workflowy-sync <node-id>
```

Where `<node-id>` is the Workflowy node that serves as the root of your task tree. Claude will process todo items under that node, complete them, and poll for new tasks.

## Uninstall

```bash
npx workflowy-sync-skill uninstall
```
