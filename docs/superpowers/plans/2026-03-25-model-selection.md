# CLI Model Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `--model` flag to `claude-qwen` and `zai` commands in `flake.nix`.

**Architecture:** Use simple argument parsing in the bash script to capture `--model` and override default model variables.

**Tech Stack:** Nix, Bash, jq.

---

### Task 1: Update Argument Parsing in `flake.nix` (COMPLETED)

**Files:**
- Modify: `flake.nix`

- [x] **Step 1: Implement the logic to capture `--model` flag**
- [x] **Step 2: Update Qwen model assignment**
- [x] **Step 3: Update Z.ai model assignment**
- [x] **Step 4: Update the "Gerando configuração" echo messages to reflect the selected model**
- [x] **Step 5: Commit**

### Task 2: Verification (COMPLETED)

**Files:**
- Test: Manual verification in terminal

- [x] **Step 1: Verify Qwen default model**
- [x] **Step 2: Verify Qwen model override**
- [x] **Step 3: Verify Z.ai default model**
- [x] **Step 4: Verify Z.ai model override**
- [x] **Step 5: Verify legacy Z.ai provider also works**
