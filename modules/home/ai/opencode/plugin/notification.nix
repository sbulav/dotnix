''
  export const NotificationPlugin = async ({ $ }) => {
    return {
      "session.idle": async () => {
        await $`notify-send -a 'OpenCode' 'OpenCode' 'Awaiting your input'`
      }
    }
  }
''
