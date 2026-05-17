import SwiftUI
import Combine

struct ContentView: View {
    // ★ 換腦手術的核心：宣告並綁定我們剛剛做好的 ViewModel
    @StateObject private var vm = POSViewModel()
    
    let pollingTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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
        .defersSystemGestures(on: .top)
        .overlay(PopupOverlayView())
        .onReceive(pollingTimer) { _ in Task { await vm.checkNewWebOrders() } }
        .task { await vm.fetchMenuData() }
        .onAppear {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeLeft))
            }
        }
    }

    // ================= UI 元件區 =================

    @ViewBuilder
    func OrderDetailsColumn(totalHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("訂單總覽").font(.headline).fontWeight(.bold).padding(.bottom, 2)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledInfoView(title: "建立時間", value: vm.formattedCreationTime)
                        LabeledInfoView(title: "交易型態", value: vm.orderMetadata.transactionType)
                        LabeledInfoView(title: "發票號碼", value: vm.orderMetadata.invoiceNumber)
                        LabeledInfoView(title: "統一編號", value: vm.orderMetadata.ubn)
                        LabeledInfoView(title: "發票載具", value: vm.orderMetadata.carrier)
                    }
                }
                Text("Ver: SuPOS_26may17_1_hermes")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
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
                Text("$\(vm.cartTotal)").font(.title3).fontWeight(.bold).foregroundColor(.red)
            }
            .padding(.horizontal)
            .frame(height: totalHeight * 0.05)
            .background(Color(UIColor.secondarySystemBackground))
        }
    }

    @ViewBuilder
    func FunctionTogglesColumn(totalHeight: CGFloat) -> some View {
        let columnWidth: CGFloat = 180
        let spacing: CGFloat = 8
        let buttonSize: CGFloat = (columnWidth - 24) / 2
        let topBottomButtonHeight: CGFloat = 60
        let arrowHeight: CGFloat = 45
        let fixedHeights = arrowHeight + buttonSize + 16
        let gridRowsPerPage = max(1, Int((totalHeight - fixedHeights) / (buttonSize + 8)))
        let buttonsPerPage = gridRowsPerPage * 2
        let totalPages = max(1, Int(ceil(Double(vm.allFunctionButtons.count) / Double(buttonsPerPage))))

        VStack(spacing: 0) {
            HStack(spacing: spacing) {
                Button(action: { withAnimation { vm.changeFunctionPage(by: -1, totalPages: totalPages) } }) {
                    Image(systemName: "chevron.up").font(.title2).foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.orange).cornerRadius(10)
                .opacity(totalPages <= 1 ? 0.5 : 1.0).disabled(totalPages <= 1)

                Button(action: { withAnimation { vm.changeFunctionPage(by: 1, totalPages: totalPages) } }) {
                    Image(systemName: "chevron.down").font(.title2).foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.orange).cornerRadius(10)
                .opacity(totalPages <= 1 ? 0.5 : 1.0).disabled(totalPages <= 1)
            }
            .frame(width: columnWidth - (spacing * 2), height: topBottomButtonHeight)
            .padding(.top, spacing * 1.5).padding(.bottom, spacing)

            GeometryReader { geo in
                VStack(spacing: 0) {
                    ForEach(0..<totalPages, id: \.self) { pageIndex in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            let start = pageIndex * buttonsPerPage
                            let end = min(start + buttonsPerPage, vm.allFunctionButtons.count)
                            
                            LazyVGrid(columns: [
                                GridItem(.fixed(buttonSize), spacing: spacing),
                                GridItem(.fixed(buttonSize))
                            ], spacing: spacing) {
                                ForEach(start..<end, id: \.self) { idx in
                                    let btn = vm.allFunctionButtons[idx]
                                    SquareFunctionButton(title: btn.title, icon: btn.icon, size: buttonSize, action: btn.action)
                                }
                                if (end - start) < buttonsPerPage {
                                    ForEach(0..<(buttonsPerPage - (end - start)), id: \.self) { _ in
                                        Color.clear.frame(width: buttonSize, height: buttonSize)
                                    }
                                }
                            }
                            .padding(.horizontal, spacing)
                            Spacer(minLength: 0)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .offset(y: -CGFloat(vm.currentFunctionPage) * geo.size.height)
                .animation(.easeInOut(duration: 0.25), value: vm.currentFunctionPage)
            }
            .clipped().contentShape(Rectangle())
            .gesture(DragGesture().onEnded { value in
                if value.translation.height < -30 { withAnimation { vm.changeFunctionPage(by: 1, totalPages: totalPages) } }
                else if value.translation.height > 30 { withAnimation { vm.changeFunctionPage(by: -1, totalPages: totalPages) } }
            })

            Spacer(minLength: spacing)
            Button(action: { vm.currentPOSViewMode = .checkout }) {
                VStack(spacing: 4) {
                    Image(systemName: "cart.fill").font(.title2)
                    Text("結帳").font(.headline)
                }
                .frame(width: columnWidth - (spacing * 2), height: topBottomButtonHeight)
                .foregroundColor(.white).background(Color.orange).cornerRadius(10)
            }
            .padding(.bottom, spacing)
        }
        .frame(width: columnWidth, height: totalHeight)
        .background(Color(UIColor.secondarySystemBackground))
    }

    @ViewBuilder
    func FunctionDisplayColumn() -> some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if vm.isLoading {
                    ProgressView("正在同步雲端菜單...").scaleEffect(1.5).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch vm.currentPOSViewMode {
                    case .manualOrdering: ManualOrderingView(size: geo.size)
                    case .transactionHistory: TransactionHistoryPanelView(size: geo.size)
                    case .onlineOrders: OnlineOrdersPanel(size: geo.size)
                    case .tempOrders: TempOrdersPanelView()
                    case .checkout: CheckoutPanelView(vm: vm, size: geo.size)
                    case .dailyTurnover: DailyTurnoverPanelView(size: geo.size)
                    }
                }
            }
            .background(Color(UIColor.systemBackground))
        }
    }
}

// ================= 子視圖元件 (Subviews) =================
extension ContentView {
    @ViewBuilder
    func ManualOrderingView(size: CGSize) -> some View {
        if let category = vm.selectedCategory {
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
        let totalPages = max(1, Int(ceil(Double(vm.categories.count) / Double(itemsPerPage))))
        let squareSize = floor(min((size.width - 90) / 5, (size.height - 140) / 4))

        VStack(spacing: 0) {
            Text("請選擇餐點分類").font(.title).fontWeight(.bold).frame(height: 60)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(0..<totalPages, id: \.self) { pageIdx in
                        let start = pageIdx * itemsPerPage
                        let end = min(start + itemsPerPage, vm.categories.count)
                        let columns = Array(repeating: GridItem(.fixed(squareSize), spacing: 15), count: 5)
                        VStack {
                            Spacer(minLength: 0)
                            LazyVGrid(columns: columns, spacing: 15) {
                                ForEach(vm.categories[start..<end], id: \.self) { cat in
                                    Button(action: { vm.selectedCategory = cat; vm.itemPage = 0 }) {
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
                .offset(x: -CGFloat(vm.categoryPage) * geo.size.width)
                .animation(.easeInOut(duration: 0.25), value: vm.categoryPage)
            }
            .clipped().contentShape(Rectangle()).gesture(DragGesture().onEnded { v in
                if v.translation.width < -40 && vm.categoryPage < totalPages - 1 { vm.categoryPage += 1 }
                else if v.translation.width > 40 && vm.categoryPage > 0 { vm.categoryPage -= 1 }
            })
            PageNavigationButtons(currentPage: $vm.categoryPage, totalPages: totalPages)
        }
    }

    @ViewBuilder
    func ItemPagingGrid(category: String, size: CGSize) -> some View {
        let items = vm.menuItems.filter { $0.category == category }
        let itemsPerPage = 20
        let totalPages = max(1, Int(ceil(Double(items.count) / Double(itemsPerPage))))
        let squareSize = floor(min((size.width - 90) / 5, (size.height - 140) / 4))

        VStack(spacing: 0) {
            HStack {
                Button(action: { vm.selectedCategory = nil }) {
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
                                    Button(action: { vm.handleItemTap(item: item) }) {
                                        VStack {
                                            Text(item.name).font(.system(size: 16, weight: .bold)).foregroundColor(.primary).multilineTextAlignment(.center)
                                            Text("$\(item.price)").font(.headline).foregroundColor(.gray)
                                        }
                                        .frame(width: squareSize, height: squareSize).background(Color(UIColor.systemBackground)).cornerRadius(12).shadow(radius: 2, y: 2)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(vm.selectedItemForOptions?.id == item.id ? Color.blue : Color.clear, lineWidth: 3))
                                    }.buttonStyle(JapaneseButtonStyle())
                                }
                            }
                            .padding(.horizontal, 15)
                            Spacer(minLength: 0)
                        }.frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .offset(x: -CGFloat(vm.itemPage) * geo.size.width)
                .animation(.easeInOut(duration: 0.25), value: vm.itemPage)
            }
            .clipped().contentShape(Rectangle()).gesture(DragGesture().onEnded { v in
                if v.translation.width < -40 && vm.itemPage < totalPages - 1 { vm.itemPage += 1 }
                else if v.translation.width > 40 && vm.itemPage > 0 { vm.itemPage -= 1 }
            })
            PageNavigationButtons(currentPage: $vm.itemPage, totalPages: totalPages)
        }
    }

    @ViewBuilder
    func OptionsBottomPanel(size: CGSize) -> some View {
        VStack(spacing: 0) {
            if let item = vm.selectedItemForOptions, let groups = item.optionsGroup?.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                Text("\(item.name) - 客製化選項").font(.headline).padding(.top, 10)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 15) {
                        ForEach(vm.allOptions.filter { groups.contains($0.group) }) { opt in
                            Button(action: { vm.addOptionToCart(option: opt) }) {
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
                        vm.selectedDateFilter = filter
                        Task { await vm.fetchHistoryFromCloud() }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 24)
                    .background(vm.selectedDateFilter == filter ? Color.blue : Color(UIColor.systemGray5))
                    .foregroundColor(vm.selectedDateFilter == filter ? .white : .primary)
                    .cornerRadius(20)
                }
                Spacer()
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            let orders = vm.filteredHistoryOrders
            if orders.isEmpty {
                VStack { Spacer(); Text("\(vm.selectedDateFilter.rawValue)尚無任何紀錄").foregroundColor(.gray); Spacer() }
            } else {
                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(Array(orders.reversed())) { order in
                            OrderRow(order: order) { vm.selectedWebOrder = order; vm.currentPOSViewMode = .onlineOrders }
                        }
                    }.padding(20)
                }
            }
        }
    }

    @ViewBuilder
    func OnlineOrdersPanel(size: CGSize) -> some View {
        VStack(spacing: 0) {
            if let order = vm.selectedWebOrder {
                HeaderView(selectedWebOrder: order, onBack: { vm.selectedWebOrder = nil })
                OrderDetailContentView(order: order)
            } else {
                OrderListView(webOrders: vm.webOrders.filter { $0.state == "PENDING" || $0.state == "READY" }, currentPage: $vm.webOrderPage, selectedOrder: $vm.selectedWebOrder)
            }
        }
    }

    @ViewBuilder
    func TempOrdersPanelView() -> some View {
        VStack(spacing: 0) {
            HStack { Text("訂單暫存區 (最多5筆)").font(.title2).fontWeight(.bold); Spacer(); Text("目前：\(vm.tempSavedOrders.count) 筆").foregroundColor(.gray) }.padding().background(Color(UIColor.systemGray6))
            if vm.tempSavedOrders.isEmpty {
                Spacer(); Text("暫無儲存訂單").foregroundColor(.gray); Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(vm.tempSavedOrders) { order in
                            Button(action: { vm.restoreOrderFromTemp(order) }) {
                                HStack {
                                    VStack(alignment: .leading) { Text(order.timeString).foregroundColor(.blue); Text("\(order.metadata.transactionType) - \(order.items.count) 品項") }
                                    Spacer(); Image(systemName: "chevron.right")
                                }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
                            }
                        }
                    }.padding()
                }
            }
            Button("返回點餐") { vm.currentPOSViewMode = .manualOrdering }.font(.headline).padding().frame(maxWidth: .infinity).background(Color.gray).foregroundColor(.white).cornerRadius(12).padding()
        }
    }

    @ViewBuilder
    func CartListView() -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.cart, id: \.id) { item in
                    let optionsPrice = item.selectedOptions.reduce(0) { $0 + $1.price }
                    let total = (item.menuItem.price + optionsPrice) * item.quantity

                    Button(action: {
                        vm.selectedCartItemID = item.id
                        vm.selectedItemForOptions = item.menuItem
                    }) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.menuItem.name)
                                        .font(.headline)
                                        .foregroundColor(vm.selectedCartItemID == item.id ? .blue : .primary)

                                    if item.isComplimentary {
                                        Text("(招待)")
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.red)
                                    }
                                }

                                ForEach(Dictionary(grouping: item.selectedOptions, by: { $0.name }).map { $0.key }, id: \.self) { optName in
                                    Text("・\(optName)")
                                        .font(.subheadline)
                                        .foregroundColor(.orange)
                                }
                            }
                            Spacer()
                            Text("$\(item.isComplimentary ? 0 : total)")
                                .fontWeight(.bold)
                                .foregroundColor(item.isComplimentary ? .red : .primary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                    .background(vm.selectedCartItemID == item.id ? Color.blue.opacity(0.1) : Color.clear)

                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    func PlaceholderView(title: String) -> some View {
        VStack { Text(title).font(.largeTitle); Button("返回點餐") { vm.currentPOSViewMode = .manualOrdering }.padding().background(Color.blue).foregroundColor(.white).cornerRadius(10) }
    }

    @ViewBuilder
    func PopupOverlayView() -> some View {
        if vm.showingOrderPopup, let order = vm.incomingOrder {
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
                        Button("訂單入機") { vm.updateWebOrderState(orderId: order.orderId, newState: "READY") }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.blue).foregroundColor(.white)
                        Button("確認訂單內容") { vm.showingOrderPopup = false; vm.currentPOSViewMode = .onlineOrders; vm.selectedWebOrder = nil }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(UIColor.systemGray5))
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
                
                // 🌟 新增：金流狀態標籤
                Text(order.paymentStatus == "PAID" ? "已結帳" : "未結帳")
                    .font(.headline).fontWeight(.bold).foregroundColor(.white)
                    .padding(.horizontal, 15).padding(.vertical, 8)
                    .background(order.paymentStatus == "PAID" ? Color.green : Color.red).cornerRadius(10)
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
                    }
                }.padding(.horizontal)
            }.padding(.vertical, 20)
            Divider()
            HStack(spacing: 15) {
                
                // 🌟 新增：帶入結帳按鈕 (僅未結帳且未取消時顯示)
                if order.paymentStatus != "PAID" && order.state != "CANCELED" {
                    Button(action: {
                        HapticManager.shared.triggerSuccess()
                        vm.prepareWebOrderForCheckout(order: order)
                    }) {
                        Text("帶入結帳").font(.title3).fontWeight(.bold).foregroundColor(.white).frame(maxWidth: .infinity, maxHeight: 60).background(Color.orange).cornerRadius(12)
                    }.buttonStyle(JapaneseButtonStyle())
                }
                Button(action: {
                    HapticManager.shared.triggerSuccess()
                    vm.updateWebOrderState(orderId: order.orderId, newState: "READY")
                }) {
                    Text("確認入機").font(.title3).fontWeight(.bold).foregroundColor(.white).frame(maxWidth: .infinity, maxHeight: 60).background(Color.blue).cornerRadius(12)
                }.buttonStyle(JapaneseButtonStyle())
                Button(action: {
                    HapticManager.shared.triggerLight()
                    vm.selectedWebOrder = nil
                }) {
                    Text("回到上一頁").font(.title3).fontWeight(.bold).foregroundColor(.gray).frame(maxWidth: .infinity, maxHeight: 60).background(Color(UIColor.systemGray5)).cornerRadius(12)
                    
                }.buttonStyle(JapaneseButtonStyle())
                Button(action: {
                    HapticManager.shared.triggerMedium()
                    vm.updateWebOrderState(orderId: order.orderId, newState: "CANCELED")
                }) {
                    
                    Text("取消訂單").font(.title3).fontWeight(.bold).foregroundColor(.white).frame(maxWidth: .infinity, maxHeight: 60).background(Color.red).cornerRadius(12)
                }.buttonStyle(JapaneseButtonStyle())
            }.padding().background(Color(UIColor.systemBackground))
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    // ================= 日營業額統計面板 =================
    @ViewBuilder
    func DailyTurnoverPanelView(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 25) {
            Text("日營業額統計")
                .font(.title)
                .fontWeight(.bold)
            Divider()
            
            VStack(spacing: 20) {
                HStack {
                    Text("今日營業額：").font(.title2)
                    Spacer()
                    Text("$\(Int(vm.todayTurnover))")
                        .font(.system(size: 48, weight: .black))
                        .foregroundColor(.blue)
                }
                HStack { Text("現金：").font(.title2); Spacer(); Text("-").font(.title2).foregroundColor(.gray) }
                HStack { Text("Uber Eats：").font(.title2); Spacer(); Text("-").font(.title2).foregroundColor(.gray) }
                HStack { Text("FoodPanda：").font(.title2); Spacer(); Text("-").font(.title2).foregroundColor(.gray) }
            }
            .padding(25)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(15)
            
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(UIColor.systemBackground))
        .onAppear {
            // 畫面一出現就自動呼叫 ViewModel 去抓歷史訂單
            Task { await vm.fetchHistoryOrders() }
        }
    }
}
