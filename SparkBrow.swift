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
    var title: String = "Spark Brow"
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
    var tabStack: NSStackView!
    var urlField: NSTextField!
    var webContainer: NSView!
    var tabs: [BrowserTab] = []
    var activeIndex: Int = 0

    let startPageHTML = """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><style>
    * { box-sizing: border-box; }
    body {
      margin: 0; height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif; color: #fff;
      background: radial-gradient(circle at 75% 20%, rgba(124,58,237,0.42), rgba(2,6,23,0.72) 70%);
    }
    .card {
      padding: 34px 40px; border-radius: 26px; text-align: center;
      background: rgba(255,255,255,0.08); backdrop-filter: blur(24px);
      border: 1px solid rgba(255,255,255,0.22); box-shadow: 0 24px 60px rgba(0,0,0,0.45);
    }
    h1 { margin: 0 0 8px; font-size: 46px; letter-spacing: -1.5px; }
    p { margin: 0 0 20px; color: rgba(255,255,255,0.72); font-size: 14px; }
    .links { display: flex; gap: 10px; justify-content: center; flex-wrap: wrap; }
    a {
      text-decoration: none; color: #fff; font-size: 13px; font-weight: 600;
      padding: 9px 16px; border-radius: 12px; background: rgba(255,255,255,0.12);
      border: 1px solid rgba(255,255,255,0.18);
    }
    a:hover { background: rgba(124,58,237,0.55); }
    .credit { margin-top: 18px; font-size: 11px; letter-spacing: 0.8px; text-transform: uppercase; color: rgba(255,255,255,0.45); }
    </style></head><body>
      <div class="card">
        <h1>Spark Brow</h1>
        <p>Liquid Glass Browser for macOS</p>
        <div class="links">
          <a href="https://www.google.com">Google</a>
          <a href="https://www.youtube.com">YouTube</a>
          <a href="https://github.com/viwinjr28-prog/SparkOS">SparkOS Repo</a>
          <a href="https://en.wikipedia.org">Wikipedia</a>
        </div>
        <div class="credit">Made by Viwin Jayaramanrani</div>
      </div>
    </body></html>
    """

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
        viewMenu.addItem(withTitle: "Reload", action: #selector(reloadPage), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Back", action: #selector(goBack), keyEquivalent: "[")
        viewMenu.addItem(withTitle: "Forward", action: #selector(goForward), keyEquivalent: "]")
        viewItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760), styleMask: style, backing: .buffered, defer: false)
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

        let topBar = NSVisualEffectView()
        topBar.material = .headerView
        topBar.blendingMode = .withinWindow
        topBar.state = .active
        topBar.wantsLayer = true
        topBar.layer?.cornerRadius = 16
        topBar.layer?.borderWidth = 1
        topBar.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let backBtn = makeIconBtn("chevron.left", action: #selector(goBack))
        let fwdBtn = makeIconBtn("chevron.right", action: #selector(goForward))
        let reloadBtn = makeIconBtn("arrow.clockwise", action: #selector(reloadPage))
        let homeBtn = makeIconBtn("house", action: #selector(goHome))
        let newTabBtn = makeIconBtn("plus", action: #selector(addNewTab))

        urlField = NSTextField()
        urlField.placeholderString = "Search Google or enter website..."
        urlField.isBezeled = false
        urlField.drawsBackground = true
        urlField.backgroundColor = NSColor.black.withAlphaComponent(0.28)
        urlField.textColor = .white
        urlField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        urlField.wantsLayer = true
        urlField.layer?.cornerRadius = 11
        urlField.layer?.borderWidth = 1
        urlField.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        urlField.delegate = self
        urlField.translatesAutoresizingMaskIntoConstraints = false

        let navRow = NSStackView(views: [backBtn, fwdBtn, reloadBtn, homeBtn, urlField, newTabBtn])
        navRow.orientation = .horizontal
        navRow.spacing = 8
        navRow.translatesAutoresizingMaskIntoConstraints = false

        tabStack = NSStackView()
        tabStack.orientation = .horizontal
        tabStack.spacing = 6
        tabStack.translatesAutoresizingMaskIntoConstraints = false

        topBar.addSubview(navRow)
        topBar.addSubview(tabStack)

        webContainer = NSView()
        webContainer.wantsLayer = true
        webContainer.layer?.cornerRadius = 16
        webContainer.layer?.masksToBounds = true
        webContainer.layer?.borderWidth = 1
        webContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        webContainer.translatesAutoresizingMaskIntoConstraints = false

        glassRoot.addSubview(topBar)
        glassRoot.addSubview(webContainer)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: glassRoot.topAnchor, constant: 34),
            topBar.leadingAnchor.constraint(equalTo: glassRoot.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: glassRoot.trailingAnchor, constant: -12),

            navRow.topAnchor.constraint(equalTo: topBar.topAnchor, constant: 10),
            navRow.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            navRow.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            urlField.heightAnchor.constraint(equalToConstant: 28),

            tabStack.topAnchor.constraint(equalTo: navRow.bottomAnchor, constant: 8),
            tabStack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            tabStack.trailingAnchor.constraint(lessThanOrEqualTo: topBar.trailingAnchor, constant: -12),
            tabStack.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),

            webContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            webContainer.leadingAnchor.constraint(equalTo: glassRoot.leadingAnchor, constant: 12),
            webContainer.trailingAnchor.constraint(equalTo: glassRoot.trailingAnchor, constant: -12),
            webContainer.bottomAnchor.constraint(equalTo: glassRoot.bottomAnchor, constant: -12)
        ])

        createTab(url: nil)
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
        b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        b.widthAnchor.constraint(equalToConstant: 28).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return b
    }

    func createTab(url: String?) {
        let cfg = WKWebViewConfiguration()
        let tab = BrowserTab(config: cfg)
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
            let b = NSButton(title: "  " + String(t.title.prefix(20)) + (tabs.count > 1 ? "  ×" : "  "), target: self, action: #selector(tabClicked(_:)))
            b.tag = i
            b.isBordered = false
            b.wantsLayer = true
            b.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            b.contentTintColor = .white
            b.layer?.cornerRadius = 9
            b.layer?.backgroundColor = (i == activeIndex ? NSColor.systemPurple.withAlphaComponent(0.55) : NSColor.white.withAlphaComponent(0.10)).cgColor
            b.heightAnchor.constraint(equalToConstant: 24).isActive = true
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
        tab.title = "Spark Brow"
        urlField.stringValue = ""
        tab.webView.loadHTMLString(startPageHTML, baseURL: nil)
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
        if let title = webView.title, !title.isEmpty { tabs[idx].title = title }
        if let u = webView.url?.absoluteString, u != "about:blank" { tabs[idx].urlString = u }
        if idx == activeIndex && tabs[idx].urlString != "spark://home" {
            urlField.stringValue = tabs[idx].urlString
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
