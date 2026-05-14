//
//  POSComponents.swift
//  SuPOS_iPad
//
//  Created by rabisu on 2026/5/13.
//

import SwiftUI
import AVFoundation
import AudioToolbox


// 通用資訊列
struct LabeledInfoView: View {
    let title: String; let value: String
    var body: some View { HStack { Text("\(title)：").foregroundColor(.gray); Text(value).lineLimit(1).minimumScaleFactor(0.8); Spacer() }.font(.subheadline) }
}

// 翻頁小按鍵
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

// 中間區域的方形大按鍵
struct SquareFunctionButton: View {
    let title: String
    let icon: String
    let size: CGFloat
    let action: () -> Void
    var isCheckout: Bool = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                // ★ 魔法 1：如果 title 是空的，代表是純圖示按鈕，我們就把圖示字體放大一點 (size: 32)
                Image(systemName: icon)
                    .font(title.isEmpty ? .system(size: 32, weight: .bold) : .title2)
                    .fontWeight(.bold)
                
                // ★ 魔法 2：只有當 title 不是空字串時，才產生 Text 元件。
                // 這樣如果是 "+" 或 "-"，就不會有隱形的字串把圖示往上擠，圖示就會完美置中！
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .foregroundColor(isCheckout ? .white : .primary)
            .frame(width: size, height: size)
            .background(isCheckout ? Color.blue : Color(UIColor.systemBackground))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(JapaneseButtonStyle())
    }
}

// 底部的左右翻頁鍵
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

// 按鍵的點擊縮放動畫特效
struct JapaneseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

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

// 全域共用工具
// 震動回饋
struct HapticManager {
    static let shared = HapticManager()
    func triggerLight() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    func triggerMedium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    func triggerSuccess() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// 音效
class SoundManager {
    static let shared = SoundManager()
    func playTap() { AudioServicesPlaySystemSound(1104) }
    func playPop() { AudioServicesPlaySystemSound(1111) }
    func playSuccess() { AudioServicesPlaySystemSound(1001) }
}

