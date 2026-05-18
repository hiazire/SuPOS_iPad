//
//  POSViewModel.swift
//  SuPOS_iPad
//
//  Created by rabisu on 2026/5/13.
//
import Foundation
import SwiftUI
import Combine

@MainActor // 確保所有 UI 狀態更新都在主執行緒安全執行
class POSViewModel: ObservableObject {
    // 雲端配置
    let API_URL = "https://script.google.com/macros/s/AKfycbw0bjJpGXFNh9TvxOdh_gFRvttou-DkSpRtzu_nFLIyr30KUHpwFr3Bn8LGWBGE5SpJcA/exec"
    
    // ================= 狀態變數 (@Published) =================
    @Published var webOrders: [WebOrder] = []
    @Published var selectedDateFilter: OrderDateFilter = .today
    @Published var incomingOrder: WebOrder? = nil
    @Published var showingOrderPopup: Bool = false
    @Published var selectedWebOrder: WebOrder? = nil
    @Published var activeWebOrderId: String = ""
    @Published var webOrderPage: Int = 0
    @Published var tempSavedOrders: [TempOrder] = []
    
    @Published var menuItems: [MenuItem] = []
    @Published var allOptions: [OptionItem] = []
    @Published var categories: [String] = []
    @Published var cart: [CartItem] = []
    @Published var isLoading = true
    @Published var historyOrders: [HistoryOrder] = []
    
    @Published var selectedCategory: String? = nil
    @Published var selectedItemForOptions: MenuItem? = nil
    @Published var selectedCartItemID: UUID? = nil
    @Published var currentPOSViewMode: POSViewMode = .manualOrdering
    
    @Published var categoryPage: Int = 0
    @Published var itemPage: Int = 0
    @Published var currentFunctionPage: Int = 0
    @Published var orderMetadata = OrderMetadata()

    // ================= 計算屬性 =================
    var cartTotal: Int {
        cart.reduce(0) { total, item in
            guard !item.isComplimentary else { return total }
            let optionsPrice = item.selectedOptions.reduce(0) { $0 + $1.price }
            return total + ((item.menuItem.price + optionsPrice) * item.quantity)
        }
    }

    var formattedCreationTime: String {
        guard let date = orderMetadata.createdAt else { return "尚未建立" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    // 自動計算今日營業額
    var todayTurnover: Double {
        let formatter = DateFormatter()
        let now = Date()
        
        // 🌟 提早在迴圈外面把字串算好，效能提升 100 倍！
        formatter.dateFormat = "yyyy/MM/dd"
        let format1 = formatter.string(from: now)
        
        formatter.dateFormat = "yyyy-MM-dd"
        let format2 = formatter.string(from: now)
        
        return historyOrders.filter { order in
            // 條件 1：必須是已結帳 PAID
            guard order.paymentStatus == "PAID" else { return false }
            
            // 條件 2：直接拿算好的 format1 與 format2 來比對
            let dateStr = order.timestamp
            return dateStr.contains(format1) || dateStr.contains(format2)
        }.reduce(0.0) { $0 + $1.totalAmount }
    }

    var allFunctionButtons: [FuncButton] {
        [
            FuncButton(title: "", icon: "plus", action: { self.adjustQuantity(ofSelected: 1) }),
            FuncButton(title: "", icon: "minus", action: { self.adjustQuantity(ofSelected: -1) }),
            FuncButton(title: "訂單暫存", icon: "tray.and.arrow.down", action: { self.saveCurrentOrderToTemp() }),
            FuncButton(title: "暫存區", icon: "tray.full", action: { self.currentPOSViewMode = .tempOrders; self.selectedItemForOptions = nil }),
            
            // FuncButton(title: "手動點餐", icon: "hand.tap", action: { self.currentPOSViewMode = .manualOrdering }),
            FuncButton(title: "手動點餐", icon: "square.grid.3x3.fill", action: { self.currentPOSViewMode = .manualOrdering; self.selectedItemForOptions = nil }),
            
            FuncButton(title: "歷史訂單", icon: "clock.arrow.circlepath", action: { self.currentPOSViewMode = .transactionHistory }),
            // 「日營業額」的按鈕資料
            FuncButton(title: "日營業額", icon: "chart.bar.doc.horizontal", action: {
                self.currentPOSViewMode = .dailyTurnover}),
            FuncButton(title: orderMetadata.transactionType, icon: "bag", action: { self.toggleTransactionType() }),
            FuncButton(title: "刪除商品", icon: "trash", action: { self.deleteSelectedCartItem() }),
            FuncButton(title: "取消交易", icon: "xmark.circle", action: { self.cancelEntireTransaction() }),
            FuncButton(title: "清除加料", icon: "minus.square", action: { self.clearOptionsOfSelected() }),
            FuncButton(title: "招待", icon: "gift.fill", action: { self.applyComplimentary() }),
            FuncButton(title: "交易紀錄", icon: "doc.text.magnifyingglass", action: {
                self.currentPOSViewMode = .transactionHistory
                self.selectedItemForOptions = nil
                Task { await self.fetchHistoryFromCloud() }
            }),
        ]
    }

    var filteredHistoryOrders: [WebOrder] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        return webOrders.filter { order in
            guard let orderDate = parseOrderDate(order.timestamp) else { return false }
            let dayDiff = calendar.dateComponents([.day], from: calendar.startOfDay(for: orderDate), to: startOfToday).day ?? 0
            switch selectedDateFilter {
            case .today: return dayDiff == 0
            case .yesterday: return dayDiff == 1
            case .threeDays: return dayDiff >= 0 && dayDiff <= 2
            case .fiveDays: return dayDiff >= 0 && dayDiff <= 4
            }
        }
    }

    // ================= 核心功能邏輯 (Logic) =================
    func submitOrder() async {
        guard !cart.isEmpty else { return }
        
        // 🌟 修正 1：轉成字典陣列，而不是事先轉成 JSON 字串
        let itemsArray = cart.map { item -> [String: Any] in
            var dict: [String: Any] = [
                "category": item.menuItem.category,
                "name": item.menuItem.name,
                "qty": item.quantity
            ]
            let addons = item.selectedOptions.map { ["name": $0.name, "qty": 1] as [String: Any] }
            if !addons.isEmpty { dict["addons"] = addons }
            return dict
        }

        guard let url = URL(string: API_URL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        // 🌟 修正 2：完美對齊 GAS 需要的 Key 值
        let payload: [String: Any] = [
            "action": "newOrder",
            "orderId": "SuPOS-\(Int.random(in: 1000...9999))",
            "items": itemsArray,
            "total": cartTotal,
            "table": orderMetadata.transactionType,
            "status": "READY",
            "paymentStatus": "PAID" // 👈 新增財務狀態，現場結帳預設為 PAID
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            isLoading = true
            let (data, _) = try await URLSession.shared.data(for: request)
            if let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = response["success"] as? Bool, success {
                SoundManager.shared.playSuccess()
                HapticManager.shared.triggerSuccess()
                cancelEntireTransaction()
                currentPOSViewMode = .manualOrdering
            } else {
                print("❌ 伺服器回傳錯誤: \(String(data: data, encoding: .utf8) ?? "")")
            }
            isLoading = false
        } catch {
            print("🛑 網路錯誤")
            isLoading = false
        }
    }

    func checkNewWebOrders() async {
        guard let url = URL(string: API_URL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        let payload = ["action": "getPendingOrders"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let res = try JSONDecoder().decode(WebOrderResponse.self, from: data)
            for order in res.orders {
                if let idx = webOrders.firstIndex(where: { $0.orderId == order.orderId }) {
                    if webOrders[idx].state == "PENDING" { webOrders[idx] = order }
                } else { webOrders.append(order) }
            }
            if let new = res.orders.first(where: { $0.state == "PENDING" }), !showingOrderPopup {
                SoundManager.shared.playSuccess()
                incomingOrder = new
                showingOrderPopup = true
            }
        } catch { print("Fetch error: \(error)") }
    }

    func fetchHistoryFromCloud() async {
        guard let url = URL(string: API_URL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        let days: Int = (selectedDateFilter == .today) ? 0 : (selectedDateFilter == .yesterday ? 1 : (selectedDateFilter == .threeDays ? 3 : 5))
        let payload: [String: Any] = ["action": "getHistoryOrders", "days": days]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let res = try JSONDecoder().decode(WebOrderResponse.self, from: data)
            for order in res.orders {
                if let idx = webOrders.firstIndex(where: { $0.orderId == order.orderId }) {
                    self.webOrders[idx] = order
                } else { self.webOrders.append(order) }
            }
        } catch { print("History fetch error") }
    }

    func parseOrderDate(_ dateString: String) -> Date? {
        let prefix = String(dateString.prefix(24))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "E MMM dd yyyy HH:mm:ss"
        return formatter.date(from: prefix)
    }

    func saveCurrentOrderToTemp() {
        guard !cart.isEmpty else { return }
        tempSavedOrders.insert(TempOrder(timestamp: Date(), items: cart, metadata: orderMetadata), at: 0)
        if tempSavedOrders.count > 5 { tempSavedOrders.removeLast() }
        cancelEntireTransaction()
        HapticManager.shared.triggerSuccess()
    }

    func restoreOrderFromTemp(_ order: TempOrder) {
        self.cart = order.items
        self.orderMetadata = order.metadata
        tempSavedOrders.removeAll { $0.id == order.id }
        currentPOSViewMode = .manualOrdering
    }

    func cancelEntireTransaction() {
        cart = []; orderMetadata = OrderMetadata(); selectedCartItemID = nil; selectedItemForOptions = nil
    }

    func adjustQuantity(ofSelected adjustment: Int) {
        guard let id = selectedCartItemID, let idx = cart.firstIndex(where: { $0.id == id }) else { return }
        cart[idx].quantity += adjustment
        if cart[idx].quantity < 1 {
            cart.remove(at: idx)
            if let lastItem = cart.last {
                selectedCartItemID = lastItem.id
                selectedItemForOptions = lastItem.menuItem
            } else {
                selectedCartItemID = nil; selectedItemForOptions = nil
            }
        }
    }

    func deleteSelectedCartItem() {
        if let id = selectedCartItemID {
            cart.removeAll { $0.id == id }
            if let lastItem = cart.last {
                selectedCartItemID = lastItem.id
                selectedItemForOptions = lastItem.menuItem
            } else {
                selectedCartItemID = nil; selectedItemForOptions = nil
            }
        }
    }

    func clearOptionsOfSelected() {
        if let id = selectedCartItemID, let idx = cart.firstIndex(where: { $0.id == id }) { cart[idx].selectedOptions = [] }
    }

    func applyComplimentary() {
        HapticManager.shared.triggerMedium()
        if let id = selectedCartItemID, let idx = cart.firstIndex(where: { $0.id == id }) {
            cart[idx].isComplimentary.toggle()
        } else if !cart.isEmpty {
            for i in 0..<cart.count { cart[i].isComplimentary = true }
        }
    }

    func toggleTransactionType() {
        let types = ["外帶", "內用", "Line自取", "電話點餐"]
        if let idx = types.firstIndex(of: orderMetadata.transactionType) {
            orderMetadata.transactionType = types[(idx + 1) % types.count]
        }
    }

    func changeFunctionPage(by adjustment: Int, totalPages: Int) {
        let next = currentFunctionPage + adjustment
        currentFunctionPage = (next >= totalPages) ? 0 : (next < 0 ? totalPages - 1 : next)
    }

    func handleItemTap(item: MenuItem) {
        HapticManager.shared.triggerMedium(); SoundManager.shared.playPop()
        if cart.isEmpty { orderMetadata.createdAt = Date() }
        let newItem = CartItem(menuItem: item, quantity: 1, selectedOptions: [])
        cart.append(newItem)
        selectedCartItemID = newItem.id; selectedItemForOptions = item
    }

    func addOptionToCart(option: OptionItem) {
        SoundManager.shared.playTap()
        if let id = selectedCartItemID, let idx = cart.firstIndex(where: { $0.id == id }) {
            cart[idx].selectedOptions.append(option)
        }
    }
    
    func fetchMenuData() async {
        guard let url = URL(string: API_URL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let res = try JSONDecoder().decode(MenuResponse.self, from: data)
            self.menuItems = res.menu; self.allOptions = res.options ?? []
            self.categories = Array(Set(res.menu.map { $0.category })).sorted()
            self.isLoading = false
        } catch { self.isLoading = false }
    }
    
    func updateWebOrderState(orderId: String, newState: String) {
        showingOrderPopup = false; incomingOrder = nil; selectedWebOrder = nil
        if let idx = webOrders.firstIndex(where: { $0.orderId == orderId }) { webOrders[idx].state = newState }
        Task {
            guard let url = URL(string: API_URL) else { return }
            var req = URLRequest(url: url); req.httpMethod = "POST"
            req.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = ["action": "updateOrderState", "orderId": orderId, "newState": newState]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            _ = try? await URLSession.shared.data(for: req)
        }
    }
    
    // 📡 抓取歷史訂單
    func fetchHistoryOrders() async {
        guard let url = URL(string: API_URL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = ["action": "getHistoryOrders", "days": 1]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let response = try? JSONDecoder().decode(HistoryResponse.self, from: data), response.success {
                await MainActor.run {
                    self.historyOrders = response.orders
                }
            }
        } catch {
            print("抓取歷史訂單失敗: \(error)")
        }
    }
    
    // 將網頁訂單帶入結帳畫面
    func prepareWebOrderForCheckout(order: WebOrder) {
        self.activeWebOrderId = order.orderId
        self.cart.removeAll()
        let parsedData = order.details.data(using: .utf8) ?? Data()
        let items: [ParsedOrderItem] = (try? JSONDecoder().decode([ParsedOrderItem].self, from: parsedData)) ?? []
        for pItem in items {
            // 根據名稱找回原始 MenuItem
            if let menuItem = self.menuItems.first(where: { $0.name == pItem.name }) {
                var options: [OptionItem] = []
                
                // 還原客製化選項
                if let addons = pItem.addons {
                    for addon in addons {
                        if let opt = self.allOptions.first(where: { $0.name == addon.name }) {
                            let count = addon.qty ?? 1
                            for _ in 0..<count { options.append(opt) }
                        }
                    }
                }
                let cartItem = CartItem(menuItem: menuItem, quantity: pItem.qty, selectedOptions: options)
                self.cart.append(cartItem)
            }
        }
        // 切換至結帳畫面
        self.currentPOSViewMode = .checkout
    }
}
