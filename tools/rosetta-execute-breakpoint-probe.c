#include <stdio.h>

static volatile int target_calls;

__attribute__((noinline)) static void execute_target(void)
{
    ++target_calls;
}

int main(void)
{
    execute_target();
    printf("target_calls=%d\n", target_calls);
    return target_calls == 1 ? 0 : 1;
}
