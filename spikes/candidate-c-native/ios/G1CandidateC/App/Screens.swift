// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Screens S01-S09 of G1-CIC-1.0 plus the anchor-code result and data/trust screens in SwiftUI. Every contract id is an
// accessibilityIdentifier.
import SwiftUI

private let primary = Color(red: 0x1F / 255, green: 0x4E / 255, blue: 0x79 / 255)

struct RootView: View {
    @ObservedObject var state: AppState
    let map: MapController

    var body: some View {
        let s = state.s
        let top = state.top
        ZStack {
            // the home screen (with its map) stays mounted under the other screens
            HomeScreen(state: state, map: map)
                .accessibilityHidden(top.kind != .home)
                .allowsHitTesting(top.kind == .home)
            if top.kind != .home {
                Group {
                    switch top.kind {
                    case .details: DetailsScreen(state: state, destinationId: top.destination ?? "")
                    case .route: RouteScreen(state: state, destinationId: top.destination ?? "")
                    case .fallback: FallbackScreen(state: state)
                    case .qr: QrScreen(state: state)
                    case .settings: SettingsScreen(state: state)
                    case .home: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(UIColor.systemBackground))
            }
            CommitProbe(state: state, revision: state.revision).frame(width: 0, height: 0)
        }
        .environment(\.layoutDirection, s.rtl ? .rightToLeft : .leftToRight)
        .tint(primary)
    }
}

private struct Header: View {
    let s: Strings
    let title: String
    var backId: String?
    var onBack: (() -> Void)?
    var titleId: String?

    var body: some View {
        HStack {
            if let backId, let onBack {
                Button(s.t("common.back"), action: onBack).buttonStyle(TargetButtonStyle()).accessibilityIdentifier(backId)
            }
            Text(title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                .modifier(OptionalIdentifier(id: titleId))
            Spacer()
        }
        .padding(.horizontal, 12)
    }
}

/// Buttons whose touch target is at least 48 x 48 points. The label carries the minimum size and the shape that takes
/// touches: a frame around a SwiftUI Button does not enlarge what can be touched (with `.frame(minHeight: 48)` around
/// the button the home actions were 20.3 points high in the accessibility tree of the simulator).
private struct TargetButtonStyle: ButtonStyle {
    enum Kind { case text, filled, outlined }
    var kind: Kind = .text
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        TargetButtonBody(configuration: configuration, kind: kind, selected: selected)
    }
}

private struct TargetButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: TargetButtonStyle.Kind
    let selected: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        configuration.label
            .padding(.horizontal, kind == .text ? 6 : 14)
            .frame(minWidth: 48, minHeight: 48)
            .foregroundStyle(kind == .filled ? Color.white : primary)
            .background(shape.fill(kind == .filled ? primary : (selected ? primary.opacity(0.16) : Color.clear)))
            .overlay(shape.stroke(kind == .outlined ? primary.opacity(0.55) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
    }
}

private struct OptionalIdentifier: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id { content.accessibilityIdentifier(id) } else { content }
    }
}

private struct LabelValue: View {
    let label: String
    let id: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption)
            Text(value).accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// ---------------------------------------------------------------- S01/S02/S03/S06

private func resultStatus(_ s: Strings, _ outcome: String, _ count: Int, _ query: String) -> String {
    switch outcome {
    case "UNIQUE_MATCH": return s.t("home.results.unique")
    case "AMBIGUOUS": return s.t("home.results.ambiguous", ["count": count])
    default: return s.t("home.results.none", ["query": query])
    }
}

struct HomeScreen: View {
    @ObservedObject var state: AppState
    let map: MapController
    /// The app window inside the safe area, measured without the keyboard (G1-LAYOUT-1.0); zero until first measured.
    @State private var window = CGSize.zero
    /// The text scale factor of the Dynamic Type setting (1.0 at the default size).
    @ScaledMetric(relativeTo: .body) private var fontScale: CGFloat = 1
    @FocusState private var searchFocused: Bool

    var body: some View {
        let enabled = state.trusted && state.index != nil
        let compact = window != .zero &&
            LayoutPolicy.mode(width: Double(window.width), height: Double(window.height), fontScale: Double(fontScale)) == .compact
        ZStack {
            if compact {
                // compact: one vertical scroll container, every block at its natural height, every result row laid out
                ScrollView {
                    VStack(spacing: 4) {
                        header
                        subtitle
                        trust
                        searchRow(enabled: enabled)
                        results(compact: true)
                        floors
                        mapPanel
                            .frame(maxWidth: .infinity)
                            .frame(height: CGFloat(LayoutPolicy.compactMapHeight(windowHeight: Double(window.height))))
                    }
                }
            } else {
                WeightedColumn(spacing: 4) {
                    header
                    subtitle
                    trust
                    searchRow(enabled: enabled)
                    // weight 2 of the free height (Compose weight(2f) / Flutter flex: 2); one subview in either state
                    results(compact: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .layoutWeight(2) // last modifier: the column reads it from this subview
                    floors
                    // weight 3 of the free height (Compose weight(3f) / Flutter flex: 3)
                    mapPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutWeight(3) // last modifier: the column reads it from this subview
                }
            }
        }
        .background {
            // measures the window; the keyboard is left out of it, so typing never changes the layout mode. A background,
            // not a layer of its own: a clear layer beside the content was an element without a description in the
            // accessibility tree
            GeometryReader { geo in
                Color.clear.task(id: geo.size) { window = geo.size }
            }
            .ignoresSafeArea(.keyboard)
        }
        .task(id: enabled) {
            if enabled { NextFrame.run { _ in state.homeShown() } }
        }
    }

    /// The title keeps its width: the actions stand beside it when they fit, else below it in a row, else below it stacked.
    private var header: some View {
        let title = Text(state.s.t("app.title")).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("home.title")
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                title
                Spacer(minLength: 6)
                actions
            }
            VStack(alignment: .leading, spacing: 4) {
                title
                HStack(spacing: 6) { actions }
            }
            VStack(alignment: .leading, spacing: 4) {
                title
                actions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var actions: some View {
        let s = state.s
        Button(s.t("lang.toggle"), action: state.toggleLang).buttonStyle(TargetButtonStyle())
            .accessibilityLabel(s.t("lang.toggle.a11y")).accessibilityIdentifier("home.lang")
        Button(s.t("home.qr.scan"), action: state.scanQr).buttonStyle(TargetButtonStyle()).accessibilityIdentifier("home.qr")
        Button(s.t("home.settings"), action: state.openSettings).buttonStyle(TargetButtonStyle()).accessibilityIdentifier("home.settings")
    }

    private var subtitle: some View {
        Text(state.s.t("app.subtitle")).font(.footnote).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trust: some View {
        Text(trustText(state.s, state.bundleInfo)).padding(.horizontal, 16).accessibilityIdentifier("home.trust")
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func searchRow(enabled: Bool) -> some View {
        let s = state.s
        return HStack(spacing: 8) {
            // the field's box is 48 points high and a touch anywhere in the box focuses the field (the text field itself
            // keeps its own height inside it)
            TextField(s.t("home.search.hint"), text: $state.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .disabled(!enabled)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { state.submitSearch() }
                .accessibilityLabel(s.t("home.search.label"))
                .accessibilityIdentifier("home.search.field")
                .padding(.horizontal, 10)
                .frame(minHeight: 48)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(UIColor.separator), lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { if enabled { searchFocused = true } }
            if !state.query.isEmpty {
                Button(s.t("home.search.clear"), action: state.clearSearch).buttonStyle(TargetButtonStyle()).accessibilityIdentifier("home.search.clear")
            }
            Button(s.t("home.search.submit")) { state.submitSearch() }
                .buttonStyle(TargetButtonStyle(kind: .filled)).disabled(!enabled).accessibilityIdentifier("home.search.submit")
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func resultRow(_ id: String) -> some View {
        let s = state.s
        if let d = state.data?.byId[id] {
            Button { state.openDetails(id) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.t("home.result.item", ["code": d.code, "name": d.name(s.lang)]))
                    Text(s.t("common.building_floor", ["building": d.building, "floor": d.floor])).font(.footnote)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 16)
            }
            .accessibilityIdentifier("home.result.\(id)")
            Divider()
        }
    }

    /// regular: the list scrolls inside the results region; compact: every row is laid out in the screen's own scroll.
    private func results(compact: Bool) -> some View {
        let s = state.s
        return VStack(alignment: .leading, spacing: 0) {
            if let results = state.results {
                Text(resultStatus(s, results.outcome, results.ids.count, state.query)).padding(.horizontal, 16).padding(.vertical, 6)
                    .accessibilityIdentifier("home.results.status")
                if compact {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(results.ids, id: \.self) { id in resultRow(id) }
                    }
                    // a container element: an identifier on a plain container would be applied to its children too
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home.results.list")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(results.ids, id: \.self) { id in resultRow(id) }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home.results.list")
                }
            } else {
                Text(s.t("home.empty")).padding(16).accessibilityIdentifier("home.empty")
                if !compact { Spacer(minLength: 0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var floors: some View {
        let s = state.s
        return HStack(spacing: 8) {
            Text(s.t("home.floor.label"))
            ForEach(1...3, id: \.self) { f in
                let selected = state.floor == f
                Button(s.t("home.floor.option", ["floor": f])) { state.setFloor(f) }
                    .buttonStyle(TargetButtonStyle(kind: .outlined, selected: selected))
                    .accessibilityLabel(selected ? s.t("home.floor.selected", ["floor": f]) : s.t("home.floor.option", ["floor": f]))
                    .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
                    .accessibilityIdentifier("home.floor.\(f)")
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mapPanel: some View {
        MapPanel(controller: map)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.s.t("home.map.label", ["floor": state.floor]))
            .accessibilityIdentifier("home.map")
    }
}

// ---------------------------------------------------------------- S04/S05

struct DetailsScreen: View {
    @ObservedObject var state: AppState
    let destinationId: String

    var body: some View {
        let s = state.s
        VStack(alignment: .leading, spacing: 0) {
            Header(s: s, title: s.t("details.title"), backId: "details.back", onBack: state.back)
            if let d = state.data?.byId[destinationId] {
                let schedule = state.data!.scheduleFor(d.id)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        LabelValue(label: s.t("details.code"), id: "details.code", value: d.code)
                        LabelValue(label: s.t("details.name"), id: "details.name", value: d.name(s.lang))
                        LabelValue(label: s.t("details.building"), id: "details.building", value: d.building)
                        LabelValue(label: s.t("details.floor"), id: "details.floor", value: String(d.floor))
                        LabelValue(label: s.t("details.status"), id: "details.status",
                                   value: s.t(d.reachable ? "details.status.reachable" : "details.status.unreachable"))
                        Text(s.t("details.schedule")).font(.headline).accessibilityAddTraits(.isHeader).padding(16)
                        if schedule.isEmpty {
                            Text(s.t("details.schedule.none")).padding(.horizontal, 16).accessibilityIdentifier("details.schedule.none")
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(schedule, id: \.code) { e in
                                    Text(scheduleItem(s, e)).padding(.horizontal, 16).padding(.vertical, 6)
                                        .accessibilityIdentifier("details.schedule.item.\(e.code)")
                                }
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("details.schedule.list")
                        }
                        HStack(spacing: 12) {
                            Button(s.t("details.route")) { state.openRoute(d.id) }.buttonStyle(TargetButtonStyle(kind: .filled))
                                .accessibilityIdentifier("details.route")
                            Button(s.t("details.showmap")) { state.showOnMap(d.id) }.buttonStyle(TargetButtonStyle(kind: .outlined))
                                .accessibilityIdentifier("details.showmap")
                        }
                        .padding(16)
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- S07

struct RouteScreen: View {
    @ObservedObject var state: AppState
    let destinationId: String

    var body: some View {
        let s = state.s
        let d = state.data?.byId[destinationId]
        let r = state.route
        VStack(alignment: .leading, spacing: 0) {
            Header(s: s, title: s.t("route.title"), backId: "route.back", onBack: state.back)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.t("route.from")).font(.headline).accessibilityAddTraits(.isHeader).padding(16)
                    ForEach(state.data?.entrances ?? [], id: \.self) { e in
                        let selected = state.origin == e
                        Button { state.setOrigin(e) } label: {
                            HStack {
                                Image(systemName: selected ? "largecircle.fill.circle" : "circle").accessibilityHidden(true)
                                Text(s.t("route.from.option", ["entrance": e]))
                                Spacer()
                            }
                            .frame(minHeight: 48)
                            .padding(.horizontal, 16)
                        }
                        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
                        .accessibilityIdentifier("route.from.\(e)")
                    }
                    LabelValue(label: s.t("route.to"), id: "route.to",
                               value: d.map { s.t("home.result.item", ["code": $0.code, "name": $0.name(s.lang)]) } ?? destinationId)
                    Toggle(s.t("route.stepfree"), isOn: $state.stepFree).frame(minHeight: 48).padding(.horizontal, 16)
                        .accessibilityIdentifier("route.stepfree")
                    Button(s.t("route.compute")) { state.computeRoute() }.buttonStyle(TargetButtonStyle(kind: .filled)).padding(16)
                        .accessibilityIdentifier("route.compute")
                    Text(trustText(s, state.bundleInfo)).padding(.horizontal, 16).accessibilityIdentifier("route.trust")
                    if let r, r.outcome == "PATH", let sum = state.summary {
                        Text(summaryText(s, sum)).font(.headline).padding(16).accessibilityIdentifier("route.summary")
                        Text(s.t("route.steps")).padding(.horizontal, 16)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(state.steps.enumerated()), id: \.offset) { i, st in
                                Text("\(i + 1). \(stepText(s, st))").padding(.horizontal, 16).padding(.vertical, 6)
                                    .accessibilityIdentifier("route.step.\(i)")
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("route.steps")
                        Button(s.t("route.ar")) { state.openAr() }.buttonStyle(TargetButtonStyle(kind: .outlined)).padding(16)
                            .accessibilityIdentifier("route.ar")
                    } else if let r {
                        Text(rejectText(s, r.outcome)).padding(16).accessibilityIdentifier("route.reject")
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- S09

struct FallbackScreen: View {
    @ObservedObject var state: AppState

    var body: some View {
        let s = state.s
        VStack(alignment: .leading, spacing: 0) {
            Header(s: s, title: s.t("fallback.title"), titleId: "fallback.title")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.t("ar.unsupported")).padding(16).accessibilityIdentifier("fallback.message")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(state.steps.enumerated()), id: \.offset) { i, st in
                            Text("\(i + 1). \(stepText(s, st))").padding(.horizontal, 16).padding(.vertical, 6)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("fallback.steps")
                    Button(s.t("fallback.back"), action: state.back).buttonStyle(TargetButtonStyle(kind: .filled)).padding(16)
                        .accessibilityIdentifier("fallback.back")
                }
            }
        }
    }
}

// ---------------------------------------------------------------- anchor code result

struct QrScreen: View {
    @ObservedObject var state: AppState

    var body: some View {
        let s = state.s
        VStack(alignment: .leading, spacing: 0) {
            Header(s: s, title: s.t("qr.title"))
            Text(qrText(s, state.qrResult ?? [:])).padding(16).accessibilityIdentifier("qr.result")
            Button(s.t("common.close"), action: state.back).buttonStyle(TargetButtonStyle(kind: .filled)).padding(16)
                .accessibilityIdentifier("qr.close")
        }
    }
}

// ---------------------------------------------------------------- data and trust

struct SettingsScreen: View {
    @ObservedObject var state: AppState

    var body: some View {
        let s = state.s
        let info = state.bundleInfo
        let update: String? = {
            switch state.updateStatus {
            case "pending": return s.t("settings.update.pending", ["percent": state.updatePercent])
            case "slow": return s.t("settings.update.slow")
            case "none": return s.t("settings.update.none")
            case "failed": return s.t("settings.update.failed")
            default: return nil
            }
        }()
        VStack(alignment: .leading, spacing: 0) {
            Header(s: s, title: s.t("settings.title"), backId: "settings.back", onBack: state.back)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LabelValue(label: s.t("settings.version"), id: "settings.version", value: info?.version ?? "-")
                    if let info, info.state == "VALID" {
                        Text(s.t("settings.validity", ["from": isoDate(info.validFromMs), "until": isoDate(info.validUntilMs)])).padding(16)
                            .accessibilityIdentifier("settings.validity")
                    }
                    Text(trustText(s, info)).padding(.horizontal, 16).accessibilityIdentifier("settings.status")
                    Button(s.t("settings.update")) { Task { @MainActor in _ = await state.update() } }
                        .buttonStyle(TargetButtonStyle(kind: .filled)).padding(16).accessibilityIdentifier("settings.update")
                    if let update { Text(update).padding(.horizontal, 16).accessibilityIdentifier("settings.update.status") }
                    if let code = state.lastResult {
                        Text(s.has("result.\(code)") ? s.t("result.\(code)") : s.t("error.generic")).padding(16)
                            .accessibilityIdentifier("settings.result")
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- layout

/// Column that gives the height left by its fixed children to the weighted ones in proportion to their weights (the
/// semantics of Compose Modifier.weight and Flutter Expanded(flex:)), so that A, B and C split the home screen alike.
/// Every child is proposed the full width; children align their own content (frame alignment follows the layout
/// direction, so RTL is unaffected).
struct WeightedColumn: Layout {
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let unconstrained = ProposedViewSize(width: bounds.width, height: nil)
        let weights = subviews.map { $0[LayoutWeight.self] }
        var fixed = spacing * CGFloat(max(subviews.count - 1, 0))
        for (index, subview) in subviews.enumerated() where weights[index] == 0 {
            fixed += subview.sizeThatFits(unconstrained).height
        }
        let total = weights.reduce(0, +)
        let free = max(bounds.height - fixed, 0)
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let height = weights[index] > 0 ? (total > 0 ? free * weights[index] / total : 0) : subview.sizeThatFits(unconstrained).height
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }
}

private struct LayoutWeight: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

extension View {
    /// Share of the free height in a WeightedColumn (0 = fixed child at its ideal height).
    func layoutWeight(_ weight: CGFloat) -> some View {
        layoutValue(key: LayoutWeight.self, value: weight)
    }
}
