_: _final: prev: {
  # Waybar 0.15 hyprland/workspace click handler sends legacy IPC dispatchers
  # (`dispatch workspace <id>`, `dispatch focusworkspaceoncurrentmonitor <id>`,
  # `dispatch workspace name:<n>`, `dispatch togglespecialworkspace ...`).
  # Hyprland 0.55+ Lua configs only accept `hl.dsp.<name>({...})` expressions,
  # so those clicks silently no-op. Patch the C++ click dispatchers in
  # workspace.cpp to use the working Lua syntax. Tracked upstream as
  # Alexays/Waybar #5008.
  waybar = prev.waybar.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./hyprland-lua-dispatch.patch ];
  });
}
