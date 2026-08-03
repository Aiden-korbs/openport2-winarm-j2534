#include <ctype.h>
#include <libusb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define OPENPORT_VID 0x0403
#define OPENPORT_PID 0xcc4d
#define BUF_LEN 4096

typedef struct openport {
    libusb_context *ctx;
    libusb_device_handle *handle;
    uint8_t intf;
    uint8_t ep_in;
    uint8_t ep_out;
} openport_t;

static void print_hex(const uint8_t *data, int len)
{
    for (int i = 0; i < len; i++) {
        printf("%02X", data[i]);
        if (i + 1 < len) printf(" ");
    }
}

static void fprint_hex(FILE *stream, const uint8_t *data, int len)
{
    for (int i = 0; i < len; i++) {
        fprintf(stream, "%02X", data[i]);
        if (i + 1 < len) fprintf(stream, " ");
    }
}

static void print_ascii_payload(const uint8_t *data, int len)
{
    int printed = 0;

    printf("  ASCII: ");
    for (int i = 0; i < len; i++) {
        if (isprint(data[i])) {
            putchar(data[i]);
            printed = 1;
        }
    }
    if (!printed) printf("(none)");
    printf("\n");
}

static int checksum_ok(const uint8_t *data, int len)
{
    uint8_t sum = 0;

    if (len < 2) return 0;
    for (int i = 0; i < len - 1; i++) sum = (uint8_t)(sum + data[i]);
    return sum == data[len - 1];
}

static int bulk_write(openport_t *op, const uint8_t *data, int len, unsigned int timeout_ms)
{
    int transferred = 0;
    int r = libusb_bulk_transfer(op->handle, op->ep_out, (uint8_t *)data, len, &transferred, timeout_ms);
    if (r != LIBUSB_SUCCESS || transferred != len) {
        fprintf(stderr, "USB write failed: %s transferred=%d/%d\n", libusb_error_name(r), transferred, len);
        return -1;
    }
    return 0;
}

static int bulk_read(openport_t *op, uint8_t *buf, int cap, unsigned int timeout_ms)
{
    int transferred = 0;
    int r = libusb_bulk_transfer(op->handle, op->ep_in, buf, cap, &transferred, timeout_ms);
    if (r == LIBUSB_ERROR_TIMEOUT) return 0;
    if (r != LIBUSB_SUCCESS) {
        fprintf(stderr, "USB read failed: %s\n", libusb_error_name(r));
        return -1;
    }
    return transferred;
}

static int contains(const uint8_t *buf, int len, const char *needle)
{
    int needle_len = (int)strlen(needle);

    if (needle_len <= 0 || len < needle_len) return 0;
    for (int i = 0; i <= len - needle_len; i++) {
        if (memcmp(buf + i, needle, needle_len) == 0) return 1;
    }
    return 0;
}

static int send_expect(openport_t *op, const uint8_t *data, int len, const char *expect, unsigned int timeout_ms)
{
    uint8_t buf[BUF_LEN];

    if (bulk_write(op, data, len, timeout_ms) != 0) return -1;

    for (;;) {
        int n = bulk_read(op, buf, sizeof(buf), timeout_ms);
        if (n <= 0) {
            fprintf(stderr, "Timed out waiting for %s\n", expect ? expect : "aro");
            return -1;
        }

        if (n >= 5 && memcmp(buf, "are 9", 5) == 0) {
            continue;
        }
        if (expect && contains(buf, n, expect)) return 0;
        if (!expect && contains(buf, n, "aro")) return 0;

        fprintf(stderr, "Unexpected OpenPort reply: ");
        fprint_hex(stderr, buf, n);
        fprintf(stderr, "\n");
    }
}

static int send_text(openport_t *op, const char *cmd, const char *expect)
{
    return send_expect(op, (const uint8_t *)cmd, (int)strlen(cmd), expect, 2000);
}

static void drain_usb(openport_t *op, unsigned int timeout_ms)
{
    uint8_t buf[BUF_LEN];

    for (;;) {
        int n = bulk_read(op, buf, sizeof(buf), timeout_ms);
        if (n <= 0) return;
    }
}

static int find_endpoints(libusb_device *dev, openport_t *op)
{
    struct libusb_config_descriptor *cfg = NULL;
    int r = libusb_get_active_config_descriptor(dev, &cfg);

    if (r != LIBUSB_SUCCESS) return -1;

    for (uint8_t i = 0; i < cfg->bNumInterfaces; i++) {
        const struct libusb_interface *iface = &cfg->interface[i];
        for (int a = 0; a < iface->num_altsetting; a++) {
            const struct libusb_interface_descriptor *alt = &iface->altsetting[a];
            uint8_t in = 0;
            uint8_t out = 0;

            for (uint8_t e = 0; e < alt->bNumEndpoints; e++) {
                const struct libusb_endpoint_descriptor *ep = &alt->endpoint[e];
                if ((ep->bmAttributes & LIBUSB_TRANSFER_TYPE_MASK) != LIBUSB_TRANSFER_TYPE_BULK) continue;
                if ((ep->bEndpointAddress & LIBUSB_ENDPOINT_DIR_MASK) == LIBUSB_ENDPOINT_IN) in = ep->bEndpointAddress;
                else out = ep->bEndpointAddress;
            }

            if (in && out) {
                op->intf = alt->bInterfaceNumber;
                op->ep_in = in;
                op->ep_out = out;
                libusb_free_config_descriptor(cfg);
                return 0;
            }
        }
    }

    libusb_free_config_descriptor(cfg);
    return -1;
}

static int open_openport(openport_t *op)
{
    libusb_device **devs = NULL;
    ssize_t count;
    int r;

    memset(op, 0, sizeof(*op));
    r = libusb_init(&op->ctx);
    if (r != LIBUSB_SUCCESS) {
        fprintf(stderr, "libusb_init failed: %s\n", libusb_error_name(r));
        return -1;
    }

    count = libusb_get_device_list(op->ctx, &devs);
    if (count < 0) {
        fprintf(stderr, "libusb_get_device_list failed\n");
        libusb_exit(op->ctx);
        return -1;
    }

    for (ssize_t i = 0; i < count; i++) {
        struct libusb_device_descriptor desc;
        libusb_device *dev = devs[i];

        if (libusb_get_device_descriptor(dev, &desc) != LIBUSB_SUCCESS) continue;
        if (desc.idVendor != OPENPORT_VID || desc.idProduct != OPENPORT_PID) continue;
        if (find_endpoints(dev, op) != 0) continue;

        r = libusb_open(dev, &op->handle);
        if (r != LIBUSB_SUCCESS) {
            fprintf(stderr, "libusb_open failed: %s\n", libusb_error_name(r));
            continue;
        }

        r = libusb_claim_interface(op->handle, op->intf);
        if (r != LIBUSB_SUCCESS) {
            fprintf(stderr, "claim interface %u failed: %s\n", op->intf, libusb_error_name(r));
            libusb_close(op->handle);
            op->handle = NULL;
            continue;
        }

        libusb_free_device_list(devs, 1);
        printf("Opened OpenPort 2.0 interface=%u ep_in=0x%02X ep_out=0x%02X\n", op->intf, op->ep_in, op->ep_out);
        return 0;
    }

    libusb_free_device_list(devs, 1);
    fprintf(stderr, "OpenPort 2.0 not found. Attach USB device to macOS, not the VM.\n");
    libusb_exit(op->ctx);
    return -1;
}

static void close_openport(openport_t *op)
{
    if (op->handle) {
        send_text(op, "atz\r\n", NULL);
        libusb_release_interface(op->handle, op->intf);
        libusb_close(op->handle);
    }
    if (op->ctx) libusb_exit(op->ctx);
}

static int openport_init(openport_t *op)
{
    if (send_text(op, "\r\n\r\nati\r\n", "ari main code version") != 0) return -1;
    if (send_text(op, "ata\r\n", NULL) != 0) return -1;

    if (send_text(op, "ato3 512 10400 0\r\n", NULL) != 0) return -1;
    if (send_text(op, "ats3 22 0\r\n", NULL) != 0) return -1;
    if (send_text(op, "ats3 3 1\r\n", NULL) != 0) return -1;
    if (send_text(op, "ats3 7 40\r\n", NULL) != 0) return -1;
    if (send_text(op, "ats3 10 110\r\n", NULL) != 0) return -1;
    if (send_text(op, "ats3 12 10\r\n", NULL) != 0) return -1;

    static const uint8_t filter[] = "atf3 1 64 4\r\n\0\0\0\0\0\0\0\0";
    if (send_expect(op, filter, (int)sizeof(filter) - 1, "arf3", 2000) != 0) return -1;

    return 0;
}

static void build_iso9141_obd(uint8_t sid, uint8_t pid, uint8_t out[6])
{
    uint8_t sum = 0;

    out[0] = 0x68;
    out[1] = 0x6A;
    out[2] = 0xF1;
    out[3] = sid;
    out[4] = pid;
    for (int i = 0; i < 5; i++) sum = (uint8_t)(sum + out[i]);
    out[5] = sum;
}

static int build_iso9141_request(uint8_t sid, int has_pid, uint8_t pid, uint8_t *out)
{
    uint8_t sum = 0;
    int len = has_pid ? 6 : 5;

    out[0] = 0x68;
    out[1] = 0x6A;
    out[2] = 0xF1;
    out[3] = sid;
    if (has_pid) out[4] = pid;
    for (int i = 0; i < len - 1; i++) sum = (uint8_t)(sum + out[i]);
    out[len - 1] = sum;
    return len;
}

static int build_iso9141_payload(const uint8_t *payload, int payload_len, uint8_t *out, int cap)
{
    uint8_t sum = 0;
    int len = payload_len + 4;

    if (payload_len <= 0 || len > cap) return -1;
    out[0] = 0x68;
    out[1] = 0x6A;
    out[2] = 0xF1;
    memcpy(out + 3, payload, payload_len);
    for (int i = 0; i < len - 1; i++) sum = (uint8_t)(sum + out[i]);
    out[len - 1] = sum;
    return len;
}

static int write_frame(openport_t *op, const uint8_t *frame, int len)
{
    uint8_t buf[128];
    int prefix_len = snprintf((char *)buf, sizeof(buf), "att3 %d 0\r\n", len);

    if (prefix_len <= 0 || prefix_len + len > (int)sizeof(buf)) return -1;
    memcpy(buf + prefix_len, frame, len);
    return bulk_write(op, buf, prefix_len + len, 2000);
}

static int five_baud_init(openport_t *op)
{
    uint8_t buf[BUF_LEN];

    if (bulk_write(op, (const uint8_t *)"atw3 51\r\n", 9, 5000) != 0) return -1;

    for (;;) {
        int n = bulk_read(op, buf, sizeof(buf), 5000);
        if (n <= 0) {
            fprintf(stderr, "five-baud init failed\n");
            return -1;
        }

        if (!contains(buf, n, "arw3")) {
            printf("Ignoring stale packet before FIVE_BAUD_INIT reply: ");
            print_hex(buf, n);
            printf("\n");
            continue;
        }

        printf("FIVE_BAUD_INIT reply: ");
        fwrite(buf, 1, n, stdout);
        if (n == 0 || buf[n - 1] != '\n') printf("\n");
        return 0;
    }
}

static int read_one_ecu_response_timeout(openport_t *op, uint8_t *out, int *out_len,
    unsigned int timeout_ms, int idle_reads)
{
    uint8_t buf[BUF_LEN];
    uint8_t msg[BUF_LEN];
    int msg_len = 0;
    int saw_msg = 0;

    *out_len = 0;
    while (idle_reads-- > 0) {
        int n = bulk_read(op, buf, sizeof(buf), timeout_ms);
        int processed = 0;

        if (n < 0) return -1;
        if (n == 0) continue;

        while (processed + 5 <= n) {
            uint8_t ch;
            uint8_t packet_len;
            uint8_t packet_type;
            int total;

            if (buf[processed] != 'a' || buf[processed + 1] != 'r') break;
            ch = buf[processed + 2];
            if (ch == 'o') {
                processed += 5;
                continue;
            }
            if (ch == 'e') {
                processed += n - processed;
                continue;
            }
            if (ch != '3') break;

            packet_len = buf[processed + 3];
            total = packet_len + 4;
            if (packet_len == 0 || processed + total > n) break;
            packet_type = (uint8_t)(buf[processed + 4] & ~0x02);

            if (packet_type == 0x00) {
                int payload_len = packet_len - 1;
                if (payload_len > 0 && msg_len + payload_len <= (int)sizeof(msg)) {
                    memcpy(msg + msg_len, buf + processed + 5, payload_len);
                    msg_len += payload_len;
                    saw_msg = 1;
                }
            } else if ((packet_type == 0x40 || packet_type == 0x44) && saw_msg) {
                memcpy(out, msg, msg_len);
                *out_len = msg_len;
                return 1;
            }

            processed += total;
        }
    }

    return 0;
}

static int read_one_ecu_response(openport_t *op, uint8_t *out, int *out_len)
{
    return read_one_ecu_response_timeout(op, out, out_len, 1000, 8);
}

static void query(openport_t *op, uint8_t sid, uint8_t pid, const char *label)
{
    uint8_t frame[6];
    uint8_t response[BUF_LEN];
    int response_len = 0;
    int r;

    build_iso9141_obd(sid, pid, frame);
    printf("\nQuery %s: ", label);
    print_hex(frame, sizeof(frame));
    printf("\n");

    if (write_frame(op, frame, sizeof(frame)) != 0) {
        printf("  Write failed.\n");
        return;
    }

    r = read_one_ecu_response(op, response, &response_len);
    if (r < 0) {
        printf("  Read failed.\n");
    } else if (r == 0) {
        printf("  No ECU response.\n");
    } else {
        printf("  RX: ");
        print_hex(response, response_len);
        printf("%s\n", checksum_ok(response, response_len) ? " checksum=OK" : " checksum=BAD");
        print_ascii_payload(response, response_len);
    }

    usleep(150000);
}

static int query_raw(openport_t *op, uint8_t sid, int has_pid, uint8_t pid,
    unsigned int timeout_ms, int idle_reads)
{
    uint8_t frame[6];
    uint8_t response[BUF_LEN];
    int frame_len;
    int response_len = 0;
    int responses = 0;

    frame_len = build_iso9141_request(sid, has_pid, pid, frame);
    printf("REQ service=%02X", sid);
    if (has_pid) printf(" pid=%02X", pid);
    else printf(" pid=--");
    printf(" frame=");
    print_hex(frame, frame_len);
    printf("\n");

    if (write_frame(op, frame, frame_len) != 0) {
        printf("ERR service=%02X", sid);
        if (has_pid) printf(" pid=%02X", pid);
        printf(" write_failed\n");
        return -1;
    }

    for (;;) {
        int r = read_one_ecu_response_timeout(op, response, &response_len, timeout_ms, idle_reads);
        if (r < 0) {
            printf("ERR service=%02X", sid);
            if (has_pid) printf(" pid=%02X", pid);
            printf(" read_failed\n");
            return responses ? responses : -1;
        }
        if (r == 0) break;

        responses++;
        printf("HIT service=%02X", sid);
        if (has_pid) printf(" pid=%02X", pid);
        else printf(" pid=--");
        if (response_len >= 5 && response[3] >= 0x40) {
            uint8_t actual_service = (uint8_t)(response[3] - 0x40);
            uint8_t actual_pid = response[4];
            printf(" actual_service=%02X actual_pid=%02X", actual_service, actual_pid);
            if (actual_service != sid || (has_pid && actual_pid != pid)) printf(" late_or_multiframe=1");
        }
        printf(" response=");
        print_hex(response, response_len);
        printf(" checksum=%s", checksum_ok(response, response_len) ? "OK" : "BAD");
        printf(" ascii=");
        for (int i = 0; i < response_len; i++) putchar(isprint(response[i]) ? response[i] : '.');
        printf("\n");
    }

    if (!responses) {
        printf("MISS service=%02X", sid);
        if (has_pid) printf(" pid=%02X", pid);
        else printf(" pid=--");
        printf("\n");
    }

    usleep(150000);
    return responses;
}

static void print_payload_ascii(const uint8_t *data, int len)
{
    for (int i = 0; i < len; i++) putchar(isprint(data[i]) ? data[i] : '.');
}

static const char *negative_response_name(uint8_t nrc)
{
    switch (nrc) {
        case 0x10: return "generalReject";
        case 0x11: return "serviceNotSupported";
        case 0x12: return "subFunctionNotSupported";
        case 0x13: return "incorrectMessageLengthOrInvalidFormat";
        case 0x21: return "busyRepeatRequest";
        case 0x22: return "conditionsNotCorrect";
        case 0x31: return "requestOutOfRange";
        case 0x33: return "securityAccessDenied";
        case 0x35: return "invalidKey";
        case 0x36: return "exceedNumberOfAttempts";
        case 0x37: return "requiredTimeDelayNotExpired";
        case 0x78: return "responsePending";
        default: return "unknown";
    }
}

static int query_payload_raw(openport_t *op, const uint8_t *payload, int payload_len,
    const char *label, unsigned int timeout_ms, int idle_reads, unsigned int pause_us)
{
    uint8_t frame[64];
    uint8_t response[BUF_LEN];
    int frame_len;
    int response_len = 0;
    int responses = 0;

    frame_len = build_iso9141_payload(payload, payload_len, frame, sizeof(frame));
    if (frame_len < 0) {
        printf("ERR label=\"%s\" invalid_payload_len=%d\n", label, payload_len);
        return -1;
    }

    printf("REQ label=\"%s\" payload=", label);
    print_hex(payload, payload_len);
    printf(" frame=");
    print_hex(frame, frame_len);
    printf("\n");

    if (write_frame(op, frame, frame_len) != 0) {
        printf("ERR label=\"%s\" write_failed\n", label);
        return -1;
    }

    for (;;) {
        int r = read_one_ecu_response_timeout(op, response, &response_len, timeout_ms, idle_reads);
        if (r < 0) {
            printf("ERR label=\"%s\" read_failed\n", label);
            return responses ? responses : -1;
        }
        if (r == 0) break;

        responses++;
        printf("HIT label=\"%s\"", label);
        if (response_len >= 4) {
            printf(" response_service=%02X", response[3]);
            if (response[3] == 0x7F && response_len >= 7) {
                printf(" negative_for=%02X nrc=%02X nrc_name=%s", response[4], response[5], negative_response_name(response[5]));
            } else if (response[3] == (uint8_t)(payload[0] + 0x40)) {
                printf(" positive_for=%02X", payload[0]);
            }
        }
        printf(" response=");
        print_hex(response, response_len);
        printf(" checksum=%s", checksum_ok(response, response_len) ? "OK" : "BAD");
        printf(" ascii=");
        print_payload_ascii(response, response_len);
        printf("\n");
    }

    if (!responses) printf("MISS label=\"%s\"\n", label);
    usleep(pause_us);
    return responses;
}

static void scan_pid_service(openport_t *op, uint8_t sid, const char *name)
{
    printf("\n=== SCAN service=%02X %s pid=00..FF ===\n", sid, name);
    for (int pid = 0; pid <= 0xFF; pid++) {
        query_raw(op, sid, 1, (uint8_t)pid, 120, 12);
    }
}

static void run_safe_obd_scan(openport_t *op)
{
    time_t now = time(NULL);

    printf("\n=== SAFE READ-ONLY GENERIC OBD SCAN ===\n");
    printf("timestamp=%ld\n", (long)now);
    printf("Skipping destructive/control services such as 04 Clear DTC and 08 Control Operation.\n");

    printf("\n=== SCAN DTC read services ===\n");
    query_raw(op, 0x03, 0, 0, 700, 3);
    query_raw(op, 0x07, 0, 0, 700, 3);
    query_raw(op, 0x0A, 0, 0, 700, 3);

    scan_pid_service(op, 0x01, "current powertrain data");
    scan_pid_service(op, 0x02, "freeze-frame data");
    scan_pid_service(op, 0x05, "oxygen sensor monitor data");
    scan_pid_service(op, 0x06, "on-board monitor data");
    scan_pid_service(op, 0x09, "vehicle information");

    printf("\n=== SCAN COMPLETE ===\n");
}

static void probe_service_pid_range(openport_t *op, uint8_t sid, const char *name,
    unsigned int timeout_ms, int idle_reads)
{
    printf("\n=== PROBE service=%02X %s pid=00..FF ===\n", sid, name);
    for (int pid = 0; pid <= 0xFF; pid++) {
        uint8_t payload[2] = { sid, (uint8_t)pid };
        char label[96];
        snprintf(label, sizeof(label), "%s %02X", name, pid);
        query_payload_raw(op, payload, sizeof(payload), label, timeout_ms, idle_reads, 90000);
    }
}

static void probe_kwp_1a_range(openport_t *op)
{
    printf("\n=== PROBE KWP/Honda service=1A ECU identification id=80..9F ===\n");
    for (int id = 0x80; id <= 0x9F; id++) {
        uint8_t payload[2] = { 0x1A, (uint8_t)id };
        char label[96];
        snprintf(label, sizeof(label), "KWP 1A ECU ID %02X", id);
        query_payload_raw(op, payload, sizeof(payload), label, 120, 6, 90000);
    }
}

static void probe_kwp_21_range(openport_t *op)
{
    printf("\n=== PROBE KWP/Honda service=21 local data id=00..FF ===\n");
    for (int id = 0; id <= 0xFF; id++) {
        uint8_t payload[2] = { 0x21, (uint8_t)id };
        char label[96];
        snprintf(label, sizeof(label), "KWP/Honda 21 local ID %02X", id);
        query_payload_raw(op, payload, sizeof(payload), label, 120, 6, 90000);
    }
}

static void probe_kwp_22_did(openport_t *op, uint16_t did)
{
    uint8_t payload[3] = { 0x22, (uint8_t)(did >> 8), (uint8_t)did };
    char label[96];

    snprintf(label, sizeof(label), "KWP/UDS 22 DID %04X", did);
    query_payload_raw(op, payload, sizeof(payload), label, 120, 6, 90000);
}

static void probe_kwp_22_ranges(openport_t *op)
{
    static const uint16_t common_dids[] = {
        0xF100, 0xF101, 0xF102, 0xF103, 0xF104, 0xF105, 0xF106, 0xF107,
        0xF108, 0xF109, 0xF10A, 0xF10B, 0xF10C, 0xF10D, 0xF10E, 0xF10F,
        0xF110, 0xF111, 0xF112, 0xF113, 0xF114, 0xF115, 0xF116, 0xF117,
        0xF118, 0xF119, 0xF11A, 0xF11B, 0xF11C, 0xF11D, 0xF11E, 0xF11F,
        0xF180, 0xF181, 0xF182, 0xF183, 0xF184, 0xF185, 0xF186, 0xF187,
        0xF188, 0xF189, 0xF18A, 0xF18B, 0xF18C, 0xF18D, 0xF18E, 0xF18F,
        0xF190, 0xF191, 0xF192, 0xF193, 0xF194, 0xF195, 0xF196, 0xF197,
        0xF198, 0xF199, 0xF19A, 0xF19B, 0xF19C, 0xF19D, 0xF19E, 0xF19F,
    };

    printf("\n=== PROBE KWP/UDS service=22 common identification DIDs ===\n");
    for (size_t i = 0; i < sizeof(common_dids) / sizeof(common_dids[0]); i++) {
        probe_kwp_22_did(op, common_dids[i]);
    }

    printf("\n=== PROBE KWP/UDS service=22 DID 0000..00FF ===\n");
    for (int did = 0x0000; did <= 0x00FF; did++) {
        probe_kwp_22_did(op, (uint16_t)did);
    }
}

static void probe_read_dtc_candidates(openport_t *op)
{
    static const uint8_t p17_00[] = { 0x17, 0x00 };
    static const uint8_t p17_ff[] = { 0x17, 0xFF };
    static const uint8_t p18_00_ff_00[] = { 0x18, 0x00, 0xFF, 0x00 };
    static const uint8_t p18_ff_ff_00[] = { 0x18, 0xFF, 0xFF, 0x00 };
    static const uint8_t p19_02_ff[] = { 0x19, 0x02, 0xFF };
    static const uint8_t p19_0a[] = { 0x19, 0x0A };

    printf("\n=== PROBE read-only DTC candidate services ===\n");
    query_payload_raw(op, p17_00, sizeof(p17_00), "KWP 17 read DTC status 00", 200, 5, 90000);
    query_payload_raw(op, p17_ff, sizeof(p17_ff), "KWP 17 read DTC status FF", 200, 5, 90000);
    query_payload_raw(op, p18_00_ff_00, sizeof(p18_00_ff_00), "KWP 18 read DTC by status 00", 200, 5, 90000);
    query_payload_raw(op, p18_ff_ff_00, sizeof(p18_ff_ff_00), "KWP 18 read DTC by status FF", 200, 5, 90000);
    query_payload_raw(op, p19_02_ff, sizeof(p19_02_ff), "UDS 19 02 read DTC by status mask FF", 200, 5, 90000);
    query_payload_raw(op, p19_0a, sizeof(p19_0a), "UDS 19 0A report supported DTC", 200, 5, 90000);
}

static void run_large_probe(openport_t *op)
{
    time_t now = time(NULL);

    printf("\n=== LARGE READ-ONLY ISO9141/K-LINE PROBE ===\n");
    printf("timestamp=%ld\n", (long)now);
    printf("Safety: this probe only sends read/status services. It skips clear-DTC, reset, security, write, output-control, routine-control, and session-control services.\n");

    printf("\n=== GENERIC OBD read/status services ===\n");
    query_raw(op, 0x03, 0, 0, 700, 3);
    query_raw(op, 0x07, 0, 0, 700, 3);
    query_raw(op, 0x0A, 0, 0, 700, 3);
    probe_service_pid_range(op, 0x01, "OBD 01 current data", 120, 8);
    probe_service_pid_range(op, 0x02, "OBD 02 freeze frame", 120, 8);
    probe_service_pid_range(op, 0x05, "OBD 05 oxygen monitor", 120, 8);
    probe_service_pid_range(op, 0x06, "OBD 06 monitor", 120, 8);
    probe_service_pid_range(op, 0x09, "OBD 09 vehicle info", 120, 8);

    probe_kwp_1a_range(op);
    probe_kwp_21_range(op);
    probe_kwp_22_ranges(op);
    probe_read_dtc_candidates(op);

    printf("\n=== LARGE PROBE COMPLETE ===\n");
}

int main(int argc, char **argv)
{
    openport_t op;
    uint8_t wake[6];
    int scan = 0;
    int probe = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--scan") == 0) scan = 1;
        else if (strcmp(argv[i], "--probe") == 0) probe = 1;
        else {
            fprintf(stderr, "Usage: %s [--scan|--probe]\n", argv[0]);
            return 2;
        }
    }

    if (scan && probe) {
        fprintf(stderr, "Use only one mode at a time: --scan or --probe\n");
        return 2;
    }

    printf("OpenPort 2.0 macOS ISO9141 Mode 09 tester\n");
    printf("Key ON, engine OFF. Close VM apps that may own the OpenPort.\n\n");

    if (open_openport(&op) != 0) return 1;
    drain_usb(&op, 50);

    if (openport_init(&op) != 0) {
        close_openport(&op);
        return 1;
    }

    build_iso9141_obd(0x01, 0x00, wake);
    printf("\nPre-init probe Mode 01 PID 00 wake: ");
    print_hex(wake, sizeof(wake));
    printf("\n");
    write_frame(&op, wake, sizeof(wake));
    drain_usb(&op, 50);

    if (five_baud_init(&op) != 0) {
        close_openport(&op);
        return 1;
    }

    if (scan) {
        run_safe_obd_scan(&op);
        close_openport(&op);
        return 0;
    }

    if (probe) {
        run_large_probe(&op);
        close_openport(&op);
        return 0;
    }

    query(&op, 0x01, 0x04, "Mode 01 PID 04 calculated load");
    query(&op, 0x01, 0x05, "Mode 01 PID 05 coolant temp");
    query(&op, 0x01, 0x0C, "Mode 01 PID 0C RPM");
    query(&op, 0x01, 0x0D, "Mode 01 PID 0D vehicle speed");
    query(&op, 0x01, 0x0F, "Mode 01 PID 0F intake air temp");
    query(&op, 0x01, 0x11, "Mode 01 PID 11 throttle position");
    query(&op, 0x01, 0x00, "Mode 01 PID 00 supported PIDs");
    query(&op, 0x09, 0x00, "Mode 09 PID 00 supported info PIDs");
    query(&op, 0x09, 0x02, "Mode 09 PID 02 VIN");
    query(&op, 0x09, 0x04, "Mode 09 PID 04 calibration ID");
    query(&op, 0x09, 0x06, "Mode 09 PID 06 CVN");
    query(&op, 0x09, 0x08, "Mode 09 PID 08 supported by ECU");
    query(&op, 0x09, 0x0B, "Mode 09 PID 0B supported by ECU");
    query(&op, 0x09, 0x0C, "Mode 09 PID 0C supported by ECU");
    query(&op, 0x09, 0x0D, "Mode 09 PID 0D supported by ECU");
    query(&op, 0x09, 0x0E, "Mode 09 PID 0E supported by ECU");

    close_openport(&op);
    return 0;
}
