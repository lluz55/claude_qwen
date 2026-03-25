# CLI Model Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `--model` flag to `claude-qwen` and `zai` commands in `flake.nix`.

**Architecture:** Use simple argument parsing in the bash script to capture `--model` and override default model variables.

**Tech Stack:** Nix, Bash, jq.

---

### Task 1: Update Argument Parsing in `flake.nix`

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Implement the logic to capture `--model` flag**

```bash
            # Processar argumentos para provedor
            PROVIDER="qwen"
            MODEL_OVERRIDE=""
            declare -a CLAUDE_ARGS=()
            
            while [[ "$#" -gt 0 ]]; do
              case $1 in
                --provider)
                  PROVIDER="$2"
                  shift 2
                  ;;
                --model)
                  MODEL_OVERRIDE="$2"
                  shift 2
                  ;;
                *)
                  CLAUDE_ARGS+=("$1")
                  shift
                  ;;
              esac
            done
```

- [ ] **Step 2: Update Qwen model assignment**

```bash
            if [ "$PROVIDER" = "qwen" ]; then
                QWEN_MODEL="${MODEL_OVERRIDE:-${qwenModel}}"
                # ...
```

- [ ] **Step 3: Update Z.ai model assignment**

```bash
            elif [ "$PROVIDER" = "zai" ]; then
                ZAI_MODEL="${MODEL_OVERRIDE:-${zaiModel}}"
                # ...
```

- [ ] **Step 4: Update the "Gerando configuração" echo messages to reflect the selected model**

```bash
                echo "⚙️ Gerando configuração do router para Qwen (com modelo $QWEN_MODEL)..."
                # and
                echo "⚙️ Gerando configuração do router para Z.ai (modelo $ZAI_MODEL)..."
```

- [ ] **Step 5: Commit**

```bash
git add flake.nix
git commit -m "feat: add --model flag for CLI model selection"
```

### Task 2: Verification

**Files:**
- Test: Manual verification in terminal

- [ ] **Step 1: Verify Qwen default model**
Run: `nix run . -- --help`
Expected: Logs show "modelo coder-model" (default).

- [ ] **Step 2: Verify Qwen model override**
Run: `nix run . -- --model qwen-max --help`
Expected: Logs show "modelo qwen-max".

- [ ] **Step 3: Verify Z.ai default model**
Run: `nix run .#zai -- --help`
Expected: Logs show "modelo glm-5" (default).

- [ ] **Step 4: Verify Z.ai model override**
Run: `nix run .#zai -- --model glm-4.7 --help`
Expected: Logs show "modelo glm-4.7".

- [ ] **Step 5: Verify legacy Z.ai provider also works**
Run: `nix run . -- --provider zai --model glm-4.7 --help`
Expected: Logs show "modelo glm-4.7".
