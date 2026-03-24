''
  export const SecurityPlugin = async () => {
    const dangerousPatterns = [
      /curl.*\|.*sh/,
      /curl.*\|.*bash/,
      /wget.*\|.*sh/,
      /wget.*\|.*bash/,
      /eval.*\$\(/,
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

        // Block path traversal in file tools
        if (["read", "write", "edit", "multiedit"].includes(input.tool)) {
          const path = output.args.filePath || ""
          if (path.includes("../")) {
            throw new Error("Path traversal attempt detected")
          }
        }
      }
    }
  }
''
