{
  lib,
  pkgs,
  runCommand,
  writeShellScriptBin,
  coreutils,
  jq,
  ...
}:
let
  inherit (lib.custom.notifications) mkDeliverScript;

  # mkDeliverScript pins curl and msmtp through writeShellApplication's
  # runtimeInputs, so PATH tricks from outside cannot replace them. Hand it a
  # package set whose curl and msmtp are stubs instead. Both record what they
  # were given under $STUB_DIR and behave as $STUB_CURL / $STUB_MSMTP say;
  # nothing touches the network.
  stubCurl = writeShellScriptBin "curl" ''
    set -eu
    bin=${coreutils}/bin
    $bin/touch "$STUB_DIR/curl.called"
    $bin/printf '%s\n' "$@" >"$STUB_DIR/curl.argv"
    response=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -K) $bin/cat "$2" >"$STUB_DIR/curl.cfg"; shift 2 ;;
        --data-binary) $bin/cat "''${2#@}" >"$STUB_DIR/curl.payload"; shift 2 ;;
        -o) response=$2; shift 2 ;;
        *) shift ;;
      esac
    done
    case "''${STUB_CURL:-ok}" in
      ok) $bin/printf '{"ok":true}' >"$response" ;;
      not-ok) $bin/printf '{"ok":false}' >"$response" ;;
      http-fail)
        $bin/printf '{"ok":false,"error_code":502}' >"$response"
        echo "curl: (22) The requested URL returned error: 502" >&2
        exit 22
        ;;
      *) echo "stub curl: unknown STUB_CURL=$STUB_CURL" >&2; exit 99 ;;
    esac
  '';

  stubMsmtp = writeShellScriptBin "msmtp" ''
    set -eu
    bin=${coreutils}/bin
    $bin/printf '%s\n' "$@" >"$STUB_DIR/msmtp.argv"
    $bin/cat >"$STUB_DIR/msmtp.stdin"
    case "''${STUB_MSMTP:-ok}" in
      ok) exit 0 ;;
      fail) echo "msmtp: cannot connect to smtp.gmail.com" >&2; exit 75 ;;
      *) echo "stub msmtp: unknown STUB_MSMTP=$STUB_MSMTP" >&2; exit 99 ;;
    esac
  '';

  stubPkgs = pkgs // {
    curl = stubCurl;
    msmtp = stubMsmtp;
  };

  deliver =
    args: "${mkDeliverScript stubPkgs ({ hostName = "testhost"; } // args)}/bin/notify-deliver";

  telegram.chatId = "-100123";
  email.recipient = "ops@example.com";

  full = deliver { inherit telegram email; };
  proxied = deliver {
    telegram = telegram // {
      proxyUrl = "socks5h://127.0.0.1:1080";
    };
    inherit email;
  };
  telegramOnly = deliver {
    inherit telegram;
    email.enable = false;
  };
  emailOnly = deliver {
    telegram.enable = false;
    inherit email;
  };
in
runCommand "notify-deliver-test" { nativeBuildInputs = [ jq ]; } ''
  set -euo pipefail
  export STUB_DIR=$TMPDIR/stub
  stdout_log=$TMPDIR/stdout
  stderr_log=$TMPDIR/stderr
  token=SEKRET-TOKEN-123
  unset TELEGRAM_TOKEN FORCE_EMAIL_ONLY STUB_CURL STUB_MSMTP

  msg=$TMPDIR/message
  printf 'backup of /srv failed\nsecond line with "quotes" and $dollars\n' >"$msg"
  long=$TMPDIR/long-message
  head -c 5000 /dev/zero | tr '\0' x >"$long"

  current=
  fail() {
    echo "FAIL [$current]: $*" >&2
    echo "--- stdout" >&2; cat "$stdout_log" >&2
    echo "--- stderr" >&2; cat "$stderr_log" >&2
    exit 1
  }

  # run_case <name> <expected-rc> <command...>
  # Environment for the case goes in front of the command via `env`.
  run_case() {
    current=$1
    local expected=$2 rc=0
    shift 2
    rm -rf "$STUB_DIR"
    mkdir -p "$STUB_DIR"
    "$@" >"$stdout_log" 2>"$stderr_log" || rc=$?
    [ "$rc" = "$expected" ] || fail "exit $rc, expected $expected"
  }

  contains() { grep -qF -- "$2" "$1" || fail "$1 lacks: $2"; }
  lacks() { if grep -qF -- "$2" "$1"; then fail "$1 unexpectedly has: $2"; fi; }
  has_line() { grep -qxF -- "$2" "$1" || fail "$1 lacks the line: $2"; }
  curl_called() { [ -e "$STUB_DIR/curl.called" ] || fail "curl was not called"; }
  curl_skipped() { [ ! -e "$STUB_DIR/curl.called" ] || fail "curl was called"; }
  msmtp_called() { [ -e "$STUB_DIR/msmtp.stdin" ] || fail "msmtp was not called"; }
  msmtp_skipped() { [ ! -e "$STUB_DIR/msmtp.stdin" ] || fail "msmtp was called"; }
  payload_is() {
    local got
    got=$(jq -c "$1" "$STUB_DIR/curl.payload")
    [ "$got" = "$2" ] || fail "payload $1 = $got, expected $2"
  }
  # The email went out with the expected envelope, headers and body.
  email_sent() {
    msmtp_called
    has_line "$STUB_DIR/msmtp.argv" "-a"
    has_line "$STUB_DIR/msmtp.argv" "gmail"
    has_line "$STUB_DIR/msmtp.argv" "ops@example.com"
    has_line "$STUB_DIR/msmtp.stdin" "From: testhost notifications <zppfan@gmail.com>"
    has_line "$STUB_DIR/msmtp.stdin" "To: ops@example.com"
    has_line "$STUB_DIR/msmtp.stdin" "Subject: $1"
    sed '1,/^$/d' "$STUB_DIR/msmtp.stdin" | cmp -s - "$msg" || fail "email body differs from the message"
    contains "$stdout_log" "delivered via email"
  }

  # 1. Telegram accepts the message: no email, payload carries the chat id,
  #    the untruncated text and the priority as disable_notification.
  for prio in default high low; do
    args=("$msg" "Backup failed")
    [ "$prio" = default ] || args+=("$prio")
    run_case "telegram ok ($prio)" 0 env TELEGRAM_TOKEN=$token ${full} "''${args[@]}"
    contains "$stdout_log" "delivered via Telegram"
    curl_called
    msmtp_skipped
    payload_is .chat_id '"-100123"'
    [ "$(jq -r .text "$STUB_DIR/curl.payload")" = "$(cat "$msg")" ] || fail "payload text differs from the message"
    if [ "$prio" = low ]; then expected=true; else expected=false; fi
    payload_is .disable_notification "$expected"
  done

  # 2. Telegram HTTP error: email fallback succeeds.
  run_case "telegram http failure" 0 env TELEGRAM_TOKEN=$token STUB_CURL=http-fail ${full} "$msg" "Backup failed"
  curl_called
  contains "$stderr_log" "Telegram delivery failed; using email fallback"
  email_sent "Backup failed"

  # 3. HTTP 200 with {"ok":false} is still a failure.
  run_case "telegram not ok" 0 env TELEGRAM_TOKEN=$token STUB_CURL=not-ok ${full} "$msg" "Backup failed"
  curl_called
  contains "$stderr_log" "Telegram delivery failed; using email fallback"
  email_sent "Backup failed"

  # 4. No token: Telegram is never tried, email carries the message.
  run_case "token unset" 0 ${full} "$msg" "Backup failed"
  curl_skipped
  contains "$stderr_log" "TELEGRAM_TOKEN is unavailable; using email fallback"
  email_sent "Backup failed"

  # 5. FORCE_EMAIL_ONLY skips Telegram even with a token.
  run_case "force email only" 0 env TELEGRAM_TOKEN=$token FORCE_EMAIL_ONLY=true ${full} "$msg" "Backup failed"
  curl_skipped
  email_sent "Backup failed"

  # 6. Both channels fail: exit 1 and the whole message lands on stderr.
  run_case "both fail" 1 env TELEGRAM_TOKEN=$token STUB_CURL=http-fail STUB_MSMTP=fail ${full} "$msg" "Backup failed"
  curl_called
  msmtp_called
  contains "$stderr_log" "email delivery failed"
  contains "$stderr_log" "undelivered message follows (subject: Backup failed)"
  sed '1,/undelivered message follows/d' "$stderr_log" | cmp -s - "$msg" || fail "stderr does not end with the full message"

  # 7. The token stays out of argv, inside the -K config; the proxy line is
  #    there only when a proxy is configured.
  run_case "no proxy" 0 env TELEGRAM_TOKEN=$token ${full} "$msg" "Backup failed"
  lacks "$STUB_DIR/curl.argv" "$token"
  has_line "$STUB_DIR/curl.cfg" "url = \"https://api.telegram.org/bot$token/sendMessage\""
  lacks "$STUB_DIR/curl.cfg" "proxy"
  run_case "proxy" 0 env TELEGRAM_TOKEN=$token ${proxied} "$msg" "Backup failed"
  lacks "$STUB_DIR/curl.argv" "$token"
  has_line "$STUB_DIR/curl.cfg" "url = \"https://api.telegram.org/bot$token/sendMessage\""
  has_line "$STUB_DIR/curl.cfg" 'proxy = "socks5h://127.0.0.1:1080"'

  # 8. Over-long messages are cut to the Telegram limit with a marker.
  run_case "truncation" 0 env TELEGRAM_TOKEN=$token ${full} "$long" "Long"
  suffix=$'\n… [truncated]'
  # jq counts characters, the shell (C locale) would count bytes of the "…".
  jq -e --arg s "$suffix" '.text | length <= 3900 + ($s | length) and . == ("x" * 3900) + $s' \
    "$STUB_DIR/curl.payload" >/dev/null || fail "text is not the first 3900 characters plus the marker"

  # 9. A newline in the subject cannot start a new mail header.
  run_case "subject newline" 0 ${full} "$msg" $'Backup failed\nBcc: evil@example.com'
  email_sent "Backup failed Bcc: evil@example.com"
  [ "$(grep -c '^Bcc:' "$STUB_DIR/msmtp.stdin" || true)" = 0 ] || fail "subject newline produced a header"

  # 10. Usage errors exit 2 without delivering anything.
  run_case "one argument" 2 env TELEGRAM_TOKEN=$token ${full} "$msg"
  contains "$stderr_log" "usage: notify-deliver"
  curl_skipped
  msmtp_skipped
  run_case "bad priority" 2 env TELEGRAM_TOKEN=$token ${full} "$msg" "Backup failed" urgent
  contains "$stderr_log" "priority must be high or low"
  curl_skipped
  msmtp_skipped

  # 11a. Telegram-only: delivers, and on failure there is nowhere to fall back.
  run_case "telegram only ok" 0 env TELEGRAM_TOKEN=$token ${telegramOnly} "$msg" "Backup failed"
  contains "$stdout_log" "delivered via Telegram"
  msmtp_skipped
  run_case "telegram only failure" 1 env TELEGRAM_TOKEN=$token STUB_CURL=http-fail ${telegramOnly} "$msg" "Backup failed"
  lacks "$stderr_log" "email fallback"
  contains "$stderr_log" "no notification channel delivered the message"
  msmtp_skipped
  run_case "telegram only forced email" 1 env TELEGRAM_TOKEN=$token FORCE_EMAIL_ONLY=true ${telegramOnly} "$msg" "Backup failed"
  contains "$stderr_log" "Telegram was skipped (FORCE_EMAIL_ONLY)"
  curl_skipped

  # 11b. Email-only: never calls curl, even with a token around.
  run_case "email only ok" 0 env TELEGRAM_TOKEN=$token ${emailOnly} "$msg" "Backup failed"
  curl_skipped
  email_sent "Backup failed"
  run_case "email only failure" 1 env TELEGRAM_TOKEN=$token STUB_MSMTP=fail ${emailOnly} "$msg" "Backup failed"
  curl_skipped
  contains "$stderr_log" "email delivery failed"

  echo "notify-deliver: all cases passed"
  touch "$out"
''
