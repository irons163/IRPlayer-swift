import Foundation
import IRFFMpeg

enum IRFFmpegBootstrap {
    private static let initialization: Void = {
        av_log_set_callback { _, _, format, arguments in
            guard let format,
                  let arguments,
                  let message =
                    IRFFLogFormatting.message(
                        format: format,
                        args: arguments
                    ) else {
                return
            }

            IRFFRuntimeDebugOutput.write(
                message.trimmingCharacters(in: .newlines)
            )
        }
        avformat_network_init()
    }()

    static func initializeIfNeeded() {
        _ = initialization
    }
}
