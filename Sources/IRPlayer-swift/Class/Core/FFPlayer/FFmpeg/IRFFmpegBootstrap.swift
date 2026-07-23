import Foundation
import IRFFMpeg

enum IRFFmpegBootstrap {
    private static let initialization: Void = {
        av_log_set_callback { _, _, format, arguments in
            guard let format,
                  let formatString = String(utf8String: format),
                  let arguments else {
                return
            }

            let message = NSString(
                format: formatString,
                arguments: arguments
            ) as String
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
