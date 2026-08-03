#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PM_DATA_LEN 4128

#define J2534_NOERROR 0
#define J2534_ERR_TIMEOUT 9
#define J2534_ERR_BUFFER_EMPTY 16

#define J2534_ISO9141 3
#define J2534_FIVE_BAUD_INIT 4
#define J2534_SET_CONFIG 2
#define J2534_CLEAR_TX_BUFFER 7
#define J2534_CLEAR_RX_BUFFER 8
#define J2534_PASS_FILTER 1

typedef struct _PASSTHRU_MSG {
    unsigned long ProtocolID;
    unsigned long RxStatus;
    unsigned long TxFlags;
    unsigned long Timestamp;
    unsigned long DataSize;
    unsigned long ExtraDataIndex;
    unsigned char Data[PM_DATA_LEN];
} PASSTHRU_MSG;

typedef struct _SBYTE_ARRAY {
    unsigned long NumOfBytes;
    unsigned char *BytePtr;
} SBYTE_ARRAY;

typedef struct _SCONFIG {
    unsigned long Parameter;
    unsigned long Value;
} SCONFIG;

typedef struct _SCONFIG_LIST {
    unsigned long NumOfParams;
    SCONFIG *ConfigPtr;
} SCONFIG_LIST;

typedef int32_t (WINAPI *PassThruOpen_t)(const void *pName, unsigned long *pDeviceID);
typedef int32_t (WINAPI *PassThruClose_t)(unsigned long DeviceID);
typedef int32_t (WINAPI *PassThruConnect_t)(unsigned long DeviceID, unsigned long ProtocolID,
    unsigned long Flags, unsigned long Baudrate, unsigned long *pChannelID);
typedef int32_t (WINAPI *PassThruDisconnect_t)(unsigned long ChannelID);
typedef int32_t (WINAPI *PassThruReadMsgs_t)(unsigned long ChannelID, PASSTHRU_MSG *pMsg,
    unsigned long *pNumMsgs, unsigned long Timeout);
typedef int32_t (WINAPI *PassThruWriteMsgs_t)(unsigned long ChannelID, const PASSTHRU_MSG *pMsg,
    unsigned long *pNumMsgs, unsigned long Timeout);
typedef int32_t (WINAPI *PassThruStartMsgFilter_t)(unsigned long ChannelID, unsigned long FilterType,
    const PASSTHRU_MSG *pMaskMsg, const PASSTHRU_MSG *pPatternMsg,
    const PASSTHRU_MSG *pFlowControlMsg, unsigned long *pMsgID);
typedef int32_t (WINAPI *PassThruIoctl_t)(unsigned long ChannelID, unsigned long IoctlID,
    const void *pInput, void *pOutput);
typedef int32_t (WINAPI *PassThruReadVersion_t)(unsigned long DeviceID, char *pFirmwareVersion,
    char *pDllVersion, char *pApiVersion);
typedef int32_t (WINAPI *PassThruGetLastError_t)(char *pErrorDescription);

static PassThruOpen_t pOpen;
static PassThruClose_t pClose;
static PassThruConnect_t pConnect;
static PassThruDisconnect_t pDisconnect;
static PassThruReadMsgs_t pReadMsgs;
static PassThruWriteMsgs_t pWriteMsgs;
static PassThruStartMsgFilter_t pStartMsgFilter;
static PassThruIoctl_t pIoctl;
static PassThruReadVersion_t pReadVersion;
static PassThruGetLastError_t pGetLastError;

static const char *j2534_name(int32_t code)
{
    switch (code) {
    case 0: return "NOERROR";
    case 1: return "ERR_NOT_SUPPORTED";
    case 2: return "ERR_INVALID_CHANNEL_ID";
    case 3: return "ERR_INVALID_PROTOCOL_ID";
    case 4: return "ERR_NULL_PARAMETER";
    case 5: return "ERR_INVALID_IOCTL_VALUE";
    case 6: return "ERR_INVALID_FLAGS";
    case 7: return "ERR_FAILED";
    case 8: return "ERR_DEVICE_NOT_CONNECTED";
    case 9: return "ERR_TIMEOUT";
    case 16: return "ERR_BUFFER_EMPTY";
    default: return "ERR_UNKNOWN";
    }
}

static void print_last_error(void)
{
    char err[256] = {0};
    if (pGetLastError && pGetLastError(err) == J2534_NOERROR && err[0]) {
        printf("  LastError: %s\n", err);
    }
}

static int check_ret(const char *what, int32_t ret)
{
    if (ret == J2534_NOERROR) {
        printf("%s: OK\n", what);
        return 1;
    }
    printf("%s: %s (%ld)\n", what, j2534_name(ret), (long)ret);
    print_last_error();
    return 0;
}

static FARPROC required(HMODULE dll, const char *name)
{
    FARPROC proc = GetProcAddress(dll, name);
    if (!proc) {
        printf("Missing export: %s\n", name);
    }
    return proc;
}

static void print_hex(const unsigned char *data, unsigned long len)
{
    unsigned long i;
    for (i = 0; i < len; i++) {
        printf("%02X", data[i]);
        if (i + 1 < len) printf(" ");
    }
}

static void print_ascii_from_frame(const unsigned char *data, unsigned long len)
{
    unsigned long i;
    int printed = 0;

    printf("  ASCII: ");
    for (i = 0; i < len; i++) {
        unsigned char c = data[i];
        if (isprint(c)) {
            putchar(c);
            printed = 1;
        }
    }
    if (!printed) printf("(none)");
    printf("\n");
}

static void build_iso9141_obd(unsigned char sid, unsigned char pid, PASSTHRU_MSG *msg)
{
    unsigned int sum = 0;
    unsigned long i;

    memset(msg, 0, sizeof(*msg));
    msg->ProtocolID = J2534_ISO9141;
    msg->RxStatus = 1;
    msg->Timestamp = 1;
    msg->DataSize = 6;
    msg->Data[0] = 0x68;
    msg->Data[1] = 0x6A;
    msg->Data[2] = 0xF1;
    msg->Data[3] = sid;
    msg->Data[4] = pid;
    for (i = 0; i < msg->DataSize - 1; i++) {
        sum += msg->Data[i];
    }
    msg->Data[5] = (unsigned char)(sum & 0xFF);
}

static void drain_reads(unsigned long channel_id)
{
    for (;;) {
        PASSTHRU_MSG msg;
        unsigned long count = 1;
        int32_t ret;
        memset(&msg, 0, sizeof(msg));
        ret = pReadMsgs(channel_id, &msg, &count, 25);
        if (ret != J2534_NOERROR || count == 0) break;
    }
}

static void read_responses(unsigned long channel_id, unsigned int attempts)
{
    int saw_any = 0;
    int saw_ecu = 0;
    unsigned int i;

    for (i = 0; i < attempts; i++) {
        PASSTHRU_MSG msg;
        unsigned long count = 1;
        int32_t ret;

        memset(&msg, 0, sizeof(msg));
        ret = pReadMsgs(channel_id, &msg, &count, 1000);
        if (ret == J2534_ERR_TIMEOUT || ret == J2534_ERR_BUFFER_EMPTY) {
            continue;
        }
        if (ret != J2534_NOERROR) {
            printf("  ReadMsgs: %s (%ld)\n", j2534_name(ret), (long)ret);
            print_last_error();
            continue;
        }
        if (count == 0 || msg.DataSize == 0) {
            continue;
        }

        saw_any = 1;
        printf("  RX status=0x%08lX size=%lu: ", msg.RxStatus, msg.DataSize);
        print_hex(msg.Data, msg.DataSize);
        printf("\n");
        if (msg.RxStatus == 0) {
            saw_ecu = 1;
            print_ascii_from_frame(msg.Data, msg.DataSize);
            return;
        }
    }

    if (!saw_any) {
        printf("  No response.\n");
    } else if (!saw_ecu) {
        printf("  No ECU response; only transmit loopback/status was received.\n");
    }
}

static void query(unsigned long channel_id, unsigned char sid, unsigned char pid, const char *label)
{
    PASSTHRU_MSG msg;
    unsigned long count = 1;
    int32_t ret;

    build_iso9141_obd(sid, pid, &msg);
    drain_reads(channel_id);

    printf("\nQuery %s: ", label);
    print_hex(msg.Data, msg.DataSize);
    printf("\n");

    ret = pWriteMsgs(channel_id, &msg, &count, 1000);
    if (!check_ret("WriteMsgs", ret)) return;

    read_responses(channel_id, 6);
    Sleep(150);
}

static void set_config_one(unsigned long channel_id, unsigned long parameter, unsigned long value)
{
    SCONFIG cfg;
    SCONFIG_LIST list;
    int32_t ret;

    cfg.Parameter = parameter;
    cfg.Value = value;
    list.NumOfParams = 1;
    list.ConfigPtr = &cfg;

    ret = pIoctl(channel_id, J2534_SET_CONFIG, &list, NULL);
    if (!check_ret("SET_CONFIG", ret)) {
        printf("  parameter=0x%02lX value=%lu\n", parameter, value);
    }
}

static void install_evoscan_filter(unsigned long channel_id)
{
    PASSTHRU_MSG mask;
    PASSTHRU_MSG pattern;
    unsigned long filter_id = 0;
    int32_t ret;

    memset(&mask, 0, sizeof(mask));
    memset(&pattern, 0, sizeof(pattern));
    mask.ProtocolID = J2534_ISO9141;
    pattern.ProtocolID = J2534_ISO9141;
    mask.TxFlags = 0x40;
    pattern.TxFlags = 0x40;
    mask.DataSize = 4;
    pattern.DataSize = 4;

    ret = pStartMsgFilter(channel_id, J2534_PASS_FILTER, &mask, &pattern, NULL, &filter_id);
    if (check_ret("StartMsgFilter EvoScan pass", ret)) {
        printf("  filter id=%lu\n", filter_id);
    }
}

static void write_probe_no_read(unsigned long channel_id, unsigned char sid, unsigned char pid, const char *label)
{
    PASSTHRU_MSG msg;
    unsigned long count = 1;
    int32_t ret;

    build_iso9141_obd(sid, pid, &msg);
    printf("\nPre-init probe %s: ", label);
    print_hex(msg.Data, msg.DataSize);
    printf("\n");

    ret = pWriteMsgs(channel_id, &msg, &count, 1000);
    check_ret("WriteMsgs", ret);
    drain_reads(channel_id);
}

int main(int argc, char **argv)
{
    const char *dll_path = "C:\\J2534\\OpenPort\\j2534.dll";
    const char *slash;
    char dll_dir[MAX_PATH];
    HMODULE dll;
    unsigned long device_id = 0;
    unsigned long channel_id = 0;
    int32_t ret;
    int i;

    for (i = 1; i < argc; i++) {
        if (_stricmp(argv[i], "--dll") == 0 && i + 1 < argc) {
            dll_path = argv[++i];
        } else {
            printf("Usage: %s [--dll C:\\J2534\\OpenPort\\j2534.dll]\n", argv[0]);
            return 2;
        }
    }

    if (!GetEnvironmentVariableA("LOG_ENABLE", NULL, 0)) {
        SetEnvironmentVariableA("LOG_ENABLE", "C:\\J2534\\op2.log");
    }
    SetEnvironmentVariableA("LIBUSB_DEBUG", "3");

    memset(dll_dir, 0, sizeof(dll_dir));
    strncpy(dll_dir, dll_path, sizeof(dll_dir) - 1);
    slash = strrchr(dll_dir, '\\');
    if (slash) {
        dll_dir[slash - dll_dir] = 0;
        SetDllDirectoryA(dll_dir);
    }

    printf("Loading %s\n", dll_path);
    dll = LoadLibraryA(dll_path);
    if (!dll) {
        printf("LoadLibrary failed: Windows error %lu\n", GetLastError());
        printf("Make sure this program is x86 and libusb-1.0.dll is next to j2534.dll.\n");
        return 1;
    }

    pOpen = (PassThruOpen_t)required(dll, "PassThruOpen");
    pClose = (PassThruClose_t)required(dll, "PassThruClose");
    pConnect = (PassThruConnect_t)required(dll, "PassThruConnect");
    pDisconnect = (PassThruDisconnect_t)required(dll, "PassThruDisconnect");
    pReadMsgs = (PassThruReadMsgs_t)required(dll, "PassThruReadMsgs");
    pWriteMsgs = (PassThruWriteMsgs_t)required(dll, "PassThruWriteMsgs");
    pStartMsgFilter = (PassThruStartMsgFilter_t)required(dll, "PassThruStartMsgFilter");
    pIoctl = (PassThruIoctl_t)required(dll, "PassThruIoctl");
    pReadVersion = (PassThruReadVersion_t)required(dll, "PassThruReadVersion");
    pGetLastError = (PassThruGetLastError_t)required(dll, "PassThruGetLastError");
    if (!pOpen || !pClose || !pConnect || !pDisconnect || !pReadMsgs || !pWriteMsgs || !pStartMsgFilter ||
        !pIoctl || !pReadVersion || !pGetLastError) {
        return 1;
    }

    printf("Key ON, engine OFF. Close EvoScan/i-HDS before running.\n\n");

    ret = pOpen("J2534-2:", &device_id);
    if (!check_ret("PassThruOpen", ret)) return 1;

    {
        char fw[80] = {0};
        char dllv[80] = {0};
        char api[80] = {0};
        ret = pReadVersion(device_id, fw, dllv, api);
        if (check_ret("ReadVersion", ret)) {
            printf("  fw=%s\n  dll=%s\n  api=%s\n", fw, dllv, api);
        }
    }

    ret = pConnect(device_id, J2534_ISO9141, 0x200, 10400, &channel_id);
    if (!check_ret("PassThruConnect ISO9141 10400", ret)) {
        pClose(device_id);
        return 1;
    }

    set_config_one(channel_id, 0x16, 0);
    set_config_one(channel_id, 0x03, 1);
    set_config_one(channel_id, 0x07, 40);
    set_config_one(channel_id, 0x0A, 110);
    set_config_one(channel_id, 0x0C, 10);
    install_evoscan_filter(channel_id);

    pIoctl(channel_id, J2534_CLEAR_TX_BUFFER, NULL, NULL);
    pIoctl(channel_id, J2534_CLEAR_RX_BUFFER, NULL, NULL);

    write_probe_no_read(channel_id, 0x01, 0x00, "Mode 01 PID 00 wake");
    pIoctl(channel_id, J2534_CLEAR_RX_BUFFER, NULL, NULL);

    {
        unsigned char init_byte = 0x33;
        unsigned char keybytes[8] = {0};
        SBYTE_ARRAY input;
        SBYTE_ARRAY output;
        input.NumOfBytes = 1;
        input.BytePtr = &init_byte;
        output.NumOfBytes = 0;
        output.BytePtr = keybytes;
        ret = pIoctl(channel_id, J2534_FIVE_BAUD_INIT, &input, &output);
        if (check_ret("FIVE_BAUD_INIT 0x33", ret)) {
            printf("  key bytes: ");
            print_hex(output.BytePtr, output.NumOfBytes);
            printf("\n");
        } else {
            printf("Continuing anyway; some vehicles/interfaces are already initialized.\n");
        }
    }

    pIoctl(channel_id, J2534_CLEAR_RX_BUFFER, NULL, NULL);

    query(channel_id, 0x01, 0x04, "Mode 01 PID 04 calculated load");
    query(channel_id, 0x01, 0x05, "Mode 01 PID 05 coolant temp");
    query(channel_id, 0x01, 0x0C, "Mode 01 PID 0C RPM");
    query(channel_id, 0x01, 0x0D, "Mode 01 PID 0D vehicle speed");
    query(channel_id, 0x01, 0x0F, "Mode 01 PID 0F intake air temp");
    query(channel_id, 0x01, 0x11, "Mode 01 PID 11 throttle position");
    query(channel_id, 0x01, 0x00, "Mode 01 PID 00 supported PIDs");
    query(channel_id, 0x09, 0x00, "Mode 09 PID 00 supported info PIDs");
    query(channel_id, 0x09, 0x02, "Mode 09 PID 02 VIN");
    query(channel_id, 0x09, 0x04, "Mode 09 PID 04 calibration ID");
    query(channel_id, 0x09, 0x06, "Mode 09 PID 06 CVN");
    query(channel_id, 0x09, 0x08, "Mode 09 PID 08 supported by ECU");
    query(channel_id, 0x09, 0x0B, "Mode 09 PID 0B supported by ECU");
    query(channel_id, 0x09, 0x0C, "Mode 09 PID 0C supported by ECU");
    query(channel_id, 0x09, 0x0D, "Mode 09 PID 0D supported by ECU");
    query(channel_id, 0x09, 0x0E, "Mode 09 PID 0E supported by ECU");

    pDisconnect(channel_id);
    pClose(device_id);
    return 0;
}
