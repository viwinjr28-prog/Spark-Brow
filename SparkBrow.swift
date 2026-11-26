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
    var isHome: Bool = true
    let webView: WKWebView
    init(config: WKWebViewConfiguration) {
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.setValue(false, forKey: "drawsBackground")
        self.webView.allowsBackForwardNavigationGestures = true
    }
}

final class SparkBrowController: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var glassRoot: GlassCardView!
    var tabStack: NSStackView!
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
        fileMenu.addItem(withTitle: "New SparkOS Tab", action: #selector(addNewTab), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeCurrentTab), keyEquivalent: "w")
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
        viewMenu.addItem(withTitle: "SparkOS Home", action: #selector(goHome), keyEquivalent: "h")
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
        sharedConfig.preferences.javaScriptCanOpenWindowsAutomatically = true

        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 800), styleMask: style, backing: .buffered, defer: false)
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

        // Minimal Liquid Glass Tab Strip (SparkOS itself handles search & dock)
        let topBar = NSVisualEffectView()
        topBar.material = .headerView
        topBar.blendingMode = .withinWindow
        topBar.state = .active
        topBar.wantsLayer = true
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let backBtn = makeIconBtn("chevron.left", action: #selector(goBack))
        let fwdBtn = makeIconBtn("chevron.right", action: #selector(goForward))
        let reloadBtn = makeIconBtn("arrow.clockwise", action: #selector(reloadPage))
        let homeBtn = makeIconBtn("house", action: #selector(goHome))
        let newTabBtn = makeIconBtn("plus", action: #selector(addNewTab))

        tabStack = NSStackView()
        tabStack.orientation = .horizontal
        tabStack.distribution = .fillEqually
        tabStack.spacing = 6
        tabStack.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [backBtn, fwdBtn, reloadBtn, homeBtn, tabStack, newTabBtn])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        topBar.addSubview(row)

        webContainer = NSView()
        webContainer.wantsLayer = true
        webContainer.translatesAutoresizingMaskIntoConstraints = false

        glassRoot.addSubview(topBar)
        glassRoot.addSubview(webContainer)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: glassRoot.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: glassRoot.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: glassRoot.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 42),

            row.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            row.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 78),
            row.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            tabStack.heightAnchor.constraint(equalToConstant: 26),

            webContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: glassRoot.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: glassRoot.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: glassRoot.bottomAnchor)
        ])

        createTab(request: nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func makeIconBtn(_ symbol: String, action: Selector) -> NSButton {
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
        b.widthAnchor.constraint(equalToConstant: 26).isActive = true
        b.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return b
    }

    @discardableResult
    func createTab(request: URLRequest?) -> BrowserTab {
        let tab = BrowserTab(config: sharedConfig)
        tab.webView.navigationDelegate = self
        tab.webView.uiDelegate = self
        tabs.append(tab)
        selectTab(tabs.count - 1)
        if let req = request {
            tab.isHome = false
            tab.title = req.url?.host ?? "Loading..."
            tab.webView.load(req)
            refreshTabBar()
        } else {
            goHome()
        }
        return tab
    }

    func selectTab(_ index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        activeIndex = index
        webContainer.subviews.forEach { $0.removeFromSuperview() }
        let wv = tabs[index].webView
        wv.frame = webContainer.bounds
        wv.autoresizingMask = [.width, .height]
        webContainer.addSubview(wv)
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

    @objc func addNewTab() { createTab(request: nil) }
    @objc func closeCurrentTab() {
        if tabs.count > 1 { tabs.remove(at: activeIndex); selectTab(max(0, activeIndex - 1)) }
        else { window.performClose(nil) }
    }
    @objc func goBack() { tabs[activeIndex].webView.goBack() }
    @objc func goForward() { tabs[activeIndex].webView.goForward() }
    @objc func reloadPage() {
        if tabs[activeIndex].isHome { goHome() } else { tabs[activeIndex].webView.reload() }
    }
    @objc func goHome() {
        let tab = tabs[activeIndex]
        tab.isHome = true
        tab.title = "SparkOS"
        if let fileURL = sparkOSFileURL() {
            tab.webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        }
        refreshTabBar()
    }

    // Open target="_blank" / SparkOS dock links in a new Spark Brow tab
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            let newTab = BrowserTab(config: configuration)
            newTab.webView.navigationDelegate = self
            newTab.webView.uiDelegate = self
            newTab.isHome = false
            newTab.title = navigationAction.request.url?.host ?? "Tab"
            tabs.append(newTab)
            selectTab(tabs.count - 1)
            return newTab.webView
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let idx = tabs.firstIndex(where: { $0.webView === webView }) else { return }
        if let u = webView.url, u.isFileURL && u.lastPathComponent == "sparkos.html" {
            tabs[idx].isHome = true
            tabs[idx].title = "SparkOS"
        } else {
            tabs[idx].isHome = false
            if let title = webView.title, !title.isEmpty { tabs[idx].title = title }
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
