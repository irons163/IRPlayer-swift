#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include <libavcodec/packet.h>
#include <libavformat/avformat.h>
#include <libavformat/avio.h>
#include <libavutil/dict.h>
#include <libavutil/error.h>
#include <libavutil/log.h>
#include <libavutil/mem.h>
#include <libavutil/time.h>

typedef struct ProbeDeadline {
    int64_t expires_at_us;
    int interrupted;
} ProbeDeadline;

static int interrupt_if_expired(void *opaque)
{
    ProbeDeadline *deadline = opaque;

    if (av_gettime_relative() < deadline->expires_at_us)
        return 0;
    deadline->interrupted = 1;
    return 1;
}

static int parse_positive_int(const char *value, int *result)
{
    char *end = NULL;
    long parsed;

    errno = 0;
    parsed = strtol(value, &end, 10);
    if (errno || !end || *end || parsed <= 0 || parsed > INT32_MAX)
        return -1;
    *result = (int)parsed;
    return 0;
}

static void usage(const char *program)
{
    fprintf(stderr,
            "usage: %s URL [--ca-file PATH] [--deadline-ms N] "
            "[--read-bytes N] [--read-iterations N] [--max-packets N] "
            "[--headers VALUE] [--reconnect] [--reconnect-streamed] "
            "[--http-persistent 0|1] [--http-multiple 0|1] "
            "[--allow-http-root] "
            "[--operation avio|demux] [--verification forced|default]\n",
            program);
}

int main(int argc, char **argv)
{
    const char *url;
    const char *ca_file = NULL;
    const char *headers = NULL;
    const char *operation = "avio";
    const char *verification = "forced";
    const char *http_persistent = NULL;
    const char *http_multiple = NULL;
    int deadline_ms = 5000;
    int read_bytes = 1;
    int read_iterations = 1;
    int max_packets = 8;
    int reconnect = 0;
    int reconnect_streamed = 0;
    int allow_http_root = 0;
    ProbeDeadline deadline;
    AVIOInterruptCB interrupt_callback;
    AVDictionary *options = NULL;
    AVIOContext *io = NULL;
    AVFormatContext *format = NULL;
    AVPacket *packet = NULL;
    uint8_t *buffer = NULL;
    char error[AV_ERROR_MAX_STRING_SIZE] = { 0 };
    int open_ret = AVERROR_UNKNOWN;
    int stream_info_ret = 0;
    int read_ret = 0;
    int close_ret = 0;
    int bytes_read = 0;
    int packet_count = 0;
    int cancel_propagated;
    int failure_ret;
    int i;

    if (argc < 2) {
        usage(argv[0]);
        return 64;
    }
    url = argv[1];
    for (i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "--ca-file") && i + 1 < argc) {
            ca_file = argv[++i];
        } else if (!strcmp(argv[i], "--deadline-ms") && i + 1 < argc) {
            if (parse_positive_int(argv[++i], &deadline_ms) < 0) {
                usage(argv[0]);
                return 64;
            }
        } else if (!strcmp(argv[i], "--read-bytes") && i + 1 < argc) {
            if (parse_positive_int(argv[++i], &read_bytes) < 0) {
                usage(argv[0]);
                return 64;
            }
        } else if (!strcmp(argv[i], "--read-iterations") && i + 1 < argc) {
            if (parse_positive_int(argv[++i], &read_iterations) < 0) {
                usage(argv[0]);
                return 64;
            }
        } else if (!strcmp(argv[i], "--max-packets") && i + 1 < argc) {
            if (parse_positive_int(argv[++i], &max_packets) < 0) {
                usage(argv[0]);
                return 64;
            }
        } else if (!strcmp(argv[i], "--headers") && i + 1 < argc) {
            headers = argv[++i];
        } else if (!strcmp(argv[i], "--reconnect")) {
            reconnect = 1;
        } else if (!strcmp(argv[i], "--reconnect-streamed")) {
            reconnect_streamed = 1;
        } else if (!strcmp(argv[i], "--allow-http-root")) {
            allow_http_root = 1;
        } else if (!strcmp(argv[i], "--http-persistent") && i + 1 < argc) {
            http_persistent = argv[++i];
            if (strcmp(http_persistent, "0") && strcmp(http_persistent, "1")) {
                usage(argv[0]);
                return 64;
            }
        } else if (!strcmp(argv[i], "--http-multiple") && i + 1 < argc) {
            http_multiple = argv[++i];
            if (strcmp(http_multiple, "0") && strcmp(http_multiple, "1")) {
                usage(argv[0]);
                return 64;
            }
        } else if (!strcmp(argv[i], "--operation") && i + 1 < argc) {
            operation = argv[++i];
            if (strcmp(operation, "avio") && strcmp(operation, "demux")) {
                usage(argv[0]);
                return 64;
            }
        } else if (!strcmp(argv[i], "--verification") && i + 1 < argc) {
            verification = argv[++i];
            if (strcmp(verification, "forced") && strcmp(verification, "default")) {
                usage(argv[0]);
                return 64;
            }
        } else {
            usage(argv[0]);
            return 64;
        }
    }
    if (strncasecmp(url, "https://", 8) &&
        !(allow_http_root && !strncasecmp(url, "http://", 7))) {
        fprintf(stderr, "probe URL must use HTTPS unless --allow-http-root is set\n");
        return 64;
    }

    if (!strcmp(operation, "avio")) {
        buffer = av_malloc(read_bytes);
        if (!buffer) {
            fprintf(stderr, "unable to allocate read buffer\n");
            return 70;
        }
    } else {
        packet = av_packet_alloc();
        format = avformat_alloc_context();
        if (!packet || !format) {
            fprintf(stderr, "unable to allocate demux state\n");
            av_packet_free(&packet);
            avformat_free_context(format);
            return 70;
        }
    }

    deadline.expires_at_us = av_gettime_relative() + (int64_t)deadline_ms * 1000;
    deadline.interrupted = 0;
    interrupt_callback.callback = interrupt_if_expired;
    interrupt_callback.opaque = &deadline;

    /* Forced mode explicitly enables verification. Default mode deliberately
     * omits tls_verify so it tests the candidate's compiled default. Neither
     * mode can disable verification. */
    if ((!strcmp(verification, "forced") &&
         av_dict_set(&options, "tls_verify", "1", 0) < 0) ||
        av_dict_set_int(&options, "rw_timeout", (int64_t)deadline_ms * 1000, 0) < 0 ||
        (ca_file && av_dict_set(&options, "ca_file", ca_file, 0) < 0) ||
        (headers && av_dict_set(&options, "headers", headers, 0) < 0) ||
        (reconnect && av_dict_set(&options, "reconnect", "1", 0) < 0) ||
        (reconnect_streamed &&
         av_dict_set(&options, "reconnect_streamed", "1", 0) < 0) ||
        (http_persistent &&
         av_dict_set(&options, "http_persistent", http_persistent, 0) < 0) ||
        (http_multiple &&
         av_dict_set(&options, "http_multiple", http_multiple, 0) < 0)) {
        fprintf(stderr, "unable to create FFmpeg options\n");
        av_dict_free(&options);
        av_free(buffer);
        av_packet_free(&packet);
        avformat_free_context(format);
        return 70;
    }

    av_log_set_level(AV_LOG_ERROR);
    if (!strcmp(operation, "avio")) {
        open_ret = avio_open2(&io, url, AVIO_FLAG_READ,
                              &interrupt_callback, &options);
        av_dict_free(&options);
        if (open_ret >= 0) {
            for (i = 0; i < read_iterations; i++) {
                read_ret = avio_read(io, buffer, read_bytes);
                if (read_ret > 0)
                    bytes_read += read_ret;
                else {
                    if (!read_ret)
                        read_ret = AVERROR_EOF;
                    break;
                }
            }
            close_ret = avio_closep(&io);
        }
    } else {
        format->interrupt_callback = interrupt_callback;
        open_ret = avformat_open_input(&format, url, NULL, &options);
        av_dict_free(&options);
        if (open_ret >= 0) {
            stream_info_ret = avformat_find_stream_info(format, NULL);
            if (stream_info_ret >= 0) {
                while (packet_count < max_packets) {
                    read_ret = av_read_frame(format, packet);
                    if (read_ret < 0)
                        break;
                    packet_count++;
                    av_packet_unref(packet);
                }
            }
            avformat_close_input(&format);
        }
    }

    failure_ret = open_ret < 0 ? open_ret :
                  stream_info_ret < 0 ? stream_info_ret : read_ret;
    if (failure_ret < 0)
        av_strerror(failure_ret, error, sizeof(error));
    cancel_propagated = deadline.interrupted &&
        (open_ret == AVERROR_EXIT || stream_info_ret == AVERROR_EXIT ||
         read_ret == AVERROR_EXIT || close_ret == AVERROR_EXIT);
    printf("{\"operation\":\"%s\",\"verification_mode\":\"%s\","
           "\"open_returncode\":%d,\"stream_info_returncode\":%d,"
           "\"read_returncode\":%d,\"close_returncode\":%d,"
           "\"bytes_read\":%d,\"packet_count\":%d,"
           "\"interrupt_callback_fired\":%s,"
           "\"cancel_propagated\":%s,\"error\":\"%s\"}\n",
           operation,
           !strcmp(verification, "forced") ?
               "forced_tls_verify_1" : "default_no_tls_verify_option",
           open_ret, stream_info_ret, read_ret, close_ret, bytes_read,
           packet_count, deadline.interrupted ? "true" : "false",
           cancel_propagated ? "true" : "false",
           failure_ret < 0 ? error : "");
    av_free(buffer);
    av_packet_free(&packet);
    if (format)
        avformat_free_context(format);

    if (cancel_propagated)
        return 11;
    if (deadline.interrupted)
        return 12;
    if (!strcmp(operation, "demux"))
        return open_ret < 0 || stream_info_ret < 0 || packet_count <= 0 ? 10 : 0;
    return open_ret < 0 || read_ret < 0 || close_ret < 0 ? 10 : 0;
}
