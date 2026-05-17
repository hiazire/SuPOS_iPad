//
//  POSModels.swift
//  SuPOS_iPad
//
//  Created by rabisu on 2026/5/13.
//

import Foundation
import SwiftUI // 如果你的 Model 裡面有用到 Color，就需要引入 SwiftUI


struct FuncButton {
    let title: String
    let icon: String
    let action: () -> Void
}

struct MenuItem: Identifiable, Codable, Hashable {
    let id: Int
    let category: String
    let name: String
    let price: Int
    let imageUrl: String
    let optionsGroup: String?

    enum CodingKeys: String, CodingKey {
        case id, category, name, price, imageUrl
        case optionsGroup = "options_group"
    }
}

struct WebOrder: Identifiable, Codable, Hashable {
    var id: String { orderId }
    let orderId: String
    let timestamp: String
    let details: String
    var state: String
    var paymentStatus: String? // 👈 新增：用於記錄 UNPAID 或 PAID
}

struct WebOrderResponse: Codable {
    let success: Bool
    let orders: [WebOrder]
}

struct MenuResponse: Codable {
    let success: Bool
    let menu: [MenuItem]
    let options: [OptionItem]?
}

struct TempOrder: Identifiable {
    let id = UUID()
    let timestamp: Date
    let items: [CartItem]
    let metadata: OrderMetadata
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "a hh:mm:ss"
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter.string(from: timestamp)
    }
}

struct ParsedOrderItem: Codable, Hashable {
    var category: String?
    var name: String
    var qty: Int
    var addons: [ParsedAddon]?
    struct ParsedAddon: Codable, Hashable {
        var name: String
        var qty: Int?
    }
}

enum POSViewMode {
    case manualOrdering
    case transactionHistory
    case checkout
    case onlineOrders
    case tempOrders
}

enum OrderDateFilter: String, CaseIterable {
    case today = "今天"
    case yesterday = "昨天"
    case threeDays = "三天內"
    case fiveDays = "五天內"
}

struct OptionItem: Identifiable, Codable, Hashable {
    var id: String { name }
    let group: String
    let name: String
    let price: Int
}

struct CartItem: Identifiable, Hashable {
    let id = UUID()
    let menuItem: MenuItem
    var quantity: Int
    var selectedOptions: [OptionItem]
    var isComplimentary: Bool = false

    static func == (lhs: CartItem, rhs: CartItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct OrderMetadata {
    var createdAt: Date?
    var transactionType: String = "外帶"
    var invoiceNumber: String = ""
    var ubn: String = ""
    var carrier: String = ""
}
