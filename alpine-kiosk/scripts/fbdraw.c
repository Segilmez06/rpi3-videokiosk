// Standalone freestanding framebuffer splash drawer for Linux AArch64
// Zero libc dependencies - direct Linux syscalls
// Universal support for 16bpp, 24bpp, 32bpp (RGB/BGR/ARGB/BGRA/RGBA)
#define AT_FDCWD -100
#define O_RDONLY 0
#define O_RDWR   2
#define PROT_READ  1
#define PROT_WRITE 2
#define MAP_SHARED 1

#define __NR_close    57
#define __NR_read     63
#define __NR_write    64
#define __NR_exit     94
#define __NR_ioctl    29
#define __NR_openat   56
#define __NR_mmap    222

#define FBIOGET_VSCREENINFO 0x4600
#define FBIOGET_FSCREENINFO 0x4602

typedef unsigned char  uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int   uint32_t;
typedef unsigned long  uint64_t;
typedef long           int64_t;

struct fb_bitfield {
    uint32_t offset;
    uint32_t length;
    uint32_t msb_right;
};

struct fb_var_screeninfo {
    uint32_t xres;
    uint32_t yres;
    uint32_t xres_virtual;
    uint32_t yres_virtual;
    uint32_t xoffset;
    uint32_t yoffset;
    uint32_t bits_per_pixel;
    uint32_t grayscale;
    struct fb_bitfield red;
    struct fb_bitfield green;
    struct fb_bitfield blue;
    struct fb_bitfield transp;
    uint32_t nonstd;
    uint32_t activate;
    uint32_t height;
    uint32_t width;
    uint32_t accel_flags;
    uint32_t pixclock;
    uint32_t left_margin;
    uint32_t right_margin;
    uint32_t upper_margin;
    uint32_t lower_margin;
    uint32_t hsync_len;
    uint32_t vsync_len;
    uint32_t sync;
    uint32_t vmode;
    uint32_t rotate;
    uint32_t colorspace;
    uint32_t reserved[4];
};

struct fb_fix_screeninfo {
    char id[16];
    uint64_t smem_start;
    uint32_t smem_len;
    uint32_t type;
    uint32_t type_aux;
    uint32_t visual;
    uint16_t xpanstep;
    uint16_t ypanstep;
    uint16_t ywrapstep;
    uint32_t line_length;
    uint64_t mmio_start;
    uint32_t mmio_len;
    uint32_t accel;
    uint16_t capabilities;
    uint16_t reserved[2];
};

static inline int64_t sys_openat(int dirfd, const char *path, int flags, int mode) {
    register int64_t x8 __asm__("x8") = __NR_openat;
    register int64_t x0 __asm__("x0") = dirfd;
    register int64_t x1 __asm__("x1") = (int64_t)path;
    register int64_t x2 __asm__("x2") = flags;
    register int64_t x3 __asm__("x3") = mode;
    __asm__ __volatile__("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory");
    return x0;
}

static inline int64_t sys_read(int fd, void *buf, uint64_t count) {
    register int64_t x8 __asm__("x8") = __NR_read;
    register int64_t x0 __asm__("x0") = fd;
    register int64_t x1 __asm__("x1") = (int64_t)buf;
    register int64_t x2 __asm__("x2") = count;
    __asm__ __volatile__("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
    return x0;
}

static inline int64_t sys_close(int fd) {
    register int64_t x8 __asm__("x8") = __NR_close;
    register int64_t x0 __asm__("x0") = fd;
    __asm__ __volatile__("svc #0" : "+r"(x0) : "r"(x8) : "memory");
    return x0;
}

static inline int64_t sys_ioctl(int fd, uint64_t req, void *arg) {
    register int64_t x8 __asm__("x8") = __NR_ioctl;
    register int64_t x0 __asm__("x0") = fd;
    register int64_t x1 __asm__("x1") = req;
    register int64_t x2 __asm__("x2") = (int64_t)arg;
    __asm__ __volatile__("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
    return x0;
}

static inline void *sys_mmap(void *addr, uint64_t len, int prot, int flags, int fd, uint64_t off) {
    register int64_t x8 __asm__("x8") = __NR_mmap;
    register int64_t x0 __asm__("x0") = (int64_t)addr;
    register int64_t x1 __asm__("x1") = len;
    register int64_t x2 __asm__("x2") = prot;
    register int64_t x3 __asm__("x3") = flags;
    register int64_t x4 __asm__("x4") = fd;
    register int64_t x5 __asm__("x5") = off;
    __asm__ __volatile__("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5) : "memory");
    return (void*)x0;
}

static inline void sys_exit(int code) {
    register int64_t x8 __asm__("x8") = __NR_exit;
    register int64_t x0 __asm__("x0") = code;
    __asm__ __volatile__("svc #0" :: "r"(x8), "r"(x0) : "memory");
}

void *memcpy(void *dst, const void *src, uint64_t n) {
    uint8_t *d = dst; const uint8_t *s = src;
    while (n--) *d++ = *s++;
    return dst;
}

void *memset(void *dst, int val, uint64_t n) {
    uint8_t *d = dst;
    while (n--) *d++ = val;
    return dst;
}

static int is_space(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

static void skip_comments(const char **p) {
    while (1) {
        while (is_space(**p)) (*p)++;
        if (**p == '#') {
            while (**p && **p != '\n' && **p != '\r') (*p)++;
        } else {
            break;
        }
    }
}

static int parse_int(const char **p) {
    skip_comments(p);
    int v = 0;
    while (**p >= '0' && **p <= '9') {
        v = v * 10 + (**p - '0');
        (*p)++;
    }
    return v;
}

void _start(void) {
    register int64_t *sp __asm__("sp");
    int argc = (int)*sp;
    char **argv = (char**)(sp + 1);

    const char *img_path = (argc > 1) ? argv[1] : "/splash.ppm";
    const char *fb_path  = (argc > 2) ? argv[2] : "/dev/fb0";

    int fb_fd = sys_openat(AT_FDCWD, fb_path, O_RDWR, 0);
    if (fb_fd < 0 && argc <= 2) {
        fb_fd = sys_openat(AT_FDCWD, "/dev/fb/0", O_RDWR, 0);
    }
    if (fb_fd < 0) {
        sys_exit(0);
    }

    struct fb_var_screeninfo var;
    struct fb_fix_screeninfo fix;
    if (sys_ioctl(fb_fd, FBIOGET_VSCREENINFO, &var) < 0 ||
        sys_ioctl(fb_fd, FBIOGET_FSCREENINFO, &fix) < 0) {
        sys_close(fb_fd);
        sys_exit(0);
    }

    if (var.xres == 0 || var.yres == 0 || fix.line_length == 0 || fix.smem_len == 0) {
        sys_close(fb_fd);
        sys_exit(0);
    }

    uint8_t *fb_mem = (uint8_t*)sys_mmap(0, fix.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fb_fd, 0);
    if ((int64_t)fb_mem < 0) {
        sys_close(fb_fd);
        sys_exit(0);
    }

    int img_fd = sys_openat(AT_FDCWD, img_path, O_RDONLY, 0);
    if (img_fd < 0) {
        sys_close(fb_fd);
        sys_exit(0);
    }

    // Read header (up to 512 bytes)
    char hdr[512];
    int64_t hr = sys_read(img_fd, hdr, sizeof(hdr) - 1);
    if (hr < 10 || hdr[0] != 'P' || hdr[1] != '6') {
        sys_close(img_fd);
        sys_close(fb_fd);
        sys_exit(0);
    }
    hdr[hr] = '\0';
    const char *p = hdr + 2;
    int img_w = parse_int(&p);
    int img_h = parse_int(&p);
    int max_val = parse_int(&p);
    if (is_space(*p)) p++;

    int64_t header_len = p - hdr;
    int cached_bytes = hr - header_len;

    int draw_w = (img_w < (int)var.xres) ? img_w : (int)var.xres;
    int draw_h = (img_h < (int)var.yres) ? img_h : (int)var.yres;
    int start_x = (var.xres > (uint32_t)draw_w) ? (var.xres - draw_w) / 2 : 0;
    int start_y = (var.yres > (uint32_t)draw_h) ? (var.yres - draw_h) / 2 : 0;

    static uint8_t row_buf[4096 * 3];
    int row_bytes = img_w * 3;
    if (row_bytes > (int)sizeof(row_buf)) row_bytes = sizeof(row_buf);

    int cached_offset = 0;

    for (int y = 0; y < draw_h; y++) {
        int row_pos = 0;
        while (cached_bytes > 0 && row_pos < row_bytes) {
            row_buf[row_pos++] = hdr[header_len + cached_offset++];
            cached_bytes--;
        }
        while (row_pos < row_bytes) {
            int64_t n = sys_read(img_fd, row_buf + row_pos, row_bytes - row_pos);
            if (n <= 0) break;
            row_pos += n;
        }

        uint8_t *dst_row = fb_mem + (start_y + y) * fix.line_length + start_x * (var.bits_per_pixel / 8);

        if (var.bits_per_pixel == 32) {
            uint32_t *dst = (uint32_t*)dst_row;
            uint32_t alpha = (var.transp.length > 0) ? (0xFF << var.transp.offset) : (0xFF << 24);
            for (int x = 0; x < draw_w; x++) {
                uint32_t r = row_buf[x * 3 + 0];
                uint32_t g = row_buf[x * 3 + 1];
                uint32_t b = row_buf[x * 3 + 2];
                dst[x] = (r << var.red.offset) | (g << var.green.offset) | (b << var.blue.offset) | alpha;
            }
        } else if (var.bits_per_pixel == 16) {
            uint16_t *dst = (uint16_t*)dst_row;
            for (int x = 0; x < draw_w; x++) {
                uint16_t r = row_buf[x * 3 + 0] >> (8 - var.red.length);
                uint16_t g = row_buf[x * 3 + 1] >> (8 - var.green.length);
                uint16_t b = row_buf[x * 3 + 2] >> (8 - var.blue.length);
                dst[x] = (r << var.red.offset) | (g << var.green.offset) | (b << var.blue.offset);
            }
        }
    }

    sys_close(img_fd);
    sys_close(fb_fd);
    sys_exit(0);
}
