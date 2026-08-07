#include <stdarg.h>
#include <windef.h>
#include <winbase.h>
#include <winuser.h>

static int close_named_window(const char *title)
{
    HWND window = FindWindowA(NULL, title);
    if (!window) {
        return 2;
    }

    if (!PostMessageA(window, WM_CLOSE, 0, 0)) {
        return 3;
    }

    return 0;
}

int main(int argc, char **argv)
{
    if (argc != 2 || !argv[1][0]) {
        return 1;
    }

    return close_named_window(argv[1]);
}
