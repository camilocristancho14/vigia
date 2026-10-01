// Modified for Vigía from Pulse (Apache-2.0).
// Where Vigía draws itself.
import Foundation

enum VigiaDisplayMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case menuBar
    case notch
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar: .localized("Menu bar")
        case .notch: .localized("Notch")
        case .both: .localized("Both")
        }
    }
}
