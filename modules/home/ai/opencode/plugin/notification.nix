''
  export const NotificationPlugin = async ({ $ }) => {
    return {
      "event": async ({ event }) => {
        if (event.type === "session.idle") {
          const message = "Awaiting your input"
          try {
            // Cross-platform desktop notification: osascript on macOS,
            // notify-send on Linux.
            if (process.platform === "darwin") {
              const script = `display notification "''${message}" with title "OpenCode"`
              await $`osascript -e ''${script}`
            } else {
              await $`notify-send -a OpenCode OpenCode ''${message}`
            }
          } catch {
            // Notifications are optional; ignore missing desktop integration.
          }
        }
      }
    }
  }
''
