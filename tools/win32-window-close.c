#include <stdio.h>
#include <windef.h>
#include <winuser.h>

static int close_named_window(const char *title)
{
    HWND window = FindWindowA(NULL, title);
    if (!window) {
        fprintf(stderr, "window not found\n");
        return 2;
    }

    if (!PostMessageA(window, WM_CLOSE, 0, 0)) {
        fprintf(stderr, "window close request failed\n");
        return 3;
    }

    return 0;
}

int main(int argc, char **argv)
{
    if (argc != 2 || !argv[1][0]) {
        fprintf(stderr, "usage: win32-window-close.exe WINDOW_TITLE\n");
        return 1;
    }

    return close_named_window(argv[1]);
}
