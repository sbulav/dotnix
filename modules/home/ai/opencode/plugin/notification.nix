''
  export const NotificationPlugin = async ({ $ }) => {
    return {
      "event": async ({ event }) => {
        if (event.type === "session.idle") {
          try {
            await $`notify-send -a OpenCode OpenCode "Awaiting your input"`
          } catch {
            // Notifications are optional; ignore missing desktop integration.
          }
        }
      }
    }
  }
''
