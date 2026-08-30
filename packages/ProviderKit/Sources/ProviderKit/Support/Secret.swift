import Foundation

/// A string that cannot be printed, logged, or encoded.
///
/// Provider credentials pass through several layers between the keychain and the
/// `Authorization` header, and every one of those layers has a plausible reason to
/// interpolate a value into a log line during debugging. Wrapping the token makes that
/// mistake impossible rather than merely discouraged: the compiler will not hand out the
/// underlying string except through `reveal()`, and every reflexive path a developer
/// might reach for — `print`, `String(describing:)`, `"\(secret)"`, `JSONEncoder` —
/// produces `<redacted>`.
///
/// `reveal()` is deliberately ugly to read at a call site. There should be exactly one
/// per adapter, immediately before the header is built.
public struct Secret: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private let value: String

    public init(_ value: String) {
        self.value = value
    }

    /// The only way out. Call this as late as possible — ideally inline in the header
    /// dictionary — so the bare string never lands in a named variable.
    public func reveal() -> String { value }

    public var isEmpty: Bool { value.isEmpty }

    /// Character count, for validation that does not need the value itself.
    public var count: Int { value.count }

    public var description: String { "<redacted>" }
    public var debugDescription: String { "<redacted>" }
}

/// Refuses to participate in serialization at all.
///
/// A `Codable` conformance that encoded the value would let a secret reach disk the first
/// time someone made a credential-carrying struct `Codable` for convenience. Encoding
/// throws instead; decoding is unsupported for the same reason.
extension Secret: Codable {
    public init(from decoder: Decoder) throws {
        throw EncodingError.invalidValue(
            "Secret",
            EncodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Secrets are read from the system credential store, never decoded."
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        throw EncodingError.invalidValue(
            "Secret",
            EncodingError.Context(
                codingPath: encoder.codingPath,
                debugDescription: "Secrets must never be encoded or persisted."
            )
        )
    }
}

/// Equality without exposing the value. Constant-time is unnecessary here — these are
/// compared only to detect rotation, never to authenticate.
extension Secret: Equatable {
    public static func == (lhs: Secret, rhs: Secret) -> Bool {
        lhs.value == rhs.value
    }
}
