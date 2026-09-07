import SwiftUI

/// "Which meal is this?" — chips for each meal-plan slot plus Other. Used by every logging path
/// (photo, library, typed search, barcode, AI text) before the entry is saved.
struct SlotPicker: View {
    @Binding var slot: String?
    @Environment(Store.self) private var store

    private static let other = "__other__"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log this as").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Plan.meals) { m in
                        chip(title: m.name, subtitle: store.kcal(slot: m.key) > 0 ? "\(Int(store.kcal(slot: m.key).rounded())) logged" : m.kcal,
                             selected: slot == m.key) { slot = m.key }
                    }
                    chip(title: "🍽️ Other", subtitle: "no slot", selected: slot == nil) { slot = nil }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func chip(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 13, weight: .bold))
                Text(subtitle).font(.system(size: 10))
            }
            .foregroundStyle(selected ? .white : Theme.text)
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(selected ? Theme.primary : Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Theme.primary : Theme.border, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

extension Plan {
    /// Button label for saving into a slot: "Log as 🌅 Breakfast" or "Add to today's log".
    static func logLabel(_ slot: String?) -> String {
        meal(slot).map { "Log as \($0.name)" } ?? "Add to today's log"
    }
}
