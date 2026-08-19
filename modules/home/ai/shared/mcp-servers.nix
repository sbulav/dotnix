# Central MCP server catalog — the single source both harness modules render
# from (via registry.nix). `providers` controls who gets a server; the split
# below deliberately preserves the historical per-harness sets. Local servers
# carry { command, args }; remote ones carry { remote.url }. `enabled` only
# matters to opencode (claude has no per-server toggle).
{
  kubernetes = {
    providers = [
      "claude"
      "opencode"
    ];
    local = {
      command = "mcp-k8s-go";
      args = [ "--readonly" ];
    };
  };
  nixos = {
    providers = [
      "claude"
      "opencode"
    ];
    local = {
      command = "nix";
      args = [
        "run"
        "github:utensils/mcp-nixos"
        "--"
      ];
    };
  };
  context7 = {
    providers = [ "claude" ];
    remote.url = "https://mcp.context7.com/mcp";
  };
  sequential-thinking = {
    providers = [ "claude" ];
    local = {
      command = "npx";
      args = [
        "-y"
        "@modelcontextprotocol/server-sequential-thinking"
      ];
    };
  };
  astro-docs = {
    providers = [ "opencode" ];
    enabled = false;
    remote.url = "https://mcp.docs.astro.build/mcp";
  };
}
