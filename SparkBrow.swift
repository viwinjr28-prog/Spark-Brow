import Cocoa
import WebKit

final class GlassCardView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class BrowserTab {
    let id = UUID()
    var title: String = "SparkOS"
    var urlString: String = "spark://home"
    let webView: WKWebView
    init(config: WKWebViewConfiguration) {
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.setValue(false, forKey: "drawsBackground")
        self.webView.allowsBackForwardNavigationGestures = true
    }
}

final class SparkBrowController: NSObject, NSApplicationDelegate, WKNavigationDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    var glassRoot: GlassCardView!
    var sidebarView: NSVisualEffectView!
    var sidebarWidthConstraint: NSLayoutConstraint!
    var sidebarOpen = false
    var tabStack: NSStackView!
    var urlField: NSTextField!
    var webContainer: NSView!
    var tabs: [BrowserTab] = []
    var activeIndex: Int = 0
    var sharedConfig: WKWebViewConfiguration!

    func sparkOSFileURL() -> URL? {
        return Bundle.main.url(forResource: "sparkos", withExtension: "html")
    }

    func setupMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Spark Brow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(addNewTab), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeCurrentTab), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "Focus Address Bar", action: #selector(focusUrlBar), keyEquivalent: "l")
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Toggle Sidebar", action: #selector(toggleSidebar), keyEquivalent: "s")
        viewMenu.addItem(withTitle: "Reload", action: #selector(reloadPage), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Back", action: #selector(goBack), keyEquivalent: "[")
        viewMenu.addItem(withTitle: "Forward", action: #selector(goForward), keyEquivalent: "]")
        viewItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        sharedConfig = WKWebViewConfiguration()
        sharedConfig.websiteDataStore = .default()

        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 790), styleMask: style, backing: .buffered, defer: false)
        window.center()
        window.title = "Spark Brow"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true

        glassRoot = GlassCardView(frame: window.contentView!.bounds)
        glassRoot.autoresizingMask = [.width, .height]
        window.contentView = glassRoot

        // Safari-style top bar (toolbar + full-width tab strip)
        let topBar = NSVisualEffectView()
        topBar.material = .headerView
        topBar.blendingMode = .withinWindow
        topBar.state = .active
        topBar.wantsLayer = true
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let sidebarBtn = makeIconBtn("sidebar.left", action: #selector(toggleSidebar))
        let backBtn = makeIconBtn("chevron.left", action: #selector(goBack))
        let fwdBtn = makeIconBtn("chevron.right", action: #selector(goForward))

        // Safari-style centered pill address bar with reload button
        let urlPill = NSView()
        urlPill.wantsLayer = true
        urlPill.layer?.cornerRadius = 11
        urlPill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        urlPill.layer?.borderWidth = 1
        urlPill.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        urlPill.translatesAutoresizingMaskIntoConstraints = false

        urlField = NSTextField()
        urlField.placeholderString = "Search or enter website name"
        urlField.isBezeled = false
        urlField.drawsBackground = false
        urlField.textColor = .white
        urlField.alignment = .center
        urlField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        urlField.delegate = self
        urlField.translatesAutoresizingMaskIntoConstraints = false

        let reloadBtn = makeIconBtn("arrow.clockwise", action: #selector(reloadPage), size: 22)
        reloadBtn.layer?.backgroundColor = NSColor.clear.cgColor

        urlPill.addSubview(urlField)
        urlPill.addSubview(reloadBtn)

        let homeBtn = makeIconBtn("house", action: #selector(goHome))
        let shareBtn = makeIconBtn("square.and.arrow.up", action: #selector(copyCurrentURL))
        let newTabBtn = makeIconBtn("plus", action: #selector(addNewTab))

        let leftSpacer = NSView(); leftSpacer.translatesAutoresizingMaskIntoConstraints = false
        let rightSpacer = NSView(); rightSpacer.translatesAutoresizingMaskIntoConstraints = false

        let navRow = NSStackView(views: [sidebarBtn, backBtn, fwdBtn, leftSpacer, urlPill, rightSpacer, homeBtn, shareBtn, newTabBtn])
        navRow.orientation = .horizontal
        navRow.spacing = 8
        navRow.alignment = .centerY
        navRow.translatesAutoresizingMaskIntoConstraints = false

        tabStack = NSStackView()
        tabStack.orientation = .horizontal
        tabStack.distribution = .fillEqually
        tabStack.spacing = 6
        tabStack.translatesAutoresizingMaskIntoConstraints = false

        topBar.addSubview(navRow)
        topBar.addSubview(tabStack)

        // Collapsible Safari-style sidebar
        sidebarView = NSVisualEffectView()
        sidebarView.material = .sidebar
        sidebarView.blendingMode = .withinWindow
        sidebarView.state = .active
        sidebarView.wantsLayer = true
        sidebarView.layer?.borderWidth = 0.5
        sidebarView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        sidebarView.translatesAutoresizingMaskIntoConstraints = false

        let sbTitle = NSTextField(labelWithString: "Bookmarks")
        sbTitle.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        sbTitle.textColor = NSColor.white.withAlphaComponent(0.6)

        let bmItems: [(String, String)] = [
            ("SparkOS Home", "spark://home"),
            ("Google", "https://www.google.com"),
            ("YouTube", "https://www.youtube.com"),
            ("GitHub · SparkOS", "https://github.com/viwinjr28-prog/SparkOS"),
            ("Wikipedia", "https://en.wikipedia.org")
        ]
        let sbList = NSStackView()
        sbList.orientation = .vertical
        sbList.alignment = .leading
        sbList.spacing = 6
        sbList.translatesAutoresizingMaskIntoConstraints = false
        sbList.addArrangedSubview(sbTitle)
        for (idx, item) in bmItems.enumerated() {
            let b = NSButton(title: "  " + item.0, target: self, action: #selector(openBookmark(_:)))
            b.tag = idx
            b.isBordered = false
            b.contentTintColor = .white
            b.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            b.alignment = .left
            b.wantsLayer = true
            b.layer?.cornerRadius = 8
            b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            b.widthAnchor.constraint(equalToConstant: 186).isActive = true
            b.heightAnchor.constraint(equalToConstant: 28).isActive = true
            sbList.addArrangedSubview(b)
        }
        sidebarView.addSubview(sbList)

        webContainer = NSView()
        webContainer.wantsLayer = true
        webContainer.translatesAutoresizingMaskIntoConstraints = false

        glassRoot.addSubview(topBar)
        glassRoot.addSubview(sidebarView)
        glassRoot.addSubview(webContainer)

        sidebarWidthConstraint = sidebarView.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: glassRoot.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: glassRoot.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: glassRoot.trailingAnchor),

            navRow.topAnchor.constraint(equalTo: topBar.topAnchor, constant: 10),
            navRow.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 78),
            navRow.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -14),

            urlPill.heightAnchor.constraint(equalToConstant: 28),
            urlPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            urlPill.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            leftSpacer.widthAnchor.constraint(equalTo: rightSpacer.widthAnchor),

            urlField.leadingAnchor.constraint(equalTo: urlPill.leadingAnchor, constant: 12),
            urlField.trailingAnchor.constraint(equalTo: reloadBtn.leadingAnchor, constant: -4),
            urlField.centerYAnchor.constraint(equalTo: urlPill.centerYAnchor),
            reloadBtn.trailingAnchor.constraint(equalTo: urlPill.trailingAnchor, constant: -6),
            reloadBtn.centerYAnchor.constraint(equalTo: urlPill.centerYAnchor),

            tabStack.topAnchor.constraint(equalTo: navRow.bottomAnchor, constant: 8),
            tabStack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            tabStack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            tabStack.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),
            tabStack.heightAnchor.constraint(equalToConstant: 26),

            sidebarView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            sidebarView.leadingAnchor.constraint(equalTo: glassRoot.leadingAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: glassRoot.bottomAnchor),
            sidebarWidthConstraint,

            sbList.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: 14),
            sbList.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 12),

            webContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: glassRoot.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: glassRoot.bottomAnchor)
        ])

        createTab(url: nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func makeIconBtn(_ symbol: String, action: Selector, size: CGFloat = 28) -> NSButton {
        let b = NSButton()
        b.bezelStyle = .rounded
        b.isBordered = false
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.contentTintColor = .white
        b.target = self
        b.action = action
        b.wantsLayer = true
        b.layer?.cornerRadius = 8
        b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        b.widthAnchor.constraint(equalToConstant: size).isActive = true
        b.heightAnchor.constraint(equalToConstant: size).isActive = true
        return b
    }

    @objc func toggleSidebar() {
        sidebarOpen.toggle()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            sidebarWidthConstraint.animator().constant = sidebarOpen ? 210 : 0
        }
    }

    @objc func openBookmark(_ sender: NSButton) {
        let urls = [
            "spark://home",
            "https://www.google.com",
            "https://www.youtube.com",
            "https://github.com/viwinjr28-prog/SparkOS",
            "https://en.wikipedia.org"
        ]
        guard sender.tag >= 0 && sender.tag < urls.count else { return }
        if urls[sender.tag] == "spark://home" { goHome() } else { navigate(urls[sender.tag]) }
    }

    @objc func copyCurrentURL() {
        let u = tabs[activeIndex].urlString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(u, forType: .string)
    }

    func createTab(url: String?) {
        let tab = BrowserTab(config: sharedConfig)
        tab.webView.navigationDelegate = self
        tabs.append(tab)
        selectTab(tabs.count - 1)
        if let u = url { navigate(u) } else { goHome() }
    }

    func selectTab(_ index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        activeIndex = index
        webContainer.subviews.forEach { $0.removeFromSuperview() }
        let wv = tabs[index].webView
        wv.frame = webContainer.bounds
        wv.autoresizingMask = [.width, .height]
        webContainer.addSubview(wv)
        urlField.stringValue = tabs[index].urlString == "spark://home" ? "" : tabs[index].urlString
        refreshTabBar()
    }

    func refreshTabBar() {
        tabStack.arrangedSubviews.forEach { tabStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (i, t) in tabs.enumerated() {
            let b = NSButton(title: String(t.title.prefix(24)) + (tabs.count > 1 ? "   ×" : ""), target: self, action: #selector(tabClicked(_:)))
            b.tag = i
            b.isBordered = false
            b.wantsLayer = true
            b.font = NSFont.systemFont(ofSize: 11.5, weight: i == activeIndex ? .semibold : .medium)
            b.contentTintColor = i == activeIndex ? .white : NSColor.white.withAlphaComponent(0.72)
            b.layer?.cornerRadius = 8
            b.layer?.backgroundColor = (i == activeIndex ? NSColor.white.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(0.06)).cgColor
            b.heightAnchor.constraint(equalToConstant: 26).isActive = true
            tabStack.addArrangedSubview(b)
        }
    }

    @objc func tabClicked(_ sender: NSButton) {
        let idx = sender.tag
        if idx == activeIndex && tabs.count > 1 {
            tabs.remove(at: idx)
            selectTab(max(0, idx - 1))
        } else {
            selectTab(idx)
        }
    }

    @objc func addNewTab() { createTab(url: nil) }
    @objc func closeCurrentTab() {
        if tabs.count > 1 { tabs.remove(at: activeIndex); selectTab(max(0, activeIndex - 1)) }
        else { window.performClose(nil) }
    }
    @objc func focusUrlBar() { window.makeFirstResponder(urlField) }
    @objc func goBack() { tabs[activeIndex].webView.goBack() }
    @objc func goForward() { tabs[activeIndex].webView.goForward() }
    @objc func reloadPage() {
        let tab = tabs[activeIndex]
        if tab.urlString == "spark://home" { goHome() } else { tab.webView.reload() }
    }
    @objc func goHome() {
        let tab = tabs[activeIndex]
        tab.urlString = "spark://home"
        tab.title = "SparkOS"
        urlField.stringValue = ""
        if let fileURL = sparkOSFileURL() {
            tab.webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        }
        refreshTabBar()
    }

    func navigate(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let target: String
        if q.contains(".") && !q.contains(" ") {
            target = q.hasPrefix("http://") || q.hasPrefix("https://") ? q : "https://" + q
        } else {
            let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            target = "https://www.google.com/search?q=" + enc
        }
        if let u = URL(string: target) {
            tabs[activeIndex].urlString = target
            tabs[activeIndex].webView.load(URLRequest(url: u))
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            navigate(urlField.stringValue)
            return true
        }
        return false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let idx = tabs.firstIndex(where: { $0.webView === webView }) else { return }
        if let u = webView.url, u.isFileURL && u.lastPathComponent == "sparkos.html" {
            tabs[idx].urlString = "spark://home"
            tabs[idx].title = "SparkOS"
        } else {
            if let title = webView.title, !title.isEmpty { tabs[idx].title = title }
            if let u = webView.url?.absoluteString, u != "about:blank" { tabs[idx].urlString = u }
        }
        if idx == activeIndex {
            urlField.stringValue = tabs[idx].urlString == "spark://home" ? "" : tabs[idx].urlString
        }
        refreshTabBar()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = SparkBrowController()
app.delegate = delegate
app.run()
