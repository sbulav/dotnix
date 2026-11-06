''
  import { $ } from "bun"

  const notify = async (message) => {
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

  export default {
    id: "notification",
    async setup(ctx) {
      await ctx.session.hook("experimental.idle", (event) => {
        // The hook re-runs when the session's own background work finishes.
        if (event.background.some((work) => work.sessionID === event.sessionID)) return
        // Fire and forget: a throwing idle hook would fail the session.
        void notify("Awaiting your input").catch(() => {})
      })
    },
  }
''
