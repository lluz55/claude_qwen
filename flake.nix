{
  description = "Claude Code integration with Qwen OAuth authentication";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Configuration
        nodeVersion = pkgs.nodejs_22;
        qwenModel = "qwen-coder-plus";
        tokenFile = "\${HOME}/.qwen/oauth_creds.json";

        # Main wrapper script
        claude-qwen = pkgs.writeShellScriptBin "claude-qwen" ''
          set -euo pipefail

          # Configuration
          export TOKEN_FILE="${tokenFile}"
          export QWEN_MODEL="${qwenModel}"
          ROUTER_PID=""

          # Cleanup function for background processes
          cleanup() {
            if [[ -n "''${ROUTER_PID:-}" ]]; then
              kill "''${ROUTER_PID}" 2>/dev/null || true
              wait "''${ROUTER_PID}" 2>/dev/null || true
            fi
          }
          trap cleanup EXIT INT TERM

          # Color output helpers
          info() { echo "📦 $*"; }
          success() { echo "✅ $*"; }
          error() { echo "❌ $*" >&2; }
          step() { echo "⚙️  $*"; }

          # 1. Check and validate authentication
          if [[ ! -f "$TOKEN_FILE" ]]; then
            info "Qwen authentication required. Starting login..."
            ${nodeVersion}/bin/npx -y @qwen-code/qwen-code
          fi

          # Validate token exists and is not empty
          if ! TOKEN=$(${pkgs.jq}/bin/jq -r '.access_token // empty' "$TOKEN_FILE" 2>/dev/null); then
            error "Failed to read token from $TOKEN_FILE"
            error "Please ensure the file contains valid JSON with 'access_token' field"
            exit 1
          fi

          if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
            error "Token is empty or invalid. Please re-authenticate:"
            error "  rm -f $TOKEN_FILE"
            error "  claude-qwen"
            exit 1
          fi

          success "Authentication verified"

          # 2. Ensure Claude Code is available
          step "Preparing environment..."

          # Add global npm bin to PATH for the router to find 'claude' command
          export PATH="$PATH:$(npm prefix -g)/bin"

          # 3. Start the router in background
          step "Starting bridge server on localhost..."
          ${nodeVersion}/bin/npx -y @musistudio/claude-code-router \
            start --token "$TOKEN" --model "$QWEN_MODEL" &
          ROUTER_PID=$!

          # Wait for router to initialize
          sleep 2

          # Verify router is still running
          if ! kill -0 "$ROUTER_PID" 2>/dev/null; then
            error "Router failed to start. Check your configuration."
            exit 1
          fi

          success "Bridge server running (PID: $ROUTER_PID)"

          # 4. Launch Claude Code
          echo ""
          step "Launching Claude Code..."
          ${nodeVersion}/bin/npx -y @anthropic-ai/claude-code
        '';

      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            nodeVersion
            pkgs.jq
            claude-qwen
            pkgs.nodePackages.npm
          ];

          shellHook = ''
            # Ensure library paths are available
            export LD_LIBRARY_PATH=${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH

            # Welcome message
            echo ""
            echo "╔════════════════════════════════════════════════════════╗"
            echo "║   Claude Code + Qwen OAuth Environment                 ║"
            echo "╚════════════════════════════════════════════════════════╝"
            echo ""
            echo "  Available commands:"
            echo "    • claude-qwen  - Start Claude Code with Qwen backend"
            echo ""
            success "Environment ready!"
            echo ""
          '';
        };

        # Optional: expose the package for direct use
        packages.default = claude-qwen;
      });
}
