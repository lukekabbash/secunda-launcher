#include <errno.h>
#include <mach/mach.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <servers/bootstrap.h>

#define ARM_DEBUG_STATE64_COMPAT 15
#define X86_DEBUG_STATE64_COMPAT 11

typedef struct
{
    uint64_t bvr[16];
    uint64_t bcr[16];
    uint64_t wvr[16];
    uint64_t wcr[16];
    uint64_t mdscr_el1;
} arm_debug_state64_compat_t;

typedef struct
{
    uint64_t dr[8];
} x86_debug_state64_compat_t;

enum debug_state_kind
{
    DEBUG_STATE_ARM,
    DEBUG_STATE_X86
};

static volatile uint32_t watched_value;

typedef struct
{
    mach_msg_header_t header;
    mach_msg_body_t body;
    mach_msg_port_descriptor_t task_port;
} task_port_message_t;

typedef union
{
    task_port_message_t message;
    uint8_t bytes[4096];
} task_port_receive_t;

extern kern_return_t bootstrap_register2(mach_port_t bootstrap_port,
                                         name_t service_name,
                                         mach_port_t service_port,
                                         uint64_t flags);

static uint64_t watch_control(uintptr_t address, size_t size)
{
    const uintptr_t offset = address & 7;
    const uint64_t byte_mask = ((UINT64_C(1) << size) - 1) << offset;
    return UINT64_C(1) | (UINT64_C(3) << 1) | (UINT64_C(3) << 3) | (byte_mask << 5);
}

static void child_trap_handler(int signal)
{
    static const char message[] = "TRAP\n";
    (void)signal;
    write(STDOUT_FILENO, message, sizeof(message) - 1);
    _exit(0);
}

static kern_return_t send_task_port(const char *service_name)
{
    task_port_message_t message;
    mach_port_t bootstrap_port, service_port;
    kern_return_t result;

    if ((result = task_get_bootstrap_port(mach_task_self(), &bootstrap_port)) != KERN_SUCCESS)
        return result;
    result = bootstrap_look_up(bootstrap_port, service_name, &service_port);
    mach_port_deallocate(mach_task_self(), bootstrap_port);
    if (result != KERN_SUCCESS) return result;

    memset(&message, 0, sizeof(message));
    message.header.msgh_bits = MACH_MSGH_BITS_COMPLEX |
        MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    message.header.msgh_size = sizeof(message);
    message.header.msgh_remote_port = service_port;
    message.body.msgh_descriptor_count = 1;
    message.task_port.name = mach_task_self();
    message.task_port.disposition = MACH_MSG_TYPE_COPY_SEND;
    message.task_port.type = MACH_MSG_PORT_DESCRIPTOR;
    result = mach_msg(&message.header, MACH_SEND_MSG, sizeof(message), 0,
                      MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    mach_port_deallocate(mach_task_self(), service_port);
    return result;
}

static int child_main(const char *service_name)
{
    struct sigaction action;
    char command;
    kern_return_t send_result;

    memset(&action, 0, sizeof(action));
    action.sa_handler = child_trap_handler;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTRAP, &action, NULL);

    send_result = send_task_port(service_name);
    printf("READY %d %p %d\n", getpid(), (const void *)&watched_value, send_result);
    fflush(stdout);
    if (send_result != KERN_SUCCESS) return 4;
    if (read(STDIN_FILENO, &command, 1) != 1) return 3;

    watched_value++;
    printf("MISS %u\n", watched_value);
    fflush(stdout);
    return 2;
}

static int set_task_watchpoint(task_t task, uintptr_t address,
                               enum debug_state_kind state_kind,
                               unsigned int *success_count)
{
    thread_act_array_t threads = NULL;
    mach_msg_type_number_t thread_count = 0;
    kern_return_t result;
    unsigned int i;

    *success_count = 0;
    result = task_threads(task, &threads, &thread_count);
    if (result != KERN_SUCCESS) return result;

    for (i = 0; i < thread_count; i++)
    {
        kern_return_t set_result;

        if (state_kind == DEBUG_STATE_X86)
        {
            x86_debug_state64_compat_t state;

            memset(&state, 0, sizeof(state));
            state.dr[0] = address;
            state.dr[6] = 0;
            state.dr[7] = 1 | (UINT64_C(3) << 16) | (UINT64_C(3) << 18);
            set_result = thread_set_state(threads[i], X86_DEBUG_STATE64_COMPAT,
                                          (thread_state_t)&state,
                                          sizeof(state) / sizeof(uint32_t));
        }
        else
        {
            arm_debug_state64_compat_t state;

            memset(&state, 0, sizeof(state));
            state.wvr[0] = address & ~(uintptr_t)7;
            state.wcr[0] = watch_control(address, sizeof(watched_value));
            set_result = thread_set_state(threads[i], ARM_DEBUG_STATE64_COMPAT,
                                          (thread_state_t)&state,
                                          sizeof(state) / sizeof(uint32_t));
        }
        if (set_result == KERN_SUCCESS)
            (*success_count)++;
        mach_port_deallocate(mach_task_self(), threads[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)threads,
                  thread_count * sizeof(*threads));
    return KERN_SUCCESS;
}

static int parent_main(const char *child_path, enum debug_state_kind state_kind)
{
    int commands[2], reports[2], status;
    char line[128], result_line[128] = "";
    char service_name[BOOTSTRAP_MAX_NAME_LEN];
    uintptr_t address;
    unsigned int success_count;
    FILE *reports_file;
    mach_port_t bootstrap_port, receive_port;
    task_port_receive_t receive;
    task_t task;
    pid_t child;
    kern_return_t register_result, receive_result, watch_result;

    if (pipe(commands) == -1 || pipe(reports) == -1) return 10;
    if (task_get_bootstrap_port(mach_task_self(), &bootstrap_port) != KERN_SUCCESS) return 13;
    if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &receive_port) != KERN_SUCCESS)
        return 14;
    if (mach_port_insert_right(mach_task_self(), receive_port, receive_port,
                               MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS)
        return 15;
    snprintf(service_name, sizeof(service_name), "/tmp/secunda-watchpoint-%d", getpid());
    if (mkdir(service_name, 0700) == -1 && errno != EEXIST) return 17;
    register_result = bootstrap_register2(bootstrap_port, service_name, receive_port, 0);
    mach_port_deallocate(mach_task_self(), bootstrap_port);
    if (register_result != KERN_SUCCESS)
    {
        fprintf(stderr, "bootstrap_register2 failed: %d\n", register_result);
        rmdir(service_name);
        return 16;
    }

    child = fork();
    if (child == -1) return 11;
    if (!child)
    {
        dup2(commands[0], STDIN_FILENO);
        dup2(reports[1], STDOUT_FILENO);
        close(commands[0]);
        close(commands[1]);
        close(reports[0]);
        close(reports[1]);
        execl(child_path, child_path, "--child", service_name, NULL);
        _exit(127);
    }

    close(commands[0]);
    close(reports[1]);
    reports_file = fdopen(reports[0], "r");
    if (!reports_file || !fgets(line, sizeof(line), reports_file) ||
        sscanf(line, "READY %*d %lx", &address) != 1)
        return 12;

    memset(&receive, 0, sizeof(receive));
    receive_result = mach_msg(&receive.message.header, MACH_RCV_MSG, 0, sizeof(receive),
                              receive_port, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    mach_port_deallocate(mach_task_self(), receive_port);
    task = receive_result == KERN_SUCCESS
        ? receive.message.task_port.name : MACH_PORT_NULL;
    watch_result = receive_result == KERN_SUCCESS
        ? set_task_watchpoint(task, address, state_kind, &success_count)
        : receive_result;
    if (task != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), task);

    write(commands[1], "G", 1);
    close(commands[1]);
    if (fgets(result_line, sizeof(result_line), reports_file) == NULL)
        result_line[0] = '\0';
    fclose(reports_file);
    waitpid(child, &status, 0);
    rmdir(service_name);

    printf("state=%s register=%d receive=%d watch=%d threads=%u child_status=%d report=%s",
           state_kind == DEBUG_STATE_X86 ? "x86" : "arm",
           register_result, receive_result, watch_result,
           receive_result == KERN_SUCCESS ? success_count : 0,
           WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status),
           result_line);
    return receive_result == KERN_SUCCESS && watch_result == KERN_SUCCESS &&
           success_count > 0 && WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : 1;
}

int main(int argc, char **argv)
{
    if (argc == 3 && !strcmp(argv[1], "--child")) return child_main(argv[2]);
    if (argc != 3 || (strcmp(argv[2], "arm") && strcmp(argv[2], "x86")))
    {
        fprintf(stderr, "usage: %s <translated-child> <arm|x86>\n", argv[0]);
        return 64;
    }
    return parent_main(argv[1], !strcmp(argv[2], "x86")
                       ? DEBUG_STATE_X86 : DEBUG_STATE_ARM);
}
