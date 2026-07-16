# Herdr Remote enterprise rollout

The rollout is intentionally split into two phases. Phase 1 deploys only the
control plane. Do not import or enable the Home Manager connector module until
each Linux host has an enrolled client certificate, private key, connector
server CA, and stable host UUID. macOS native and connector support is out of
scope; do not add the connector module to `mba13` or to global Home Manager
modules.

## Phase 1: deploy the zanoza control plane

1. Build and deploy `zanoza`. Confirm that `herdr-controlplane.service` is
   active and that TCP 8443 is listening. Do not expose port 8080 beyond
   loopback.
2. On `zanoza`, verify the service directly without displaying any secret:

   ```sh
   curl --fail http://127.0.0.1:8080/healthz
   curl --fail http://127.0.0.1:8080/readyz
   ```

3. Open `https://herdr.sbulav.ru` in a private browser session. Complete
   Authelia two-factor authentication, confirm the PWA loads, and verify
   `https://herdr.sbulav.ru/healthz` and `/readyz` through that authenticated
   route. A request without the Authelia cookie must not reach the service.
4. Send requests containing fake `X-OIDC-Issuer`, `X-OIDC-Audience`,
   `X-OIDC-Subject`, and `X-OIDC-Assurance` headers and verify they cannot
   change the authenticated identity. Traefik must replace all four values
   after `auth-chain`.
5. Back up `/var/lib/herdr-controlplane/control.db` with a SQLite-consistent
   method and keep the connector issuing CA material in the encrypted backup.

## Phase 2: enroll and enable Linux connectors

Perform these steps separately for `mz` and `zanoza`. Never reuse an enrollment
token, private key, certificate, or host UUID between hosts.

1. Export the authenticated browser cookies to a protected Netscape-format
   cookie jar outside the repository, then create exactly one enrollment for
   the current host. The state-changing request needs the same cookie, the
   `csrf_token` returned by the session endpoint, and the exact origin header:

   ```sh
   umask 077
   origin=https://herdr.sbulav.ru
   host=mz # repeat later with host=zanoza
   cookie_jar=/path/outside/repository/herdr-cookies.txt

   curl --fail --silent --show-error \
     --cookie "$cookie_jar" \
     --header "Origin: $origin" \
     --output session.json \
     "$origin/api/v1/session"
   csrf_token=$(jq --exit-status --raw-output .csrf_token session.json)

   curl --fail --silent --show-error \
     --cookie "$cookie_jar" \
     --header "Origin: $origin" \
     --header "X-CSRF-Token: $csrf_token" \
     --header 'Content-Type: application/json' \
     --data "$(jq --compact-output --null-input --arg name "$host" '{display_name:$name}')" \
     --output enrollment.json \
     "$origin/api/v1/enrollments"
   jq --exit-status --raw-output .token enrollment.json > enrollment-token
   jq --exit-status --raw-output .host_id enrollment.json > host-id
   ```

   `umask 077` keeps the cookie-derived data and one-time token mode `0600`.
   The token expires after ten minutes. Do not print it or put it in shell
   history.

2. In a mode `0700` staging directory on the connector host, generate a P-256
   private key and CSR. Submit only the CSR and one-time token to
   `POST https://herdr.sbulav.ru/v1/enroll` using the authenticated session
   cookie. This route remains behind Authelia, so the connector's unattended
   enrollment mode must not be used against it without cookie support.
   Generate and submit the CSR without printing the token or private key:

   ```sh
   install -d -m 0700 connector-enrollment
   mv enrollment-token host-id connector-enrollment/
   cd connector-enrollment
   origin=https://herdr.sbulav.ru
   cookie_jar=/path/outside/repository/herdr-cookies.txt

   openssl genpkey \
     -algorithm EC \
     -pkeyopt ec_paramgen_curve:P-256 \
     -out connector-client.key
   openssl req \
     -new \
     -key connector-client.key \
     -subj / \
     -out connector-client.csr

   jq --compact-output --null-input \
     --rawfile token enrollment-token \
     --rawfile csr connector-client.csr \
     '{token:($token | rtrimstr("\n")),csr_pem:$csr}' \
     > enrollment-request.json
   curl --fail --silent --show-error \
     --cookie "$cookie_jar" \
     --header "Origin: $origin" \
     --header 'Content-Type: application/json' \
     --data-binary @enrollment-request.json \
     --output enrollment-response.json \
     "$origin/v1/enroll"

   jq --exit-status --raw-output .host_id enrollment-response.json > host-id
   jq --exit-status --raw-output .certificate_pem enrollment-response.json \
     > connector-client.crt
   rm connector-client.csr enrollment-request.json enrollment-token
   ```

   Record `host-id` as that host's stable UUID. The response's
   `ca_certificate_pem` is the connector **client issuing CA**, not necessarily
   the CA that verifies the port-8443 server certificate. Do not copy the
   private key off the host in plaintext. Delete `session.json`,
   `enrollment.json`, `enrollment-response.json`, and the exported cookie jar
   when both hosts are enrolled.

3. Add the client certificate, private key, and CA that verifies the direct
   connector endpoint certificate for `herdr.sbulav.ru:8443` to that host's
   encrypted SOPS file. Use distinct keys such as `connector_client_cert`,
   `connector_client_key`, and `connector_server_ca`, owned by `sab` and mode
   `0400` when materialized. Do not use the browser HTTPS trust chain unless it
   is also the actual issuer of the port-8443 certificate. Confirm the server
   CA and certificate fingerprint out of band before enabling the service.

4. Only after step 3, import
   `inputs.herdr-remote.homeManagerModules.connector` directly in the Linux
   homes `homes/x86_64-linux/sab@mz/default.nix` and
   `homes/x86_64-linux/sab@zanoza/default.nix`. Do not add it to global home
   modules or any Darwin home. Declare the three Home Manager SOPS secrets and
   enable `services.herdr-connector` with:

   - `controlPlaneUrl = "wss://herdr.sbulav.ru:8443/v1/connectors/ws"`;
   - `rotateUrl = "https://herdr.sbulav.ru:8443/v1/connectors/rotate"`;
   - the host-specific stable UUID from enrollment;
   - display name `mz` or `zanoza`;
   - `initialCertFile`, `keyFile`, and `serverCaFile` set to the corresponding
     SOPS runtime paths;
   - instance `default` using `/home/sab/.config/herdr/herdr.sock`.

5. Build each Home Manager configuration before activation. Start one
   connector at a time and inspect `systemctl --user status herdr-connector`
   plus sanitized control-plane logs. Confirm the PWA sees only the intended
   host UUID and instance.
6. Verify read-only behavior first: inspect status, bounded output, and prompt
   snapshots without sending input. Then confirm the checked Herdr fork
   advertises `checked_input.v1` with a nonzero input revision. Perform one
   harmless checked write and verify a stale revision is rejected. Never
   bypass the capability or revision checks.
7. Exercise credential lifecycle before relying on the deployment:
   - rotate through the configured mTLS `/v1/connectors/rotate` endpoint and
     confirm the mutable certificate changes while the private key does not;
   - revoke with authenticated, CSRF-protected
     `DELETE /api/v1/hosts/HOST_UUID/credential` and confirm the active lease
     closes;
   - create a new one-time enrollment, generate a new key and CSR, replace the
     SOPS certificate and key, retain or update the returned stable UUID as
     required, and restart the connector.

## Rollback

1. Disable `services.herdr-connector` and remove its per-home module import on
   `mz` and `zanoza`; rebuild the homes. Revoke any issued connector
   credentials. The local Herdr installation remains available through
   `custom.cli-apps.herdr`.
2. If the control plane must be rolled back, stop `herdr-controlplane`, remove
   the `herdr.sbulav.ru` route and TCP 8443 firewall opening, and deploy the
   previous `zanoza` generation. Restore the SQLite database and CA material
   only from the matching encrypted backup. Do not restore the obsolete relay,
   SSH polling, native mobile, or power-control services.
