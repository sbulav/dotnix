_: _final: prev: {
  openconnect = prev.openconnect.overrideAttrs (oldAttrs: rec {
    version = "master";
    src = prev.fetchFromGitLab {
      owner = "openconnect";
      repo = "openconnect";
      rev = "master";
      sha256 = "sha256-OBEojqOf7cmGtDa9ToPaJUHrmBhq19/CyZ5agbP7WUw="; # update with the actual hash
    };
  });
}
