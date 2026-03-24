{
  description = "Claude Code + Qwen/Z.ai Integration via Nix Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      
      qwenModel = "qwen3-coder-plus";
      zaiModel = "glm-4.7";
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          
          claude-qwen-script = pkgs.writeShellScriptBin "claude-qwen" ''
            #!/usr/bin/env bash
            set -e
            
            ROUTER_DIR="$HOME/.claude-code-router"
            
            # Garantir que jq e nodejs estejam no PATH
            export PATH="${pkgs.jq}/bin:${pkgs.nodejs_22}/bin:$PATH"
            
            # Processar argumentos para provedor
            PROVIDER="qwen"
            declare -a CLAUDE_ARGS=()
            
            while [[ "$#" -gt 0 ]]; do
              case $1 in
                --provider)
                  PROVIDER="$2"
                  shift 2
                  ;;
                *)
                  CLAUDE_ARGS+=("$1")
                  shift
                  ;;
              esac
            done
            
            if [ "$PROVIDER" = "qwen" ]; then
                QWEN_MODEL="${qwenModel}"
                OAUTH_FILE="$HOME/.qwen/oauth_creds.json"
                
                if [ ! -f "$OAUTH_FILE" ] || [ -z "$(${pkgs.jq}/bin/jq -r '.access_token // empty' "$OAUTH_FILE" 2>/dev/null)" ]; then
                    echo "⚠️ Token Qwen OAuth não encontrado ou inválido."
                    echo "Iniciando qwen-code para autenticação..."
                    echo "👉 DICA: Digite /auth, escolha a opção 'Qwen OAuth', conclua no navegador e depois digite /exit"
                    echo ""
                    ${pkgs.nodejs_22}/bin/npx -y @qwen-code/qwen-code@latest
                fi
                
                if [ ! -f "$OAUTH_FILE" ]; then
                    echo "❌ Falha ao obter credenciais."
                    exit 1
                fi
                
                TOKEN=$(${pkgs.jq}/bin/jq -r '.access_token' "$OAUTH_FILE")
                
                mkdir -p "$ROUTER_DIR"
                echo "⚙️ Gerando configuração do router para Qwen..."
                ${pkgs.jq}/bin/jq -n \
                  --arg token "$TOKEN" \
                  --arg model "$QWEN_MODEL" \
                  '{
                    "PORT": 3457,
                    "LOG": true,
                    "LOG_LEVEL": "debug",
                    "Providers": [
                      {
                        "name": "qwen",
                        "api_base_url": "https://portal.qwen.ai/v1/chat/completions",
                        "api_key": $token,
                        "models": ["claude-3-5-sonnet-20241022", "claude-3-7-sonnet-20250219", "claude-sonnet-4-6", "claude-sonnet-latest", $model]
                      }
                    ],
                    "Router": {
                      "claude-3-5-sonnet-20241022": ("qwen," + $model),
                      "claude-3-7-sonnet-20250219": ("qwen," + $model),
                      "claude-3-5-sonnet-latest": ("qwen," + $model),
                      "claude-3-7-sonnet-latest": ("qwen," + $model),
                      "claude-sonnet-4-6": ("qwen," + $model),
                      "claude-sonnet-latest": ("qwen," + $model),
                      "default": ("qwen," + $model),
                      "think": ("qwen," + $model)
                    }
                  }' > "$ROUTER_DIR/config.json"

                echo "🚀 Reiniciando Claude Code Router..."
                pkill -9 -f "claude-code-router" 2>/dev/null || true
                pkill -9 -f "ccr start" 2>/dev/null || true
                sleep 1
                rm -f /tmp/ccr.log
                nohup ${pkgs.nodejs_22}/bin/npx -y @musistudio/claude-code-router@latest start > /tmp/ccr.log 2>&1 &
                ROUTER_PID=$!
                
                cleanup() { kill -9 $ROUTER_PID 2>/dev/null || true; pkill -9 -f "claude-code-router" 2>/dev/null || true; }
                trap cleanup EXIT INT TERM
                
                for i in {1..20}; do
                    if (exec 3<>/dev/tcp/127.0.0.1/3457) 2>/dev/null; then
                        exec 3>&-
                        echo "✅ Router na porta 3457."
                        break
                    fi
                    sleep 0.5
                done
                
                export ANTHROPIC_BASE_URL="http://127.0.0.1:3457"
                export ANTHROPIC_API_KEY="sk-ant-dummy"
                
                echo "🤖 Iniciando Claude Code (Qwen)..."
                ${pkgs.nodejs_22}/bin/npx -y @anthropic-ai/claude-code@latest "''${CLAUDE_ARGS[@]}"

            elif [ "$PROVIDER" = "zai" ]; then
                ZAI_MODEL="${zaiModel}"
                ZAI_CREDS="$HOME/.zai/credentials.json"
                ZAI_ISOLATION_DIR="$HOME/.zai-claude-env"
                
                if [ ! -f "$ZAI_CREDS" ] || [ -z "$(${pkgs.jq}/bin/jq -r '.api_key // empty' "$ZAI_CREDS" 2>/dev/null)" ]; then
                    echo "⚠️ API Key Z.ai não encontrada."
                    set +e
                    read -s -p "🔑 Digite sua API Key Z.ai: " ZAI_KEY < /dev/tty
                    echo ""
                    set -e
                    if [ -z "$ZAI_KEY" ]; then echo "❌ API Key vazia. Abortando."; exit 1; fi
                    mkdir -p "$(dirname "$ZAI_CREDS")"
                    ${pkgs.jq}/bin/jq -n --arg key "$ZAI_KEY" '{api_key: $key}' > "$ZAI_CREDS"
                fi
                
                TOKEN=$(${pkgs.jq}/bin/jq -r '.api_key' "$ZAI_CREDS")
                
                # Preparar diretório isolado
                mkdir -p "$ZAI_ISOLATION_DIR"
                
                # Configuração baseada em https://docs.z.ai/devpack/tool/claude
                export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
                export ANTHROPIC_AUTH_TOKEN="$TOKEN"
                export ANTHROPIC_API_KEY="$TOKEN"
                export API_TIMEOUT_MS="3000000"
                
                ZAI_SETTINGS="$ZAI_ISOLATION_DIR/settings.json"
                ${pkgs.jq}/bin/jq -n \
                  --arg sonnet "$ZAI_MODEL" \
                  --arg haiku "glm-4.5-air" \
                  '{
                    "env": {
                      "ANTHROPIC_DEFAULT_SONNET_MODEL": $sonnet,
                      "ANTHROPIC_DEFAULT_HAIKU_MODEL": $haiku,
                      "ANTHROPIC_DEFAULT_OPUS_MODEL": $sonnet
                    }
                  }' > "$ZAI_SETTINGS"
                
                echo "🚀 Iniciando Claude Code (Z.ai) - Isolado em $ZAI_ISOLATION_DIR"
                
                # Isolar ambiente alterando HOME e XDG
                OLD_HOME="$HOME"
                export HOME="$ZAI_ISOLATION_DIR"
                export XDG_CONFIG_HOME="$HOME/.config"
                export XDG_DATA_HOME="$HOME/.local/share"
                export XDG_CACHE_HOME="$HOME/.cache"
                
                # Manter .gitconfig e SSH se existirem para que ferramentas funcionem
                [ -f "$OLD_HOME/.gitconfig" ] && ln -sf "$OLD_HOME/.gitconfig" "$HOME/.gitconfig"
                [ -d "$OLD_HOME/.ssh" ] && ln -sf "$OLD_HOME/.ssh" "$HOME/.ssh"
                
                ${pkgs.nodejs_22}/bin/npx -y @anthropic-ai/claude-code@latest --settings "$ZAI_SETTINGS" "''${CLAUDE_ARGS[@]}"
            else
                echo "❌ Provedor desconhecido: $PROVIDER"
                exit 1
            fi
          '';
        in {
          default = claude-qwen-script;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/claude-qwen";
        };
      });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            buildInputs = [
              pkgs.nodejs_22
              pkgs.nodePackages.npm
              pkgs.jq
              self.packages.${system}.default
            ];
            
            shellHook = ''
              echo "==========================================================="
              echo " Claude Code + Qwen / Z.ai Integration (via nix flake) "
              echo "==========================================================="
              echo "Comandos disponíveis:"
              echo "  claude-qwen                 - Inicia com Qwen (Padrão)"
              echo "  claude-qwen --provider zai  - Inicia com Z.ai"
              echo "  npx ...                     - Ferramentas NPM e nodejs"
              echo "==========================================================="
            '';
          };
        }
      );
    };
}
