#!/bin/bash
# PreToolUse hook - TDD enforcement before editing source files
# Fires before Write/Edit/MultiEdit tools
#
# NOTE: This repo is meta (docs/workflows only).
# We check for workflow files (.github/workflows/*.yml) instead of /src/

# Read the tool input (JSON with file_path, content, etc.)
TOOL_INPUT=$(cat)

# Extract the file path being edited (requires jq)
FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.tool_input.file_path // empty')

# Check for workflow files (this repo's "source code")
if [[ "$FILE_PATH" == *".github/workflows/"* ]]; then
  cat << 'EOF'
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "TDD CHECK: Are you editing a workflow without testing it first? Test with: act workflow_dispatch --secret-file .env.test"}}
EOF
fi

# Check for test files - allow without warning
if [[ "$FILE_PATH" == *"/tests/"* ]]; then
  exit 0
fi

# No output = allow the tool to proceed
