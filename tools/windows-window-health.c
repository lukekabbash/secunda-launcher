#define WIN32_LEAN_AND_MEAN
#include <windows.h>

enum {
    health_ok = 0,
    health_fatal_window = 42,
    health_bad_arguments = 64,
    health_window_not_found = 65
};

struct probe_context {
    DWORD target_pid;
    DWORD watch_ms;
    DWORD show_window_id;
    int quiet;
    int found_fatal;
};

static int parse_dword(const char *text, DWORD *value_out)
{
    DWORD value = 0;

    if (!*text) return 0;
    while (*text)
    {
        DWORD digit;
        if (*text < '0' || *text > '9') return 0;
        digit = (DWORD)(*text++ - '0');
        if (value > (0xffffffffUL - digit) / 10) return 0;
        value = value * 10 + digit;
    }
    *value_out = value;
    return 1;
}

static int contains_ignoring_case(const char *text, const char *needle)
{
    int text_length = lstrlenA(text);
    int needle_length = lstrlenA(needle);
    int offset;

    if (!needle_length || needle_length > text_length) return 0;
    for (offset = 0; offset + needle_length <= text_length; ++offset)
    {
        int index;
        for (index = 0; index < needle_length; ++index)
        {
            unsigned char left = (unsigned char)text[offset + index];
            unsigned char right = (unsigned char)needle[index];
            if (left >= 'A' && left <= 'Z') left = (unsigned char)(left + ('a' - 'A'));
            if (right >= 'A' && right <= 'Z') right = (unsigned char)(right + ('a' - 'A'));
            if (left != right) break;
        }
        if (index == needle_length) return 1;
    }
    return 0;
}

static int describes_fatal_launch(const char *text)
{
    static const char *const signatures[] = {
        "fatal error",
        "error during initialization",
        "unhandled exception caught",
        "wine mono installer",
        "wine gecko installer"
    };
    int index;

    for (index = 0; index < (int)(sizeof(signatures) / sizeof(signatures[0])); ++index)
    {
        if (contains_ignoring_case(text, signatures[index])) return 1;
    }
    return 0;
}

static void utf8_text(HWND window, char *buffer, int buffer_size)
{
    WCHAR wide[1024];
    DWORD_PTR message_result = 0;
    int wide_capacity = (int)(sizeof(wide) / sizeof(wide[0]));
    int length;
    int converted;

    buffer[0] = '\0';
    wide[0] = L'\0';
    if (SendMessageTimeoutW(
            window,
            WM_GETTEXT,
            (WPARAM)wide_capacity,
            (LPARAM)wide,
            SMTO_ABORTIFHUNG | SMTO_BLOCK,
            500,
            &message_result))
    {
        length = (int)message_result;
    }
    else
    {
        length = GetWindowTextW(window, wide, wide_capacity);
    }
    if (length <= 0) return;
    converted = WideCharToMultiByte(
        CP_UTF8, 0, wide, length, buffer, buffer_size - 1, NULL, NULL);
    if (converted <= 0) return;
    buffer[converted] = '\0';
}

static void utf8_class(HWND window, char *buffer, int buffer_size)
{
    WCHAR wide[256];
    int length = GetClassNameW(window, wide, (int)(sizeof(wide) / sizeof(wide[0])));
    int converted;

    buffer[0] = '\0';
    if (length <= 0) return;
    converted = WideCharToMultiByte(
        CP_UTF8, 0, wide, length, buffer, buffer_size - 1, NULL, NULL);
    if (converted <= 0) return;
    buffer[converted] = '\0';
}

static BOOL CALLBACK inspect_child(HWND window, LPARAM parameter)
{
    struct probe_context *context = (struct probe_context *)parameter;
    char text[4096];
    char class_name[1024];
    RECT bounds;

    utf8_text(window, text, sizeof(text));
    utf8_class(window, class_name, sizeof(class_name));
    SetRectEmpty(&bounds);
    GetWindowRect(window, &bounds);
    if (describes_fatal_launch(text)) context->found_fatal = 1;
    if (!context->quiet && (text[0] || class_name[0]))
    {
        char line[6144];
        DWORD written;
        int length = wsprintfA(
            line,
            "child\thwnd=%p\tvisible=%d\trect=%ld,%ld,%ld,%ld\tclass=%s\ttext=%s\r\n",
            window,
            IsWindowVisible(window) ? 1 : 0,
            bounds.left,
            bounds.top,
            bounds.right,
            bounds.bottom,
            class_name,
            text);
        WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), line, (DWORD)length, &written, NULL);
    }
    return TRUE;
}

static BOOL CALLBACK inspect_window(HWND window, LPARAM parameter)
{
    struct probe_context *context = (struct probe_context *)parameter;
    DWORD process_id = 0;
    char text[4096];
    char class_name[1024];
    RECT bounds;

    GetWindowThreadProcessId(window, &process_id);
    if (context->target_pid && process_id != context->target_pid) return TRUE;

    utf8_text(window, text, sizeof(text));
    utf8_class(window, class_name, sizeof(class_name));
    SetRectEmpty(&bounds);
    GetWindowRect(window, &bounds);
    if (describes_fatal_launch(text)) context->found_fatal = 1;
    if (!context->quiet)
    {
        char line[6144];
        DWORD written;
        int length = wsprintfA(
            line,
            "window\thwnd=%p\tpid=%lu\tvisible=%d\trect=%ld,%ld,%ld,%ld\tclass=%s\ttext=%s\r\n",
            window,
            (unsigned long)process_id,
            IsWindowVisible(window) ? 1 : 0,
            bounds.left,
            bounds.top,
            bounds.right,
            bounds.bottom,
            class_name,
            text);
        WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), line, (DWORD)length, &written, NULL);
    }
    EnumChildWindows(window, inspect_child, parameter);
    return TRUE;
}

static int parse_arguments(int argc, char **argv, struct probe_context *context)
{
    int index;

    ZeroMemory(context, sizeof(*context));
    for (index = 1; index < argc; ++index)
    {
        if (!lstrcmpA(argv[index], "--quiet-health"))
        {
            context->quiet = 1;
        }
        else if (!lstrcmpA(argv[index], "--pid") && index + 1 < argc)
        {
            if (!parse_dword(argv[++index], &context->target_pid)
                || !context->target_pid) return 0;
        }
        else if (!lstrcmpA(argv[index], "--watch-ms") && index + 1 < argc)
        {
            if (!parse_dword(argv[++index], &context->watch_ms)) return 0;
        }
        else if (!lstrcmpA(argv[index], "--show-hwnd") && index + 1 < argc)
        {
            if (!parse_dword(argv[++index], &context->show_window_id)
                || !context->show_window_id) return 0;
        }
        else
        {
            return 0;
        }
    }
    return 1;
}

int main(int argc, char **argv)
{
    struct probe_context context;

    if (!parse_arguments(argc, argv, &context))
    {
        static const char usage[] =
            "usage: windows-window-health.exe [--pid PID] [--watch-ms MS] "
            "[--show-hwnd HWND] [--quiet-health]\r\n";
        DWORD written;
        WriteFile(
            GetStdHandle(STD_ERROR_HANDLE),
            usage,
            (DWORD)(sizeof(usage) - 1),
            &written,
            NULL);
        return health_bad_arguments;
    }

    if (context.show_window_id)
    {
        HWND window = (HWND)(ULONG_PTR)context.show_window_id;
        if (!IsWindow(window)) return health_window_not_found;
        ShowWindow(window, SW_SHOW);
        SetWindowPos(
            window,
            HWND_TOP,
            0,
            0,
            0,
            0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }

    {
        ULONGLONG deadline = GetTickCount64() + context.watch_ms;
        do
        {
            EnumWindows(inspect_window, (LPARAM)&context);
            if (context.found_fatal || !context.watch_ms) break;
            Sleep(100);
        } while (GetTickCount64() < deadline);
    }
    return context.found_fatal ? health_fatal_window : health_ok;
}
