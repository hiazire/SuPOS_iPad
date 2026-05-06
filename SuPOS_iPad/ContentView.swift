import SwiftUI
import AVFoundation
import AudioToolbox
internal import Combine

// ================= 1. 資料模型區 (Data Model) =================

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
}

struct OrderMetadata {
    var createdAt: Date?
    var transactionType: String = "外帶"
    var invoiceNumber: String = ""
    var ubn: String = ""
    var carrier: String = ""
}

// ================= 2. 主視圖 (Main View) =================

struct ContentView: View {
    // 雲端配置
    let API_URL = "https://script.google.com/macros/s/AKfycbw0bjJpGXFNh9TvxOdh_gFRvttou-DkSpRtzu_nFLIyr30KUHpwFr3Bn8LGWBGE5SpJcA/exec"
    
    // 狀態變數
    @State private var webOrders: [WebOrder] = []
    @State private var selectedDateFilter: OrderDateFilter = .today
    @State private var incomingOrder: WebOrder? = nil
    @State private var showingOrderPopup: Bool = false
    @State private var webOrderPage: Int = 0
    @State private var selectedWebOrder: WebOrder? = nil
    @State private var tempSavedOrders: [TempOrder] = []
    
    @State private var menuItems: [MenuItem] = []
    @State private var allOptions: [OptionItem] = []
    @State private var categories: [String] = []
    @State private var cart: [CartItem] = []
    @State private var isLoading = true
    
    @State private var selectedCategory: String? = nil
    @State private var selectedItemForOptions: MenuItem? = nil
    @State private var selectedCartItemID: UUID? = nil
    @State private var currentPOSViewMode: POSViewMode = .manualOrdering
    
    @State private var categoryPage: Int = 0
    @State private var itemPage: Int = 0
    @State private var currentFunctionPage: Int = 0
    @State private var orderMetadata = OrderMetadata()
    
    let pollingTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // --- 計算屬性 ---
    var cartTotal: Int {
        cart.reduce(0) { total, item in
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

    var allFunctionButtons: [FuncButton] {
        [
            FuncButton(title: "訂單暫存", icon: "tray.and.arrow.down", action: { saveCurrentOrderToTemp() }),
            FuncButton(title: "暫存區", icon: "tray.full", action: { currentPOSViewMode = .tempOrders; selectedItemForOptions = nil }),
            FuncButton(title: "+1", icon: "plus", action: { adjustQuantity(ofSelected: 1) }),
            FuncButton(title: "-1", icon: "minus", action: { adjustQuantity(ofSelected: -1) }),
            FuncButton(title: "手動點餐", icon: "square.grid.3x3.fill", action: { currentPOSViewMode = .manualOrdering; selectedItemForOptions = nil }),
            FuncButton(title: orderMetadata.transactionType, icon: "bag", action: { toggleTransactionType() }),
            FuncButton(title: "刪除商品", icon: "trash", action: { deleteSelectedCartItem() }),
            FuncButton(title: "取消交易", icon: "xmark.circle", action: { cancelEntireTransaction() }),
            FuncButton(title: "清除加料", icon: "minus.square", action: { clearOptionsOfSelected() }),
            FuncButton(title: "交易紀錄", icon: "doc.text.magnifyingglass", action: {
                currentPOSViewMode = .transactionHistory
                selectedItemForOptions = nil
                Task { await fetchHistoryFromCloud() } // 點擊時同步抓取方案 B
            })
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                OrderDetailsColumn(totalHeight: geometry.size.height)
                    .frame(width: geometry.size.width * 0.3)
                Divider()
                FunctionTogglesColumn(totalHeight: geometry.size.height)
                Divider()
                FunctionDisplayColumn()
                    .frame(maxWidth: .infinity)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .top) // 👈 加回：頂部手勢延遲（需滑動兩次才能拉出系統選單）
        .overlay(PopupOverlayView())    // 👈 這裡就是呼叫被我獨立出去的新彈窗元件
        .onReceive(pollingTimer) { _ in Task { await checkNewWebOrders() } }
        .task { await fetchMenuData() }
        .onAppear {
            // 👈 加回：強制橫向邏輯，確保萬無一失
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeLeft))
            }
        }
    }

    // ================= 3. UI 元件區 =================

    // --- 左側：點餐明細 ---
    @ViewBuilder
    func OrderDetailsColumn(totalHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("訂單總覽").font(.headline).fontWeight(.bold).padding(.bottom, 2)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledInfoView(title: "建立時間", value: formattedCreationTime)
                        LabeledInfoView(title: "交易型態", value: orderMetadata.transactionType)
                        LabeledInfoView(title: "發票號碼", value: orderMetadata.invoiceNumber)
                        LabeledInfoView(title: "統一編號", value: orderMetadata.ubn)
                        LabeledInfoView(title: "發票載具", value: orderMetadata.carrier)
                    }
                }
            }
            .padding(10)
            .frame(height: totalHeight * 0.2, alignment: .topLeading)
            .background(Color(UIColor.systemGray6))
            
            Divider()
            
            CartListView()
                .frame(height: totalHeight * 0.75)
            
            Divider()
            
            HStack {
                Text("總計金額").font(.title3).fontWeight(.bold)
                Spacer()
                Text("$\(cartTotal)").font(.title3).fontWeight(.bold).foregroundColor(.red)
            }
            .padding(.horizontal)
            .frame(height: totalHeight * 0.05)
            .background(Color(UIColor.secondarySystemBackground))
        }
    }

    // --- 中間：機械感功能切換 ---
    @ViewBuilder
    func FunctionTogglesColumn(totalHeight: CGFloat) -> some View {
        let columnWidth: CGFloat = 100
        let buttonSize: CGFloat = columnWidth - 10
        let arrowHeight: CGFloat = 45
        let fixedHeights = (arrowHeight * 2) + buttonSize + 10
        let functionsPerPage = max(1, Int((totalHeight - fixedHeights) / (buttonSize + 8)))
        let totalPages = max(1, Int(ceil(Double(allFunctionButtons.count) / Double(functionsPerPage))))

        VStack(spacing: 0) {
            FunctionPageButton(icon: "chevron.up", height: arrowHeight, action: { changeFunctionPage(by: -1, totalPages: totalPages) }, isDisabled: totalPages <= 1)
            
            GeometryReader { geo in
                VStack(spacing: 0) {
                    ForEach(0..<totalPages, id: \.self) { pageIndex in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            let start = pageIndex * functionsPerPage
                            let end = min(start + functionsPerPage, allFunctionButtons.count)
                            ForEach(start..<end, id: \.self) { idx in
                                SquareFunctionButton(title: allFunctionButtons[idx].title, icon: allFunctionButtons[idx].icon, size: buttonSize, action: allFunctionButtons[idx].action)
                                Spacer(minLength: 0)
                            }
                            if (end - start) < functionsPerPage {
                                ForEach(0..<(functionsPerPage - (end - start)), id: \.self) { _ in
                                    Color.clear.frame(width: buttonSize, height: buttonSize)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .offset(y: -CGFloat(currentFunctionPage) * geo.size.height)
                .animation(.easeInOut(duration: 0.25), value: currentFunctionPage)
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture().onEnded { value in
                if value.translation.height < -30 { changeFunctionPage(by: 1, totalPages: totalPages) }
                else if value.translation.height > 30 { changeFunctionPage(by: -1, totalPages: totalPages) }
            })

            FunctionPageButton(icon: "chevron.down", height: arrowHeight, action: { changeFunctionPage(by: 1, totalPages: totalPages) }, isDisabled: totalPages <= 1)
            
            Spacer(minLength: 8)
            SquareFunctionButton(title: "結帳", icon: "cart.fill", size: buttonSize, action: { currentPOSViewMode = .checkout }, isCheckout: true)
        }
        .frame(width: columnWidth, height: totalHeight)
        .background(Color(UIColor.secondarySystemBackground))
    }

    // --- 右側：功能展示分流 ---
    @ViewBuilder
    func FunctionDisplayColumn() -> some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("正在同步雲端菜單...").scaleEffect(1.5).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch currentPOSViewMode {
                    case .manualOrdering: ManualOrderingView(size: geo.size)
                    case .transactionHistory: TransactionHistoryPanelView(size: geo.size)
                    case .onlineOrders: OnlineOrdersPanel(size: geo.size)
                    case .tempOrders: TempOrdersPanelView()
                    case .checkout: PlaceholderView(title: "結帳介面")
                    }
                }
            }
            .background(Color(UIColor.systemBackground))
        }
    }

    // ================= 4. 核心功能邏輯 (Logic) =================

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
            await MainActor.run {
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
            }
        } catch { print("Fetch error: \(error)") }
    }

    func fetchHistoryFromCloud() async {
        guard let url = URL(string: API_URL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        // 方案 B：告知後端需要歷史資料
        let days: Int = (selectedDateFilter == .today) ? 0 : (selectedDateFilter == .yesterday ? 1 : (selectedDateFilter == .threeDays ? 3 : 5))
        let payload: [String: Any] = ["action": "getHistoryOrders", "days": days]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let res = try JSONDecoder().decode(WebOrderResponse.self, from: data)
            await MainActor.run {
                for order in res.orders {
                    if let idx = webOrders.firstIndex(where: { $0.orderId == order.orderId }) {
                        self.webOrders[idx] = order
                    } else { self.webOrders.append(order) }
                }
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

    // --- 其他 Helper 函數 ---
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
        if cart[idx].quantity < 1 { cart.remove(at: idx); selectedCartItemID = nil }
    }

    func deleteSelectedCartItem() {
        if let id = selectedCartItemID { cart.removeAll { $0.id == id }; selectedCartItemID = nil }
    }

    func clearOptionsOfSelected() {
        if let id = selectedCartItemID, let idx = cart.firstIndex(where: { $0.id == id }) { cart[idx].selectedOptions = [] }
    }

    func toggleTransactionType() {
        let types = ["外帶", "內用", "電話Line自取件"]
        if let idx = types.firstIndex(of: orderMetadata.transactionType) {
            orderMetadata.transactionType = types[(idx + 1) % types.count]
        }
    }

    func changeFunctionPage(by adjustment: Int, totalPages: Int) {
        withAnimation {
            let next = currentFunctionPage + adjustment
            currentFunctionPage = (next >= totalPages) ? 0 : (next < 0 ? totalPages - 1 : next)
        }
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
            await MainActor.run {
                self.menuItems = res.menu; self.allOptions = res.options ?? []
                self.categories = Array(Set(res.menu.map { $0.category })).sorted()
                self.isLoading = false
            }
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
}

// ================= 5. 子視圖元件 (Subviews) =================

struct OrderListView: View {
    let webOrders: [WebOrder]
    @Binding var currentPage: Int
    @Binding var selectedOrder: WebOrder?

    var body: some View {
        VStack(spacing: 0) {
            Text("今日線上訂單").font(.system(size: 36, weight: .black)).padding(.vertical, 20).frame(maxWidth: .infinity)
            Divider()
            ScrollView {
                VStack(spacing: 15) {
                    if webOrders.isEmpty {
                        Text("目前尚無線上訂單").font(.title2).foregroundColor(.gray).padding(.top, 50)
                    } else {
                        ForEach(webOrders) { order in
                            OrderRow(order: order) { self.selectedOrder = order }
                        }
                    }
                }
                .padding(.top, 15).padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct OrderRow: View {
    let order: WebOrder
    let onTap: () -> Void
    var cleanTime: String { String(order.timestamp.prefix(24)) }
    var stateColor: Color {
        switch order.state {
        case "PENDING": return .orange
        case "READY": return .blue
        case "PRINTED": return .green
        case "CANCELED": return .red
        default: return .gray
        }
    }
    var stateText: String {
        switch order.state {
        case "PENDING": return "等待入機"
        case "READY": return "已入機"
        case "PRINTED": return "已列印"
        case "CANCELED": return "已取消"
        default: return order.state
        }
    }
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("單號：\(order.orderId)").font(.system(size: 32, weight: .black)).foregroundColor(.primary)
                    Text(cleanTime).font(.headline).foregroundColor(.gray)
                }
                Spacer()
                Text(stateText).font(.headline).fontWeight(.bold).foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 10).background(stateColor).cornerRadius(12)
                Image(systemName: "chevron.right").foregroundColor(Color.gray.opacity(0.5))
            }
            .padding(20).background(Color(UIColor.secondarySystemBackground)).cornerRadius(16)
        }
        .buttonStyle(JapaneseButtonStyle())
    }
}

extension ContentView {
    @ViewBuilder
    func ManualOrderingView(size: CGSize) -> some View {
        if let category = selectedCategory {
            VStack(spacing: 0) {
                ItemPagingGrid(category: category, size: CGSize(width: size.width, height: size.height * 0.7))
                Divider()
                OptionsBottomPanel(size: CGSize(width: size.width, height: size.height * 0.3))
            }
        } else {
            CategoryPagingGrid(size: size)
        }
    }

    @ViewBuilder
    func CategoryPagingGrid(size: CGSize) -> some View {
        let itemsPerPage = 20
        let totalPages = max(1, Int(ceil(Double(categories.count) / Double(itemsPerPage))))
        let squareSize = floor(min((size.width - 90) / 5, (size.height - 140) / 4))

        VStack(spacing: 0) {
            Text("請選擇餐點分類").font(.title).fontWeight(.bold).frame(height: 60)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(0..<totalPages, id: \.self) { pageIdx in
                        let start = pageIdx * itemsPerPage
                        let end = min(start + itemsPerPage, categories.count)
                        let columns = Array(repeating: GridItem(.fixed(squareSize), spacing: 15), count: 5)
                        VStack {
                            Spacer(minLength: 0)
                            LazyVGrid(columns: columns, spacing: 15) {
                                ForEach(categories[start..<end], id: \.self) { cat in
                                    Button(action: { selectedCategory = cat; itemPage = 0 }) {
                                        Text(cat).font(.title3).fontWeight(.bold).foregroundColor(.white).frame(width: squareSize, height: squareSize)
                                            .background(LinearGradient(colors: [.blue.opacity(0.7), .blue], startPoint: .top, endPoint: .bottom))
                                            .cornerRadius(12).shadow(radius: 3, y: 4)
                                    }.buttonStyle(JapaneseButtonStyle())
                                }
                            }
                            .padding(.horizontal, 15)
                            Spacer(minLength: 0)
                        }.frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .offset(x: -CGFloat(categoryPage) * geo.size.width)
                .animation(.easeInOut(duration: 0.25), value: categoryPage)
            }
            .clipped().contentShape(Rectangle()).gesture(DragGesture().onEnded { v in
                if v.translation.width < -40 && categoryPage < totalPages - 1 { categoryPage += 1 }
                else if v.translation.width > 40 && categoryPage > 0 { categoryPage -= 1 }
            })
            PageNavigationButtons(currentPage: $categoryPage, totalPages: totalPages)
        }
    }

    @ViewBuilder
    func ItemPagingGrid(category: String, size: CGSize) -> some View {
        let items = menuItems.filter { $0.category == category }
        let itemsPerPage = 20
        let totalPages = max(1, Int(ceil(Double(items.count) / Double(itemsPerPage))))
        let squareSize = floor(min((size.width - 90) / 5, (size.height - 140) / 4))

        VStack(spacing: 0) {
            HStack {
                Button(action: { selectedCategory = nil }) {
                    HStack { Image(systemName: "chevron.left"); Text("返回分類") }.font(.headline).padding(10).background(Color.gray.opacity(0.15)).cornerRadius(8)
                }
                Spacer(); Text(category).font(.title).fontWeight(.bold); Spacer()
            }.padding(.horizontal).frame(height: 60)
            
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(0..<totalPages, id: \.self) { pageIdx in
                        let start = pageIdx * itemsPerPage
                        let end = min(start + itemsPerPage, items.count)
                        let columns = Array(repeating: GridItem(.fixed(squareSize), spacing: 15), count: 5)
                        VStack {
                            Spacer(minLength: 0)
                            LazyVGrid(columns: columns, spacing: 15) {
                                ForEach(items[start..<end]) { item in
                                    Button(action: { handleItemTap(item: item) }) {
                                        VStack {
                                            Text(item.name).font(.system(size: 16, weight: .bold)).foregroundColor(.primary).multilineTextAlignment(.center)
                                            Text("$\(item.price)").font(.headline).foregroundColor(.gray)
                                        }
                                        .frame(width: squareSize, height: squareSize).background(Color(UIColor.systemBackground)).cornerRadius(12).shadow(radius: 2, y: 2)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedItemForOptions?.id == item.id ? Color.blue : Color.clear, lineWidth: 3))
                                    }.buttonStyle(JapaneseButtonStyle())
                                }
                            }
                            .padding(.horizontal, 15)
                            Spacer(minLength: 0)
                        }.frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .offset(x: -CGFloat(itemPage) * geo.size.width)
                .animation(.easeInOut(duration: 0.25), value: itemPage)
            }
            .clipped().contentShape(Rectangle()).gesture(DragGesture().onEnded { v in
                if v.translation.width < -40 && itemPage < totalPages - 1 { itemPage += 1 }
                else if v.translation.width > 40 && itemPage > 0 { itemPage -= 1 }
            })
            PageNavigationButtons(currentPage: $itemPage, totalPages: totalPages)
        }
    }

    @ViewBuilder
    func OptionsBottomPanel(size: CGSize) -> some View {
        VStack(spacing: 0) {
            if let item = selectedItemForOptions, let groups = item.optionsGroup?.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                Text("\(item.name) - 客製化選項").font(.headline).padding(.top, 10)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 15) {
                        ForEach(allOptions.filter { groups.contains($0.group) }) { opt in
                            Button(action: { addOptionToCart(option: opt) }) {
                                VStack {
                                    Text(opt.name).font(.headline).fontWeight(.bold)
                                    Text(opt.price > 0 ? "+\(opt.price)元" : "免費").font(.subheadline)
                                }.frame(minWidth: 110, minHeight: 65).background(Color.orange.opacity(0.15)).foregroundColor(.orange).cornerRadius(10)
                            }.buttonStyle(JapaneseButtonStyle())
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 10)
                }
            } else {
                Text("等待選擇餐點...").foregroundColor(.gray).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Color(UIColor.systemGray6))
    }

    @ViewBuilder
    func TransactionHistoryPanelView(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack { Spacer(); Text("線上訂單交易紀錄").font(.title).fontWeight(.bold); Spacer() }.padding().frame(height: 70).background(Color(UIColor.systemGray6))
            Divider()
            HStack(spacing: 15) {
                ForEach(OrderDateFilter.allCases, id: \.self) { filter in
                    Button(filter.rawValue) {
                        selectedDateFilter = filter
                        Task { await fetchHistoryFromCloud() }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 24)
                    .background(selectedDateFilter == filter ? Color.blue : Color(UIColor.systemGray5))
                    .foregroundColor(selectedDateFilter == filter ? .white : .primary)
                    .cornerRadius(20)
                }
                Spacer()
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            let orders = filteredHistoryOrders
            if orders.isEmpty {
                VStack { Spacer(); Text("\(selectedDateFilter.rawValue)尚無任何紀錄").foregroundColor(.gray); Spacer() }
            } else {
                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(Array(orders.reversed())) { order in
                            OrderRow(order: order) { selectedWebOrder = order; currentPOSViewMode = .onlineOrders }
                        }
                    }.padding(20)
                }
            }
        }
    }

    @ViewBuilder
    func OnlineOrdersPanel(size: CGSize) -> some View {
        VStack(spacing: 0) {
            if let order = selectedWebOrder {
                HeaderView(selectedWebOrder: order, onBack: { selectedWebOrder = nil })
                OrderDetailContentView(order: order)
            } else {
                OrderListView(webOrders: webOrders.filter { $0.state == "PENDING" || $0.state == "READY" }, currentPage: $webOrderPage, selectedOrder: $selectedWebOrder)
            }
        }
    }

    @ViewBuilder
    func TempOrdersPanelView() -> some View {
        VStack(spacing: 0) {
            HStack { Text("訂單暫存區 (最多5筆)").font(.title2).fontWeight(.bold); Spacer(); Text("目前：\(tempSavedOrders.count) 筆").foregroundColor(.gray) }.padding().background(Color(UIColor.systemGray6))
            if tempSavedOrders.isEmpty {
                Spacer(); Text("暫無儲存訂單").foregroundColor(.gray); Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(tempSavedOrders) { order in
                            Button(action: { restoreOrderFromTemp(order) }) {
                                HStack {
                                    VStack(alignment: .leading) { Text(order.timeString).foregroundColor(.blue); Text("\(order.metadata.transactionType) - \(order.items.count) 品項") }
                                    Spacer(); Image(systemName: "chevron.right")
                                }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
                            }
                        }
                    }.padding()
                }
            }
            Button("返回點餐") { currentPOSViewMode = .manualOrdering }.font(.headline).padding().frame(maxWidth: .infinity).background(Color.gray).foregroundColor(.white).cornerRadius(12).padding()
        }
    }

    @ViewBuilder
    func CartListView() -> some View {
        List(cart) { item in
            let total = (item.menuItem.price + item.selectedOptions.reduce(0) { $0 + $1.price }) * item.quantity
            Button(action: { selectedCartItemID = item.id; selectedItemForOptions = item.menuItem }) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.menuItem.name).font(.headline).foregroundColor(selectedCartItemID == item.id ? .blue : .primary)
                        ForEach(Dictionary(grouping: item.selectedOptions, by: { $0.name }).map { $0.key }, id: \.self) { optName in
                            Text("・\(optName)").font(.subheadline).foregroundColor(.orange)
                        }
                    }
                    Spacer(); Text("$\(total)").fontWeight(.bold)
                }.padding(.vertical, 4)
            }
            .listRowBackground(selectedCartItemID == item.id ? Color.blue.opacity(0.1) : Color.clear)
        }.listStyle(.plain)
    }

    @ViewBuilder
    func PlaceholderView(title: String) -> some View {
        VStack { Text(title).font(.largeTitle); Button("返回點餐") { currentPOSViewMode = .manualOrdering }.padding().background(Color.blue).foregroundColor(.white).cornerRadius(10) }
    }

    @ViewBuilder
    func PopupOverlayView() -> some View {
        if showingOrderPopup, let order = incomingOrder {
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 0) {
                    VStack(spacing: 15) {
                        Text("🔔 收到新線上訂單！").font(.largeTitle).fontWeight(.bold).foregroundColor(.red)
                        Text("單號：\(order.orderId)").font(.title2).fontWeight(.bold)
                        Text("時間：\(order.timestamp)").font(.title3).foregroundColor(.gray)
                    }.frame(height: 240)
                    Divider()
                    HStack(spacing: 0) {
                        Button("訂單入機") { updateWebOrderState(orderId: order.orderId, newState: "READY") }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.blue).foregroundColor(.white)
                        Button("確認訂單內容") { showingOrderPopup = false; currentPOSViewMode = .onlineOrders; selectedWebOrder = nil }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(UIColor.systemGray5))
                    }.frame(height: 80)
                }.frame(width: 450, height: 320).background(Color(UIColor.systemBackground)).cornerRadius(20).shadow(radius: 20)
            }
        }
    }
    
    @ViewBuilder
    func HeaderView(selectedWebOrder: WebOrder?, onBack: @escaping () -> Void) -> some View {
        HStack {
            if selectedWebOrder != nil {
                Button(action: onBack) {
                    HStack { Image(systemName: "chevron.left"); Text("返回列表") }
                    .font(.title3).fontWeight(.bold).padding(10).background(Color.gray.opacity(0.15)).cornerRadius(8)
                }
            }
            Spacer()
            Text(selectedWebOrder == nil ? "今日線上訂單" : "訂單詳細內容").font(.title).fontWeight(.bold)
            Spacer()
            Color.clear.frame(width: 100, height: 10)
        }.padding().frame(height: 70)
    }
    
    @ViewBuilder
    func OrderDetailContentView(order: WebOrder) -> some View {
        let parsedData = order.details.data(using: .utf8) ?? Data()
        let items: [ParsedOrderItem] = (try? JSONDecoder().decode([ParsedOrderItem].self, from: parsedData)) ?? []
        let groupedItems = Dictionary(grouping: items, by: { $0.category ?? "其他" })

        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Text("單號：\(order.orderId)").font(.title2).fontWeight(.black)
                Text("時間：\(order.timestamp)").font(.headline).foregroundColor(.gray)
                Spacer()
                Text(order.state == "PENDING" ? "等待入機" : order.state)
                    .font(.headline).fontWeight(.bold).foregroundColor(.white)
                    .padding(.horizontal, 15).padding(.vertical, 8)
                    .background(order.state == "PENDING" ? Color.orange : Color.gray).cornerRadius(10)
            }.padding().background(Color(UIColor.systemGray6))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    ForEach(groupedItems.keys.sorted(), id: \.self) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            Text("【\(category)】").font(.title3).fontWeight(.heavy).foregroundColor(.blue)
                            if let categoryItems = groupedItems[category] {
                                ForEach(categoryItems, id: \.self) { item in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .top) {
                                            Text(item.name).font(.headline).fontWeight(.bold)
                                            Spacer()
                                            Text("- \(item.qty)").font(.title3).fontWeight(.black)
                                        }
                                        if let addons = item.addons, !addons.isEmpty {
                                            VStack(alignment: .leading, spacing: 4) {
                                                ForEach(addons, id: \.self) { addon in
                                                    let qtyText = (addon.qty ?? 1) > 1 ? " x\(addon.qty!)" : ""
                                                    Text("  - \(addon.name)\(qtyText)").font(.subheadline).foregroundColor(.gray)
                                                }
                                            }
                                        }
                                    }.padding(.leading, 10).padding(.bottom, 5)
                                }
                            }
                        }
                    }.padding(.horizontal)
                }.padding(.vertical, 20)
            }
            
            Divider()
            
            HStack(spacing: 15) {
                Button(action: {
                    HapticManager.shared.triggerSuccess()
                    updateWebOrderState(orderId: order.orderId, newState: "READY")
                }) {
                    Text("確認入機").font(.title3).fontWeight(.bold).foregroundColor(.white).frame(maxWidth: .infinity, maxHeight: 60).background(Color.blue).cornerRadius(12)
                }.buttonStyle(JapaneseButtonStyle())
                
                Button(action: {
                    HapticManager.shared.triggerLight()
                    selectedWebOrder = nil
                }) {
                    Text("回到上一頁").font(.title3).fontWeight(.bold).foregroundColor(.gray).frame(maxWidth: .infinity, maxHeight: 60).background(Color(UIColor.systemGray5)).cornerRadius(12)
                }.buttonStyle(JapaneseButtonStyle())
                
                Button(action: {
                    HapticManager.shared.triggerMedium()
                    updateWebOrderState(orderId: order.orderId, newState: "CANCELED")
                }) {
                    Text("取消訂單").font(.title3).fontWeight(.bold).foregroundColor(.white).frame(maxWidth: .infinity, maxHeight: 60).background(Color.red).cornerRadius(12)
                }.buttonStyle(JapaneseButtonStyle())
            }.padding().background(Color(UIColor.systemBackground))
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// ================= 6. 基礎元件 & 樣式 =================

struct LabeledInfoView: View {
    let title: String; let value: String
    var body: some View { HStack { Text("\(title)：").foregroundColor(.gray); Text(value).lineLimit(1).minimumScaleFactor(0.8); Spacer() }.font(.subheadline) }
}

struct FunctionPageButton: View {
    let icon: String; let height: CGFloat; let action: () -> Void; let isDisabled: Bool
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.title2).fontWeight(.bold).frame(maxWidth: .infinity, minHeight: height)
                .background(isDisabled ? Color.gray.opacity(0.1) : Color(UIColor.systemBackground))
                .foregroundColor(isDisabled ? .gray : .primary).cornerRadius(10)
        }.disabled(isDisabled).padding(.horizontal, 5)
    }
}

struct SquareFunctionButton: View {
    let title: String; let icon: String; let size: CGFloat; let action: () -> Void; var isCheckout: Bool = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.title2).fontWeight(.bold)
                Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.5)
            }
            .foregroundColor(isCheckout ? .white : .primary).frame(width: size, height: size)
            .background(isCheckout ? Color.blue : Color(UIColor.systemBackground))
            .cornerRadius(10).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        }.buttonStyle(JapaneseButtonStyle())
    }
}

struct PageNavigationButtons: View {
    @Binding var currentPage: Int; let totalPages: Int
    var body: some View {
        HStack(spacing: 15) {
            NavBtn(icon: "arrow.left", active: currentPage > 0) { currentPage -= 1 }
            NavBtn(icon: "arrow.right", active: currentPage < totalPages - 1) { currentPage += 1 }
        }
    }
    func NavBtn(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title).fontWeight(.bold).frame(width: 80, height: 50)
                .background(active ? Color.blue : Color.gray.opacity(0.3)).foregroundColor(.white).cornerRadius(10)
        }.disabled(!active)
    }
}

struct JapaneseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct HapticManager {
    static let shared = HapticManager()
    func triggerLight() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    func triggerMedium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    func triggerSuccess() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

class SoundManager {
    static let shared = SoundManager()
    func playTap() { AudioServicesPlaySystemSound(1104) }
    func playPop() { AudioServicesPlaySystemSound(1111) }
    func playSuccess() { AudioServicesPlaySystemSound(1001) }
}
