# Design Spec: CLI Model Selection for Claude Code + Qwen/Z.ai (COMPLETED)

## Goal
Implement a `--model` command-line flag to allow users to specify which LLM model to use for both Qwen and Z.ai providers.

## Architecture
The `flake.nix` contains a bash script (`claude-qwen-script`) that handles provider selection and router configuration. We will extend its argument parsing logic.

## Changes
1.  **Argument Parsing:**
    *   Add a `MODEL_OVERRIDE=""` variable.
    *   Update the `while` loop to recognize `--model`.
    *   If `--model` is provided, set `MODEL_OVERRIDE` to its value.
2.  **Model Assignment:**
    *   For Qwen: `QWEN_MODEL="${MODEL_OVERRIDE:-${qwenModel}}"`
    *   For Z.ai: `ZAI_MODEL="${MODEL_OVERRIDE:-${zaiModel}}"`
3.  **Router/Settings Config:**
    *   The existing `jq` calls already use `QWEN_MODEL` and `ZAI_MODEL` variables, so they will automatically pick up the override.

## Verification Plan
- **Automated Tests:** Create a reproduction script that runs the flake with and without the `--model` flag and inspects the generated `config.json`.
- **Manual Verification:**
    - `nix run .#zai -- --model glm-4.7 --help` -> Check logs for "modelo glm-4.7".
    - `nix run . -- --model qwen-max --help` -> Check logs for "modelo qwen-max".
    - `nix run . -- --help` -> Check logs for default "modelo coder-model".
