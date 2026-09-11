{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
# One logrotate block per application instead of a single shared rule.
#
# logrotate refuses to rotate a file whose parent directory is world-writable
# or writable by a group that is not "root", and aborts the whole run:
#
#   error: skipping "/tank/sing-box/logs/sing-box.log" because parent directory
#   has insecure permissions (It's world writable or writable by group which is
#   not "root") Set "su" directive in config file to tell logrotate which
#   user/group should be used for rotation.
#
# `su` is therefore mandatory. What silences the check is the *presence* of the
# directive, not what it switches to: with `su root root` logrotate keeps
# rotating as root, which is the status quo for the rules that already work, and
# the directive exists only to satisfy the permission check. Hence `root`/`root`
# defaults.
#
# Set a real `user`/`group` only when the rotating host has a **named** account
# that owns the directory. logrotate resolves `su` through getpwnam/getgrnam and
# then getpwuid/getgrgid, so a bare numeric id works only if some account or
# group actually holds that number; otherwise logrotate errors
# "unknown user '<id>'" / "unknown group '<id>'" and skips the whole block.
# Verified on zanoza: the /tank container uids (999, 998, 997) have no host
# entries, so numeric ids there silently dropped three of the four rules.
# See README.md.
let
  inherit (lib)
    types
    mkIf
    mkRemovedOptionModule
    mapAttrs
    mapAttrsToList
    optionalAttrs
    ;
  inherit (lib.${namespace}) mkBoolOpt mkOpt;

  cfg = config.${namespace}.services.logrotate;
in
{
  imports = [
    (mkRemovedOptionModule [
      namespace
      "services"
      "logrotate"
      "logFiles"
    ] "Use custom.services.logrotate.rules.<name> with per-application `user`/`group` instead.")
  ];

  options.${namespace}.services.logrotate = with types; {
    enable = mkBoolOpt false "Whether or not to configure logrotate.";

    rules = mkOpt (attrsOf (submodule {
      options = {
        files = mkOpt (listOf str) [ ] "Log files or globs rotated by this rule.";

        user =
          mkOpt str "root"
            "User logrotate switches to for this rule (`su`). Must name an account that exists on the rotating host; a numeric uid works only if some account actually holds it, otherwise logrotate errors `unknown user '<id>'` and skips the block. The default keeps rotation as root, which is all the `su` directive is needed for.";

        group =
          mkOpt str "root"
            "Group logrotate switches to for this rule (`su`). Must name a group that exists on the rotating host; a numeric gid works only if some group actually holds it, otherwise logrotate errors `unknown group '<id>'` and skips the block. The default keeps rotation as root, which is all the `su` directive is needed for.";

        frequency = mkOpt (enum [
          "hourly"
          "daily"
          "weekly"
          "monthly"
          "yearly"
        ]) "daily" "How often this rule rotates.";

        rotate = mkOpt int 7 "How many rotated generations to keep.";

        copytruncate = mkBoolOpt true "Copy then truncate in place (keeps the inode Alloy tails). Set false plus `postrotate` for applications that reopen their log on a signal.";

        postrotate =
          mkOpt (nullOr lines) null
            "Shell run after rotation (e.g. a reopen signal). Only useful with `copytruncate = false`.";

        extraSettings = mkOpt (attrsOf (oneOf [
          bool
          int
          str
          (listOf str)
        ])) { } "Extra logrotate directives merged into the block (override the defaults).";
      };
    })) { } "Per-application rotation rules, one logrotate block each.";
  };

  config = mkIf cfg.enable {
    assertions =
      (mapAttrsToList (name: rule: {
        assertion = rule.files != [ ];
        message = "custom.services.logrotate.rules.${name}.files is empty: a rule with no files rotates nothing.";
      }) cfg.rules)
      ++ (mapAttrsToList (name: rule: {
        assertion = rule.postrotate != null -> !rule.copytruncate;
        message = ''
          custom.services.logrotate.rules.${name} sets `postrotate` together with `copytruncate = true`.
          With copytruncate logrotate truncates the original file itself, so the application never reopens
          it and the hook only fires a redundant signal. Set `copytruncate = false` when the application
          reopens its log on a signal (that is what makes the hook necessary), or drop `postrotate`.
        '';
      }) cfg.rules);

    services.logrotate.settings = mapAttrs (
      _name: rule:
      {
        inherit (rule)
          files
          frequency
          rotate
          copytruncate
          ;
        su = "${rule.user} ${rule.group}";
        dateext = true;
        dateformat = "-%Y-%m-%d";
        compress = true;
        compresscmd = "${pkgs.zstd}/bin/zstd";
        compressoptions = "-10";
        compressext = ".zst";
        uncompresscmd = "${pkgs.zstd}/bin/unzstd";
        missingok = true;
        notifempty = true;
      }
      // optionalAttrs (rule.postrotate != null) { inherit (rule) postrotate; }
      // rule.extraSettings
    ) cfg.rules;
  };
}
