import AppKit
import SwiftUI
import TockCore

/// The popover: every Service's current code, filterable by typing.
struct CodeList: View {
    let store: Store
    let addService: () -> Void
    let showSettings: () -> Void
    let dismiss: () -> Void
    @State private var query = ""
    @FocusState private var searching: Bool

    private static let rowHeight: CGFloat = 56
    private static let visibleRows = 7.5

    private var matches: [Service] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.services }
        return store.services.filter { "\($0.issuer) \($0.account)".localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(nsImage: NSApplication.shared.applicationIconImage).resizable()
                        .frame(width: 22, height: 22).accessibilityHidden(true)
                    Text("Tock").font(.system(size: 15, weight: .bold))
                    Spacer(minLength: 8)
                    IconButton(symbol: "plus", label: "Add service", action: addService)
                    IconButton(symbol: "gearshape", label: "Settings", action: showSettings)
                }
                if !store.services.isEmpty { search }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
            Divider().overlay(Palette.line)
            VStack(spacing: 12) {
                if let error = store.error {
                    Text(error).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.ember.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                if store.services.isEmpty { empty }
                else if matches.isEmpty {
                    Text("No services match \"\(query)\"").font(.system(size: 12)).foregroundStyle(Palette.dust)
                        .frame(maxWidth: .infinity).padding(.vertical, 22)
                } else { codes }
            }
            .padding(12)
            .animation(.spring(duration: 0.3, bounce: 0.1), value: matches.map(\.id))
            Divider().overlay(Palette.line)
            HStack {
                Text(store.clearsClipboard ? "Copied codes clear after 30 seconds" : "Click a code to copy it")
                    .font(.system(size: 11)).foregroundStyle(Palette.dust)
                Spacer()
                Button("Quit Tock") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.dust)
            }.padding(.horizontal, 14).padding(.vertical, 9)
        }
        .frame(width: 360).background(Palette.ground).foregroundStyle(Palette.ink)
        .onChange(of: store.popoverShown) { _, shown in
            guard shown else { return }
            query = ""
            searching = true
        }
    }

    private var search: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.dust)
            TextField("", text: $query).accessibilityLabel("Search").placeholder("Search, then Return to copy", shown: query.isEmpty)
                .textFieldStyle(.plain).font(.system(size: 12.5))
                .focused($searching)
                .onSubmit {
                    guard let first = matches.first else { return }
                    store.copy(first.code(at: Date()))
                    dismiss()
                }
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(searching ? Palette.spent : Palette.line))
    }

    private var codes: some View {
        let services = matches
        let height = Self.rowHeight * min(Double(services.count), Self.visibleRows) + CGFloat(max(0, min(services.count, 8) - 1))
        // The clock runs only while the popover is on screen; 30 frames a second keeps the rings sweeping smoothly.
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !store.popoverShown)) { context in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                        if index > 0 { Divider().overlay(Palette.line) }
                        CodeRow(service: service, tint: Palette.tint(at: store.position(of: service.id)), now: context.date, copy: store.copy)
                            .transition(.opacity)
                    }
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(height: height)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield").font(.system(size: 28, weight: .light)).foregroundStyle(Palette.dust)
            Text("No services yet").font(.system(size: 15, weight: .semibold))
            Text("Add the setup key a site shows when you turn on two-factor authentication.")
                .font(.system(size: 12)).foregroundStyle(Palette.dust).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add a service", action: addService).buttonStyle(QuietButtonStyle(prominent: true)).padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 12)
    }
}

private struct CodeRow: View {
    let service: Service
    let tint: Color
    let now: Date
    let copy: (String) -> Void
    @State private var hovering = false
    @State private var copiedAt: Date?

    var body: some View {
        let code = service.code(at: now)
        let remaining = service.remaining(at: now)
        let copied = copiedAt.map { now.timeIntervalSince($0) < 1.4 } ?? false
        Button {
            copy(code)
            copiedAt = Date()
        } label: {
            HStack(spacing: 11) {
                Monogram(issuer: service.issuer, tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(service.issuer).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    if !service.account.isEmpty {
                        Text(service.account).font(.system(size: 11)).foregroundStyle(Palette.dust).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                ZStack(alignment: .trailing) {
                    Text(grouped(code))
                        .font(.readout(service.digits > 6 ? 16 : 18))
                        .foregroundStyle(remaining <= 5 ? Palette.ember : Palette.ink)
                        .contentTransition(.numericText())
                        .opacity(copied ? 0 : 1).blur(radius: copied ? 3 : 0)
                    Label("Copied", systemImage: "checkmark")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.mint)
                        .opacity(copied ? 1 : 0).scaleEffect(copied ? 1 : 0.85)
                }
                .lineLimit(1).fixedSize()
                .animation(.snappy(duration: 0.3), value: code)
                .animation(.spring(duration: 0.3, bounce: 0.3), value: copied)
                CountdownRing(remaining: remaining, period: service.period)
            }
            .padding(.horizontal, 12).frame(height: 56)
            .background(hovering ? Palette.wash : .clear)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(PressableStyle(pressedScale: 0.985))
        .onHover { hovering = $0 }
        .help("Copy code")
        .accessibilityLabel("\(service.issuer) \(service.account), code \(code)")
        .accessibilityHint("Copies the code")
    }
}
