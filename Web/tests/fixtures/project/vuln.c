#include <stdio.h>
#include <string.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    char buf[16];
    strcpy(buf, argv[1]);
    system(getenv("CMD"));
    printf(argv[2]);
    return 0;
}
