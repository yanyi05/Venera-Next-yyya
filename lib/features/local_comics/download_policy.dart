/// Reading gets priority without discarding active requests or pausing a queue.
int readingDownloadConcurrency(int configured, {required bool reading}) =>
    reading ? 1 : configured.clamp(1, 16);
