#!/usr/bin/env python3
"""Claude Code hook: preview proposed edits as a Neovim diff before approval.

Wire this up in ~/.claude/settings.json:

  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write|MultiEdit",
        "hooks": [ { "type": "command",
          "command": "python3 ~/.config/nvim/scripts/claude_diff_preview.py pre" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write|MultiEdit",
        "hooks": [ { "type": "command",
          "command": "python3 ~/.config/nvim/scripts/claude_diff_preview.py post" } ] }
    ]
  }

On PreToolUse it computes the file's proposed content and opens it side-by-side
with the current version in diff mode, so the change is visible before you
approve it. On PostToolUse it tears the diff down.
"""
import sys
import json
import os
import subprocess


def nvim_addr():
    addr = os.environ.get("NVIM")
    if addr:
        return addr
    try:
        with open("/tmp/claude_nvim_socket", "r") as f:
            return f.read().strip()
    except Exception:
        return None


def remote_expr(addr, expr):
    try:
        subprocess.run(
            ["nvim", "--server", addr, "--remote-expr", expr],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


def compute_proposed(tool_name, tool_input, original_content):
    if tool_name in ("Write", "write_file", "write_to_file"):
        return tool_input.get("content")

    if tool_name == "Edit":
        old = tool_input.get("old_string")
        new = tool_input.get("new_string")
        if old is None or new is None:
            return None
        if tool_input.get("replace_all"):
            return original_content.replace(old, new)
        return original_content.replace(old, new, 1)

    if tool_name == "MultiEdit":
        edits = tool_input.get("edits") or []
        proposed = original_content
        for edit in edits:
            old = edit.get("old_string")
            new = edit.get("new_string")
            if old is None or new is None:
                continue
            if edit.get("replace_all"):
                proposed = proposed.replace(old, new)
            else:
                proposed = proposed.replace(old, new, 1)
        return proposed

    return None


def main():
    if len(sys.argv) < 2:
        sys.exit(0)
    stage = sys.argv[1]  # "pre" or "post"

    addr = nvim_addr()
    if not addr:
        sys.exit(0)

    if stage == "post":
        remote_expr(addr, "v:lua.ClaudeCloseProposedDiff()")
        sys.exit(0)

    if stage != "pre":
        sys.exit(0)

    try:
        data = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)

    tool_name = data.get("tool_name")
    tool_input = data.get("tool_input") or {}
    if not tool_name or not tool_input:
        sys.exit(0)

    target_file = tool_input.get("file_path")
    if not target_file:
        sys.exit(0)
    target_file = os.path.abspath(target_file)

    # New files (Write) may not exist yet -> diff against an empty buffer.
    original_content = ""
    if os.path.exists(target_file):
        try:
            with open(target_file, "r", encoding="utf-8") as f:
                original_content = f.read()
        except Exception:
            sys.exit(0)

    proposed_content = compute_proposed(tool_name, tool_input, original_content)
    if proposed_content is None:
        sys.exit(0)

    temp_dir = "/tmp/claude_diff"
    os.makedirs(temp_dir, exist_ok=True)
    temp_file = os.path.join(temp_dir, os.path.basename(target_file))
    try:
        with open(temp_file, "w", encoding="utf-8") as f:
            f.write(proposed_content)
    except Exception:
        sys.exit(0)

    escaped_target = target_file.replace("'", "\\'")
    escaped_temp = temp_file.replace("'", "\\'")
    remote_expr(addr, f"v:lua.ClaudeShowProposedDiff('{escaped_target}', '{escaped_temp}')")

    sys.exit(0)


if __name__ == "__main__":
    main()
