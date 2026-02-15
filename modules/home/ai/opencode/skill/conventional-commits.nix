{
  name = "conventional-commits";
  version = "1.0.0";
  description = "Guide for Conventional Commits format for writing commit messages and PR descriptions. Use when creating commits, writing pull requests, reviewing commit message quality, or ensuring consistent commit history across projects.";
  allowed-tools = [
    "Read"
    "Write"
    "Edit"
    "Grep"
    "Glob"
    "Bash"
  ];
  content = ''
    # Conventional Commits: Guide to Commit Message Format

    ## Overview

    Conventional Commits is a specification for adding human and machine-readable meaning to commit messages. This guide helps create consistent, informative commit messages and PR descriptions.

    **Use this guide for:**
    - Writing commit messages from staged changes
    - Creating pull request descriptions
    - Reviewing commit message quality
    - Ensuring consistent commit history

    ## Commit Message Format

    ### Standard Format

    ```
    <type>(<scope>): <subject>

    <body>

    <footer>
    ```

    **Structure rules:**
    - **Subject line** (required): Type, optional scope, description
    - **Body** (optional): Detailed explanation, motivation, context
    - **Footer** (optional): Breaking changes, issue references, co-authors

    ### Subject Line Requirements

    **Format:** `type(scope): description`

    **Length:**
    - Maximum 72 characters for subject line
    - No period at the end
    - Use imperative mood ("add" not "added")

    **Example:**
    ```
    feat(auth): add OAuth2 login support
    ```

    ## Commit Types

    | Type | Description | Example |
    |------|-------------|---------|
    | `feat` | New feature | `feat(api): add user endpoints` |
    | `fix` | Bug fix | `fix(auth): resolve token expiry` |
    | `docs` | Documentation only | `docs(readme): update install steps` |
    | `style` | Code style (formatting, semicolons) | `style: format with prettier` |
    | `refactor` | Code restructuring | `refactor(db): extract connection pool` |
    | `perf` | Performance improvement | `perf(query): add index on users` |
    | `test` | Adding/updating tests | `test(auth): add login flow tests` |
    | `build` | Build system changes | `build: update webpack config` |
    | `ci` | CI/CD configuration | `ci: add GitHub Actions workflow` |
    | `chore` | Maintenance tasks | `chore: update dependencies` |
    | `revert` | Revert previous commit | `revert: rollback auth changes` |

    ## Determining Commit Type

    ### Ask These Questions

    1. **Does it add functionality?** → `feat`
    2. **Does it fix a bug?** → `fix`
    3. **Is it only documentation?** → `docs`
    4. **Does it improve performance?** → `perf`
    5. **Is it restructuring without behavior change?** → `refactor`
    6. **Is it test-related?** → `test`
    7. **Is it build/CI configuration?** → `build` or `ci`
    8. **Is it routine maintenance?** → `chore`

    ### Analyzing Changes

    **Look at files changed:**
    ```bash
    # See what changed
    git diff --name-only
    ```

    **Common patterns:**
    - `.md` files only → likely `docs`
    - `test/` directory → likely `test`
    - `package.json`, `Cargo.toml` → possibly `chore` or `build`
    - Config files → `ci` or `build`

    **Look at the diff:**
    ```bash
    # See actual changes
    git diff --cached
    ```

    **Indicators:**
    - New functions/exports → `feat`
    - Deletion of error-prone code → `fix`
    - Moving code between files → `refactor`
    - Optimization patterns → `perf`

    ## Scope Guidelines

    ### When to Use Scope

    **Use scope when:**
    - Multiple components exist in the project
    - Change affects specific module/package
    - It clarifies what changed

    **Examples:**
    ```
    feat(auth): add login endpoint
    fix(api): handle null responses
    docs(readme): update examples
    ```

    ### When to Omit Scope

    **Skip scope when:**
    - Change affects whole codebase
    - Single-component project
    - Would be redundant

    **Examples:**
    ```
    feat: add dark mode
    fix: resolve memory leak
    chore: update dependencies
    ```

    ### Common Scope Values

    Based on project type:

    **Web app:**
    - `api`, `ui`, `auth`, `db`, `cache`

    **Library:**
    - `core`, `utils`, `cli`, `types`

    **Monorepo:**
    - `package-name`, `service-name`

    **Infrastructure:**
    - `terraform`, `k8s`, `ci`, `monitoring`

    ## Writing the Subject

    ### Imperative Mood

    **Use command form:**
    - ✅ "add feature"
    - ✅ "fix bug"
    - ✅ "update docs"
    - ❌ "added feature"
    - ❌ "fixing bug"
    - ❌ "updates docs"

    **Quick test:**
    > If applied, this commit will _______

    Example: "If applied, this commit will **add user authentication**"

    ### Be Specific

    **Bad:**
    ```
    fix: bug
    feat: update
    ```

    **Good:**
    ```
    fix(auth): handle expired tokens gracefully
    feat(api): add pagination to user list
    ```

    ### Focus on "Why" Not "What"

    **Bad:**
    ```
    fix: change timeout from 30 to 60 seconds
    ```

    **Good:**
    ```
    fix(api): increase timeout for slow connections

    Some users on slow networks were experiencing timeouts.
    Increasing from 30s to 60s resolves the issue.
    ```

    ## Writing the Body

    ### When to Include Body

    **Always include body for:**
    - Breaking changes
    - Complex changes needing explanation
    - Changes requiring context
    - "Why" isn't obvious from subject

    **Can skip body for:**
    - Simple, obvious changes
    - Single-line fixes
    - Changes with self-explanatory subjects

    ### Body Format

    ```
    Short summary (what and why)

    - Bullet points for details
    - Explain motivation
    - Mention side effects
    - Reference related issues
    ```

    **Example:**
    ```
    feat(auth): implement JWT authentication

    Replace session-based auth with JWT tokens for better scalability
    and support for multiple clients (web, mobile, API).

    - Tokens expire after 24 hours
    - Refresh token mechanism for seamless UX
    - Backward compatible with existing sessions

    Fixes #123
    ```

    ### Body Guidelines

    1. **Separate from subject with blank line**
    2. **Wrap at 72 characters**
    3. **Explain motivation and contrast with previous behavior**
    4. **Reference issues and PRs**

    ## Breaking Changes

    ### Format

    ```
    feat(api)!: remove deprecated endpoints

    BREAKING CHANGE: The /v1/users endpoint has been removed.
    Use /v2/users instead which requires authentication.
    ```

    **Indicators:**
    - `!` after type/scope: `feat!:` or `feat(api)!:`
    - `BREAKING CHANGE:` in footer

    ### What Constitutes Breaking

    **API/Library:**
    - Removing public functions
    - Changing function signatures
    - Modifying return types
    - Removing/changing error codes

    **Infrastructure:**
    - Changing required variables
    - Modifying database schema
    - Updating required versions

    **Documentation:**
    - Major reorganization (if linked from external sources)

    ## Footer Format

    ### Common Footer Elements

    **Issue references:**
    ```
    Fixes #123
    Closes #456
    Relates to #789
    ```

    **Breaking changes:**
    ```
    BREAKING CHANGE: description of what broke
    ```

    **Co-authors:**
    ```
    Co-authored-by: Name <email@example.com>
    ```

    **Acknowledgments:**
    ```
    Refs #123
    See-also: #456
    ```

    ### Footer Formatting

    - Each footer on its own line
    - Separator from body with blank line
    - Format: `Token: value` or `Token #value`

    ## Alternative Conventions

    ### Path-Based (Nixpkgs Style)

    Common in monorepos:

    ```
    path/to/module: description

    nixos/postgresql: add backup service
    home/programs/git: add rebase.autoSquash option
    ```

    **When to use:**
    - Monorepo with clear directory structure
    - Each directory owned by different team
    - Need to filter commits by path

    ## Multi-Commit Guidelines

    ### Atomic Commits

    **Each commit should:**
    - Represent one logical change
    - Leave codebase in working state
    - Be revertible independently

    **Bad:**
    ```
    commit 1: Add feature + fix bug + update docs + refactor
    ```

    **Good:**
    ```
    commit 1: feat: add feature
    commit 2: fix: fix discovered bug
    commit 3: docs: document feature
    commit 4: refactor: cleanup related code
    ```

    ### Commit Order

    **Logical sequence:**
    1. Dependency changes (first)
    2. Core functionality
    3. Tests for new functionality
    4. Documentation

    ## PR Description Format

    ### Template

    ```markdown
    ## Summary
    Brief description of changes (1-2 sentences)

    ## Changes
    - **Feature A**: Description
    - **Fix B**: Description
    - **Refactor C**: Description

    ## Testing
    - [ ] Unit tests added/updated
    - [ ] Integration tests pass
    - [ ] Manual testing performed

    ## Breaking Changes
    - None / List any breaking changes

    ## Related Issues
    Fixes #123
    Relates to #456

    ## Checklist
    - [ ] Code follows style guidelines
    - [ ] Commits follow conventional format
    - [ ] Documentation updated
    - [ ] Tests added/updated
    ```

    ### PR Title

    Follow commit message format:
    ```
    feat: add user authentication
    fix: resolve memory leak in worker
    docs: update API reference
    ```

    ## Common Mistakes

    ### Subject Line Issues

    ❌ **Too long:**
    ```
    feat(auth): implement a comprehensive user authentication system with JWT tokens and refresh mechanism
    ```

    ✅ **Concise:**
    ```
    feat(auth): add JWT authentication
    ```

    ❌ **Past tense:**
    ```
    feat: added new feature
    ```

    ✅ **Imperative:**
    ```
    feat: add new feature
    ```

    ❌ **Ends with period:**
    ```
    feat: add feature.
    ```

    ✅ **No period:**
    ```
    feat: add feature
    ```

    ### Type Issues

    ❌ **Wrong type:**
    ```
    feat: fix typo in readme  # Should be docs
    fix: update dependencies  # Should be chore
    ```

    ✅ **Correct type:**
    ```
    docs: fix typo in readme
    chore: update dependencies
    ```

    ### Scope Issues

    ❌ **Inconsistent:**
    ```
    feat(api): add endpoint
    fix(API): handle error  # Inconsistent casing
    ```

    ✅ **Consistent:**
    ```
    feat(api): add endpoint
    fix(api): handle error
    ```

    ## Checklist Before Committing

    - [ ] Type correctly identifies change nature
    - [ ] Scope is consistent with project conventions (if used)
    - [ ] Subject is under 72 characters
    - [ ] Subject uses imperative mood
    - [ ] No period at end of subject
    - [ ] Body explains why (if needed)
    - [ ] Breaking changes marked with `!`
    - [ ] Issues referenced in footer
    - [ ] Each commit is atomic and logical

    ## Example Workflow

    ### Scenario: Adding a Feature

    **1. Look at what changed:**
    ```bash
    git diff --cached --name-only
    # Output: src/auth/login.js, src/auth/token.js

    git diff --cached
    # Shows: added login function, token handling
    ```

    **2. Determine type and scope:**
    - Type: `feat` (new functionality)
    - Scope: `auth` (authentication component)

    **3. Write subject line:**
    ```
    feat(auth): add JWT authentication
    ```

    **4. Write body (optional):**
    ```
    feat(auth): add JWT authentication

    Implements login/logout via JWT tokens for better scalability
    and support for multiple clients (web, mobile, API).

    - Added endpoints for login/logout
    - Implemented refresh token mechanism
    - Added middleware for protected routes

    Closes #45
    ```

    **5. Check:**
    - [ ] Type correct? Yes, `feat`
    - [ ] Scope consistent? Yes, `auth`
    - [ ] Length < 72? Yes
    - [ ] Imperative? Yes, "add"
    - [ ] No period? Yes
    - [ ] Body explains why? Yes

    **6. Commit:**
    ```bash
    git commit -m "feat(auth): add JWT authentication" \
      -m "" \
      -m "Implements login/logout via JWT tokens for better scalability" \
      -m "and support for multiple clients (web, mobile, API)." \
      -m "" \
      -m "- Added endpoints for login/logout" \
      -m "- Implemented refresh token mechanism" \
      -m "- Added middleware for protected routes" \
      -m "" \
      -m "Closes #45"
    ```

    ## See Also

    - For commit message style: commit-messages reference
    - For Git workflow: git-workflows reference
    - For writing style: technical-writer skill
    - For removing AI patterns: humanizer skill
  '';
}
