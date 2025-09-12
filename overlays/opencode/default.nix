_: _final: prev: {
  opencode = prev.opencode.overrideAttrs (old: let
    version = "0.7.6";
    src = prev.fetchFromGitHub {
      owner = "sst";
      repo = "opencode";
      rev = "v${version}";
      hash = "sha256-pDG/wXbTbplBmssYbPjbAQ1O+EL5YeLAtQhioiRNIVc=";
    };
  in {
    inherit version src;
    tui = old.tui.overrideAttrs (_: {
      inherit version src;
      vendorHash = "sha256-de5FtS7iMrbmoLlIjdfrxs2OEI/f1dfU90GIJbvdO50=";
    });
    node_modules = old.node_modules.overrideAttrs (_: {
      inherit version src;
      outputHash = "sha256-PmLO0aU2E7NlQ7WtoiCQzLRw4oKdKxS5JI571lvbhHo=";
    });
  });
}
