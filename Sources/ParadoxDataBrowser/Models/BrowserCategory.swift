import Foundation

enum ParadoxBrowserCategory: CaseIterable, Identifiable {
    case customers
    case parts
    case communications
    case sales
    case service
    case other

    var id: String { rawValue }
    var rawValue: String {
        switch self {
        case .customers: return "customers"
        case .parts: return "parts"
        case .communications: return "communications"
        case .sales: return "sales"
        case .service: return "service"
        case .other: return "other"
        }
    }

    var displayName: String {
        switch self {
        case .customers: return "Customers"
        case .parts: return "Parts"
        case .communications: return "Communications"
        case .sales: return "Sales & Quotes"
        case .service: return "Service & Equipment"
        case .other: return "Other"
        }
    }

    private var keywords: [String] {
        switch self {
        case .customers:
            return ["cust", "customer", "client", "account", "alist", "user"]
        case .parts:
            return ["part", "comp", "component", "item", "stock", "belt", "bolt", "inventory"]
        case .communications:
            return ["comm", "fax", "email", "note", "contact", "tel", "phone", "letter"]
        case .sales:
            return ["quote", "order", "invoice", "bill", "ship", "purchase"]
        case .service:
            return ["service", "repair", "equip", "serial", "install", "warranty"]
        case .other:
            return []
        }
    }

    static func category(for filename: String) -> ParadoxBrowserCategory {
        let trimmed = filename.lowercased()
        for category in allCases where category != .other {
            if category.keywords.contains(where: { trimmed.contains($0) }) {
                return category
            }
        }
        return .other
    }
}
