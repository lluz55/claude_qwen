{
  description = "Claude Code + Qwen OAuth Integration via Nix Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      
      qwenModel = "qwen3-coder-plus";
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          
          claude-qwen-script = pkgs.writeShellScriptBin "claude-qwen" ''
            #!/usr/bin/env bash
            set -e
            
            QWEN_MODEL="${qwenModel}"
            OAUTH_FILE="$HOME/.qwen/oauth_creds.json"
            ROUTER_DIR="$HOME/.claude-code-router"
            
            # Garantir que jq e nodejs estejam no PATH
            export PATH="${pkgs.jq}/bin:${pkgs.nodejs_22}/bin:$PATH"
            
            # 1. Verificar/obter token OAuth
            if [ ! -f "$OAUTH_FILE" ] || [ -z "$(${pkgs.jq}/bin/jq -r '.access_token // empty' "$OAUTH_FILE" 2>/dev/null)" ]; then
                echo "⚠️ Token Qwen OAuth não encontrado ou inválido."
                echo "Iniciando qwen-code para autenticação..."
                echo "👉 DICA: Digite /auth, escolha a opção 'Qwen OAuth', conclua no navegador e depois digite /exit"
                echo ""
                ${pkgs.nodejs_22}/bin/npx -y @qwen-code/qwen-code@latest
            fi
            
            if [ ! -f "$OAUTH_FILE" ]; then
                echo "❌ Falha ao obter credenciais. O arquivo não foi criado."
                exit 1
            fi
            
            TOKEN=$(${pkgs.jq}/bin/jq -r '.access_token' "$OAUTH_FILE")
            
            if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
                echo "❌ Token inválido no arquivo."
                exit 1
            fi
            
            # 2. Configurar o router
            mkdir -p "$ROUTER_DIR"
            echo "⚙️ Gerando configuração do router..."
            ${pkgs.jq}/bin/jq -n \
              --arg token "$TOKEN" \
              --arg model "$QWEN_MODEL" \
              '{
                PORT: 3456,
                LOG: true,
                Providers: [
                  {
                    name: "qwen",
                    api_base_url: "https://portal.qwen.ai/v1/chat/completions",
                    api_key: $token,
                    models: [$model],
                    transformer: { use: ["deepseek"] }
                  }
                ],
                Router: {
                  default: ("qwen," + $model),
                  think: ("qwen," + $model)
                }
              }' > "$ROUTER_DIR/config.json"
            
            # 3. Iniciar o router em background
            echo "🚀 Garantindo que nenhuma instância anterior esteja rodando..."
            pkill -f "ccr start" 2>/dev/null || true
            
            echo "🚀 Iniciando Claude Code Router..."
            rm -f /tmp/ccr.log
            nohup ${pkgs.nodejs_22}/bin/npx -y @musistudio/claude-code-router@latest start > /tmp/ccr.log 2>&1 &
            ROUTER_PID=$!
            
            cleanup() {
                echo "🛑 Finalizando processos..."
                kill $ROUTER_PID 2>/dev/null || true
                pkill -f "ccr start" 2>/dev/null || true
            }
            trap cleanup EXIT INT TERM
            
            echo "Aguardando inicialização do router..."
            for i in {1..20}; do
                # Tentar conectar no socket do router
                if (exec 3<>/dev/tcp/127.0.0.1/3456) 2>/dev/null; then
                    exec 3>&-
                    echo "✅ Router iniciado com sucesso na porta 3456."
                    break
                fi
                sleep 0.5
                echo -n "."
            done
            echo ""
            
            # 4. Iniciar o Claude Code
            echo "🤖 Iniciando Claude Code via router..."
            export ANTHROPIC_BASE_URL="http://127.0.0.1:3456"
            export ANTHROPIC_AUTH_TOKEN="dummy-token"
            # O Claude Code exige que a API BASE termine sem /v1 se estiver usando o router que simula o endpoint Anthropic
            ${pkgs.nodejs_22}/bin/npx -y @anthropic-ai/claude-code@latest "$@"
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
              echo "================================================="
              echo " Claude Code + Qwen OAuth (via nix flake) "
              echo "================================================="
              echo "Comandos disponíveis:"
              echo "  claude-qwen    - Inicia o Claude Code integrado com Qwen"
              echo "  npx ...        - Ferramentas NPM e nodejs disponiveis"
              echo "================================================="
            '';
          };
        }
      );
    };
}
