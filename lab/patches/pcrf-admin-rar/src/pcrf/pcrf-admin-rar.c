/* DRAFT, NOT COMPILED, NOT TESTED — WIP v1 2026-11-06 20:21:01 +07 */
/*
 * Lab-only admin trigger. Unix socket + pre-shared token; no network listener.
 * Request: <token> <IMSI> [APN]\n. Response: matched/pushed/no-active-session.
 */
#include "pcrf-context.h"
#include "pcrf-fd-path.h"
#include "pcrf-admin-rar.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <poll.h>
#include <fcntl.h>
#include <ctype.h>
#define ADMIN_SOCKET "/run/open5gs-pcrf-admin.sock"
static int admin_fd = -1;
static int write_all(int fd, const char *s) {
    size_t left = strlen(s);
    while (left) { ssize_t n = write(fd, s, left); if (n <= 0) return -1; s += n; left -= n; }
    return 0;
}
int pcrf_admin_rar_init(void)
{
    struct sockaddr_un addr;
    int flags;
    if (!getenv("PCRF_ADMIN_TOKEN") || getenv("PCRF_ADMIN_TOKEN")[0] == '\0') {
        ogs_error("PCRF_ADMIN_TOKEN must be set; admin RAR disabled");
        return OGS_ERROR;
    }
    admin_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (admin_fd < 0) return OGS_ERROR;
    unlink(ADMIN_SOCKET);
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strcpy(addr.sun_path, ADMIN_SOCKET);
    if (bind(admin_fd, (struct sockaddr *)&addr, sizeof(addr)) != 0 ||
            chmod(ADMIN_SOCKET, 0600) != 0 || listen(admin_fd, 4) != 0) {
        ogs_error("pcrf admin socket setup failed: %s", strerror(errno));
        close(admin_fd); admin_fd = -1; return OGS_ERROR;
    }
    flags = fcntl(admin_fd, F_GETFD); fcntl(admin_fd, F_SETFD, flags | FD_CLOEXEC);
    ogs_info("Authenticated PCRF admin RAR trigger ready on %s", ADMIN_SOCKET);
    return OGS_OK;
}
void pcrf_admin_rar_final(void)
{
    if (admin_fd >= 0) close(admin_fd);
    admin_fd = -1; unlink(ADMIN_SOCKET);
}
void pcrf_admin_rar_dispatch(void)
{
    struct pollfd pfd = { .fd = admin_fd, .events = POLLIN };
    int fd, matched = 0, pushed = 0;
    char buf[256], *save = NULL, *token, *imsi, *apn, *ue_ip, *end;
    const char *secret = getenv("PCRF_ADMIN_TOKEN");
    if (admin_fd < 0 || poll(&pfd, 1, 0) <= 0 || !(pfd.revents & POLLIN)) return;
    fd = accept4(admin_fd, NULL, NULL, SOCK_CLOEXEC);
    if (fd < 0) return;
    ssize_t len = read(fd, buf, sizeof(buf)-1);
    if (len <= 0) { close(fd); return; }
    buf[len] = '\0';
    token = strtok_r(buf, " \t\r\n", &save);
    imsi = strtok_r(NULL, " \t\r\n", &save);
    apn = strtok_r(NULL, " \t\r\n", &save);
    ue_ip = strtok_r(NULL, " \t\r\n", &save);
    if (!secret || !token || !imsi || strcmp(secret, token) != 0)
        { write_all(fd, "unauthorized\n"); close(fd); return; }
    if (!apn || !ue_ip || inet_addr(ue_ip) == INADDR_NONE)
        { write_all(fd, "usage: token IMSI APN UE_IPV4\n"); close(fd); return; }
    if (strlen(imsi) < 5 || strlen(imsi) > 15)
        { write_all(fd, "invalid-imsi\n"); close(fd); return; }
    for (end = imsi; *end; end++) if (!isdigit((unsigned char)*end))
        { write_all(fd, "invalid-imsi\n"); close(fd); return; }
    {
        uint8_t *sid = pcrf_sess_find_by_ipv4(inet_addr(ue_ip));
        if (sid && pcrf_gx_send_pcc_rar(sid, imsi, apn, &matched) == OGS_OK) pushed++;
    }
    if (!matched) write_all(fd, "no-active-session\n");
    else { char response[80]; snprintf(response, sizeof(response),
            "pushed=%d matched=%d\n", pushed, matched); write_all(fd, response); }
    close(fd);
}
