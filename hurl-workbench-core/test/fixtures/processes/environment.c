/* Inspect envp before any language runtime can add platform variables. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int compare(const void *a, const void *b) {
  return strcmp(*(const char *const *)a, *(const char *const *)b);
}

int main(int argc, char **argv, char **envp) {
  if (argc != 5) return 2;
  size_t count = 0;
  while (envp[count]) count++;
  char **names = calloc(count + 1, sizeof(char *));
  size_t length = 3;
  for (size_t i = 0; i < count; i++) {
    char *equals = strchr(envp[i], '=');
    if (!equals) return 3;
    names[i] = strndup(envp[i], (size_t)(equals - envp[i]));
    length += strlen(names[i]) + 3;
    if (!strcmp(names[i], "SELECTED") && *(equals + 1)) return 4;
    if (!strcmp(names[i], "BOUND") && strcmp(equals + 1, "private-bound-sentinel")) return 4;
  }
  qsort(names, count, sizeof(char *), compare);
  char *observed = calloc(length, 1);
  strcat(observed, "[");
  for (size_t i = 0; i < count; i++) {
    if (i) strcat(observed, ",");
    strcat(observed, "\""); strcat(observed, names[i]); strcat(observed, "\"");
  }
  strcat(observed, "]");
  if (!strcmp(argv[4], "inherit")) {
    if (!getenv("PATH")) return 5;
  } else if (strcmp(observed, argv[4])) { puts(observed); return 5; }
  int probe = !strcmp(argv[2], "probe") || !strcmp(argv[2], "retry");
  if (probe) {
    char *service = calloc(strlen(argv[3]) + 16, 1);
    strcpy(service, argv[3]);
    char *slash = strrchr(service, '/');
    if (!slash) return 6;
    strcpy(slash + 1, "service");
    while (access(service, F_OK)) usleep(10000);
    free(service);
    if (!strcmp(argv[2], "retry")) {
      char *counter = calloc(strlen(argv[3]) + 16, 1);
      strcpy(counter, argv[3]); strcat(counter, ".attempts");
      int attempts = 0;
      FILE *previous = fopen(counter, "r");
      if (previous) { fscanf(previous, "%d", &attempts); fclose(previous); }
      FILE *next = fopen(counter, "w");
      if (!next) return 8;
      fprintf(next, "%d", attempts + 1); fclose(next); free(counter);
      if (!attempts) return 1;
    }
  }
  FILE *marker = fopen(argv[3], "w");
  if (!marker) return 7;
  fprintf(marker, "%d", getpid()); fclose(marker);
  if (!probe) sleep(60);
  return 0;
}
