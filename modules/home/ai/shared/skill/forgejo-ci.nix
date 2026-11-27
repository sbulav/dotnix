# Forgejo Actions through fj-ex; issues, pull requests and comments go through
# fj. The token comes from the wrapper in modules/home/tools/fj-ex, which is
# why the skill never mentions one.
{
  name = "forgejo-ci";
  version = "1.0.0";
  description = "Forgejo Actions CI through `fj-ex`: read run and job logs, explain a failed run, rerun or cancel it, wait for the result. Use when given a Forgejo `/actions/runs/` URL, when a push or pull request check fails on Forgejo, or when asked to restart CI.";
  allowed-tools = [
    "Bash"
    "Read"
    "Grep"
  ];
  content = ''
    Forgejo Actions go through `fj-ex`. Issues, pull requests and comments go
    through `fj`.

    ## Target

    Every command names the repo as `--repo <host>/<owner>/<repo>`, host
    included, so it addresses the Forgejo instance whatever the local git
    remotes are. A run URL maps field by field:

    ```
    https://<host>/<owner>/<repo>/actions/runs/<run>/jobs/<job>/attempt/<attempt>
    --repo <host>/<owner>/<repo> --run-index <run> --job-index <job> --attempt <attempt>
    ```

    `--run-index` is the run number shown in the web URL. `--job-index` counts
    from 0. `--attempt` defaults to the latest attempt. With no URL, take host
    and repo from `git remote -v` and pick the run from
    `fj-ex actions runs --repo <target> --limit 10` (`--latest` works in place
    of `--run-index`; `--workflow <file>` narrows by workflow). `--status
    failure` filters only the page already fetched, so pair it with
    `--limit 50`; an empty result means no failed run among those 50.

    `fj-ex` authenticates itself. An auth error (`No API token`, 401, 403) is a
    finding: quote it to the user and stop there; the credential is theirs to
    fix.

    ## Explain a failed run

    1. List the jobs: `fj-ex actions jobs --repo <target> --run-index <run>`.
       Done when every failed job's index is known.
    2. Save each failed job's log to a file in your temp directory, then search
       the file; a full log is too large to read whole:
       `fj-ex actions logs job --repo <target> --run-index <run> --job-index <job> --out-file <file>`
       (`fj-ex actions logs run ... --out-dir <dir>` saves every job at once).
       Search case-insensitively for `❌|error|failed|fatal|exit code|panic`
       and read the lines around the first hit; the runner marks a failed step
       `❌  Failure - <step>`, but a failure inside a container build shows
       only as its own error lines. Done when you can quote the first failing
       command and its error lines for every failed job.
    3. Report per failed job: the job, the failing step, the quoted error
       lines, and whether the cause is the change under test or the
       environment (runner, network, registry, cache). Compare with an earlier
       `--attempt` when the run was already retried.

    ## Rerun or cancel

    A rerun or cancel changes shared CI, so the user approves each one.

    1. Show the request with `--dry-run`:
       `fj-ex actions rerun --repo <target> --run-index <run> --failed-only --dry-run`
       (`--job-index <job>` reruns one job; without either flag the whole run
       restarts). `fj-ex actions cancel` takes the same target flags.
    2. After the user approves, run the same command without `--dry-run`. A
       rerun adds a new attempt under the same run index.
    3. Wait for the outcome:
       `fj-ex actions wait --repo <target> --run-index <run> --timeout 30m`,
       then list the jobs again. Done when you have reported each job's final
       status, and the failure explanation above for any that failed again.

    Other flags: `fj-ex actions <command> --help`.
  '';
}
