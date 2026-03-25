# Claude Code + Qwen OAuth Integration

Uma integração entre o [Claude Code](https://github.com/anthropics/claude-code) e o modelo [Qwen Coder](https://qwenlm.github.io/) usando autenticação OAuth, gerenciado através de um ambiente Nix Flake reproduzível.

## 🎯 Visão Geral

Este projeto cria um ambiente de desenvolvimento auto-contido que:

1. **Gerencia autenticação OAuth** com Qwen Code
2. **Inicia um servidor de ponte** (bridge router) que redireciona requisições para a API Qwen
abre o Claude Code normalmente, mas usando o modelo `coder-model` como backend

### Arquitetura

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Claude Code    │────▶│  Bridge Router   │────▶│  Qwen API       │
│  (CLI Interface)│     │  (localhost)     │     │  (qwen-coder+)  │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                              ▲
                              │
                         ┌────┴────┐
                         │  OAuth  │
                         │  Token  │
                         └─────────┘
```

## 📋 Pré-requisitos

- **Nix** (com suporte a flakes) instalado
- **Node.js** 22 (gerenciado pelo Nix)
- Conexão com internet para downloads iniciais

### Verificando suporte a flakes

```bash
# Adicione experimental features se necessário
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

## 🚀 Instalação e Uso

### Entrar no ambiente de desenvolvimento

```bash
cd /home/lluz/tmp/cc_qwen
nix develop
```

Você verá uma mensagem de boas-vindas confirmando que o ambiente está pronto.

### Primeiro uso (autenticação)

```bash
claude-qwen
```

No primeiro uso, você será redirecionado para fazer login na sua conta Qwen:

1. O navegador abrirá (ou você receberá um URL)
2. Faça login com suas credenciais Qwen/Alibaba
3. O token OAuth será salvo em `~/.qwen/oauth_creds.json`

### Usos subsequentes

Após autenticado, basta executar:

```bash
nix develop    # Entra no ambiente
claude-qwen    # Inicia Claude Code com Qwen backend
```

## 🛠️ Comandos Disponíveis

Dentro do ambiente Nix (`nix develop`):

| Comando | Descrição |
|---------|-----------|
| `claude-qwen` | Inicia Claude Code com backend Qwen Coder Plus |
| `npx @anthropic-ai/claude-code` | Claude Code original (sem Qwen) |
| `npx @musistudio/claude-code-router` | Bridge router standalone |

## 📁 Estrutura do Projeto

```
.
├── flake.nix          # Configuração do ambiente Nix
├── flake.lock         # Locks reproducíveis das dependências
└── README.md          # Este arquivo
```

## ⚙️ Configuração

### Mudar o modelo Qwen

Edite `flake.nix` e modifique a variável `qwenModel`:

```nix
qwenModel = "qwen-coder-plus";  # ou outro modelo disponível
```

### Localização do token

O token OAuth é armazenado em:
```
~/.qwen/oauth_creds.json
```

Para re-autenticar, simplesmente remova este arquivo e rode `claude-qwen` novamente.

## 🐛 Troubleshooting

### "Token is empty or invalid"

**Causa:** Token expirado ou corrompido.

**Solução:**
```bash
rm -f ~/.qwen/oauth_creds.json
claude-qwen  # Vai pedir autenticação novamente
```

### "Router failed to start"

**Causa:** Porta já em uso ou dependências faltando.

**Solução:**
```bash
# Verifique se já existe um router rodando
ps aux | grep claude-code-router

# Mate processos órfãos se necessário
pkill -f claude-code-router
```

### "npx: command not found"

**Causa:** Ambiente Nix não foi ativado corretamente.

**Solução:**
```bash
# Certifique-se de estar usando nix develop
nix develop
# Não use 'nix run' ou 'nix shell' diretamente
```

### Erro de permissão no token

**Causa:** Permissões incorretas no arquivo de credenciais.

**Solução:**
```bash
chmod 600 ~/.qwen/oauth_creds.json
```

## 🔧 Desenvolvimento

### Adicionar novas dependências

Edite `flake.nix` e adicione ao `buildInputs`:

```nix
devShells.default = pkgs.mkShell {
  buildInputs = [
    nodeVersion
    pkgs.jq
    claude-qwen
    pkgs.nodePackages.npm
    # pkgs.sua-dependencia-aqui  # ← Adicione aqui
  ];
  ...
};
```

### Atualizar dependências

```bash
nix flake update
```

## 📝 Notas Técnicas

### Por que Nix Flake?

- **Reproduzibilidade:** Mesmo ambiente em qualquer máquina
- **Isolamento:** Não polui o sistema global
- **Declarativo:** Configuração versionada no código

### Como funciona o router?

O `@musistudio/claude-code-router` cria um servidor local que:
1. Intercepta chamadas da API do Claude Code
2. Substitui o endpoint Anthropic pela API Qwen
3. Usa o token OAuth para autenticação
4. Traduz requisições/respostas entre os formatos

### Segurança

- O token OAuth é armazenado localmente apenas
- O router roda em `localhost` (não exposto externamente)
- Credenciais nunca são enviadas para servidores de terceiros além da Qwen API oficial

## 📄 Licença

Este projeto é fornecido como-is, sem garantias.

## 🙏 Agradecimentos

- [Anthropic](https://www.anthropic.com/) pelo Claude Code
- [Alibaba Qwen](https://qwenlm.github.io/) pelo modelo Qwen Coder
- [musistudio](https://github.com/musistudio) pelo claude-code-router
- Comunidade Nix pelas ferramentas reproduzíveis
