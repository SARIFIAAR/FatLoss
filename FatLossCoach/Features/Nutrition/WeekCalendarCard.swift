import SwiftUI

/// Apple-Fitness-style week strip: swipe between weeks, tap a day. Each day shows a calorie ring
/// (eaten vs target) so you can see the week at a glance; the selected day drives the cards below.
struct WeekCalendarCard: View {
    @Binding var selected: String          // DateKey
    @Environment(Store.self) private var store
    @State private var weekOffset = 0      // 0 = the week containing today, -1 = last week …

    private var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var weekStart: Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        let thisWeek = calendar.date(from: comps) ?? today
        return calendar.date(byAdding: .day, value: weekOffset * 7, to: thisWeek) ?? thisWeek
    }
    private var days: [Date] { (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) } }

    private var title: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        let a = f.string(from: weekStart), b = f.string(from: days.last ?? weekStart)
        if a == b { return a }
        let m = DateFormatter(); m.dateFormat = "MMM"
        return "\(m.string(from: weekStart)) – \(b)"
    }

    var body: some View {
        Card {
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.25)) { weekOffset -= 1 } } label: { chevron("chevron.left") }
                Spacer()
                Text(title).font(Theme.scoreS).foregroundStyle(Theme.text)
                Spacer()
                if selected != store.today || weekOffset != 0 {
                    Button("Today") { withAnimation(.easeInOut(duration: 0.25)) { weekOffset = 0; selected = store.today } }
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.primary)
                        .padding(.trailing, 6)
                }
                Button { withAnimation(.easeInOut(duration: 0.25)) { weekOffset += 1 } } label: { chevron("chevron.right") }
                    .disabled(weekOffset >= 0)
                    .opacity(weekOffset >= 0 ? 0.3 : 1)
            }
            .padding(.bottom, 10)

            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let key = DateKey.key(day)
                    DayCell(date: day, key: key, isSelected: key == selected, isFuture: day > today,
                            fraction: fraction(key), over: over(key), hasMeals: !(store.data.meals[key] ?? []).isEmpty)
                        .onTapGesture { if day <= today { selected = key } }
                }
            }
            .id(weekOffset)
            .transition(.opacity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 25).onEnded { g in
                withAnimation(.easeInOut(duration: 0.25)) {
                    if g.translation.width < 0, weekOffset < 0 { weekOffset += 1 }
                    else if g.translation.width > 0 { weekOffset -= 1 }
                }
            })

            let t = store.totals(on: selected)
            let meals = store.data.meals[selected] ?? []
            HStack(spacing: 6) {
                Text(selected == store.today ? "Today" : Self.longDay(selected)).font(Theme.scoreS).foregroundStyle(Theme.text)
                Text("·").foregroundStyle(Theme.muted)
                Text(meals.isEmpty ? "nothing logged" : "\(Int(t.kcal.rounded())) kcal · \(meals.count) meal\(meals.count == 1 ? "" : "s")")
                    .font(.system(size: 13)).foregroundStyle(meals.isEmpty ? Theme.muted : Theme.primary)
                Spacer()
            }
            .padding(.top, 10)
        }
        .onAppear { jumpToSelected() }
        .onChange(of: selected) { _, _ in jumpToSelected() }
    }

    /// Show the week that contains the selected day (e.g. when launched on a past day).
    private func jumpToSelected() {
        guard let d = DateKey.date(selected) else { return }
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        let thisWeek = calendar.date(from: comps) ?? today
        let sel = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        let selWeek = calendar.date(from: sel) ?? d
        let weeks = calendar.dateComponents([.weekOfYear], from: thisWeek, to: selWeek).weekOfYear ?? 0
        if weeks != weekOffset { weekOffset = weeks }
    }

    private func fraction(_ key: String) -> Double {
        let g = Double(store.data.goals.kcal)
        return g > 0 ? min(store.totals(on: key).kcal / g, 1) : 0
    }
    private func over(_ key: String) -> Bool { store.totals(on: key).kcal > Double(store.data.goals.kcal) }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
            .frame(width: 30, height: 30).background(Theme.bg).clipShape(Circle())
    }

    static func longDay(_ key: String) -> String {
        guard let d = DateKey.date(key) else { return key }
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }
}

private struct DayCell: View {
    let date: Date
    let key: String
    let isSelected: Bool
    let isFuture: Bool
    let fraction: Double
    let over: Bool
    let hasMeals: Bool

    private var weekday: String { let f = DateFormatter(); f.dateFormat = "EEEEE"; return f.string(from: date) }
    private var dayNumber: String { let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: date) }
    private var isToday: Bool { key == DateKey.key() }

    var body: some View {
        VStack(spacing: 6) {
            Text(weekday).font(.system(size: 11, weight: .bold)).foregroundStyle(isToday ? Theme.primary : Theme.muted)
            ZStack {
                Circle().stroke(Theme.border, lineWidth: 3)
                Circle().trim(from: 0, to: isFuture ? 0 : fraction)
                    .stroke(over ? Theme.red : Theme.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if isSelected { Circle().fill(Theme.primary).padding(4) }
                Text(dayNumber).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isSelected ? .white : Theme.text)
            }
            .frame(width: 40, height: 40)
            Circle().fill(hasMeals ? Theme.accent : .clear).frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity)
        .opacity(isFuture ? 0.35 : 1)
        .contentShape(Rectangle())
    }
}
