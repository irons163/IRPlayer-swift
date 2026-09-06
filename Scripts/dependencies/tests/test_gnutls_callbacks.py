#!/usr/bin/env python3
"""Compile and execute focused tests against functions from tls_gnutls.c."""

from __future__ import annotations

import argparse
import re
import subprocess
import tempfile
from pathlib import Path


def extract_function(source: str, name: str) -> str:
    match = re.search(rf"^static [^\n]*\b{re.escape(name)}\s*\(", source, re.MULTILINE)
    if not match:
        raise RuntimeError(f"unable to find {name}")
    brace = source.find("{", match.start())
    if brace < 0:
        raise RuntimeError(f"unable to find body for {name}")
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[match.start() : index + 1]
    raise RuntimeError(f"unterminated body for {name}")


HARNESS_PREFIX = r'''
#include <assert.h>
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/types.h>

#define AVERROR(e) (-(e))
#define AVERROR_EXIT (-12345)
#define AV_LOG_ERROR 16
#define AV_LOG_WARNING 24
#define GNUTLS_CERT_INVALID 2u
#define GNUTLS_CRT_X509 1
#define GNUTLS_X509_FMT_DER 0
#define GNUTLS_E_AGAIN (-10)
#define GNUTLS_E_INTERRUPTED (-11)
#define GNUTLS_E_PREMATURE_TERMINATION (-12)
#define GNUTLS_E_WARNING_ALERT_RECEIVED (-13)
#define av_err2str(error) "mock av error"

typedef void *gnutls_transport_ptr_t;
typedef void *gnutls_session_t;
typedef void *gnutls_x509_crt_t;
typedef struct gnutls_datum_t {
    unsigned char *data;
    unsigned int size;
} gnutls_datum_t;

typedef struct TLSShared {
    int verify;
    int listen;
    char *host;
    void *tcp;
} TLSShared;

typedef struct TLSContext {
    TLSShared tls_shared;
    gnutls_session_t session;
    int io_err;
} TLSContext;

typedef struct URLContext {
    void *priv_data;
} URLContext;

static int mock_read_ret;
static int mock_write_ret;
static int mock_verify_ret;
static unsigned int mock_status;
static int mock_cert_type = GNUTLS_CRT_X509;
static int mock_list_present = 1;
static unsigned int mock_list_size = 1;
static int mock_init_ret;
static int mock_import_ret;
static int mock_hostname_ret = 1;
static int mock_deinit_count;
static unsigned char mock_der[] = { 1 };
static gnutls_datum_t mock_list[] = { { mock_der, sizeof(mock_der) } };

static int ffurl_read(void *tcp, void *buf, size_t len)
{
    (void)tcp;
    (void)buf;
    (void)len;
    return mock_read_ret;
}

static int ffurl_write(void *tcp, const void *buf, size_t len)
{
    (void)tcp;
    (void)buf;
    (void)len;
    return mock_write_ret;
}

static int gnutls_certificate_verify_peers2(gnutls_session_t session,
                                             unsigned int *status)
{
    (void)session;
    *status = mock_status;
    return mock_verify_ret;
}

static int gnutls_certificate_type_get(gnutls_session_t session)
{
    (void)session;
    return mock_cert_type;
}

static const gnutls_datum_t *gnutls_certificate_get_peers(
    gnutls_session_t session, unsigned int *size)
{
    (void)session;
    *size = mock_list_size;
    return mock_list_present ? mock_list : NULL;
}

static int gnutls_x509_crt_init(gnutls_x509_crt_t *cert)
{
    if (mock_init_ret >= 0)
        *cert = (void *)1;
    return mock_init_ret;
}

static int gnutls_x509_crt_import(gnutls_x509_crt_t cert,
                                  const gnutls_datum_t *data, int format)
{
    assert(cert != NULL);
    assert(data == &mock_list[0]);
    assert(format == GNUTLS_X509_FMT_DER);
    return mock_import_ret;
}

static int gnutls_x509_crt_check_hostname(gnutls_x509_crt_t cert,
                                           const char *hostname)
{
    assert(cert != NULL);
    assert(hostname != NULL);
    return mock_hostname_ret;
}

static void gnutls_x509_crt_deinit(gnutls_x509_crt_t cert)
{
    assert(cert != NULL);
    mock_deinit_count++;
}

static const char *gnutls_strerror(int error)
{
    (void)error;
    return "mock error";
}

static void av_log(void *context, int level, const char *format, ...)
{
    (void)context;
    (void)level;
    (void)format;
}
'''


HARNESS_MAIN = r'''
static void reset_verifier(void)
{
    mock_verify_ret = 0;
    mock_status = 0;
    mock_cert_type = GNUTLS_CRT_X509;
    mock_list_present = 1;
    mock_list_size = 1;
    mock_init_ret = 0;
    mock_import_ret = 0;
    mock_hostname_ret = 1;
    mock_deinit_count = 0;
}

int main(void)
{
    TLSContext context = { 0 };
    URLContext url = { &context };
    unsigned char byte = 0;

    mock_read_ret = AVERROR_EXIT;
    errno = 0;
    assert(gnutls_url_pull(&context, &byte, 1) == -1);
    assert(errno == EINTR);
    assert(context.io_err == AVERROR_EXIT);
    assert(print_tls_error(&url, GNUTLS_E_INTERRUPTED) == AVERROR_EXIT);
    assert(context.io_err == 0);

    context.io_err = 0;
    mock_write_ret = AVERROR_EXIT;
    errno = 0;
    assert(gnutls_url_push(&context, &byte, 1) == -1);
    assert(errno == EINTR);
    assert(context.io_err == AVERROR_EXIT);
    assert(print_tls_error(&url, GNUTLS_E_INTERRUPTED) == AVERROR_EXIT);
    assert(context.io_err == 0);

    mock_read_ret = AVERROR(EAGAIN);
    errno = 0;
    assert(gnutls_url_pull(&context, &byte, 1) == -1);
    assert(errno == EAGAIN);
    assert(context.io_err == 0);
    assert(print_tls_error(&url, GNUTLS_E_AGAIN) == AVERROR(EAGAIN));

    mock_write_ret = AVERROR(EAGAIN);
    errno = 0;
    assert(gnutls_url_push(&context, &byte, 1) == -1);
    assert(errno == EAGAIN);
    assert(context.io_err == 0);

    mock_read_ret = AVERROR(EIO);
    assert(gnutls_url_pull(&context, &byte, 1) == -1);
    assert(context.io_err == AVERROR(EIO));
    assert(print_tls_error(&url, GNUTLS_E_PREMATURE_TERMINATION) == AVERROR(EIO));
    assert(context.io_err == 0);

    mock_write_ret = AVERROR(EPIPE);
    assert(gnutls_url_push(&context, &byte, 1) == -1);
    assert(context.io_err == AVERROR(EPIPE));
    assert(print_tls_error(&url, GNUTLS_E_PREMATURE_TERMINATION) == AVERROR(EPIPE));
    assert(context.io_err == 0);

    mock_read_ret = 1;
    mock_write_ret = 1;
    assert(gnutls_url_pull(&context, &byte, 1) == 1);
    assert(gnutls_url_push(&context, &byte, 1) == 1);
    mock_read_ret = 0;
    assert(gnutls_url_pull(&context, &byte, 1) == 0);

    context.tls_shared.verify = 1;
    context.tls_shared.listen = 0;
    assert(tls_should_verify_peer(&context.tls_shared));
    context.tls_shared.listen = 1;
    assert(!tls_should_verify_peer(&context.tls_shared));
    context.tls_shared.listen = 0;
    context.tls_shared.verify = 0;
    assert(!tls_should_verify_peer(&context.tls_shared));

    context.tls_shared.host = "example.test";
    reset_verifier();
    assert(tls_verify_gnutls_peer(&url) == 0);
    assert(mock_deinit_count == 1);

    reset_verifier();
    mock_verify_ret = -1;
    assert(tls_verify_gnutls_peer(&url) == AVERROR(EIO));
    assert(mock_deinit_count == 0);

    reset_verifier();
    mock_cert_type = 999;
    assert(tls_verify_gnutls_peer(&url) == AVERROR(EIO));
    assert(mock_deinit_count == 0);

    reset_verifier();
    mock_list_present = 0;
    assert(tls_verify_gnutls_peer(&url) == AVERROR(EIO));
    assert(mock_deinit_count == 0);

    reset_verifier();
    mock_list_size = 0;
    assert(tls_verify_gnutls_peer(&url) == AVERROR(EIO));
    assert(mock_deinit_count == 0);

    reset_verifier();
    mock_init_ret = -1;
    assert(tls_verify_gnutls_peer(&url) == AVERROR(EIO));
    assert(mock_deinit_count == 0);

    reset_verifier();
    mock_import_ret = -1;
    assert(tls_verify_gnutls_peer(&url) == AVERROR(EIO));
    assert(mock_deinit_count == 1);

    reset_verifier();
    mock_hostname_ret = 0;
    assert(tls_verify_gnutls_peer(&url) == AVERROR(EIO));
    assert(mock_deinit_count == 1);

    reset_verifier();
    mock_status = GNUTLS_CERT_INVALID;
    assert(tls_verify_gnutls_peer(&url) == AVERROR(EIO));
    assert(mock_deinit_count == 0);

    puts("gnutls callback and peer-verifier tests passed");
    return 0;
}
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True,
                        help="path to the patched libavformat/tls_gnutls.c")
    parser.add_argument("--cc", default="clang")
    args = parser.parse_args()

    source = args.source.read_text(encoding="utf-8")
    functions = "\n\n".join(
        extract_function(source, name)
        for name in (
            "print_tls_error",
            "gnutls_url_pull",
            "gnutls_url_push",
            "tls_should_verify_peer",
            "tls_verify_gnutls_peer",
        )
    )
    harness = HARNESS_PREFIX + "\n" + functions + "\n" + HARNESS_MAIN

    with tempfile.TemporaryDirectory(prefix="irplayer-gnutls-test-") as directory:
        root = Path(directory)
        c_file = root / "test.c"
        executable = root / "test"
        c_file.write_text(harness, encoding="utf-8")
        subprocess.run(
            [args.cc, "-std=c11", "-Wall", "-Wextra", "-Werror",
             str(c_file), "-o", str(executable)],
            check=True,
        )
        subprocess.run([str(executable)], check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
