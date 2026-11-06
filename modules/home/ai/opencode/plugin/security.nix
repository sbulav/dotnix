let
  patterns = import ../../shared/security-patterns.nix;
  jsPatterns = builtins.concatStringsSep ",\n    " (builtins.concatLists (map (e: e.js) patterns));
in
''
  import { isAbsolute, resolve } from "node:path"

  const expandHome = (value) => {
    if (typeof value !== "string") return value
    if (value === "~") return process.env.HOME || value
    if (value.startsWith("~/")) return `''${process.env.HOME || "~"}/''${value.slice(2)}`
    return value
  }

  const isWithin = (base, target) => target === base || target.startsWith(`''${base}/`)

  const resolveRelativePath = (base, value) => {
    if (typeof value !== "string" || value === "") return null

    const expanded = expandHome(value)
    if (isAbsolute(expanded)) return null

    return resolve(base, expanded)
  }

  const assertRelativePathStaysInWorkspace = (base, value, label) => {
    const resolved = resolveRelativePath(base, value)
    if (resolved && !isWithin(base, resolved)) {
      throw new Error(`''${label} escapes the workspace`)
    }
  }

  // Protect .env and variants, but allow .env.local
  const isProtectedEnvFile = (p) => /(?:^|\/)\.env(?:\.(?!local$).*)?$/.test(p || "")

  const commandReferencesProtectedEnvFile = (command) =>
    /(?:^|[\s|;&`('"=])(?:[^\s|;&`('"=]*\/)?\.env(?:\.(?!local(?:$|[\s|;&`)'"]))[^\s|;&`('"=]*)?(?=$|[\s|;&`)'"])/i.test(
      command || ""
    )

  // Protect secret-bearing dirs/files (~/.ssh, ~/.kube, kubeconfig) regardless of
  // whether the tool was handed an absolute or relative path. These sit outside
  // the workspace, so the relative-escape check never sees them.
  const isProtectedPath = (value) => {
    if (typeof value !== "string" || value === "") return false
    const expanded = expandHome(value)
    return (
      /(?:^|\/)\.ssh(?:\/|$)/i.test(expanded) ||
      /(?:^|\/)\.kube(?:\/|$)/i.test(expanded) ||
      /(?:^|\/)kubeconfig(?:$|\.)/i.test(expanded)
    )
  }

  const isSshConfig = (value) => {
    if (typeof value !== "string" || !process.env.HOME) return false
    const expanded = expandHome(value)
    return isAbsolute(expanded) && resolve(expanded) === resolve(process.env.HOME, ".ssh/config")
  }

  export default {
    id: "security",
    async setup(ctx) {
      // Relative-escape checks resolve against the location this plugin
      // instance serves.
      const workspace = ctx.location.directory

      const dangerousPatterns = [
        ${jsPatterns}
      ]

      await ctx.tool.hook("execute.before", (event) => {
        const tool = event.tool
        const args = event.input || {}

        // Block dangerous shell patterns that permission lists can't express
        if (tool === "shell") {
          const cmd = args.command || ""
          for (const pattern of dangerousPatterns) {
            if (pattern.test(cmd)) {
              throw new Error("Dangerous command pattern detected")
            }
          }
          // Block shell commands that reference .env files
          if (commandReferencesProtectedEnvFile(cmd)) {
            throw new Error(".env files are protected")
          }
        }

        if (!workspace) {
          return
        }

        // Block relative paths that escape the workspace while allowing
        // normalized paths like ./foo/../bar and absolute paths that the
        // regular permission system can still govern.
        if (["read", "write", "edit"].includes(tool)) {
          assertRelativePathStaysInWorkspace(workspace, args.path, "path")
          if (isProtectedEnvFile(args.path)) {
            throw new Error(".env files are protected")
          }
          if (isProtectedPath(args.path) && !(tool === "read" && isSshConfig(args.path))) {
            throw new Error("~/.ssh, ~/.kube, and kubeconfig files are protected")
          }
        }

        if (["grep", "glob"].includes(tool)) {
          assertRelativePathStaysInWorkspace(workspace, args.path, "path")
          if (tool === "grep" && args.path && isProtectedEnvFile(args.path)) {
            throw new Error(".env files are protected")
          }
          if (isProtectedPath(args.path)) {
            throw new Error("~/.ssh, ~/.kube, and kubeconfig files are protected")
          }
        }

        if (tool === "glob") {
          const pattern = args.pattern || ""
          if (pattern === ".." || pattern.startsWith("../") || pattern.includes("/../")) {
            throw new Error("Glob pattern escapes the workspace")
          }
          if (isProtectedPath(pattern)) {
            throw new Error("~/.ssh, ~/.kube, and kubeconfig files are protected")
          }
        }

        // Apply the write/edit checks to every path a patch touches.
        if (tool === "patch") {
          const patchText = typeof args.patchText === "string" ? args.patchText : ""
          const headerPattern = /^\s*\*\*\* (?:Add File|Delete File|Update File|Move to):\s*(.+?)\s*$/gm
          for (const match of patchText.matchAll(headerPattern)) {
            const p = match[1]
            assertRelativePathStaysInWorkspace(workspace, p, "path")
            if (isProtectedEnvFile(p)) {
              throw new Error(".env files are protected")
            }
            if (isProtectedPath(p)) {
              throw new Error("~/.ssh, ~/.kube, and kubeconfig files are protected")
            }
          }
        }
      })
    },
  }
''
