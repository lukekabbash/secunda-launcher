#define COBJMACROS
#include <d3d11.h>

static void write_message(const char *message)
{
    DWORD length = 0;
    DWORD written = 0;
    while (message[length] != '\0') ++length;
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), message, length, &written, NULL);
}

void mainCRTStartup(void)
{
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    D3D_FEATURE_LEVEL selected_level = 0;
    const D3D_FEATURE_LEVEL requested_levels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0,
    };

    HRESULT result = D3D11CreateDevice(
        NULL,
        D3D_DRIVER_TYPE_HARDWARE,
        NULL,
        0,
        requested_levels,
        sizeof(requested_levels) / sizeof(requested_levels[0]),
        D3D11_SDK_VERSION,
        &device,
        &selected_level,
        &context
    );

    if (FAILED(result)) {
        write_message("Direct3D device creation failed.\r\n");
        ExitProcess(1);
    }

    switch (selected_level) {
    case D3D_FEATURE_LEVEL_11_1:
        write_message("Direct3D device ready at feature level 11.1\r\n");
        break;
    case D3D_FEATURE_LEVEL_11_0:
        write_message("Direct3D device ready at feature level 11.0\r\n");
        break;
    case D3D_FEATURE_LEVEL_10_1:
        write_message("Direct3D device ready at feature level 10.1\r\n");
        break;
    case D3D_FEATURE_LEVEL_10_0:
        write_message("Direct3D device ready at feature level 10.0\r\n");
        break;
    default:
        write_message("Direct3D device ready at an unexpected feature level.\r\n");
        break;
    }

    ID3D11DeviceContext_Release(context);
    ID3D11Device_Release(device);
    ExitProcess(0);
}
