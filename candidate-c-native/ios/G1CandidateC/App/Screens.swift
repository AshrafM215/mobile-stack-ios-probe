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
                Button(s.t("common.back"), action: onBack).frame(minWidth: 48, minHeight: 48).accessibilityIdentifier(backId)
            }
            Text(title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                .modifier(OptionalIdentifier(id: titleId))
            Spacer()
        }
        .padding(.horizontal, 12)
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
            Text(label).font(.caption).foregroundStyle(.secondary)
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

    var body: some View {
        let s = state.s
        let enabled = state.trusted && state.index != nil
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(s.t("app.title")).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader).accessibilityIdentifier("home.title")
                Spacer()
                Button(s.t("lang.toggle"), action: state.toggleLang).frame(minHeight: 48)
                    .accessibilityLabel(s.t("lang.toggle.a11y")).accessibilityIdentifier("home.lang")
                Button(s.t("home.qr.scan"), action: state.scanQr).frame(minHeight: 48).accessibilityIdentifier("home.qr")
                Button(s.t("home.settings"), action: state.openSettings).frame(minHeight: 48).accessibilityIdentifier("home.settings")
            }
            .padding(.horizontal, 12)
            Text(s.t("app.subtitle")).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
            Text(trustText(s, state.bundleInfo)).padding(.horizontal, 16).accessibilityIdentifier("home.trust")
            HStack(spacing: 8) {
                TextField(s.t("home.search.hint"), text: $state.query)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!enabled)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { state.submitSearch() }
                    .accessibilityLabel(s.t("home.search.label"))
                    .accessibilityIdentifier("home.search.field")
                if !state.query.isEmpty {
                    Button(s.t("home.search.clear"), action: state.clearSearch).frame(minHeight: 48).accessibilityIdentifier("home.search.clear")
                }
                Button(s.t("home.search.submit")) { state.submitSearch() }
                    .buttonStyle(.borderedProminent).frame(minHeight: 48).disabled(!enabled).accessibilityIdentifier("home.search.submit")
            }
            .padding(.horizontal, 16)
            Group {
                if let results = state.results {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(resultStatus(s, results.outcome, results.ids.count, state.query)).padding(.horizontal, 16).padding(.vertical, 6)
                            .accessibilityIdentifier("home.results.status")
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(results.ids, id: \.self) { id in
                                    if let d = state.data?.byId[id] {
                                        Button { state.openDetails(id) } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(s.t("home.result.item", ["code": d.code, "name": d.name(s.lang)]))
                                                Text(s.t("common.building_floor", ["building": d.building, "floor": d.floor])).font(.footnote)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                            .padding(.horizontal, 16)
                                        }
                                        .accessibilityIdentifier("home.result.\(id)")
                                        Divider()
                                    }
                                }
                            }
                        }
                        .accessibilityIdentifier("home.results.list")
                    }
                } else {
                    Text(s.t("home.empty")).padding(16).accessibilityIdentifier("home.empty")
                    Spacer(minLength: 0)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .layoutPriority(2)
            HStack(spacing: 8) {
                Text(s.t("home.floor.label"))
                ForEach(1...3, id: \.self) { f in
                    let selected = state.floor == f
                    Button(s.t("home.floor.option", ["floor": f])) { state.setFloor(f) }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 48)
                        .accessibilityLabel(selected ? s.t("home.floor.selected", ["floor": f]) : s.t("home.floor.option", ["floor": f]))
                        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
                        .accessibilityIdentifier("home.floor.\(f)")
                }
            }
            .padding(.horizontal, 16)
            MapPanel(controller: map)
                .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
                .layoutPriority(3)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(s.t("home.map.label", ["floor": state.floor]))
                .accessibilityIdentifier("home.map")
        }
        .task(id: enabled) {
            if enabled { NextFrame.run { _ in state.homeShown() } }
        }
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
                            Button(s.t("details.route")) { state.openRoute(d.id) }.buttonStyle(.borderedProminent).frame(minHeight: 48)
                                .accessibilityIdentifier("details.route")
                            Button(s.t("details.showmap")) { state.showOnMap(d.id) }.buttonStyle(.bordered).frame(minHeight: 48)
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
                    Button(s.t("route.compute")) { state.computeRoute() }.buttonStyle(.borderedProminent).frame(minHeight: 48).padding(16)
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
                        Button(s.t("route.ar")) { state.openAr() }.buttonStyle(.bordered).frame(minHeight: 48).padding(16)
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
                    Button(s.t("fallback.back"), action: state.back).buttonStyle(.borderedProminent).frame(minHeight: 48).padding(16)
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
            Button(s.t("common.close"), action: state.back).buttonStyle(.borderedProminent).frame(minHeight: 48).padding(16)
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
                        .buttonStyle(.borderedProminent).frame(minHeight: 48).padding(16).accessibilityIdentifier("settings.update")
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
