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

  export const SecurityPlugin = async ({ directory, worktree }) => {
    const workspace = worktree || directory
    const dangerousPatterns = [
      /\b(curl|wget)\b[^|]*\|\s*\b(sh|bash)\b/i,
      /\beval\b.*\$\(/,
      /:\(\)\{.*:\|:.*\};:/
    ]

    return {
      "tool.execute.before": async (input, output) => {
        // Block dangerous bash patterns that permission lists can't express
        if (input.tool === "bash") {
          const cmd = output.args.command || ""
          for (const pattern of dangerousPatterns) {
            if (pattern.test(cmd)) {
              throw new Error("Dangerous command pattern detected")
            }
          }
        }

        if (!workspace) {
          return
        }

        // Block relative paths that escape the workspace while allowing
        // normalized paths like ./foo/../bar and absolute paths that the
        // regular permission system can still govern.
        if (["read", "write", "edit", "multiedit"].includes(input.tool)) {
          assertRelativePathStaysInWorkspace(workspace, output.args.filePath, "filePath")
        }

        if (["grep", "glob", "list"].includes(input.tool)) {
          assertRelativePathStaysInWorkspace(workspace, output.args.path, "path")
        }

        if (input.tool === "glob") {
          const pattern = output.args.pattern || ""
          if (pattern === ".." || pattern.startsWith("../") || pattern.includes("/../")) {
            throw new Error("Glob pattern escapes the workspace")
          }
        }
      }
    }
  }
''
