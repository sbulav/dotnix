{lib, ...}: final: prev: {
  ocis-bin-patched = prev.ocis_5-bin.overrideAttrs (oldAttrs: {
    meta = with lib; {
      description = "ownCloud Infinite Scale Stack";
      # homepage = "https://owncloud.dev/ocis/";
      # changelog = "https://github.com/owncloud/ocis/releases/tag/v${finalAttrs.version}";
      # oCIS is licensed under non-free EULA which can be found here :
      # https://github.com/owncloud/ocis/releases/download/v5.0.1/End-User-License-Agreement-for-ownCloud-Infinite-Scale.pdf
      # Patch to run via flakes
      license = lib.licenses.mit;
      # maintainers = with maintainers; [
      #   ramblurr
      #   bhankas
      #   danth
      #   ramblurr
      # ];

      # platforms =
      #   (lib.intersectLists platforms.linux (
      #     lib.platforms.arm ++ lib.platforms.aarch64 ++ lib.platforms.x86
      #   ))
      #   ++ (lib.intersectLists platforms.darwin (lib.platforms.aarch64 ++ lib.platforms.x86_64));

      # sourceProvenance = [sourceTypes.binaryNativeCode];
      mainProgram = "ocis";
    };
  });
}
