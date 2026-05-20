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
                Text("Ver: SuPOS_26may19_2_rabi")
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
        VStack(spacing: 0) {
            TopCategoryGrid(size: CGSize(width: size.width, height: size.height * 0.30))
            Divider()
            if let category = vm.selectedCategory {
                ItemPagingGrid(category: category, size: CGSize(width: size.width, height: size.height * 0.35))
            } else {
                VStack { Spacer(); Text("請先選擇分類").foregroundColor(.gray); Spacer() }
                    .frame(width: size.width, height: size.height * 0.35)
            }
            Divider()
            PageNavigationControl(size: CGSize(width: size.width, height: size.height * 0.10))
            Divider()
            OptionsBottomPanel(size: CGSize(width: size.width, height: size.height * 0.25))
        }
    }
    
    @ViewBuilder
    func TopCategoryGrid(size: CGSize) -> some View {
        let itemsPerPage = 10 // 🌟 5欄 x 2列 = 每頁 10 個
        let totalPages = max(1, Int(ceil(Double(vm.categories.count) / Double(itemsPerPage))))
        
        // 依據 30% 的新高度精確計算按鈕尺寸，完美填滿不留大白邊
        let squareWidth = floor((size.width - 90) / 5)
        let squareHeight = floor((size.height - 50) / 2)

        VStack(spacing: 0) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(0..<totalPages, id: \.self) { pageIdx in
                        let start = pageIdx * itemsPerPage
                        let end = min(start + itemsPerPage, vm.categories.count)
                        let columns = Array(repeating: GridItem(.fixed(squareWidth), spacing: 15), count: 5)
                        
                        VStack {
                            Spacer(minLength: 0)
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(vm.categories[start..<end], id: \.self) { cat in
                                    Button(action: {
                                        vm.selectedCategory = cat
                                        vm.itemPage = 0
                                        vm.selectedItemForOptions = nil
                                    }) {
                                        Text(cat)
                                            // 調整餐點分類按鍵中的字體大小
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundColor(vm.selectedCategory == cat ? .white : .blue)
                                            .frame(width: squareWidth, height: squareHeight)
                                            .background(
                                                vm.selectedCategory == cat
                                                ? LinearGradient(colors: [.orange.opacity(0.8), .orange], startPoint: .top, endPoint: .bottom)
                                                : LinearGradient(colors: [.blue.opacity(0.1), .blue.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                                            )
                                            .cornerRadius(12)
                                            .shadow(radius: vm.selectedCategory == cat ? 3 : 0, y: vm.selectedCategory == cat ? 4 : 0)
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
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture().onEnded { v in
                if v.translation.width < -40 && vm.categoryPage < totalPages - 1 { vm.categoryPage += 1 }
                else if v.translation.width > 40 && vm.categoryPage > 0 { vm.categoryPage -= 1 }
            })
            
            // 🌟 底部優雅的小圓點分頁提示
            if totalPages > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(vm.categoryPage == index ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .frame(height: size.height)
        .background(Color(UIColor.systemGray6))
    }


        @ViewBuilder
    func CategoryPagingGrid(size: CGSize) -> some View {
        let itemsPerPage = 15
        let totalPages = max(1, Int(ceil(Double(vm.categories.count) / Double(itemsPerPage))))
        let squareSize = floor(min((size.width - 90) / 5, (size.height - 140) / 3))

        VStack(spacing: 0) {
            Text("請選擇餐點分類")
                .font(.title)
                .fontWeight(.bold)
                .frame(height: 60)
            
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
                                        Text(cat)
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .frame(width: squareSize, height: squareSize)
                                            .background(LinearGradient(colors: [.blue.opacity(0.7), .blue], startPoint: .top, endPoint: .bottom))
                                            .cornerRadius(12)
                                            .shadow(radius: 3, y: 4)
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
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture().onEnded { v in
                if v.translation.width < -40 && vm.categoryPage < totalPages - 1 { vm.categoryPage += 1 }
                else if v.translation.width > 40 && vm.categoryPage > 0 { vm.categoryPage -= 1 }
            })
            
            if totalPages > 1 {
                HStack(spacing: 10) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(vm.categoryPage == index ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                            .animation(.easeInOut(duration: 0.2), value: vm.categoryPage)
                    }
                }
                .padding(.top, 15)
                .padding(.bottom, 25)
            }
            // PageNavigationButtons(currentPage: $vm.categoryPage, totalPages: totalPages)
        }
    }

    @ViewBuilder
    // 手動點餐的中間層按鍵佈局
    func ItemPagingGrid(category: String, size: CGSize) -> some View {
        let items = vm.menuItems.filter { $0.category == category }
        let itemsPerPage = 15 // 🌟 改為 5欄 x 2列 = 每頁 10 個
        let totalPages = max(1, Int(ceil(Double(items.count) / Double(itemsPerPage))))
        
        // 精確計算餐點按鈕尺寸，完美填滿中間的 50% 高度
        let squareWidth = floor((size.width - 90) / 5)      // 按鍵寬度
        // let squareHeight = floor((size.height - 50) / 2)    // 按鍵高度
        let squareHeight: CGFloat = 70 // 🌟 直接鎖死高度在110

        

        VStack(spacing: 0) {
            // 🚫 原本這裡的「返回分類」和「分類名稱」HStack 已經被徹底移除，釋放空間！

            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(0..<totalPages, id: \.self) { pageIdx in
                        let start = pageIdx * itemsPerPage
                        let end = min(start + itemsPerPage, items.count)
                        let columns = Array(repeating: GridItem(.fixed(squareWidth), spacing: 15), count: 5)
                        
                        VStack {
                            LazyVGrid(columns: columns, spacing: 15) {
                                ForEach(items[start..<end]) { item in
                                    Button(action: { vm.handleItemTap(item: item) }) {
                                        VStack(spacing: 8) {
                                            Text(item.name)
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundColor(.primary)
                                                .multilineTextAlignment(.center)
                                            // Text("$\(item.price)") 在單品的按鍵上顯示金額
                                                .lineLimit(2) //允許文字最多折成2行
                                                .minimumScaleFactor(0.8) // 如果品項名稱太長，字體會自動的稍微縮小一些以求完整顯示
                                                .padding(.horizontal, 4) // 左右留一點空間，不要貼齊邊緣
                                        }
                                        .frame(width: squareWidth, height: squareHeight)
                                        .background(Color(UIColor.systemBackground))
                                        .cornerRadius(12)
                                        .shadow(radius: 2, y: 2)
                                        // 如果被選中，加上藍色外框
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(vm.selectedItemForOptions?.id == item.id ? Color.blue : Color.clear, lineWidth: 3))
                                    }.buttonStyle(JapaneseButtonStyle())
                                }
                            }
                            .padding(.horizontal, 15)
                            .padding(.top, 15)
                            Spacer(minLength: 0)
                        }.frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .offset(x: -CGFloat(vm.itemPage) * geo.size.width)
                .animation(.easeInOut(duration: 0.25), value: vm.itemPage)
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture().onEnded { v in
                // 處理左右滑動翻頁
                if v.translation.width < -40 && vm.itemPage < totalPages - 1 { vm.itemPage += 1 }
                else if v.translation.width > 40 && vm.itemPage > 0 { vm.itemPage -= 1 }
            })
            
            // 🌟 加入 iOS 原生質感的小圓點分頁提示
            if totalPages > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(vm.itemPage == index ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 5)
                .padding(.bottom, 10)
            }
        }
    }


    @ViewBuilder
    func OptionsBottomPanel(size: CGSize) -> some View {
        if let item = vm.selectedItemForOptions,
           let cartId = vm.selectedCartItemID,
           let cartIndex = vm.cart.firstIndex(where: { $0.id == cartId }) {
            
            let availableGroups = item.optionsGroup?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
            let allMatchedOptions = vm.allOptions.filter { availableGroups.contains($0.group) }
            let singleOptions = allMatchedOptions.filter { ($0.optionType ?? "").lowercased() == "single" }
            let multiOptions = allMatchedOptions.filter { ($0.optionType ?? "").lowercased() == "multi" }
            
            // 🌟 核心魔法：將陣列切割成 3x2 (每頁 6 個) 與 2x2 (每頁 4 個)
            let singleChunks = stride(from: 0, to: singleOptions.count, by: 6).map { Array(singleOptions[$0..<min($0 + 6, singleOptions.count)]) }
            let multiChunks = stride(from: 0, to: multiOptions.count, by: 4).map { Array(multiOptions[$0..<min($0 + 4, multiOptions.count)]) }
            
            HStack(spacing: 0) {
                // 🌟 左側 60%：單選替換區 (3 欄 x 2 列)
                VStack(spacing: 0) {
                    Text("單選替換區").font(.caption).fontWeight(.bold).foregroundColor(.orange).padding(.top, 5)
                    if singleChunks.isEmpty { Spacer() } else {
                        TabView {
                            ForEach(0..<singleChunks.count, id: \.self) { pageIdx in
                                VStack {
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                        ForEach(singleChunks[pageIdx]) { opt in
                                            let isSelected = vm.cart[cartIndex].selectedOptions.contains(where: { $0.id == opt.id })
                                            Button(action: {
                                                vm.cart[cartIndex].selectedOptions.removeAll(where: { $0.group == opt.group })
                                                if !isSelected { vm.cart[cartIndex].selectedOptions.append(opt) }
                                            }) { OptionButtonUI(opt: opt, isSelected: isSelected) }
                                        }
                                    }
                                    Spacer()
                                }.padding(10)
                            }
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                    }
                }.frame(width: size.width * 0.6).background(Color.orange.opacity(0.05))
                
                Divider()
                
                // 🌟 右側 40%：加料複選區 (2 欄 x 2 列)
                VStack(spacing: 0) {
                    Text("加料複選區").font(.caption).fontWeight(.bold).foregroundColor(.blue).padding(.top, 5)
                    if multiChunks.isEmpty { Spacer() } else {
                        TabView {
                            ForEach(0..<multiChunks.count, id: \.self) { pageIdx in
                                VStack {
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                                        ForEach(multiChunks[pageIdx]) { opt in
                                            let isSelected = vm.cart[cartIndex].selectedOptions.contains(where: { $0.id == opt.id })
                                            Button(action: {
                                                // 🌟 直接新增，不再作切換。點幾下就加幾份！
                                                vm.cart[cartIndex].selectedOptions.append(opt)
                                                vm.selectedOptionName = opt.name // 🌟 自動選中它，方便客人反悔時直接按左側的 ➖
                                            }) { OptionButtonUI(opt: opt, isSelected: isSelected) }
                                        }
                                    }
                                    Spacer()
                                }.padding(10)
                            }
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                    }
                }.frame(width: size.width * 0.4).background(Color.blue.opacity(0.05))
            }.frame(width: size.width, height: size.height).background(Color(UIColor.systemGray6))
        } else {
            Text("等待選擇餐點...").foregroundColor(.gray).frame(maxWidth: .infinity, maxHeight: .infinity).frame(height: size.height).background(Color(UIColor.systemGray6))
        }
    }
    
    @ViewBuilder
    func OptionButtonUI(opt: OptionItem, isSelected: Bool) -> some View {
        VStack(spacing: 4) {
            Text(opt.name)
                .font(.system(size: 15, weight: .bold))
                .multilineTextAlignment(.center)
            
            Text(opt.price > 0 ? "+\(opt.price)元" : (opt.price < 0 ? "\(opt.price)元" : "免費"))
                .font(.system(size: 13))
        }
        .frame(height: 55)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.blue : Color(UIColor.systemBackground))
        .foregroundColor(isSelected ? .white : .primary)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 0 : 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 2)
    }
    
    @ViewBuilder
    func PageNavigationControl(size: CGSize) -> some View {
        let items = vm.menuItems.filter { $0.category == vm.selectedCategory ?? "" }
        let itemsPerPage = 15
        let totalPages = max(1, Int(ceil(Double(items.count) / Double(itemsPerPage))))
        
        HStack {
            // 左側翻頁按鈕
            Button(action: { if vm.itemPage > 0 { vm.itemPage -= 1 } }) {
                Image(systemName: "chevron.left.2")
                    .font(.title).fontWeight(.bold)
                    .frame(width: 100, height: size.height * 0.8)
                    .background(vm.itemPage > 0 ? Color.gray.opacity(0.2) : Color.clear)
                    .foregroundColor(vm.itemPage > 0 ? .primary : .gray.opacity(0.3))
                    .cornerRadius(10)
            }
            .disabled(vm.itemPage <= 0)
            
            Spacer()
            
            // 中間分頁資訊
            if vm.selectedCategory != nil {
                Text("第 \(vm.itemPage + 1) 頁 / 共 \(totalPages) 頁")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 右側翻頁按鈕
            Button(action: { if vm.itemPage < totalPages - 1 { vm.itemPage += 1 } }) {
                Image(systemName: "chevron.right.2")
                    .font(.title).fontWeight(.bold)
                    .frame(width: 100, height: size.height * 0.8)
                    .background(vm.itemPage < totalPages - 1 ? Color.gray.opacity(0.2) : Color.clear)
                    .foregroundColor(vm.itemPage < totalPages - 1 ? .primary : .gray.opacity(0.3))
                    .cornerRadius(10)
            }
            .disabled(vm.itemPage >= totalPages - 1)
        }
        .padding(.horizontal, 20)
        .frame(width: size.width, height: size.height)
        .background(Color(UIColor.systemBackground))
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
                        vm.selectedOptionName = nil
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

                                let groupedOptions = Dictionary(grouping: item.selectedOptions, by: { $0.name })
                                ForEach(groupedOptions.keys.sorted(), id: \.self) { optName in
                                    let opts = groupedOptions[optName] ?? []
                                    let optCount = opts.count
                                    let isSingle = (opts.first?.optionType ?? "").lowercased() == "single"

                                    if isSingle {
                                        // 🌟 單選替換區：淡橘色背景，滿版寬度，不可獨立調整數量 (點擊時清空 selectedOptionName)
                                        Button(action: {
                                            vm.selectedCartItemID = item.id
                                            vm.selectedItemForOptions = item.menuItem
                                            vm.selectedOptionName = nil // 確保不會進入加料調整模式
                                        }) {
                                            HStack {
                                                Text("・\(optName)")
                                                    .font(.subheadline)
                                                    .foregroundColor(.orange)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 8).padding(.vertical, 6)
                                            .frame(maxWidth: .infinity, alignment: .leading) // 🌟 和購物車同寬
                                            .background(Color.orange.opacity(0.1))
                                            .cornerRadius(6)
                                        }
                                    } else {
                                        // 🌟 加料複選區：淡藍色背景，滿版寬度，可點擊進入調整模式
                                        let isSelectedOption = (vm.selectedCartItemID == item.id && vm.selectedOptionName == optName)
                                        Button(action: {
                                            vm.selectedCartItemID = item.id
                                            vm.selectedItemForOptions = item.menuItem
                                            vm.selectedOptionName = optName // 選中此加料，允許 +/- 調整
                                        }) {
                                            HStack {
                                                Text("・\(optName)\(optCount > 1 ? " x\(optCount)" : "")")
                                                    .font(.subheadline).fontWeight(.bold)
                                                    .foregroundColor(isSelectedOption ? .white : .blue)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 8).padding(.vertical, 6)
                                            .frame(maxWidth: .infinity, alignment: .leading) // 🌟 和購物車同寬
                                            .background(isSelectedOption ? Color.blue : Color.blue.opacity(0.1))
                                            .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                            Spacer()
                            
                            // 🌟 新增的數量顯示區塊 🌟
                            // 注意：你的變數名稱是 item.quantity，不是 qty 喔！
                            if item.quantity > 1 {
                                Text("x\(item.quantity)")
                                    .font(.title3) // 字體稍微放大一點
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                    .padding(.trailing, 8) // 和右邊的金額稍微拉開呼吸空間
                            }
                            
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
            // 🚫 移除「返回列表」按鍵，避免畫面重複衝突
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
        
        // 🌟 1. 提早把排序好的陣列抽出來，減輕 ForEach 的推理負擔
        let sortedCategories = groupedItems.keys.sorted()
        
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Text("單號：\(order.orderId)").font(.title2).fontWeight(.black)
                Text("時間：\(order.timestamp)").font(.headline).foregroundColor(.gray)
                Spacer()
                
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
                    ForEach(sortedCategories, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            Text("【\(category)】").font(.title3).fontWeight(.heavy).foregroundColor(.blue)
                            if let categoryItems = groupedItems[category] {
                                ForEach(categoryItems, id: \.self) { item in
                                    OrderDetailItemRow(item: item, vm: vm)
                                }
                            }
                        }
                    }
                }.padding(.horizontal)
            }.padding(.vertical, 20)
            
            Divider()
            
            HStack(spacing: 15) {
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
                    if order.paymentStatus == "PAID" || order.state == "CANCELED" {
                        vm.currentPOSViewMode = .transactionHistory
                    }
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

    // 專門用來處理每一列餐點顯示的子視圖
    @ViewBuilder
    func OrderDetailItemRow(item: ParsedOrderItem, vm: POSViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.headline).fontWeight(.bold)
                    
                    // 🌟 聰明比對：拿訂單的「餐點名稱」去 POS 菜單庫裡面查價格
                    let matchedItem = vm.menuItems.first(where: { $0.name == item.name })
                    let itemPrice = matchedItem?.price ?? 0
                    
                    Text("$\(itemPrice)").font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Text("x \(item.qty)").font(.title3).fontWeight(.black).foregroundColor(.blue)
            }
            
            if let addons = item.addons, !addons.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(addons, id: \.self) { addon in
                        let qtyText = (addon.qty ?? 1) > 1 ? " x\(addon.qty!)" : ""
                        
                        // 🌟 聰明比對：拿訂單的「選項名稱」去 POS 客製化選項庫裡面查價格
                        let matchedOption = vm.allOptions.first(where: { $0.name == addon.name })
                        let addonPrice = matchedOption?.price ?? 0
                        let priceText = addonPrice > 0 ? " (+\(addonPrice)元)" : ""
                        
                        Text("  - \(addon.name)\(qtyText)\(priceText)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(.leading, 10)
        .padding(.bottom, 5)
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
