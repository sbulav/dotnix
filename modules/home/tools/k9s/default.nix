{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.tools.k9s;
in
{
  options.custom.tools.k9s = {
    enable = mkBoolOpt true "Whether or not to enable k9s.";
  };

  config = mkIf cfg.enable {
    xdg.enable = lib.mkForce pkgs.stdenv.isLinux;

    programs.k9s = {
      enable = true;

      plugins = {
        # https://github.com/derailed/k9s/blob/master/plugins/debug-container.yaml
        debug = {
          shortCut = "Shift-D";
          description = "Add debug container";
          dangerous = true;
          scopes = [ "containers" ];
          command = "bash";
          background = false;
          args = [
            "-c"
            "kubectl debug -it --context $CONTEXT -n=$NAMESPACE $POD --target=$NAME --image=registry-k8s.pyn.ru/k8s/quay.io/tccr/netshoot:v0.13.0 --share-processes -- bash"
          ];
        };
        argocd = {
          shortCut = "s";
          description = "Sync ArgoCD Application";
          scopes = [ "application" ];
          command = "argocd";
          background = true;
          confirm = true;
          args = [
            "app"
            "sync $NAME --app-namespace $NAMESPACE"
          ];
        };
      };
    };
  };
}
