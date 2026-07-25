# Module lifecycle

Snowfall automatically discovers modules below `modules/nixos`, `modules/darwin`,
`modules/home`, and `modules/shared`. Files in those directories are active module
surface: they must evaluate with the pinned inputs and be reasonable to enable.
An option defaulting to `false` is not, by itself, a reason to remove a module.

Historical or incomplete implementations belong in a sibling directory whose name
starts with an underscore, such as `modules/_nixos-disabled` or
`modules/_darwin-disabled`. Snowfall does not discover these directories. A
quarantined module must not be referenced by active suites or host configurations.
Keep it only when its implementation still provides useful migration or design
context; otherwise delete it and rely on Git history.

Move a quarantined module back into the active tree only after:

1. removing placeholder credentials and obsolete workarounds;
2. updating it for the pinned inputs;
3. enabling it in an intended host or home profile; and
4. evaluating and building that profile.

## July 2026 audit

| Surface | Decision | Evidence |
| --- | --- | --- |
| NixOS LF | Quarantine | No host enables it, every active home enables Yazi, and the module mixes obsolete Home Manager configuration into a NixOS module. |
| Authentik | Quarantine | No host enables it and its implementation is entirely commented out. Authelia remains active on `zanoza`. |
| Seafile | Quarantine | No host enables it; the module is marked non-working and still contains placeholder credentials. OpenCloud remains active on `zanoza`. |
| Nextcloud | Retain, suspended | It is explicitly disabled on `zanoza`, but encrypted credentials and backups for its retained data still exist. Removal needs a separate data-retention decision. |
| Historical Darwin | Retain in quarantine | The old `mbp16` profiles and modules already live under `.disabled` and `modules/_darwin-disabled`; the active Darwin host is `mba13`. |

The active Nix language server is `nixd`. Development suites install it through
`custom.tools.lsp`; server profiles that need it list it explicitly. `nil` is not
installed globally.
