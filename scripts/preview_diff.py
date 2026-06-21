#!/usr/bin/env python3
import sys
import json
import os
import subprocess

def main():
    if len(sys.argv) < 2:
        sys.exit(0)
    
    stage = sys.argv[1] # "pre" or "post"
    nvim_addr = os.environ.get("NVIM")
    if not nvim_addr:
        sys.exit(0)

    if stage == "post":
        cmd = "<cmd>AntigravityCloseProposedDiff<cr>"
        try:
            subprocess.run(["nvim", "--server", nvim_addr, "--remote-send", cmd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass
        sys.exit(0)

    if stage == "pre":
        try:
            data = json.load(sys.stdin)
        except Exception:
            sys.exit(0)

        tool_name = data.get("toolName") or data.get("tool_name")
        tool_input = data.get("toolInput") or data.get("tool_input") or {}

        if not tool_name or not tool_input:
            sys.exit(0)

        target_file = tool_input.get("TargetFile") or tool_input.get("targetFile")
        if not target_file:
            sys.exit(0)

        target_file = os.path.abspath(target_file)
        if not os.path.exists(target_file):
            sys.exit(0)

        try:
            with open(target_file, "r", encoding="utf-8") as f:
                original_content = f.read()
        except Exception:
            sys.exit(0)

        proposed_content = None

        if tool_name in ("write_to_file", "write_file"):
            proposed_content = tool_input.get("CodeContent") or tool_input.get("codeContent")
        
        elif tool_name == "replace_file_content":
            target_content = tool_input.get("TargetContent") or tool_input.get("targetContent")
            replacement_content = tool_input.get("ReplacementContent") or tool_input.get("replacementContent")
            if target_content is not None and replacement_content is not None:
                proposed_content = original_content.replace(target_content, replacement_content, 1)

        elif tool_name == "multi_replace_file_content":
            chunks = tool_input.get("ReplacementChunks") or tool_input.get("replacementChunks")
            if chunks:
                proposed_content = original_content
                for chunk in chunks:
                    tc = chunk.get("TargetContent") or chunk.get("targetContent")
                    rc = chunk.get("ReplacementContent") or chunk.get("replacementContent")
                    if tc is not None and rc is not None:
                        proposed_content = proposed_content.replace(tc, rc, 1)

        if proposed_content is None:
            sys.exit(0)

        # Write proposed content to a temporary file
        temp_dir = "/tmp/antigravity_diff"
        os.makedirs(temp_dir, exist_ok=True)
        temp_file = os.path.join(temp_dir, os.path.basename(target_file))
        
        try:
            with open(temp_file, "w", encoding="utf-8") as f:
                f.write(proposed_content)
        except Exception:
            sys.exit(0)

        # Send remote command to Neovim
        cmd = f"<cmd>AntigravityShowProposedDiff {target_file} {temp_file}<cr>"
        try:
            subprocess.run(["nvim", "--server", nvim_addr, "--remote-send", cmd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

    sys.exit(0)

if __name__ == "__main__":
    main()
