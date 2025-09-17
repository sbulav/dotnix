# OpenCode Custom Home Manager Module

This module provides a modular configuration for the OpenCode AI assistant under the `custom.ai.opencode` namespace, organized into separate files for better maintainability.

## Structure

- `default.nix` - Main module definition using `programs.opencode`
- `providers.nix` - AI provider configurations (OpenAI, Anthropic, etc.)
- `mcp-servers.nix` - MCP (Model Context Protocol) server configurations
- `agent/` - Directory for agent configuration files (`.nix` files)
- `command/` - Directory for command configuration files (`.nix` files)

## Usage

Enable the module in your Home Manager configuration:

```nix
{
  custom.ai.opencode = {
    enable = true;
    settings = {
      # Override default settings here
      model = "hhdev-anthropic/claude-sonnet-4-20250514";
      theme = "dark";
    };
  };
}
```

## Adding Custom Providers

Edit `providers.nix` to add new AI providers:

```nix
{
  "my-custom-provider" = {
    name = "My Custom Provider";
    npm = "@ai-sdk/openai-compatible";
    options = {
      baseURL = "https://my-api.example.com";
      apiKey = "{env:CUSTOM_API_KEY}";
    };
    models = {
      "my-model" = {
        name = "My Model";
      };
    };
  };
}
```

## Adding Agents

Create `.nix` files in the `agent/` directory:

```nix
# agent/coding-assistant.nix
{
  name = "Coding Assistant";
  description = "Specialized coding assistant";
  model = "hhdev-openai/gpt-4.1";
  temperature = 0.3;
  system_prompt = "You are a helpful coding assistant...";
}
```

### Included Agents

- **committer**: Generate and apply Conventional Commits for staged changes, safely. Uses `hhdev-openai/gpt-4.1` with low temperature for deterministic formatting. Has restricted permissions to prevent accidental file modifications.
- **pr-creator**: Creates Pull Requests in Forgejo from the current branch. Determines owner/repo and default branch from git, generates a concise Russian description based on commits, and calls curl with FJ_TOKEN. Uses restricted permissions for safe git operations and API calls.

### Included Commands

- **commit**: Draft (and optionally apply) a Conventional Commit for staged changes. Uses the `committer` agent to analyze staged changes and propose a properly formatted Conventional Commit message. Requires user confirmation before applying the commit.
- **pr**: Create a Pull Request in Forgejo from the current branch with a concise Russian description. Uses the `pr-creator` agent to determine repository details from git, generate PR content, and call the Forgejo API. Supports argument overrides for title, body, base branch, host, owner, and repo. Includes dry-run mode for testing.

## Adding Commands

Create `.nix` files in the `command/` directory:

```nix
# command/format-code.nix
{
  name = "Format Code";
  description = "Format the current file";
  command = "prettier --write $FILE";
  timeout = 10;
}
```

## MCP Servers

Edit `mcp-servers.nix` to configure MCP servers:

```nix
{
  my-server = {
    type = "local";
    command = ["my-mcp-server" "--port" "8080"];
    enabled = true;
  };
}
```

## Generated Files

The module generates the following configuration files in `~/.config/opencode/`:

- `opencode.json` - Main configuration
- `agents/*.json` - Agent configurations
- `commands/*.json` - Command configurations
- `tools/*` - Tool scripts (if configured)