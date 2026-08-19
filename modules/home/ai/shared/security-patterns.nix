# Single source for the security denylist enforced by BOTH harnesses:
#   - `bash`: POSIX ERE strings, rendered into the Claude Code PreToolUse
#     Bash hook's grep -qE loop (claude/default.nix)
#   - `js`: JS regex literals, rendered into the opencode SecurityPlugin's
#     dangerousPatterns array (opencode/plugin/security.nix)
# The dialects cannot share one expression (ERE has no non-capturing groups,
# lookaheads, or flags) — when adding a protection, add BOTH forms.
[
  {
    id = "pipe-to-shell";
    bash = [
      ''curl.*\|.*sh''
      ''curl.*\|.*bash''
      ''wget.*\|.*sh''
      ''wget.*\|.*bash''
    ];
    js = [ ''/\b(curl|wget)\b[^|]*\|\s*\b(sh|bash)\b/i'' ];
  }
  {
    id = "eval-download";
    bash = [
      ''eval.*\$\(curl''
      ''eval.*\$\(wget''
    ];
    js = [ ''/\beval\b.*\$\(/'' ];
  }
  {
    id = "fork-bomb";
    bash = [ '':\(\)\{.*:\|:.*\};:'' ];
    js = [ ''/:\(\)\{.*:\|:.*\};:/'' ];
  }
  # Reading SSH / Kubernetes credentials
  {
    id = "ssh-dir";
    bash = [ ''\.ssh(/|$| )'' ];
    js = [ ''/\.ssh(?:\/|$|\s)/i'' ];
  }
  {
    id = "kube-dir";
    bash = [ ''\.kube(/|$| )'' ];
    js = [ ''/\.kube(?:\/|$|\s)/i'' ];
  }
  {
    id = "kubeconfig";
    bash = [ "kubeconfig" ];
    js = [ "/kubeconfig/i" ];
  }
  # Dumping the environment (which carries injected secrets)
  {
    id = "source-env";
    bash = [ ''(source|\.)\s+.*\.env($|\s)'' ];
    js = [ ''/(?:source|\.)\s+.*\.env(?:$|\s)/'' ];
  }
  {
    id = "printenv";
    bash = [ ''\bprintenv\b'' ];
    js = [ ''/\bprintenv\b/'' ];
  }
  {
    id = "declare-p";
    bash = [ ''\bdeclare\s+-p\b'' ];
    js = [ ''/\bdeclare\s+-p\b/'' ];
  }
  {
    id = "export-p";
    bash = [ ''\bexport\s+-p\b'' ];
    js = [ ''/\bexport\s+-p\b/'' ];
  }
  {
    id = "kubeconfig-var";
    bash = [ ''\$KUBECONFIG'' ];
    js = [ ''/\$KUBECONFIG/'' ];
  }
]
