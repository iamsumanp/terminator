import SwiftUI
import AppKit
import WebKit

struct AppTab: Identifiable {
    let id: String
    let title: String
    let shortcutLabel: String?
    let iconName: String?
    let monogram: String
    let badgeColor: Color
    let landingURL: URL?
    let isLocal: Bool

    static let openAI = AppTab(
        id: "openAI",
        title: "OpenAI",
        shortcutLabel: "⌥1",
        iconName: "openai",
        monogram: "O",
        badgeColor: Color(red: 0.14, green: 0.84, blue: 0.71),
        landingURL: URL(string: "https://chatgpt.com"),
        isLocal: false
    )

    static let gemini = AppTab(
        id: "gemini",
        title: "Gemini",
        shortcutLabel: "⌥2",
        iconName: "gemini",
        monogram: "G",
        badgeColor: Color(red: 0.35, green: 0.54, blue: 1.00),
        landingURL: URL(string: "https://gemini.google.com"),
        isLocal: false
    )

    static let anthropic = AppTab(
        id: "anthropic",
        title: "Anthropic",
        shortcutLabel: "⌥3",
        iconName: "anthropic",
        monogram: "A",
        badgeColor: Color(red: 0.90, green: 0.62, blue: 0.38),
        landingURL: URL(string: "https://claude.ai"),
        isLocal: false
    )

    static let docsumo = AppTab(
        id: "docsumo",
        title: "Docsumo",
        shortcutLabel: "⌥4",
        iconName: "docsumo",
        monogram: "D",
        badgeColor: Color(red: 0.93, green: 0.32, blue: 0.43),
        landingURL: URL(string: "https://chat.docsumo.com/chat"),
        isLocal: false
    )

    static let local = AppTab(
        id: "local",
        title: "Local",
        shortcutLabel: "⌥5",
        iconName: "local",
        monogram: "L",
        badgeColor: Color(red: 0.50, green: 0.56, blue: 0.63),
        landingURL: nil,
        isLocal: true
    )

    static func custom(_ provider: CustomProvider) -> AppTab? {
        guard let url = URL(string: provider.urlString) else { return nil }
        let trimmed = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? (url.host ?? "Custom") : trimmed
        let monogram = String(title.prefix(1)).uppercased()
        return AppTab(
            id: "custom-\(provider.id.uuidString)",
            title: title,
            shortcutLabel: nil,
            iconName: nil,
            monogram: monogram.isEmpty ? "C" : monogram,
            badgeColor: Color(red: 0.86, green: 0.60, blue: 0.36),
            landingURL: url,
            isLocal: false
        )
    }
}

@MainActor
final class WebViewCoordinator: NSObject, ObservableObject {
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false

    private var webViews: [String: WKWebView] = [:]
    private var observations: [NSKeyValueObservation] = []
    private var activeTabID: String?
    private var activeTabIsLocal: Bool = false
    private let processPool = WKProcessPool()
    private var pageZoom: Double = 1.0

    func select(tabID: String, isLocal: Bool) {
        activeTabID = tabID
        activeTabIsLocal = isLocal
        bindActiveWebView()
    }

    func webView(for tab: AppTab) -> WKWebView {
        if let existing = webViews[tab.id] {
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
        webView.pageZoom = pageZoom

        if let url = tab.landingURL {
            webView.load(URLRequest(url: url))
        }

        webViews[tab.id] = webView
        if tab.id == activeTabID {
            bindActiveWebView()
        }
        return webView
    }

    func goBack() {
        guard let activeTabID else { return }
        webViews[activeTabID]?.goBack()
    }

    func goForward() {
        guard let activeTabID else { return }
        webViews[activeTabID]?.goForward()
    }

    func reload() {
        guard let activeTabID else { return }
        webViews[activeTabID]?.reload()
    }

    func setPageZoom(_ zoom: Double) {
        pageZoom = zoom
        for webView in webViews.values {
            webView.pageZoom = zoom
        }
    }

    func focusActiveInput() {
        guard !activeTabIsLocal, let activeTabID, let webView = webViews[activeTabID] else { return }
        webView.window?.makeFirstResponder(webView)
        _ = webView.becomeFirstResponder()

        let script = """
        (() => {
          const isVisible = (el) => {
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            return rect.width > 6 && rect.height > 6 &&
              style.visibility !== 'hidden' &&
              style.display !== 'none';
          };

          const isEditable = (el) => {
            if (!el || !isVisible(el)) return false;
            if (el.matches('textarea')) return !el.disabled && !el.readOnly;
            if (el.matches('input')) {
              const t = (el.type || 'text').toLowerCase();
              const ok = ['text', 'search', 'email', 'url', 'tel', 'password', 'number'];
              return ok.includes(t) && !el.disabled && !el.readOnly;
            }
            return el.isContentEditable === true;
          };

          const rank = (el) => {
            const rect = el.getBoundingClientRect();
            const attrs = [
              el.getAttribute('placeholder') || '',
              el.getAttribute('aria-label') || '',
              el.getAttribute('name') || '',
              el.id || '',
              el.className || ''
            ].join(' ').toLowerCase();

            let score = 0;
            if (attrs.match(/message|chat|prompt|reply|ask|send|write/)) score += 100;
            if (el.matches('textarea,[contenteditable=\"true\"]')) score += 20;
            if (rect.top > window.innerHeight * 0.45) score += 25;
            score += Math.min(rect.width, 900) / 40;
            return score;
          };

          const nodes = Array.from(document.querySelectorAll('textarea, input, [contenteditable=\"true\"]'))
            .filter(isEditable)
            .sort((a, b) => rank(b) - rank(a));

          const target = nodes[0];
          if (!target) return;
          target.focus({ preventScroll: true });

          if (target.matches('textarea,input')) {
            const len = target.value?.length ?? 0;
            target.setSelectionRange?.(len, len);
          } else if (target.isContentEditable) {
            const sel = window.getSelection();
            const range = document.createRange();
            range.selectNodeContents(target);
            range.collapse(false);
            sel?.removeAllRanges();
            sel?.addRange(range);
          }
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func bindActiveWebView() {
        observations.removeAll()

        guard !activeTabIsLocal, let activeTabID, let webView = webViews[activeTabID] else {
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
    @State private var selectedTabID: String = AppTab.openAI.id
    @State private var resizeStartSize: CGSize?
    private let minWebZoom: Double = 0.7
    private let maxWebZoom: Double = 2.0
    private let webZoomStep: Double = 0.1

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
                selectedTabID = visibleTabIDs.contains(selectedTabID) ? selectedTabID : initialTab.id
            }
            web.setPageZoom(clampedWebZoom(state.webZoom))
            selectCurrentTabInWebCoordinator()
            for tab in visibleTabs where !tab.isLocal {
                _ = web.webView(for: tab)
            }
        }
        .onChange(of: selectedTabID) { _ in
            selectCurrentTabInWebCoordinator()
        }
        .onChange(of: visibleTabIDs) { _ in
            guard let fallback = visibleTabs.first else { return }
            if !visibleTabIDs.contains(selectedTabID) {
                selectedTabID = fallback.id
            }
        }
        .onChange(of: state.focusRequestToken) { _ in
            if !(selectedTab?.isLocal ?? false) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    web.focusActiveInput()
                }
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
            HStack(spacing: 2) {
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
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(visibleTabs) { tab in
                        Button {
                            selectedTabID = tab.id
                        } label: {
                            HStack(spacing: isCompactTopBar ? 0 : 7) {
                                tabIcon(tab)
                                if !isCompactTopBar, let shortcut = tab.shortcutLabel {
                                    Text(shortcut)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                }
                            }
                            .foregroundStyle(selectedTabID == tab.id ? .white : .white.opacity(0.66))
                            .frame(minWidth: isCompactTopBar ? 38 : 76, minHeight: 36)
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedTabID == tab.id ? Color.white.opacity(0.16) : Color.clear)
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
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 4) {
                Button {
                    adjustWebZoom(by: -webZoomStep)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(canZoomOut ? 0.88 : 0.35))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(!canZoomOut)
                .keyboardShortcut("-", modifiers: .command)
                .help("Zoom Out (\u{2318}-)")

                Button {
                    resetWebZoom()
                } label: {
                    Group {
                        if isCompactTopBar {
                            Text("\(Int((state.webZoom * 100).rounded()))")
                        } else {
                            Text(webZoomLabel)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(minWidth: isCompactTopBar ? 34 : 44, minHeight: 22)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("0", modifiers: .command)
                .help("Reset Zoom (\u{2318}0)")

                Button {
                    adjustWebZoom(by: webZoomStep)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(canZoomIn ? 0.88 : 0.35))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(!canZoomIn)
                .keyboardShortcut("=", modifiers: .command)
                .help("Zoom In (\u{2318}=)")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))

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
        } else if selectedTab?.isLocal == true && state.prefersNativeTab {
            LocalNativeChatPane(state: state)
        } else if let tab = selectedTab, !tab.isLocal {
            ProviderWebView(webView: web.webView(for: tab))
                .id(tab.id)
                .background(Color.clear)
        } else if let fallback = firstWebTab {
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
        let customTabs: [AppTab] = state.customProviders.compactMap { provider in
            guard provider.isEnabled else { return nil }
            return AppTab.custom(provider)
        }
        tabs.append(contentsOf: customTabs)
        if state.prefersNativeTab {
            tabs.append(.local)
        }
        return tabs
    }

    private var visibleTabIDs: [String] {
        visibleTabs.map(\.id)
    }

    private var canUseWebControls: Bool {
        selectedTab?.isLocal == false
    }

    private var isCompactTopBar: Bool {
        state.panelWidth < 760
    }

    private var webZoomLabel: String {
        "\(Int((state.webZoom * 100).rounded()))%"
    }

    private var canZoomIn: Bool {
        state.webZoom < maxWebZoom
    }

    private var canZoomOut: Bool {
        state.webZoom > minWebZoom
    }

    private func clampedWebZoom(_ zoom: Double) -> Double {
        min(max(zoom, minWebZoom), maxWebZoom)
    }

    private func adjustWebZoom(by delta: Double) {
        let adjusted = (state.webZoom + delta) / webZoomStep
        let rounded = (adjusted.rounded() * webZoomStep)
        applyWebZoom(rounded)
    }

    private func resetWebZoom() {
        applyWebZoom(1.0)
    }

    private func applyWebZoom(_ zoom: Double) {
        let clamped = clampedWebZoom(zoom)
        guard abs(clamped - state.webZoom) > 0.0001 else { return }
        state.webZoom = clamped
        web.setPageZoom(clamped)
        state.persist()
    }

    @ViewBuilder
    private func tabIcon(_ tab: AppTab) -> some View {
        if let iconName = tab.iconName, let image = bundledTabIcon(named: iconName) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 14, height: 14)
        } else if tab.isLocal {
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

    private var selectedTab: AppTab? {
        visibleTabs.first(where: { $0.id == selectedTabID })
    }

    private var firstWebTab: AppTab? {
        visibleTabs.first(where: { !$0.isLocal })
    }

    private func selectCurrentTabInWebCoordinator() {
        guard let tab = selectedTab else { return }
        web.select(tabID: tab.id, isLocal: tab.isLocal)
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
            requestComposerFocus()
        }
        .onChange(of: state.focusRequestToken) { _ in
            requestComposerFocus()
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
                favoriteModelIDs: Set(state.favoriteModelIDs),
                onSelect: { id in
                    state.selectedModelID = id
                    state.persist()
                    showingModelMenu = false
                },
                onToggleFavorite: { id in
                    state.toggleFavoriteModel(id)
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

    private func requestComposerFocus() {
        composerFocused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            composerFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            composerFocused = true
        }
    }
}
