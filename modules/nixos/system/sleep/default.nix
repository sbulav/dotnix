{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.system.sleep;

  sleepHooks = pkgs.writeShellScript "system-sleep-hooks" ''
    #!${pkgs.bash}/bin/bash
    set -eu

    if [[ "${boolToString cfg.gvfsUnmountFix.enable}" == "true" && "$1" == "pre" ]]; then
      while IFS=' ' read -r _ mountpoint fstype _; do
        if [[ "$fstype" == "fuse.gvfsd-fuse" ]]; then
          mountpoint=$(printf '%b' "$mountpoint")
          ${pkgs.fuse3}/bin/fusermount3 -uz "$mountpoint" 2>/dev/null || true
        fi
      done < /proc/mounts
    fi

    if [[ "$1" == "post" ]] && [[ "${
      boolToString (cfg.gvfsUnmountFix.enable || cfg.audioResumeFix.enable)
    }" == "true" ]]; then
      (
        sleep ${toString cfg.resumeDelaySeconds}

        for uid_dir in /run/user/*; do
          if [[ ! -d "$uid_dir" || ! -S "$uid_dir/bus" ]]; then
            continue
          fi

          uid=$(basename "$uid_dir")
          gid=$(${pkgs.coreutils}/bin/stat -c %g "$uid_dir")

          ${pkgs.util-linux}/bin/setpriv \
            --reuid "$uid" \
            --regid "$gid" \
            --clear-groups \
            ${pkgs.coreutils}/bin/env \
            DBUS_SESSION_BUS_ADDRESS="unix:path=$uid_dir/bus" \
            XDG_RUNTIME_DIR="$uid_dir" \
            ${pkgs.systemd}/bin/systemctl --user \
            restart \
            ${optionalString cfg.gvfsUnmountFix.enable "gvfs-daemon.service"} \
            ${optionalString cfg.audioResumeFix.enable "wireplumber.service pipewire.service pipewire-pulse.service"} \
            2>/dev/null || true
        done
      ) &
    fi
  '';
in
{
  options.system.sleep = with types; {
    enable = mkBoolOpt false "Whether to enable system sleep and resume fixes.";

    resumeDelaySeconds = mkOpt int 5 "Delay before running post-resume recovery actions.";

    gvfsUnmountFix.enable = mkBoolOpt false "Whether to unmount gvfs FUSE mounts before suspend and restart GVFS after resume.";

    audioResumeFix.enable = mkBoolOpt false "Whether to restart user audio services after resume.";
  };

  config = mkIf cfg.enable {
    environment.etc."systemd/system-sleep/custom-sleep-hooks" = {
      source = sleepHooks;
      mode = "0755";
    };
  };
}
