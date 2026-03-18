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

  skillDir = ../opencode/skill;

  # Reuse the opencode skill renderer — both tools share the same SKILL.md format
  optionalYamlField =
    key: value: if value != null && value != "" then "${key}: ${builtins.toJSON value}" else "";

  toSkillMarkdown = _name: skill: ''
    ---
    name: ${builtins.toJSON skill.name}
    description: ${builtins.toJSON skill.description}
    ${optionalYamlField "version" (skill.version or null)}
    ${
      if (skill ? allowed-tools && skill.allowed-tools != [ ]) then
        "allowed-tools:\n" + lib.concatStringsSep "\n" (map (tool: "  - ${tool}") skill.allowed-tools)
      else
        ""
    }
    ---
    ${skill.content or ""}
  '';

  # Import all skill .nix files from the shared opencode/skill directory
  skills =
    let
      files = builtins.readDir skillDir;
      nixFiles = filterAttrs (name: _: lib.hasSuffix ".nix" name) files;
    in
    lib.mapAttrs' (
      name: _:
      let
        fileName = lib.removeSuffix ".nix" name;
        skill = import (skillDir + "/${name}");
      in
      nameValuePair fileName skill
    ) nixFiles;

  dataHome = config.xdg.dataHome;

  # Only the hooks worth having — security, notifications, pre-compact, subagent summary
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
              )

              for pattern in "''${dangerous_patterns[@]}"; do
                if echo "$cmd" | grep -qE "$pattern"; then
                  echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"Dangerous command pattern detected"}}'
                  exit 2
                fi
              done

              exit 0
            '';
          }
        ];
      }
      # Block path traversal in file tools
      {
        matcher = "Write|Edit|MultiEdit|Read";
        hooks = [
          {
            type = "command";
            timeout = 5;
            command = ''
              input=$(cat)

              if echo "$input" | jq -r '.tool_input | to_entries[] | .value' 2>/dev/null | grep -qE '\.\./' ; then
                echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"Path traversal attempt detected"}}'
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
  };

  settings = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
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

  # Wrap the binary to inject proxy env vars — works in all shells and scripts,
  # unlike a shell alias which only applies to interactive sessions
  claudeWrapped = pkgs.symlinkJoin {
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
    home.packages = [ claudeWrapped ];

    home.file = {
      ".claude/settings.json".text = builtins.toJSON settings;
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
    # Shared skills from opencode — same SKILL.md format, zero duplication
    // lib.mapAttrs' (
      name: skill:
      nameValuePair ".claude/skills/${skill.name}/SKILL.md" {
        text = toSkillMarkdown name skill;
      }
    ) skills;
  };
}
