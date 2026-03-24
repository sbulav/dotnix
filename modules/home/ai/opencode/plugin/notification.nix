''
  export const NotificationPlugin = async ({ $ }) => {
    return {
      "session.idle": async () => {
        try {
          await $`command -v notify-send >/dev/null 2>&1 && notify-send -a OpenCode OpenCode "Awaiting your input"`
        } catch {
          // Notifications are optional; ignore missing desktop integration.
        }
      }
    }
  }
''
