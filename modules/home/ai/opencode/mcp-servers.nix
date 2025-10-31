{
  kubernetes = {
    type = "local";
    command = [
      "mcp-k8s-go"
      "--readonly"
    ];
    enabled = true;
  };
  nixos = {
    type = "local";
    command = [
      "nix"
      "run"
      "github:utensils/mcp-nixos"
      "--"
    ];
    enabled = true;
  };
}
