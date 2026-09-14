import Foundation
import SwiftUI

struct ScreenshotItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let createdAt: Date
}

enum ScreenshotPhase: Equatable {
    case idle
    case requestingPermission
    case selecting
    case capturing
    case saving
    case failed(String)
}

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, rectangle, arrow, pen, text, redact

    var id: Self { self }

    var title: String {
        switch self {
        case .select: "Select"
        case .rectangle: "Rectangle"
        case .arrow: "Arrow"
        case .pen: "Pen"
        case .text: "Text"
        case .redact: "Redact"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .rectangle: "rectangle"
        case .arrow: "arrow.up.right"
        case .pen: "pencil.tip"
        case .text: "textformat"
        case .redact: "rectangle.fill"
        }
    }
}

struct ScreenshotAnnotation: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case rectangle, arrow, pen, text, redact
    }

    let id: UUID
    var kind: Kind
    var rect: CGRect?
    var points: [CGPoint]
    var text: String?
    var color: AnnotationColor
    var lineWidth: Double

    init(
        id: UUID = UUID(),
        kind: Kind,
        rect: CGRect? = nil,
        points: [CGPoint] = [],
        text: String? = nil,
        color: AnnotationColor = .fault,
        lineWidth: Double = 3
    ) {
        self.id = id
        self.kind = kind
        self.rect = rect
        self.points = points
        self.text = text
        self.color = color
        self.lineWidth = lineWidth
    }
}

struct AnnotationColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let fault = AnnotationColor(red: 0.878, green: 0.365, blue: 0.220, alpha: 1)

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
