import SwiftUI

struct CheckoutPanelView: View {
    @ObservedObject var vm: POSViewModel
    let size: CGSize

    let paymentMethods = ["現金", "Line Pay", "信用卡", "街口支付"]
    @State private var selectedMethod = "現金"

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
                .frame(width: size.width * 0.45)
            Divider()
            rightPanel
        }
        .background(Color(UIColor.systemBackground))
    }

    // ================= 左半部：結帳明細 =================
    @ViewBuilder
    private var leftPanel: some View {
        VStack(spacing: 0) {
            Text("結帳明細")
                .font(.title)
                .fontWeight(.bold)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemGray5))
            Divider()

            ScrollView {
                VStack(spacing: 15) {
                    ForEach(vm.cart, id: \.id) { item in
                        cartItemRow(for: item)
                    }
                }
                .padding()
            }

            cartTotalFooter  // ⬅️ 拆出獨立 view
        }
    }

    // ================= 總計Footer =================
    @ViewBuilder
    private var cartTotalFooter: some View {
        HStack {
            Text("應收總計")
                .font(.title2)
            Spacer()
            Text("$\(vm.cartTotal)")
                .font(.system(size: 40, weight: .black))
                .foregroundColor(.red)
        }
        .padding(20)
        .background(Color(UIColor.systemGray6))
    }

    // ================= 右半部：支付與操作 =================
    @ViewBuilder
    private var rightPanel: some View {
        VStack(spacing: 0) {
            Text("選擇支付方式")
                .font(.title)
                .fontWeight(.bold)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemGray5))
            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                ForEach(paymentMethods, id: \.self) { method in
                    // 🌟 修正1：呼叫抽出來的獨立按鈕函數，拯救 Timeout 報錯
                    paymentMethodButton(for: method)
                }
            }
            .padding(20)

            Spacer()

            if selectedMethod == "現金" {
                cashHintView
            }

            Spacer()

            bottomActionButtons
        }
    }

    // ================= 現金提示 =================
    @ViewBuilder
    private var cashHintView: some View {
        VStack(spacing: 8) {
            Image(systemName: "banknote")
                // 🌟 修正2：恢復使用 font 來控制 SF Symbol 的大小，永遠不會有 frame 報錯
                .font(.system(size: 40))
                .foregroundColor(.green)
                .padding(.bottom, 5)
            Text("未來可擴充實收金額與找零計算")
                .foregroundColor(.gray)
        }
    }

// ================= 底部按鈕列 =================
    @ViewBuilder
    private var bottomActionButtons: some View {
        let isCartEmpty = vm.cart.isEmpty

        HStack(spacing: 20) {
            Button(action: {
                if vm.selectedWebOrder != nil {
                    vm.currentPOSViewMode = .onlineOrders
                } else {
                    vm.currentPOSViewMode = .manualOrdering
                }
            }) {
                Text("返回修改")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 70)
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(15)
            }
            .buttonStyle(JapaneseButtonStyle())

            Button(action: {
                Task {
                    await vm.submitOrder()
                }
            }) {
                HStack {
                    if vm.isLoading {
                        ProgressView().tint(.white).padding(.trailing, 10)
                    }
                    Text(vm.isLoading ? "正在送單..." : "確認結帳")
                }
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 70)
                .background(vm.isLoading ? Color.gray : Color.green)
                .foregroundColor(.white)
                .cornerRadius(15)
            }
            .buttonStyle(JapaneseButtonStyle())
            .disabled(isCartEmpty || vm.isLoading)
            .opacity((isCartEmpty || vm.isLoading) ? 0.5 : 1.0)
        }
        .padding(20)
    }

    @ViewBuilder
    private func paymentMethodButton(for method: String) -> some View {
        let isSelected = (selectedMethod == method)

        Button(action: { selectedMethod = method }) {
            paymentMethodLabel(method: method, isSelected: isSelected)
        }
        .buttonStyle(JapaneseButtonStyle())
    }

    @ViewBuilder
    private func paymentMethodLabel(method: String, isSelected: Bool) -> some View {
        let bgColor = isSelected ? Color(UIColor.systemBlue) : Color(UIColor.systemGray6)
        let fgColor = isSelected ? Color(UIColor.white) : Color(UIColor.label)
        let borderColor = isSelected ? Color(UIColor.systemBlue) : Color(UIColor.systemGray3)

        Text(method)
            .font(.title2)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80)  // ⬅️ 改用 minHeight/maxHeight
            .background(bgColor)
            .foregroundColor(fgColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )
    }

    @ViewBuilder
    private func cartItemRow(for item: CartItem) -> some View {
        let optionsPrice = item.selectedOptions.reduce(0) { $0 + $1.price }
        let itemTotal = item.isComplimentary ? 0 : ((item.menuItem.price + optionsPrice) * item.quantity)

        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.menuItem.name).font(.headline)
                    if item.isComplimentary {
                        Text("(招待)")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                    let groupedOptions = Dictionary(grouping: item.selectedOptions, by: { $0.name })
                    ForEach(groupedOptions.keys.sorted(), id: \.self) { optName in
                        let optCount = groupedOptions[optName]?.count ?? 0
                        Text("・\(optName)\(optCount > 1 ? " x\(optCount)" : "")")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                Text("x \(item.quantity)").font(.headline)
                Spacer()
                Text("$\(itemTotal)").font(.title3).fontWeight(.bold)
            }
            .padding(.bottom, 15)

            Divider()
        }
    }
}
