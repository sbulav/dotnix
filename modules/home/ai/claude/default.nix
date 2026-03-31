{
  lib,
  config,
  pkgs,
  ...
}:
with lib.custom;
let
  inherit (lib)
    mkIf
    mkEnableOption
    nameValuePair
    filterAttrs
    ;

  cfg = config.custom.ai.claude;

  localSkillDir = ../opencode/skill;
  workflowSkillDir = ../shared/workflow/skill;

  # Reuse the opencode skill renderer - both tools share the same SKILL.md format
  optionalYamlField =
    key: value: if value != null && value != "" then "${key}: ${builtins.toJSON value}" else "";

  toSkillMarkdown = _name: skill: ''
    ---
    name: ${builtins.toJSON skill.name}
    description: ${builtins.toJSON skill.description}
    ${optionalYamlField "version" (skill.version or null)}
    ${optionalYamlField "argument-hint" (skill."argument-hint" or null)}
    ${optionalYamlField "disable-model-invocation" (skill."disable-model-invocation" or null)}
    ${optionalYamlField "user-invocable" (skill."user-invocable" or null)}
    ${optionalYamlField "model" (skill.model or null)}
    ${optionalYamlField "context" (skill.context or null)}
    ${optionalYamlField "agent" (skill.agent or null)}
    ${
      if (skill ? allowed-tools && skill.allowed-tools != [ ]) then
        "allowed-tools:\n" + lib.concatStringsSep "\n" (map (tool: "  - ${tool}") skill.allowed-tools)
      else
        ""
    }
    ---
    ${skill.content or ""}
  '';

  processSkillDir =
    dir:
    let
      files = builtins.readDir dir;
      nixFiles = filterAttrs (name: _: lib.hasSuffix ".nix" name) files;
    in
    lib.mapAttrs' (
      name: _:
      let
        fileName = lib.removeSuffix ".nix" name;
        skill = import (dir + "/${name}");
      in
      nameValuePair fileName skill
    ) nixFiles;

  skills = (processSkillDir localSkillDir) // (processSkillDir workflowSkillDir);

  dataHome = config.xdg.dataHome;

  langfusePython = pkgs.python3.withPackages (ps: [ ps.langfuse ]);

  # Only the hooks worth having - security, notifications, pre-compact, subagent summary
  hooks = {
    Notification = [
      {
        matcher = "";
        hooks = [
          {
            type = "command";
            command = "notify-send -a 'Claude Code' 'Claude Code' 'Awaiting your input'";
          }
        ];
      }
    ];

    PreToolUse = [
      # Block dangerous bash patterns that permission lists can't express
      {
        matcher = "Bash";
        hooks = [
          {
            type = "command";
            timeout = 5;
            command = ''
              input=$(cat)
              cmd=$(echo "$input" | jq -r '.tool_input.command // ""')

              dangerous_patterns=(
                'curl.*\|.*sh'
                'curl.*\|.*bash'
                'wget.*\|.*sh'
                'wget.*\|.*bash'
                'eval.*\$\(curl'
                'eval.*\$\(wget'
                ':\(\)\{.*:\|:.*\};:'
                '\.ssh(/|$| )'
                '\.kube(/|$| )'
                'kubeconfig'
                '(source|\.)\s+.*\.env($|\s)'
                '\bprintenv\b'
                '\bdeclare\s+-p\b'
                '\bexport\s+-p\b'
                '\$KUBECONFIG'
              )

              for pattern in "''${dangerous_patterns[@]}"; do
                if echo "$cmd" | grep -qE "$pattern"; then
                  echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"Dangerous command pattern detected"}}'
                  exit 2
                fi
              done

              if echo "$cmd" | grep -qE '(^|[[:space:]|;&=])([^[:space:]|;&=]*/)?\.env($|[[:space:]|;&=])'; then
                echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":".env file is protected"}}'
                exit 2
              fi

              exit 0
            '';
          }
        ];
      }
      # Block path traversal and direct .env access in file tools
      {
        matcher = "Write|Edit|MultiEdit|Read|Glob|Grep";
        hooks = [
          {
            type = "command";
            timeout = 5;
            command = ''
              input=$(cat)
              tool_name=$(echo "$input" | jq -r '.tool_name // ""')
              target=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // .tool_input.path // .tool_input.pattern // ""')

              if echo "$input" | jq -r '.tool_input | to_entries[] | .value' 2>/dev/null | grep -qE '\.\./' ; then
                echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"Path traversal attempt detected"}}'
                exit 2
              fi

              if [[ "$tool_name" =~ ^(Read|Write|Edit|MultiEdit)$ ]] && [[ -n "$target" ]] && echo "$target" | grep -qE '(^|/)\.env$'; then
                echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":".env file is protected"}}'
                exit 2
              fi

              if [[ -n "$target" ]] && echo "$target" | grep -qiE '(^|/)(\.ssh|\.kube)(/|$)'; then
                echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"~/.ssh and ~/.kube are protected"}}'
                exit 2
              fi

              if [[ -n "$target" ]] && echo "$target" | grep -qiE '(^|/)kubeconfig($|\.)'; then
                echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"kubeconfig files are protected"}}'
                exit 2
              fi

              exit 0
            '';
          }
        ];
      }
    ];

    PreCompact = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = ''
              mkdir -p ${dataHome}/claude-code/context-backups
              input=$(cat)
              session_id=$(echo "$input" | jq -r '.session_id // "unknown"')

              backup_file="${dataHome}/claude-code/context-backups/compact-$(date +%Y%m%d-%H%M%S).log"

              echo "=== Context Compaction at $(date) ===" >> "$backup_file"
              echo "Session ID: $session_id" >> "$backup_file"
              echo "Working Directory: $(pwd)" >> "$backup_file"

              echo "" >> "$backup_file"
              echo "Git Status:" >> "$backup_file"
              git status --short 2>/dev/null >> "$backup_file" || echo "Not a git repository" >> "$backup_file"

              echo "" >> "$backup_file"
              echo "Recently Modified Files:" >> "$backup_file"
              git diff --name-only HEAD 2>/dev/null >> "$backup_file" || echo "N/A" >> "$backup_file"
            '';
          }
        ];
      }
    ];

    SubagentStop = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            timeout = 10;
            command = ''
              input=$(cat)
              transcript_path=$(echo "$input" | jq -r '.agent_transcript_path // empty')

              if [[ -z "$transcript_path" ]] || [[ ! -f "$transcript_path" ]]; then
                exit 0
              fi

              line_count=$(wc -l < "$transcript_path")
              if [[ "$line_count" -lt 4 ]]; then
                exit 0
              fi

              summary=$(jq -s '
                def tool_uses:
                  [.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")];
                def files_modified:
                  [tool_uses | .[] | select(.name == "Edit" or .name == "Write" or .name == "MultiEdit") | .input.file_path // .input.filePath // empty] | map(select(. != null and . != "")) | unique | length;
                def bash_count:
                  [tool_uses | .[] | select(.name == "Bash")] | length;
                def read_count:
                  [tool_uses | .[] | select(.name == "Read" or .name == "Glob" or .name == "Grep")] | length;
                def error_count:
                  [.[] | select(.type == "tool_result") | select(.error == true or .is_error == true)] | length;
                def last_text:
                  [.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text // empty] | last // "" | split("\n")[0] | if length > 80 then .[0:80] + "..." else . end;
                {
                  files: files_modified,
                  bash: bash_count,
                  reads: read_count,
                  errors: error_count,
                  summary: last_text
                }
              ' "$transcript_path" 2>/dev/null)

              files=$(echo "$summary" | jq -r '.files // 0')
              bash=$(echo "$summary" | jq -r '.bash // 0')
              reads=$(echo "$summary" | jq -r '.reads // 0')
              errors=$(echo "$summary" | jq -r '.errors // 0')
              text=$(echo "$summary" | jq -r '.summary // ""')

              parts=()
              [[ "$files" -gt 0 ]] && parts+=("$files files")
              [[ "$bash" -gt 0 ]] && parts+=("$bash cmds")
              [[ "$reads" -gt 0 ]] && parts+=("$reads reads")
              [[ "$errors" -gt 0 ]] && parts+=("$errors errs")

              if [[ ''${#parts[@]} -gt 0 ]]; then
                IFS=', '; stats="''${parts[*]}"; unset IFS
                notify_msg="[$stats] $text"
              elif [[ -n "$text" ]]; then
                notify_msg="$text"
              else
                notify_msg="Subagent completed"
              fi

              notify-send -a "Claude Code" "Claude Code" "$notify_msg"
            '';
          }
        ];
      }
    ];

    Stop = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "${langfusePython}/bin/python ${config.home.homeDirectory}/.claude/hooks/langfuse_hook.py >> ${config.home.homeDirectory}/.claude/hooks/langfuse-stop.log 2>&1";
          }
        ];
      }
    ];
  };

  settings = {
    permissions = {
      allow = [
        "Glob"
        "Grep"
        "Read"
        "Task"
        "TodoWrite"
        # Git — safe read-only ops
        "Bash(git status)"
        "Bash(git log *)"
        "Bash(git diff *)"
        "Bash(git show *)"
        "Bash(git branch *)"
        "Bash(git remote *)"
        # Forgejo via tea
        "Bash(tea issues *)"
        "Bash(tea pulls *)"
        "Bash(tea comment *)"
        "Bash(tea issues create *)"
        "Bash(tea pr create *)"
        # Basic filesystem
        "Bash(ls *)"
        "Bash(mkdir *)"
        # Nix tooling
        "Bash(nix *)"
        "Bash(nixos-option *)"
        "Bash(systemctl list-units *)"
        "Bash(systemctl list-timers *)"
        "Bash(systemctl status *)"
        "Bash(journalctl *)"
        "Bash(claude --version)"
        "WebFetch(domain:github.com)"
        "WebFetch(domain:raw.githubusercontent.com)"
      ];
      ask = [
        # Git — mutating ops
        "Bash(git add *)"
        "Bash(git checkout *)"
        "Bash(git commit *)"
        "Bash(git merge *)"
        "Bash(git pull *)"
        "Bash(git push *)"
        "Bash(git rebase *)"
        "Bash(git reset *)"
        "Bash(git restore *)"
        "Bash(git stash *)"
        "Bash(git switch *)"
        # File ops
        "Bash(cp *)"
        "Bash(mv *)"
        "Bash(rm *)"
        "Bash(chmod *)"
        "Bash(curl *)"
        "Bash(sudo *)"
        "Bash(nixos-rebuild *)"
        # Content readers — bypass file-tool hooks, so require approval
        "Bash(cat *)"
        "Bash(head *)"
        "Bash(tail *)"
        "Bash(find *)"
        "Bash(grep *)"
        "Bash(rg *)"
      ];
      deny = [
        "Bash(rm -rf /*)"
        "Bash(dd *)"
        "Bash(mkfs *)"
        # Environment variable exposure
        "Bash(env)"
        "Bash(env *)"
        "Bash(printenv)"
        "Bash(printenv *)"
        "Bash(set)"
        "Bash(declare -p *)"
        "Bash(export -p)"
      ];
    };
    vim = true;
    statusLine = {
      type = "command";
      command = "${dataHome}/claude-code/statusline.sh";
    };
    env = {
      CLAUDE_CODE_ENABLE_TELEMETRY = "0";
      CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS = "1";
    };
    inherit hooks;
  };

  settingsFile = pkgs.writeText "claude-settings.json" (builtins.toJSON settings);

  # Proxy wrapper - programs.claude-code will wrap this again for --mcp-config
  claudeWithProxy = pkgs.symlinkJoin {
    name = "claude-code";
    paths = [ pkgs.unstable.claude-code ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude \
        --set HTTPS_PROXY "http://fwdproxy.pyn.ru:4443" \
        --set HTTP_PROXY  "http://fwdproxy.pyn.ru:4443" \
        --set NO_PROXY    "localhost,127.0.0.1"
    '';
  };
in
{
  options.custom.ai.claude = {
    enable = mkBoolOpt false "Whether to enable the Claude AI CLI assistant";
  };

  config = mkIf cfg.enable {

    programs.claude-code = {
      enable = true;
      package = claudeWithProxy;
      # settings intentionally omitted - keep settings.json mutable for plugin installs
      mcpServers = {
        kubernetes = {
          command = "mcp-k8s-go";
          args = [ "--readonly" ];
        };
        nixos = {
          command = "nix";
          args = [
            "run"
            "github:utensils/mcp-nixos"
            "--"
          ];
        };
        context7 = {
          type = "http";
          url = "https://mcp.context7.com/mcp";
        };
        sequential-thinking = {
          command = "npx";
          args = [
            "-y"
            "@modelcontextprotocol/server-sequential-thinking"
          ];
        };
      };
    };

    home.activation.claudeSettings = {
      after = [ "writeBoundary" ];
      before = [ ];
      data = ''
        CLAUDE_DIR="$HOME/.claude"
        SETTINGS="$CLAUDE_DIR/settings.json"
        mkdir -p "$CLAUDE_DIR"
        if [ -L "$SETTINGS" ]; then
          rm "$SETTINGS"
        fi
        if [ -f "$SETTINGS" ]; then
          chmod 644 "$SETTINGS"
          ${pkgs.jq}/bin/jq --slurpfile nix ${settingsFile} \
            '. * $nix[0]' "$SETTINGS" > "$SETTINGS.tmp" \
            && mv "$SETTINGS.tmp" "$SETTINGS"
        else
          cp ${settingsFile} "$SETTINGS"
          chmod 644 "$SETTINGS"
        fi
      '';
    };

    home.file = {
      ".claude/hooks/langfuse_hook.py" = {
        executable = true;
        source = ./langfuse_hook.py;
      };

      ".local/share/claude-code/statusline.sh" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          input=$(cat)
          MODEL=$(echo "$input" | jq -r '.model.display_name // "claude"')
          PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

          BAR_WIDTH=10
          FILLED=$((PCT * BAR_WIDTH / 100))
          EMPTY=$((BAR_WIDTH - FILLED))
          BAR=""
          [ "$FILLED" -gt 0 ] && printf -v F "%''${FILLED}s" && BAR="''${F// /▓}"
          [ "$EMPTY"  -gt 0 ] && printf -v E "%''${EMPTY}s"  && BAR="$BAR''${E// /░}"

          printf "[$MODEL] ctx $BAR %s%%\n" "$PCT"
        '';
      };
    }
    # Shared skills from opencode - same SKILL.md format, zero duplication
    // lib.mapAttrs' (
      name: skill:
      nameValuePair ".claude/skills/${skill.name}/SKILL.md" {
        text = toSkillMarkdown name skill;
      }
    ) skills;
  };
}
