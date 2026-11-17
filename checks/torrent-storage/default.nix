{
  lib,
  pkgs,
  runCommand,
  python3,
  qbittorrent-nox,
  rtorrent,
  stdenv,
  writeText,
  ...
}:
let
  hostConfig = import ../../systems/x86_64-linux/zanoza { inherit lib pkgs; };
  host = hostConfig.custom.containers;
  # Test the container modules' public settings, not their source text. Unrelated
  # host services are inert; the container config functions are evaluated below.
  evaluated = lib.evalModules {
    specialArgs = {
      inherit lib pkgs;
      namespace = "custom";
      inputs = { };
    };
    modules = [
      ../../modules/nixos/containers/qbittorrent
      ../../modules/nixos/containers/flood
      ../../modules/nixos/containers/opencloud
      ../../modules/nixos/containers/jellyfin
      {
        options =
          lib.genAttrs [ "networking" "systemd" "containers" "sops" ] (
            _:
            lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            }
          )
          // {
            custom.containers.traefik.routes = lib.mkOption { type = lib.types.attrs; };
            custom.containers.adguard.enable = lib.mkOption { default = false; };
            custom.security.sops.secrets = lib.mkOption { type = lib.types.attrs; };
          };
        config.custom.containers = {
          inherit (host)
            qbittorrent
            flood
            opencloud
            jellyfin
            ;
        };
        config.sops.secrets.opencloud-env.path = "/run/secrets/opencloud-env";
        config.sops.secrets."jellyfin/oidc_client_secret".path = "/run/secrets/jellyfin/oidc_client_secret";
        config.sops.secrets."jellyfin/api_key".path = "/run/secrets/jellyfin/api_key";
      }
    ];
  };
  qbit =
    (evaluated.config.containers.qbittorrent.config {
      config.services.qbittorrent.profileDir = "/var/lib/qBittorrent";
    }).services.qbittorrent.serverConfig.BitTorrent.Session;
  flood = evaluated.config.containers.flood.config { };
  mounts = evaluated.config.containers.opencloud.bindMounts;
  personalSpace = "/var/lib/opencloud/posix-storage/users/05307840-a7bf-4448-8dc4-6a9ca7375cb9";
in
assert qbit.DefaultSavePath == "/data/torrents/completed";
assert qbit.TempPathEnabled;
assert qbit.TempPath == "/data/torrents/incomplete";
assert mounts."${personalSpace}/Downloads".hostPath == "/tank/torrents/finished";
assert mounts."${personalSpace}/LegacyDownloads".hostPath == "/tank/torrents/completed";
assert evaluated.config.custom.containers.flood.completedDirectory == "finished";
assert mounts."${personalSpace}/QBittorrent".hostPath == "/tank/media/torrents/completed";
assert evaluated.config.containers.jellyfin.bindMounts."/var/lib/jellyfin/media".isReadOnly;
assert
  evaluated.config.custom.containers.jellyfin.libraries."TV Shows" == {
    collectionType = "tvshows";
    paths = [ "/var/lib/jellyfin/media/tv" ];
  };
assert builtins.hasAttr "jellyfin-library-setup" evaluated.config.systemd.services;
assert builtins.elem "container@qbittorrent.service"
  hostConfig.systemd.services."container@opencloud".after;
assert builtins.elem "container@flood.service"
  hostConfig.systemd.services."container@opencloud".after;
assert hostConfig.containers.opencloud.config.users.groups.media.gid == 2000;
assert builtins.elem "media"
  hostConfig.containers.opencloud.config.users.users.opencloud.extraGroups;
runCommand "torrent-storage-test" { nativeBuildInputs = [ python3 ]; } (
  lib.optionalString stdenv.isLinux ''
    python3 ${./test.py} ${lib.getExe qbittorrent-nox} ${lib.getExe rtorrent} \
      ${writeText "qbit-session.json" (builtins.toJSON qbit)} \
      ${writeText "completion.rc" flood.services.rtorrent.configText}
  ''
  + ''touch "$out"''
)
