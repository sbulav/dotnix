#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;
static void stop(int signal_number) { (void)signal_number; running = 0; }

int main(int argc, char **argv) {
  close(STDOUT_FILENO);
  close(STDERR_FILENO);
  signal(SIGINT, stop);
  signal(SIGTERM, stop);
  const char *output = NULL;
  for (int i = 1; i + 1 < argc; i++)
    if (!strcmp(argv[i], "-o")) output = argv[i + 1];
  const char *log = getenv("FAKE_RECORDER_LOG");
  if (log) {
    FILE *file = fopen(log, "a");
    if (!file) return 2;
    fprintf(file, "%ld\n", (long)getpid());
    fclose(file);
  }
  const char *mode = getenv("FAKE_RECORDER_MODE");
  if (output && (!mode || strcmp(mode, "hang"))) {
    FILE *file = fopen(output, "w");
    if (!file) return 2;
    fputs("recording", file);
    fclose(file);
  }
  while (running) pause();
  return 0;
}
