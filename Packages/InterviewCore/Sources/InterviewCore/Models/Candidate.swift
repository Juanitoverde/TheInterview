import Foundation

/// How the receptionist and interviewer address the candidate ("Ms. Rivera", "Dr. Okafor", or just "Jane").
public enum FormOfAddress: String, Codable, CaseIterable, Identifiable, Sendable {
    case mr
    case ms
    case mrs
    case mx
    case dr
    case firstName

    public var id: String { rawValue }

    /// The honorific placed before the surname, or `nil` when the candidate prefers their first name.
    public var honorific: String? {
        switch self {
        case .mr: "Mr."
        case .ms: "Ms."
        case .mrs: "Mrs."
        case .mx: "Mx."
        case .dr: "Dr."
        case .firstName: nil
        }
    }

    public var displayName: String {
        honorific ?? "First name only"
    }
}

public struct CandidateProfile: Codable, Equatable, Sendable {
    public var fullName: String
    public var formOfAddress: FormOfAddress

    public init(fullName: String, formOfAddress: FormOfAddress) {
        self.fullName = fullName
        self.formOfAddress = formOfAddress
    }

    private var nameParts: [String] {
        fullName.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public var firstName: String? { nameParts.first }

    /// The name characters use when speaking to the candidate, e.g. "Ms. Rivera".
    /// Returns `nil` when no name was given so lines can be phrased without one.
    public var addressedName: String? {
        let parts = nameParts
        guard let first = parts.first else { return nil }
        guard let honorific = formOfAddress.honorific else { return first }
        return "\(honorific) \(parts.last ?? first)"
    }
}
