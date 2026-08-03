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

int main(int argc, char **argv)
{
    openport_t op;
    uint8_t wake[6];
    int scan = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--scan") == 0) scan = 1;
        else {
            fprintf(stderr, "Usage: %s [--scan]\n", argv[0]);
            return 2;
        }
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
