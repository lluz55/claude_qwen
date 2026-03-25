{
  description = "Claude Code + Qwen/Z.ai Integration via Nix Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      
      qwenModel = "coder-model";
      zaiModel = "glm-5";
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
            
            if [ "$PROVIDER" = "qwen" ]; then
                QWEN_MODEL="${MODEL_OVERRIDE:-${qwenModel}}"
                QWEN_ISOLATION_DIR="$PWD/.pi/qwen"
                mkdir -p "$QWEN_ISOLATION_DIR"

                # Configuração do Router
                ROUTER_DIR="$QWEN_ISOLATION_DIR/.claude-code-router"
                
                # Garantir que jq e nodejs estejam no PATH
                export PATH="${pkgs.jq}/bin:${pkgs.nodejs_22}/bin:$PATH"

                # Tentar encontrar um token VÁLIDO em múltiplos locais possíveis
                OAUTH_FILE=""
                TOKEN=""
                CURRENT_TIME=$(${pkgs.jq}/bin/jq -n 'now * 1000')

                check_token() {
                    local file=$1
                    local type=$2
                    if [ -f "$file" ]; then
                        local t=""
                        local e=0
                        if [ "$type" = "agent" ]; then
                            t=$(${pkgs.jq}/bin/jq -r '.["qwen-cli"].access_token // .access_token // empty' "$file")
                            e=$(${pkgs.jq}/bin/jq -r '.["qwen-cli"].expires // .expires // .expiry_date // 0' "$file")
                        else
                            t=$(${pkgs.jq}/bin/jq -r '.access_token // empty' "$file")
                            e=$(${pkgs.jq}/bin/jq -r '.expires // .expiry_date // 0' "$file")
                        fi

                        if [ -n "$t" ]; then
                            if [ "$e" -gt 0 ] && [ "$(${pkgs.jq}/bin/jq -n "$CURRENT_TIME > $e")" = "true" ]; then
                                local e_sec=$(${pkgs.jq}/bin/jq -n "$e / 1000 | floor")
                                echo "ℹ️ Token em $file expirou em $(date -d @$e_sec 2>/dev/null || echo "$e ms"). Removendo..."
                                rm -f "$file"
                                return 1
                            fi
                            TOKEN="$t"
                            OAUTH_FILE="$file"
                            return 0
                        fi
                    fi
                    return 1
                }

                # Ordem de preferência (usando if para evitar que set -e aborte o script)
                if ! check_token "$QWEN_ISOLATION_DIR/.qwen/oauth_creds.json" "standard"; then
                    if ! check_token "$QWEN_ISOLATION_DIR/agent/auth.json" "agent"; then
                        check_token "$HOME/.qwen/oauth_creds.json" "standard" || true
                    fi
                fi
                
                if [ -z "$TOKEN" ]; then
                    echo "⚠️ Nenhum token Qwen OAuth válido encontrado."
                    echo "Iniciando qwen-code para autenticação isolada em $QWEN_ISOLATION_DIR..."
                    echo "👉 DICA: No qwen-code, digite /auth, escolha 'Qwen OAuth' e complete no navegador."
                    echo "👉 IMPORTANTE: Após o sucesso, digite /exit para o Claude iniciar."
                    echo ""
                    
                    OLD_HOME_AUTH="$HOME"
                    export HOME="$QWEN_ISOLATION_DIR"
                    ${pkgs.nodejs_22}/bin/npx -y @qwen-code/qwen-code@latest
                    export HOME="$OLD_HOME_AUTH"
                    
                    if check_token "$QWEN_ISOLATION_DIR/.qwen/oauth_creds.json" "standard"; then
                        echo "✅ Novo token obtido. Sincronizando com agent/auth.json..."
                        mkdir -p "$QWEN_ISOLATION_DIR/agent"
                        # Sincronizar para o formato que o agent espera
                        ${pkgs.jq}/bin/jq -n --arg tk "$TOKEN" '{"qwen-cli": {"access_token": $tk, "type": "oauth"}}' > "$QWEN_ISOLATION_DIR/agent/auth.json"
                    fi
                fi
                
                if [ -z "$TOKEN" ]; then
                    echo "❌ Falha ao obter credenciais."
                    exit 1
                fi
                
                # Preparar diretório isolado para Claude Code (.claude)
                QWEN_CLAUDE_DIR="$QWEN_ISOLATION_DIR/.claude"
                mkdir -p "$QWEN_CLAUDE_DIR"

                # Configurações do Claude
                QWEN_SETTINGS="$QWEN_ISOLATION_DIR/settings.json"
                ${pkgs.jq}/bin/jq -n \
                  --arg sonnet "$QWEN_MODEL" \
                  '{
                    "env": {
                      "ANTHROPIC_DEFAULT_SONNET_MODEL": $sonnet,
                      "ANTHROPIC_DEFAULT_HAIKU_MODEL": $sonnet,
                      "ANTHROPIC_DEFAULT_OPUS_MODEL": $sonnet
                    }
                  }' > "$QWEN_SETTINGS"

                echo "⚙️ Isolando ambiente em $QWEN_ISOLATION_DIR..."
                
                # Isolar ambiente alterando HOME e XDG ANTES de iniciar o router
                OLD_HOME="$HOME"
                export HOME="$QWEN_ISOLATION_DIR"
                export XDG_CONFIG_HOME="$HOME/.config"
                export XDG_DATA_HOME="$HOME/.local/share"
                export XDG_CACHE_HOME="$HOME/.cache"
                
                # Manter .gitconfig e SSH se existirem para que ferramentas funcionem
                [ -f "$OLD_HOME/.gitconfig" ] && ln -sf "$OLD_HOME/.gitconfig" "$HOME/.gitconfig"
                [ -d "$OLD_HOME/.ssh" ] && ln -sf "$OLD_HOME/.ssh" "$HOME/.ssh"

                mkdir -p "$ROUTER_DIR"
                echo "⚙️ Gerando configuração do router para Qwen (com modelo $QWEN_MODEL)..."
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
                        "transformer": "qwen-cli",
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
                
                cleanup() { 
                  kill -9 $ROUTER_PID 2>/dev/null || true; 
                  pkill -9 -f "claude-code-router" 2>/dev/null || true; 
                }
                trap cleanup EXIT INT TERM
                
                for i in {1..20}; do
                    if (exec 3<>/dev/tcp/127.0.0.1/3457) 2>/dev/null; then
                        exec 3>&-
                        echo "✅ Router na porta 3457."
                        break
                    fi
                    sleep 0.5
                done
                
                echo "🚀 Iniciando Claude Code (Qwen)..."
                export ANTHROPIC_BASE_URL="http://127.0.0.1:3457"
                export ANTHROPIC_API_KEY="sk-ant-dummy"
                export ANTHROPIC_AUTH_TOKEN="sk-ant-dummy"
                
                ${pkgs.nodejs_22}/bin/npx -y @anthropic-ai/claude-code@latest --settings "$QWEN_SETTINGS" "''${CLAUDE_ARGS[@]}"

            elif [ "$PROVIDER" = "zai" ]; then
                ZAI_MODEL="${MODEL_OVERRIDE:-${zaiModel}}"
                ZAI_ISOLATION_DIR="$PWD/.pi/zai"
                mkdir -p "$ZAI_ISOLATION_DIR"

                # Configuração do Router
                ROUTER_DIR="$ZAI_ISOLATION_DIR/.claude-code-router"
                
                # Garantir que jq e nodejs estejam no PATH
                export PATH="${pkgs.jq}/bin:${pkgs.nodejs_22}/bin:$PATH"

                # Tentar encontrar um token VÁLIDO em múltiplos locais possíveis
                TOKEN=""
                
                check_zai_token() {
                    local file=$1
                    if [ -f "$file" ]; then
                        local t=""
                        # Tentar formato auth.json ou credentials.json
                        t=$(${pkgs.jq}/bin/jq -r '.api_key // .access_token // empty' "$file" 2>/dev/null)
                        if [ -n "$t" ]; then
                            TOKEN="$t"
                            return 0
                        fi
                    fi
                    return 1
                }

                # Ordem de preferência
                if ! check_zai_token "$ZAI_ISOLATION_DIR/.zai/auth.json"; then
                    if ! check_zai_token "$ZAI_ISOLATION_DIR/.zai/credentials.json"; then
                        if ! check_zai_token "$HOME/.zai/auth.json"; then
                            check_zai_token "$HOME/.zai/credentials.json" || true
                        fi
                    fi
                fi
                
                if [ -z "$TOKEN" ]; then
                    echo "⚠️ Nenhum token Z.ai válido encontrado."
                    echo "Iniciando zcode para autenticação isolada em $ZAI_ISOLATION_DIR..."
                    echo "👉 DICA: No zcode, o comando de autenticação iniciará automaticamente."
                    echo "👉 IMPORTANTE: Após salvar a chave, digite /exit para o Claude iniciar."
                    echo ""
                    
                    OLD_HOME_AUTH="$HOME"
                    export HOME="$ZAI_ISOLATION_DIR"
                    # zcode auth para configurar a chave
                    ${pkgs.nodejs_22}/bin/npx -y @staticpayload/zai-code@latest auth
                    export HOME="$OLD_HOME_AUTH"
                    
                    if check_zai_token "$ZAI_ISOLATION_DIR/.zai/auth.json"; then
                        echo "✅ Novo token obtido."
                    fi
                fi
                
                if [ -z "$TOKEN" ]; then
                    echo "❌ Falha ao obter credenciais Z.ai."
                    exit 1
                fi
                
                # Preparar diretório isolado para Claude Code (.claude)
                ZAI_CLAUDE_DIR="$ZAI_ISOLATION_DIR/.claude"
                mkdir -p "$ZAI_CLAUDE_DIR"

                # Configurações do Claude
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

                echo "⚙️ Isolando ambiente em $ZAI_ISOLATION_DIR..."
                
                # Isolar ambiente alterando HOME e XDG ANTES de iniciar o router
                OLD_HOME="$HOME"
                export HOME="$ZAI_ISOLATION_DIR"
                export XDG_CONFIG_HOME="$HOME/.config"
                export XDG_DATA_HOME="$HOME/.local/share"
                export XDG_CACHE_HOME="$HOME/.cache"
                
                # Manter .gitconfig e SSH se existirem para que ferramentas funcionem
                [ -f "$OLD_HOME/.gitconfig" ] && ln -sf "$OLD_HOME/.gitconfig" "$HOME/.gitconfig"
                [ -d "$OLD_HOME/.ssh" ] && ln -sf "$OLD_HOME/.ssh" "$HOME/.ssh"

                mkdir -p "$ROUTER_DIR"
                echo "⚙️ Gerando configuração do router para Z.ai (modelo $ZAI_MODEL)..."
                ${pkgs.jq}/bin/jq -n \
                  --arg token "$TOKEN" \
                  --arg model "$ZAI_MODEL" \
                  '{
                    "PORT": 3458,
                    "LOG": true,
                    "LOG_LEVEL": "debug",
                    "Providers": [
                      {
                        "name": "zai",
                        "api_base_url": "https://api.z.ai/api/coding/paas/v4/chat/completions",
                        "api_key": $token,
                        "transformer": "zai",
                        "models": ["claude-3-5-sonnet-20241022", "claude-3-7-sonnet-20250219", "claude-sonnet-4-6", "claude-sonnet-latest", $model, "glm-4.7"]
                      }
                    ],
                    "Router": {
                      "claude-3-5-sonnet-20241022": ("zai," + $model),
                      "claude-3-7-sonnet-20250219": ("zai," + $model),
                      "claude-3-5-sonnet-latest": ("zai," + $model),
                      "claude-3-7-sonnet-latest": ("zai," + $model),
                      "claude-sonnet-4-6": ("zai," + $model),
                      "claude-sonnet-latest": ("zai," + $model),
                      "default": ("zai," + $model),
                      "think": ("zai," + $model)
                    }
                  }' > "$ROUTER_DIR/config.json"

                echo "🚀 Reiniciando Claude Code Router (Z.ai)..."
                pkill -9 -f "claude-code-router" 2>/dev/null || true
                pkill -9 -f "ccr start" 2>/dev/null || true
                sleep 1
                rm -f /tmp/ccr_zai.log
                nohup ${pkgs.nodejs_22}/bin/npx -y @musistudio/claude-code-router@latest start > /tmp/ccr_zai.log 2>&1 &
                ROUTER_PID=$!
                
                cleanup() { 
                  kill -9 $ROUTER_PID 2>/dev/null || true; 
                  pkill -9 -f "claude-code-router" 2>/dev/null || true; 
                }
                trap cleanup EXIT INT TERM
                
                for i in {1..20}; do
                    if (exec 3<>/dev/tcp/127.0.0.1/3458) 2>/dev/null; then
                        exec 3>&-
                        echo "✅ Router na porta 3458."
                        break
                    fi
                    sleep 0.5
                done
                
                echo "🚀 Iniciando Claude Code (Z.ai)..."
                export ANTHROPIC_BASE_URL="http://127.0.0.1:3458"
                export ANTHROPIC_API_KEY="sk-ant-dummy"
                export ANTHROPIC_AUTH_TOKEN="sk-ant-dummy"
                
                ${pkgs.nodejs_22}/bin/npx -y @anthropic-ai/claude-code@latest --settings "$ZAI_SETTINGS" "''${CLAUDE_ARGS[@]}"
            else
                echo "❌ Provedor desconhecido: $PROVIDER"
                exit 1
            fi
          '';
          
          zai-script = pkgs.writeShellScriptBin "zai" ''
            #!/usr/bin/env bash
            ${claude-qwen-script}/bin/claude-qwen --provider zai "$@"
          '';
        in {
          default = claude-qwen-script;
          zai = zai-script;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/claude-qwen";
        };
        zai = {
          type = "app";
          program = "${self.packages.${system}.zai}/bin/zai";
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
              self.packages.${system}.zai
            ];
            
            shellHook = ''
              echo "==========================================================="
              echo " Claude Code + Qwen / Z.ai Integration (via nix flake) "
              echo "==========================================================="
              echo "Comandos disponíveis:"
              echo "  claude-qwen                 - Inicia com Qwen (Padrão)"
              echo "  zai                         - Inicia com Z.ai (Coding Mode)"
              echo "  claude-qwen --provider zai  - Inicia com Z.ai (Legado)"
              echo "  npx ...                     - Ferramentas NPM e nodejs"
              echo "==========================================================="
            '';
          };
        }
      );
    };
}
