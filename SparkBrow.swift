import Cocoa
import WebKit

func roundedMaskImage(radius: CGFloat) -> NSImage {
    let d = radius * 2 + 2
    let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        return true
    }
    img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    img.resizingMode = .stretch
    return img
}

final class LiquidGlassPill: NSVisualEffectView {
    init(radius: CGFloat = 15) {
        super.init(frame: .zero)
        self.material = .hudWindow
        self.blendingMode = .withinWindow
        self.state = .active
        self.maskImage = roundedMaskImage(radius: radius)
        self.wantsLayer = true
        self.layer?.cornerRadius = radius
        self.layer?.masksToBounds = true
        self.layer?.borderWidth = 1
        self.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
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
    var glassRoot: NSVisualEffectView!
    var floatBar: LiquidGlassPill!
    var tabStack: NSStackView!
    var bootOverlay: NSVisualEffectView!
    var webContainer: NSView!
    var tabs: [BrowserTab] = []
    var activeIndex: Int = 0
    var sharedConfig: WKWebViewConfiguration!

    let adBlockJSON = """
    [
      {"trigger":{"url-filter":".*doubleclick\\\\.net.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*googlesyndication\\\\.com.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*googleadservices\\\\.com.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*adnxs\\\\.com.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*scorecardresearch\\\\.com.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*taboola\\\\.com.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*outbrain\\\\.com.*"},"action":{"type":"block"}}
    ]
    """

    func sparkOSFileURL() -> URL? {
        return Bundle.main.url(forResource: "sparkos", withExtension: "html")
    }

    func setupMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Spark Brow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New SparkOS Tab", action: #selector(addNewTab), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeCurrentTab), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem(); mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let viewItem = NSMenuItem(); mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "SparkOS Home", action: #selector(goHome), keyEquivalent: "h")
        viewMenu.addItem(withTitle: "Reload", action: #selector(reloadPage), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Back", action: #selector(goBack), keyEquivalent: "[")
        viewMenu.addItem(withTitle: "Forward", action: #selector(goForward), keyEquivalent: "]")
        viewItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }

    func playBootAnimation() {
        bootOverlay = NSVisualEffectView(frame: glassRoot.bounds)
        bootOverlay.material = .hudWindow
        bootOverlay.blendingMode = .behindWindow
        bootOverlay.state = .active
        bootOverlay.autoresizingMask = [.width, .height]
        bootOverlay.wantsLayer = true
        bootOverlay.layer?.backgroundColor = NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.09, alpha: 0.90).cgColor

        let bootWeb = WKWebView(frame: bootOverlay.bounds)
        bootWeb.setValue(false, forKey: "drawsBackground")
        bootWeb.autoresizingMask = [.width, .height]
        let bootHTML = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        body { margin:0; height:100vh; display:flex; flex-direction:column; align-items:center; justify-content:center;
          font-family:-apple-system,BlinkMacSystemFont,sans-serif; color:#fff; background:transparent; overflow:hidden; }
        .glow { position:absolute; width:260px; height:260px; border-radius:50%; background:radial-gradient(circle, rgba(124,58,237,0.45), transparent 70%); animation: pulse 1.2s ease-out forwards; }
        @keyframes pulse { 0%{ transform:scale(0.5); opacity:0; } 100%{ transform:scale(1.25); opacity:1; } }
        .star { position:relative; width:56px; height:56px; margin-bottom:14px; animation: pop 0.65s cubic-bezier(0.2,0.9,0.3,1.2) forwards; }
        @keyframes pop { 0%{ transform:scale(0.3) rotate(-30deg); opacity:0; } 100%{ transform:scale(1) rotate(0); opacity:1; } }
        h1 { position:relative; margin:0; font-size:38px; letter-spacing:-1.3px; animation: up 0.6s ease forwards; }
        p { position:relative; margin:6px 0 0; font-size:11px; letter-spacing:1.6px; text-transform:uppercase; color:rgba(255,255,255,0.58); animation: up 0.7s ease forwards; }
        @keyframes up { 0%{ transform:translateY(10px); opacity:0; } 100%{ transform:translateY(0); opacity:1; } }
        </style></head><body>
          <div class="glow"></div>
          <svg class="star" viewBox="0 0 64 64"><path d="M32 4 L39 25 L60 32 L39 39 L32 60 L25 39 L4 32 L25 25 Z" fill="#fff"/></svg>
          <h1>Spark Brow</h1>
          <p>Liquid Glass</p>
        </body></html>
        """
        bootWeb.loadHTMLString(bootHTML, baseURL: nil)
        bootOverlay.addSubview(bootWeb)
        glassRoot.addSubview(bootOverlay)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.90) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.45
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.bootOverlay.animator().alphaValue = 0
            }, completionHandler: {
                self.bootOverlay.removeFromSuperview()
            })
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        sharedConfig = WKWebViewConfiguration()
        sharedConfig.websiteDataStore = .default()
        sharedConfig.preferences.javaScriptCanOpenWindowsAutomatically = true

        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "SparkAirBlock", encodedContentRuleList: adBlockJSON) { list, _ in
            if let list = list {
                DispatchQueue.main.async { self.sharedConfig.userContentController.add(list) }
            }
        }

        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1300, height: 830), styleMask: style, backing: .buffered, defer: false)
        window.center()
        window.title = "Spark Brow"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true

        glassRoot = NSVisualEffectView(frame: window.contentView!.bounds)
        glassRoot.material = .hudWindow
        glassRoot.blendingMode = .behindWindow
        glassRoot.state = .active
        glassRoot.autoresizingMask = [.width, .height]
        window.contentView = glassRoot

        webContainer = NSView()
        webContainer.wantsLayer = true
        webContainer.translatesAutoresizingMaskIntoConstraints = false

        // Smart Floating Pill: hidden when on a single SparkOS Home tab; appears when browsing or >1 tab
        floatBar = LiquidGlassPill(radius: 14)
        floatBar.translatesAutoresizingMaskIntoConstraints = false
        floatBar.isHidden = true

        let backBtn = makeIconBtn("chevron.left", action: #selector(goBack))
        let fwdBtn = makeIconBtn("chevron.right", action: #selector(goForward))
        let reloadBtn = makeIconBtn("arrow.clockwise", action: #selector(reloadPage))
        let homeBtn = makeIconBtn("sparkles", action: #selector(goHome))
        let newTabBtn = makeIconBtn("plus", action: #selector(addNewTab))

        tabStack = NSStackView()
        tabStack.orientation = .horizontal
        tabStack.spacing = 4
        tabStack.translatesAutoresizingMaskIntoConstraints = false

        let pillRow = NSStackView(views: [backBtn, fwdBtn, reloadBtn, homeBtn, tabStack, newTabBtn])
        pillRow.orientation = .horizontal
        pillRow.spacing = 6
        pillRow.alignment = .centerY
        pillRow.translatesAutoresizingMaskIntoConstraints = false
        floatBar.addSubview(pillRow)

        glassRoot.addSubview(webContainer)
        glassRoot.addSubview(floatBar)

        NSLayoutConstraint.activate([
            webContainer.topAnchor.constraint(equalTo: glassRoot.topAnchor),
            webContainer.leadingAnchor.constraint(equalTo: glassRoot.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: glassRoot.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: glassRoot.bottomAnchor),

            floatBar.topAnchor.constraint(equalTo: glassRoot.topAnchor, constant: 10),
            floatBar.leadingAnchor.constraint(equalTo: glassRoot.leadingAnchor, constant: 78),
            floatBar.trailingAnchor.constraint(lessThanOrEqualTo: glassRoot.trailingAnchor, constant: -16),
            floatBar.heightAnchor.constraint(equalToConstant: 36),

            pillRow.centerYAnchor.constraint(equalTo: floatBar.centerYAnchor),
            pillRow.leadingAnchor.constraint(equalTo: floatBar.leadingAnchor, constant: 8),
            pillRow.trailingAnchor.constraint(equalTo: floatBar.trailingAnchor, constant: -8),
            tabStack.heightAnchor.constraint(equalToConstant: 24)
        ])

        createTab()
        playBootAnimation()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func makeIconBtn(_ symbol: String, action: Selector, size: CGFloat = 24) -> NSButton {
        let b = NSButton()
        b.bezelStyle = .rounded
        b.isBordered = false
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.contentTintColor = .white
        b.target = self
        b.action = action
        b.wantsLayer = true
        b.layer?.cornerRadius = 8
        b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        b.widthAnchor.constraint(equalToConstant: size).isActive = true
        b.heightAnchor.constraint(equalToConstant: size).isActive = true
        return b
    }

    func updateFloatBarVisibility() {
        let singleHome = (tabs.count == 1 && tabs[0].isHome)
        floatBar.isHidden = singleHome
    }

    func refreshTabBar() {
        tabStack.arrangedSubviews.forEach { tabStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (i, t) in tabs.enumerated() {
            let b = NSButton(title: "  " + String(t.title.prefix(18)) + (tabs.count > 1 ? "  ×" : "  "), target: self, action: #selector(tabClicked(_:)))
            b.tag = i
            b.isBordered = false
            b.wantsLayer = true
            b.font = NSFont.systemFont(ofSize: 11, weight: i == activeIndex ? .semibold : .medium)
            b.contentTintColor = i == activeIndex ? .white : NSColor.white.withAlphaComponent(0.70)
            b.layer?.cornerRadius = 8
            b.layer?.backgroundColor = (i == activeIndex ? NSColor.systemPurple.withAlphaComponent(0.55) : NSColor.white.withAlphaComponent(0.08)).cgColor
            b.heightAnchor.constraint(equalToConstant: 24).isActive = true
            tabStack.addArrangedSubview(b)
        }
        updateFloatBarVisibility()
    }

    @discardableResult
    func createTab() -> BrowserTab {
        let tab = BrowserTab(config: sharedConfig)
        tab.webView.navigationDelegate = self
        tab.webView.uiDelegate = self
        tabs.append(tab)
        selectTab(tabs.count - 1)
        goHome()
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

    @objc func tabClicked(_ sender: NSButton) {
        let idx = sender.tag
        if idx == activeIndex && tabs.count > 1 {
            tabs.remove(at: idx)
            selectTab(max(0, idx - 1))
        } else {
            selectTab(idx)
        }
    }

    @objc func addNewTab() { createTab() }
    @objc func closeCurrentTab() {
        if tabs.count > 1 { tabs.remove(at: activeIndex); selectTab(max(0, activeIndex - 1)) }
        else { window.performClose(nil) }
    }
    @objc func goBack() {
        if tabs[activeIndex].webView.canGoBack { tabs[activeIndex].webView.goBack() }
        else { goHome() }
    }
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
