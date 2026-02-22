import SwiftUI
import AppKit
import WebKit

enum AppTab: String, CaseIterable, Identifiable {
    case openAI
    case gemini
    case anthropic
    case docsumo
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        case .anthropic: return "Anthropic"
        case .docsumo: return "Docsumo"
        case .local: return "Local"
        }
    }

    var shortcutLabel: String {
        switch self {
        case .openAI: return "⌥1"
        case .gemini: return "⌥2"
        case .anthropic: return "⌥3"
        case .docsumo: return "⌥4"
        case .local: return "⌥5"
        }
    }

    var iconName: String {
        switch self {
        case .openAI: return "openai"
        case .gemini: return "gemini"
        case .anthropic: return "anthropic"
        case .docsumo: return "docsumo"
        case .local: return "local"
        }
    }

    var monogram: String {
        switch self {
        case .openAI: return "O"
        case .gemini: return "G"
        case .anthropic: return "A"
        case .docsumo: return "D"
        case .local: return "L"
        }
    }

    var badgeColor: Color {
        switch self {
        case .openAI: return Color(red: 0.14, green: 0.84, blue: 0.71)
        case .gemini: return Color(red: 0.35, green: 0.54, blue: 1.00)
        case .anthropic: return Color(red: 0.90, green: 0.62, blue: 0.38)
        case .docsumo: return Color(red: 0.93, green: 0.32, blue: 0.43)
        case .local: return Color(red: 0.50, green: 0.56, blue: 0.63)
        }
    }

    var landingURL: URL? {
        switch self {
        case .openAI: return URL(string: "https://chatgpt.com")
        case .gemini: return URL(string: "https://gemini.google.com")
        case .anthropic: return URL(string: "https://claude.ai")
        case .docsumo: return URL(string: "https://chat.docsumo.com/chat")
        case .local: return nil
        }
    }
}

@MainActor
final class WebViewCoordinator: NSObject, ObservableObject {
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false

    private var webViews: [AppTab: WKWebView] = [:]
    private var observations: [NSKeyValueObservation] = []
    private var activeTab: AppTab = .openAI
    private let processPool = WKProcessPool()

    func select(_ tab: AppTab) {
        activeTab = tab
        bindActiveWebView()
    }

    func webView(for tab: AppTab) -> WKWebView {
        if let existing = webViews[tab] {
            return existing
        }

        let configuration = WKWebViewConfiguration()
        configuration.processPool = processPool
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        webView.uiDelegate = self

        if let url = tab.landingURL {
            webView.load(URLRequest(url: url))
        }

        webViews[tab] = webView
        if tab == activeTab {
            bindActiveWebView()
        }
        return webView
    }

    func goBack() {
        webViews[activeTab]?.goBack()
    }

    func goForward() {
        webViews[activeTab]?.goForward()
    }

    func reload() {
        webViews[activeTab]?.reload()
    }

    private func bindActiveWebView() {
        observations.removeAll()

        guard activeTab != .local, let webView = webViews[activeTab] else {
            canGoBack = false
            canGoForward = false
            isLoading = false
            return
        }

        observations = [
            webView.observe(\.canGoBack, options: [.new, .initial]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.canGoBack = view.canGoBack
                }
            },
            webView.observe(\.canGoForward, options: [.new, .initial]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.canGoForward = view.canGoForward
                }
            },
            webView.observe(\.isLoading, options: [.new, .initial]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.isLoading = view.isLoading
                }
            }
        ]
    }
}

extension WebViewCoordinator: WKNavigationDelegate, WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

private struct ProviderWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard webView.superview !== nsView else { return }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        nsView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: nsView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: nsView.bottomAnchor)
        ])
    }
}

struct ContentView: View {
    @ObservedObject var state: AppState
    @StateObject private var web = WebViewCoordinator()
    @State private var selectedTab: AppTab = .openAI
    @State private var resizeStartSize: CGSize?

    var body: some View {
        ZStack {
            background

            VStack(spacing: 2) {
                topBar
                tabContent
                    .frame(maxHeight: .infinity)
            }
            .padding(.top, 2)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(width: CGFloat(state.panelWidth), height: CGFloat(state.panelHeight))
        .overlay(alignment: .bottomLeading) {
            resizeHandle
        }
        .overlay(settingsOverlay)
        .onAppear {
            state.boot()
            if let initialTab = visibleTabs.first {
                selectedTab = visibleTabs.contains(selectedTab) ? selectedTab : initialTab
            }
            web.select(selectedTab)
            for tab in visibleTabs where tab != .local {
                _ = web.webView(for: tab)
            }
        }
        .onChange(of: selectedTab) { newTab in
            web.select(newTab)
        }
        .onChange(of: visibleTabIDs) { _ in
            guard let fallback = visibleTabs.first else { return }
            if !visibleTabs.contains(selectedTab) {
                selectedTab = fallback
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.07, blue: 0.10),
                Color(red: 0.08, green: 0.09, blue: 0.12),
                Color(red: 0.05, green: 0.06, blue: 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                web.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity((canUseWebControls && web.canGoBack) ? 0.88 : 0.35))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!canUseWebControls || !web.canGoBack)

            Button {
                web.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity((canUseWebControls && web.canGoForward) ? 0.88 : 0.35))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!canUseWebControls || !web.canGoForward)

            Button {
                web.reload()
            } label: {
                Image(systemName: web.isLoading ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(canUseWebControls ? 0.88 : 0.35))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!canUseWebControls)

            Spacer()

            HStack(spacing: 6) {
                ForEach(visibleTabs) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 7) {
                            tabIcon(tab)
                            Text(tab.shortcutLabel)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.66))
                        .frame(minWidth: 90, minHeight: 40)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedTab == tab ? Color.white.opacity(0.16) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
            }

            Spacer()

            Button {
                state.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button {
                NSApp.keyWindow?.orderOut(nil)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var tabContent: some View {
        if visibleTabs.isEmpty {
            VStack(spacing: 10) {
                Text("No providers visible")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Add API keys in Settings or enable \"Show providers without API keys\".")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                Button("Open Settings") {
                    state.showingSettings = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if selectedTab == .local && state.prefersNativeTab {
            LocalNativeChatPane(state: state)
        } else if visibleTabs.contains(selectedTab) {
            let webTab: AppTab = selectedTab == .local ? .openAI : selectedTab
            ProviderWebView(webView: web.webView(for: webTab))
                .id(webTab.id)
                .background(Color.clear)
        } else if let fallback = visibleTabs.first {
            ProviderWebView(webView: web.webView(for: fallback))
                .id(fallback.id)
                .background(Color.clear)
        } else {
            Color.clear
        }
    }

    private var visibleTabs: [AppTab] {
        var tabs: [AppTab] = []
        if state.showUnconfiguredProviders || hasKey(state.keys.openAI) {
            tabs.append(.openAI)
        }
        if state.showUnconfiguredProviders || hasKey(state.keys.gemini) {
            tabs.append(.gemini)
        }
        if state.showUnconfiguredProviders || hasKey(state.keys.anthropic) {
            tabs.append(.anthropic)
        }
        if state.prefersDocsumoTab {
            tabs.append(.docsumo)
        }
        if state.prefersNativeTab {
            tabs.append(.local)
        }
        return tabs
    }

    private var visibleTabIDs: [String] {
        visibleTabs.map(\.id)
    }

    private var canUseWebControls: Bool {
        selectedTab != .local && visibleTabs.contains(selectedTab)
    }

    @ViewBuilder
    private func tabIcon(_ tab: AppTab) -> some View {
        if let image = bundledTabIcon(named: tab.iconName) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 14, height: 14)
        } else if tab == .local {
            Image(systemName: "terminal.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 14, height: 14)
        } else {
            ZStack {
                Circle()
                    .fill(tab.badgeColor.opacity(0.88))
                Text(tab.monogram)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black.opacity(0.82))
            }
            .frame(width: 14, height: 14)
        }
    }

    private func bundledTabIcon(named name: String) -> NSImage? {
        let exts = ["png", "pdf", "jpg", "jpeg", "webp"]
        for ext in exts {
            if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Icons"),
               let image = NSImage(contentsOf: url) {
                return image
            }
            if let url = Bundle.module.url(forResource: "Icons/\(name)", withExtension: ext),
               let image = NSImage(contentsOf: url) {
                return image
            }
            if let url = Bundle.module.url(forResource: name, withExtension: ext),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.right.and.arrow.down.left")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.65))
            .padding(8)
            .background(Color.black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(8)
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if resizeStartSize == nil {
                            resizeStartSize = CGSize(width: state.panelWidth, height: state.panelHeight)
                        }
                        guard let resizeStartSize else { return }

                        let proposedWidth = resizeStartSize.width - value.translation.width
                        let proposedHeight = resizeStartSize.height + value.translation.height
                        let clampedWidth = Double(min(max(proposedWidth, 520), 1200))
                        let clampedHeight = Double(min(max(proposedHeight, 420), 980))

                        var transaction = Transaction()
                        transaction.animation = nil
                        withTransaction(transaction) {
                            state.panelWidth = clampedWidth
                            state.panelHeight = clampedHeight
                        }
                    }
                    .onEnded { _ in
                        resizeStartSize = nil
                        state.persist()
                    }
            )
    }

    private func hasKey(_ key: String) -> Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var settingsOverlay: some View {
        if state.showingSettings {
            ZStack {
                Color.black.opacity(0.48)
                    .ignoresSafeArea()
                    .onTapGesture {
                        state.showingSettings = false
                    }

                SettingsView(state: state)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(nsColor: .windowBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
                    .onTapGesture { }
            }
        }
    }
}

private struct LocalNativeChatPane: View {
    @ObservedObject var state: AppState

    @State private var composerFocused: Bool = false
    @State private var showingModelMenu: Bool = false
    @State private var showingHistoryMenu: Bool = false
    @State private var showingKeysMenu: Bool = false

    private let bottomAnchorID = "chat-bottom-anchor"

    var body: some View {
        VStack(spacing: 8) {
            localBar
            chatSurface
                .frame(maxHeight: .infinity)
            composer
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                composerFocused = true
            }
        }
    }

    private var localBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color(red: 0.98, green: 0.57, blue: 0.39))
                .font(.system(size: 14, weight: .semibold))

            Text(state.currentSessionTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)

            Spacer()

            historyButton
            modelButton

            Button {
                showingKeysMenu.toggle()
            } label: {
                Image(systemName: "key")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingKeysMenu, arrowEdge: .top) {
                APIKeysDropdownView(state: state) {
                    showingKeysMenu = false
                    state.showingSettings = true
                }
            }

            Button("New") {
                state.createNewSession()
                state.persist()
                composerFocused = true
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var historyButton: some View {
        Button {
            showingHistoryMenu.toggle()
        } label: {
            HStack(spacing: 8) {
                Text("History")
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingHistoryMenu, arrowEdge: .top) {
            HistoryDropdownView(
                sessions: state.sortedSessions,
                currentSessionID: state.currentSessionID,
                onSelect: { id in
                    state.selectSession(id)
                    showingHistoryMenu = false
                },
                onNewSession: {
                    state.createNewSession()
                    state.persist()
                    showingHistoryMenu = false
                }
            )
        }
    }

    private var modelButton: some View {
        Button {
            showingModelMenu.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(shortModelLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(red: 0.56, green: 0.86, blue: 1.0))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(red: 0.36, green: 0.54, blue: 0.76).opacity(0.24))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingModelMenu, arrowEdge: .top) {
            ModelDropdownView(
                models: state.availableModels,
                selectedModelID: state.selectedModelID,
                onSelect: { id in
                    state.selectedModelID = id
                    state.persist()
                    showingModelMenu = false
                },
                onConfigure: {
                    showingModelMenu = false
                    state.showingSettings = true
                }
            )
        }
    }

    private var chatSurface: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if state.messages.isEmpty {
                        emptyState
                    }

                    ForEach(state.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if state.isSending {
                        HStack(alignment: .top, spacing: 10) {
                            modelBadge
                            Text("Thinking...")
                                .font(.system(size: 15, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.62))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Spacer()
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .onChange(of: state.messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: state.isSending) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("What shall we think through?")
                .font(.system(size: 36, weight: .light, design: .serif))
                .foregroundStyle(.white.opacity(0.92))
            Text("Start a prompt below. Use History to switch between sessions.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 30)

                Text(message.text)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .lineSpacing(4)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.19, green: 0.33, blue: 1.0), Color(red: 0.16, green: 0.24, blue: 0.86)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: 560, alignment: .trailing)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                modelBadge

                VStack(alignment: .leading, spacing: 6) {
                    Text(providerTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))

                    Text(message.text)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .lineSpacing(6)
                        .foregroundStyle(.white.opacity(0.92))
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .frame(maxWidth: 620, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var modelBadge: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.55, green: 0.40, blue: 1.0), Color(red: 0.33, green: 0.58, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = state.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.95))
            }

            if !state.attachments.isEmpty {
                attachmentRow
            }

            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    PromptInputView(text: $state.draft, isFocused: $composerFocused, onSend: {
                        state.sendCurrentDraft()
                    })
                    .frame(minHeight: 34, maxHeight: 54)
                    .padding(.horizontal, 10)

                    if state.draft.isEmpty {
                        Text("Ask anything...")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.34))
                            .padding(.horizontal, 18)
                            .padding(.top, 10)
                    }
                }

                HStack(spacing: 10) {
                    if state.isLoadingModels {
                        ProgressView().controlSize(.small)
                    }

                    Spacer()

                    Button {
                        state.pickAttachments()
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .buttonStyle(.plain)

                    Button {
                        state.sendCurrentDraft()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                            Text("Send")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.18, green: 0.35, blue: 1.0), Color(red: 0.16, green: 0.23, blue: 0.82)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isSending)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.06, green: 0.08, blue: 0.12).opacity(0.97))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(composerFocused ? .white.opacity(0.24) : .white.opacity(0.09), lineWidth: 1)
                    )
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var attachmentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(state.attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(attachment.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Button {
                            state.removeAttachment(attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var providerTitle: String {
        state.selectedModel?.provider.title ?? "Assistant"
    }

    private var shortModelLabel: String {
        state.selectedModel?.displayName ?? "Select model"
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }
}
