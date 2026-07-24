//
//  IRFFDictionary.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import Foundation
import IRFFMpeg

final class IRFFDictionary {
    struct Diagnostics: Equatable {
        let closed: Bool
        let hasRawPointer: Bool
        let entryCount: Int
    }

    private var rawPointer: OpaquePointer?
    private var closed = false

    init() {}

    convenience init?(
        entries: [(key: String, value: String)]
    ) {
        guard !entries.isEmpty else { return nil }
        self.init()

        for entry in entries {
            guard set(
                key: entry.key,
                value: entry.value
            ) else {
                close()
                return nil
            }
        }
    }

    deinit {
        close()
    }

    var diagnostics: Diagnostics {
        Diagnostics(
            closed: closed,
            hasRawPointer: rawPointer != nil,
            entryCount: values.count
        )
    }

    var values: [String: String] {
        Self.values(from: rawPointer) ?? [:]
    }

    @discardableResult
    func set(
        key: String,
        value: String
    ) -> Bool {
        guard !closed else { return false }
        let result = key.withCString { key in
            value.withCString { value in
                av_dict_set(
                    &rawPointer,
                    key,
                    value,
                    0
                )
            }
        }
        return result >= 0
    }

    func withMutableRawPointer(
        _ body: (inout OpaquePointer?) -> Int32
    ) -> Int32 {
        guard !closed else { return -1 }
        return body(&rawPointer)
    }

    func close() {
        guard !closed else { return }
        av_dict_free(&rawPointer)
        closed = true
    }

    static func values(
        from borrowedDictionary: OpaquePointer?
    ) -> [String: String]? {
        guard let borrowedDictionary else { return nil }

        var values: [String: String] = [:]
        var entry: UnsafeMutablePointer<AVDictionaryEntry>?
        while let nextEntry = av_dict_get(
            borrowedDictionary,
            "",
            entry,
            AV_DICT_IGNORE_SUFFIX
        ) {
            if let key = string(
                fromCString: nextEntry.pointee.key
            ),
            let value = string(
                fromCString: nextEntry.pointee.value
            ) {
                values[key] = value
            }
            entry = nextEntry
        }
        return values.isEmpty ? nil : values
    }

    static func values(
        entries: [(
            key: UnsafePointer<CChar>?,
            value: UnsafePointer<CChar>?
        )]
    ) -> [String: String]? {
        var values: [String: String] = [:]
        for entry in entries {
            if let key = string(fromCString: entry.key),
               let value = string(
                   fromCString: entry.value
               ) {
                values[key] = value
            }
        }
        return values.isEmpty ? nil : values
    }

    static func string(
        fromCString cString: UnsafePointer<CChar>?
    ) -> String? {
        guard let cString else { return nil }
        return String(validatingUTF8: cString)
    }
}
