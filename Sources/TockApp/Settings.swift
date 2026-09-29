import ServiceManagement
import SwiftUI
import TockCore

enum SettingsScreen: Equatable {
    case list
    /// Adds a Service when the value is nil, otherwise edits it.
    case editor(Service?)
}

@MainActor @Observable
final class SettingsNavigation {
    var screen = SettingsScreen.list
}

struct SettingsView: View {
    let store: Store
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        ZStack {
            switch navigation.screen {
            case .list:
                ServiceSettings(store: store, open: { navigation.screen = .editor($0) })
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            case .editor(let service):
                ServiceEditor(store: store, existing: service, close: { navigation.screen = .list })
                    .id(service?.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
            }
        }
        .animation(.spring(duration: 0.38, bounce: 0.12), value: navigation.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.ground).foregroundStyle(Palette.ink).font(.system(size: 13))
    }
}

private struct ServiceSettings: View {
    let store: Store
    let open: (Service?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Settings").font(.system(size: 20, weight: .bold))
                    Spacer()
                    Button { open(nil) } label: { Label("Add service", systemImage: "plus") }
                        .buttonStyle(QuietButtonStyle(prominent: true)).keyboardShortcut("n")
                }
                if let error = store.error {
                    Text(error).font(.system(size: 12)).foregroundStyle(Palette.ember).fixedSize(horizontal: false, vertical: true)
                }
                Panel(title: "Services", footer: "Codes appear in the menu bar in this order. Each service, secret included, is stored in your login keychain.") {
                    if store.services.isEmpty {
                        Text("No services yet. Add one with the setup key from the site's two-factor settings.")
                            .font(.system(size: 12)).foregroundStyle(Palette.dust).padding(14)
                    }
                    ForEach(Array(store.services.enumerated()), id: \.element.id) { index, service in
                        if index > 0 { Divider().overlay(Palette.line) }
                        row(service, first: index == 0, last: index == store.services.count - 1)
                    }
                }
                Panel(title: "General") {
                    Toggle(isOn: Binding(get: { store.launchesAtLogin }, set: { store.setLaunchAtLogin($0) })) {
                        Text("Launch at login").fontWeight(.semibold)
                    }
                    .toggleStyle(TockSwitch()).padding(14)
                    if let message = store.loginMessage {
                        HStack {
                            Text(message).font(.system(size: 11)).foregroundStyle(Palette.dust).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }.buttonStyle(QuietButtonStyle())
                        }.padding(.horizontal, 14).padding(.bottom, 12)
                    }
                    Divider().overlay(Palette.line)
                    Toggle(isOn: Binding(get: { store.clearsClipboard }, set: { store.clearsClipboard = $0 })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Clear copied codes").fontWeight(.semibold)
                            Text("Empties the clipboard 30 seconds after a copy, unless you copied something else.")
                                .font(.system(size: 11)).foregroundStyle(Palette.dust)
                        }
                    }
                    .toggleStyle(TockSwitch()).padding(14)
                }
            }
            .padding(.horizontal, 22).padding(.top, 34).padding(.bottom, 22)
        }
        .scrollIndicators(.never)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.readLoginStatus() }
    }

    private func row(_ service: Service, first: Bool, last: Bool) -> some View {
        HStack(spacing: 12) {
            Monogram(issuer: service.issuer, tint: Palette.tint(at: store.position(of: service.id)), size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(service.issuer).fontWeight(.semibold).lineLimit(1)
                Text([service.account, summary(service)].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                    .font(.system(size: 11)).foregroundStyle(Palette.dust).lineLimit(1)
            }
            Spacer(minLength: 8)
            IconButton(symbol: "chevron.up", label: "Move \(service.issuer) up") { withAnimation(.snappy) { store.move(service, by: -1) } }
                .disabled(first).opacity(first ? 0.35 : 1)
            IconButton(symbol: "chevron.down", label: "Move \(service.issuer) down") { withAnimation(.snappy) { store.move(service, by: 1) } }
                .disabled(last).opacity(last ? 0.35 : 1)
            Button("Edit") { open(service) }.buttonStyle(QuietButtonStyle()).padding(.leading, 4)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

func summary(_ service: Service) -> String {
    "\(service.digits) digits · \(service.period)s · \(service.algorithm.label)"
}

private struct ServiceEditor: View {
    let store: Store
    let existing: Service?
    let close: () -> Void

    @State private var issuer: String
    @State private var account: String
    @State private var key: String
    @State private var algorithm: Algorithm
    @State private var digits: Int
    @State private var period: String
    @State private var revealed: Bool
    @State private var advanced = false
    @State private var linkNote: String?
    @State private var linkFailed = false
    @State private var confirmingDelete = false
    @FocusState private var focus: Field?

    private enum Field { case issuer, key }

    init(store: Store, existing: Service?, close: @escaping () -> Void) {
        self.store = store
        self.existing = existing
        self.close = close
        let service = existing ?? Service(issuer: "", secret: Data())
        _issuer = State(initialValue: service.issuer)
        _account = State(initialValue: service.account)
        _key = State(initialValue: existing.map { Base32.encode($0.secret) } ?? "")
        _algorithm = State(initialValue: service.algorithm)
        _digits = State(initialValue: service.digits)
        _period = State(initialValue: String(service.period))
        // A new key is easier to check while visible; a saved one stays hidden until asked for.
        _revealed = State(initialValue: existing == nil)
    }

    /// The Service the form describes, or nil while any field is invalid.
    private var draft: Service? {
        let name = issuer.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let secret = Base32.decode(key), let seconds = Int(period), Service.periodRange.contains(seconds) else { return nil }
        return Service(id: existing?.id ?? UUID(), issuer: name, account: account.trimmingCharacters(in: .whitespaces),
                       secret: secret, algorithm: algorithm, digits: digits, period: seconds)
    }

    private var keyProblem: String? {
        guard !key.isEmpty, !key.lowercased().hasPrefix("otpauth://") else { return nil }
        return Base32.decode(key) == nil ? "Setup keys use only the letters A to Z and the digits 2 to 7." : nil
    }

    private var periodProblem: String? {
        guard let seconds = Int(period), Service.periodRange.contains(seconds) else {
            return "Use a period between \(Service.periodRange.lowerBound) and \(Service.periodRange.upperBound) seconds."
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        IconButton(symbol: "chevron.left", label: "Back", action: close)
                        Text(existing == nil ? "Add service" : "Edit \(existing?.issuer ?? "")").font(.system(size: 20, weight: .bold)).lineLimit(1)
                    }
                    Panel(title: "Service") {
                        VStack(spacing: 12) {
                            PanelField(label: "Name") {
                                TextField("", text: $issuer).accessibilityLabel("Name").placeholder("Such as GitHub", shown: issuer.isEmpty).focused($focus, equals: .issuer)
                            }
                            PanelField(label: "Account") {
                                TextField("", text: $account).accessibilityLabel("Account").placeholder("Optional, such as you@example.com", shown: account.isEmpty)
                            }
                        }.padding(14)
                    }
                    Panel(title: "Setup key", footer: "Use the key a site shows under \"Can't scan the QR code?\" or \"Enter a setup key\". Spaces and lower case are fine. Pasting an otpauth:// link fills in every field.") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Group {
                                    if revealed { TextField("", text: $key) }
                                    else { SecureField("", text: $key) }
                                }
                                .accessibilityLabel("Setup key")
                                .placeholder("JBSW Y3DP EHPK 3PXP", shown: key.isEmpty)
                                .font(.system(size: 13, design: .monospaced)).focused($focus, equals: .key)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10).frame(height: 32)
                                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(keyProblem == nil ? Palette.line : Palette.ember.opacity(0.6)))
                                IconButton(symbol: revealed ? "eye.slash" : "eye", label: revealed ? "Hide key" : "Show key") { revealed.toggle() }
                            }
                            if let problem = keyProblem ?? linkNote {
                                Text(problem).font(.system(size: 11))
                                    .foregroundStyle(keyProblem != nil || linkFailed ? Palette.ember : Palette.mint)
                                    .transition(.opacity.combined(with: .offset(y: -4)))
                            }
                        }
                        .padding(14)
                        .animation(.easeOut(duration: 0.18), value: keyProblem ?? linkNote)
                    }
                    advancedPanel
                    if let draft { preview(draft).transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top))) }
                    if let error = store.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(Palette.ember).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 22).padding(.top, 34).padding(.bottom, 22)
                .animation(.spring(duration: 0.34, bounce: 0.12), value: draft == nil)
            }
            .scrollIndicators(.never)
            Divider().overlay(Palette.line)
            HStack {
                if existing != nil {
                    Button("Delete") { confirmingDelete = true }.buttonStyle(QuietButtonStyle(destructive: true))
                }
                Spacer()
                Button("Cancel", action: close).buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Add service" : "Save") {
                    if let draft, store.save(draft) { close() }
                }
                .buttonStyle(QuietButtonStyle(prominent: true)).keyboardShortcut(.defaultAction).disabled(draft == nil)
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .onAppear { focus = .issuer }
        .onChange(of: key) { _, value in readLink(value) }
        .confirmationDialog("Delete \(existing?.issuer ?? "this service")?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                if let existing { store.delete(existing) }
                close()
            }
        } message: {
            Text("Tock removes its secret from the keychain. Turn off two-factor on the site first, or you may lose access to it.")
        }
    }

    private var advancedPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { withAnimation(.spring(duration: 0.34, bounce: 0.12)) { advanced.toggle() } } label: {
                HStack(spacing: 6) {
                    Text("Advanced").font(.system(size: 12, weight: .semibold))
                    Text("\(digits) digits · \(period)s · \(algorithm.label)").font(.system(size: 11))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).rotationEffect(.degrees(advanced ? 180 : 0))
                }
                .foregroundStyle(Palette.dust).padding(.leading, 4).contentShape(Rectangle())
            }.buttonStyle(PressableStyle())
            if advanced {
                VStack(alignment: .leading, spacing: 0) {
                    setting("Digits") {
                        SlidingSegments(options: Service.digitChoices.map { ($0, "\($0)") }, selection: $digits)
                    }
                    Divider().overlay(Palette.line)
                    setting("Period") {
                        HStack(spacing: 8) {
                            TextField("", text: $period).accessibilityLabel("Period in seconds").textFieldStyle(.plain).font(.readout(12.5, weight: .medium))
                                .multilineTextAlignment(.trailing).frame(width: 44)
                                .padding(.horizontal, 8).frame(height: 28)
                                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(periodProblem == nil ? Palette.line : Palette.ember.opacity(0.6)))
                            Text("seconds").font(.system(size: 12)).foregroundStyle(Palette.dust)
                            Spacer()
                        }
                    }
                    Divider().overlay(Palette.line)
                    setting("Algorithm") {
                        SlidingSegments(options: Algorithm.allCases.map { ($0, $0.label) }, selection: $algorithm)
                    }
                }
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)).combined(with: .scale(scale: 0.98, anchor: .top)),
                                        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))))
                Text(periodProblem ?? "Change these only if the site lists different values. Almost every site uses 6 digits, 30 seconds, and SHA-1.")
                    .font(.system(size: 11)).foregroundStyle(periodProblem == nil ? Palette.dust : Palette.ember)
                    .padding(.horizontal, 4).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setting(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.dust).frame(width: 84, alignment: .leading)
            control()
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func preview(_ service: Service) -> some View {
        Panel(title: "Current code", footer: "Sites usually ask for this code to finish turning on two-factor. It should match what they expect.") {
            TimelineView(.periodic(from: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)), by: 1)) { context in
                let code = service.code(at: context.date)
                HStack(spacing: 12) {
                    Monogram(issuer: service.issuer, tint: Palette.tint(at: store.position(of: service.id)))
                    Text(grouped(code)).font(.readout(22)).contentTransition(.numericText()).animation(.snappy, value: code)
                    Spacer()
                    CountdownRing(remaining: service.remaining(at: context.date), period: service.period, size: 26)
                }
                .padding(14)
            }
        }
    }

    private func readLink(_ value: String) {
        guard value.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("otpauth://") else {
            if linkFailed { linkNote = nil; linkFailed = false }
            return
        }
        do {
            let service = try Service(otpauth: value)
            issuer = service.issuer
            account = service.account
            algorithm = service.algorithm
            digits = service.digits
            period = String(service.period)
            key = Base32.encode(service.secret)
            linkNote = "Filled in from the otpauth link."
            linkFailed = false
        } catch {
            linkNote = error.localizedDescription
            linkFailed = true
        }
    }
}

/// Segmented choice whose selection pill slides between options.
struct SlidingSegments<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                let selected = value == selection
                Button { withAnimation(.spring(duration: 0.3, bounce: 0.2)) { selection = value } } label: {
                    Text(label).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Palette.ink : Palette.dust)
                        .frame(maxWidth: .infinity).frame(height: 24)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7).fill(Palette.pill)
                                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.line))
    }
}
