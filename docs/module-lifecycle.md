# Module lifecycle

Snowfall automatically discovers modules below `modules/nixos`, `modules/darwin`,
`modules/home`, and `modules/shared`. Files in those directories are active module
surface: they must evaluate with the pinned inputs and be reasonable to enable.
An option defaulting to `false` is not, by itself, a reason to remove a module.

A module that no host or home enables and that is not expected to come back is
deleted, together with every integration that only served it (routes, OIDC
clients, dashboard entries, host entries). Git history is the archive: there is
no quarantine tree. To revive one, restore it from history, then:

1. remove placeholder credentials and obsolete workarounds;
2. update it for the pinned inputs;
3. enable it in an intended host or home profile; and
4. evaluate and build that profile.

Deleting a module never deletes its data. Datasets and state directories on the
host (for example `/tank/nextcloud`) are removed by hand, as a separate decision.

## History

| Date | Surface | Decision |
| --- | --- | --- |
| 2026-07 | NixOS LF, Authentik, Seafile | Quarantined: unused, commented out, or non-working with placeholder credentials. |
| 2026-07 | Historical Darwin (`mbp16`) | Quarantined; the active Darwin host is `mba13`. |
| 2026-09 | All quarantine trees (`modules/_darwin-disabled`, `modules/_nixos-disabled`, `.disabled`) | Deleted. |
| 2026-09 | Nextcloud | Deleted with its Authelia client, Traefik middleware and homepage entry; OpenCloud replaced it. `/tank/nextcloud` on `zanoza` is untouched. |

The active Nix language server is `nixd`. Development suites install it through
`custom.tools.lsp`; server profiles that need it list it explicitly. `nil` is not
installed globally.
