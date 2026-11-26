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

final class AirGlassView: NSVisualEffectView {
    init(material: NSVisualEffectView.Material = .hudWindow, blending: NSVisualEffectView.BlendingMode = .withinWindow, radius: CGFloat = 18) {
        super.init(frame: .zero)
        self.material = material
        self.blendingMode = blending
        self.state = .active
        self.maskImage = roundedMaskImage(radius: radius)
        self.wantsLayer = true
        self.layer?.cornerRadius = radius
        self.layer?.masksToBounds = true
        self.layer?.borderWidth = 1
        self.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class BrowserTab {
    let id = UUID()
    var title: String = "SparkOS"
    var urlString: String = "spark://home"
    var isHome: Bool = true
    let webView: WKWebView
    init(config: WKWebViewConfiguration) {
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.setValue(false, forKey: "drawsBackground")
        self.webView.allowsBackForwardNavigationGestures = true
    }
}

final class SparkBrowController: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var glassRoot: NSVisualEffectView!
    var topBar: AirGlassView!
    var leftRail: AirGlassView!
    var drawerBox: AirGlassView!
    var drawerWebView: WKWebView!
    var bootOverlay: NSVisualEffectView!
    var tabStack: NSStackView!
    var urlField: NSTextField!
    var webContainer: NSView!
    var tabs: [BrowserTab] = []
    var activeIndex: Int = 0
    var sharedConfig: WKWebViewConfiguration!
    var drawerOpen = false
    var activeDrawerPanel = "boosts"
    var adBlockRuleList: WKContentRuleList?
    var breakTimer: Timer?

    let adBlockJSON = """
    [
      {"trigger":{"url-filter":".*doubleclick\\\\.net.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*googlesyndication\\\\.com.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*googleadservices\\\\.com.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*adnxs\\\\.com.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*scorecardresearch\\\\.com.*"},"action":{"type":"block"}}
    ]
    """

    func airPanelHTML() -> String {
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><style>
        * { box-sizing: border-box; user-select: none; }
        body {
          margin: 0; padding: 18px; color: #fff; background: transparent;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
        }
        .head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px; }
        .head h2 { margin: 0; font-size: 17px; font-weight: 700; letter-spacing: -0.3px; }
        .xbtn {
          width: 26px; height: 26px; border-radius: 50%; border: 1px solid rgba(255,255,255,0.2);
          background: rgba(255,255,255,0.1); color: #fff; cursor: pointer; font-size: 14px;
        }
        .tabs { display: grid; grid-template-columns: repeat(4, 1fr); gap: 6px; margin-bottom: 14px; }
        .tbtn {
          padding: 7px 4px; border-radius: 10px; border: 1px solid rgba(255,255,255,0.14);
          background: rgba(255,255,255,0.06); color: rgba(255,255,255,0.75);
          font-size: 11px; font-weight: 600; cursor: pointer;
        }
        .tbtn.on { background: rgba(124,58,237,0.55); color: #fff; border-color: rgba(255,255,255,0.34); }
        .card {
          padding: 13px; border-radius: 16px; margin-bottom: 10px;
          background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.14);
        }
        .row { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
        .sub { font-size: 11.5px; color: rgba(255,255,255,0.65); margin-top: 2px; }
        .pill {
          padding: 6px 12px; border-radius: 99px; border: 1px solid rgba(255,255,255,0.22);
          background: rgba(255,255,255,0.12); color: #fff; font-size: 12px; font-weight: 600; cursor: pointer;
        }
        .pill.on { background: #7c3aed; border-color: rgba(255,255,255,0.4); }
        input[type=range] { width: 100%; margin-top: 10px; accent-color: #a78bfa; }
        .breath-wrap { display: flex; flex-direction: column; align-items: center; padding: 18px 8px; gap: 16px; }
        .ring {
          width: 128px; height: 128px; border-radius: 50%;
          background: radial-gradient(circle, rgba(167,139,250,0.45), rgba(124,58,237,0.18));
          border: 2px solid rgba(255,255,255,0.45);
          display: flex; align-items: center; justify-content: center; flex-direction: column;
          transition: transform 3.8s ease-in-out, box-shadow 3.8s ease-in-out;
          box-shadow: 0 0 30px rgba(124,58,237,0.35);
        }
        .ring.inhale { transform: scale(1.22); box-shadow: 0 0 55px rgba(167,139,250,0.65); }
        .ring.exhale { transform: scale(0.86); box-shadow: 0 0 18px rgba(124,58,237,0.25); }
        .ring b { font-size: 15px; }
        .ring span { font-size: 11px; color: rgba(255,255,255,0.75); }
        .bm { display: flex; flex-direction: column; gap: 8px; }
        .bm button {
          text-align: left; padding: 10px 13px; border-radius: 12px; border: 1px solid rgba(255,255,255,0.14);
          background: rgba(255,255,255,0.08); color: #fff; font-size: 13px; font-weight: 600; cursor: pointer;
        }
        .bm button:hover { background: rgba(124,58,237,0.42); }
        .pane { display: none; }
        .pane.on { display: block; }
        </style></head><body>
        <div class="head">
          <h2 id="panelTitle">Soundscapes</h2>
          <button class="xbtn" onclick="post('close')">×</button>
        </div>
        <div class="tabs">
          <button class="tbtn on" data-p="boosts" onclick="showPane('boosts')">Sound</button>
          <button class="tbtn" data-p="break" onclick="showPane('break')">Breathe</button>
          <button class="tbtn" data-p="bookmarks" onclick="showPane('bookmarks')">Links</button>
          <button class="tbtn" data-p="air" onclick="showPane('air')">Air UI</button>
        </div>

        <div class="pane on" id="p-boosts">
          <div class="card">
            <div class="row"><div><b>Hyperfocus · 40Hz</b><div class="sub">Soft brown noise + gamma focus tone</div></div><button class="pill" id="b-focus" onclick="toggleSound('focus')">Play</button></div>
            <input type="range" min="0" max="100" value="45" oninput="setVol(this.value)">
          </div>
          <div class="card">
            <div class="row"><div><b>Spring Rain</b><div class="sub">Filtered ambient rainfall</div></div><button class="pill" id="b-rain" onclick="toggleSound('rain')">Play</button></div>
          </div>
          <div class="card">
            <div class="row"><div><b>Sea Waves</b><div class="sub">Slow ocean swell for calm reading</div></div><button class="pill" id="b-waves" onclick="toggleSound('waves')">Play</button></div>
          </div>
          <div class="card">
            <div class="row"><div><b>Deep Relax · 10Hz</b><div class="sub">Alpha binaural drone</div></div><button class="pill" id="b-relax" onclick="toggleSound('relax')">Play</button></div>
          </div>
        </div>

        <div class="pane" id="p-break">
          <div class="card breath-wrap">
            <div class="ring" id="breathRing"><b id="breathCue">Ready</b><span id="breathSec">Box 4-4-4-4</span></div>
            <div class="row">
              <button class="pill on" id="breathBtn" onclick="toggleBreath()">Start Breathing</button>
            </div>
          </div>
          <div class="card">
            <div class="row"><div><b>Break Reminder</b><div class="sub">Gentle nudge every 45 min</div></div><button class="pill" id="remBtn" onclick="toggleRem()">Off</button></div>
          </div>
        </div>

        <div class="pane" id="p-bookmarks">
          <div class="bm">
            <button onclick="post('nav:spark://home')">✦ SparkOS Home</button>
            <button onclick="post('nav:https://www.google.com')">Google</button>
            <button onclick="post('nav:https://www.youtube.com')">YouTube</button>
            <button onclick="post('nav:https://github.com/viwinjr28-prog/SparkOS')">SparkOS GitHub Repo</button>
            <button onclick="post('nav:https://en.wikipedia.org')">Wikipedia</button>
          </div>
        </div>

        <div class="pane" id="p-air">
          <div class="card">
            <div class="row"><div><b>Built-in Ad Blocker</b><div class="sub">Blocks common ad &amp; tracker scripts</div></div><button class="pill on" id="adBtn" onclick="toggleAdBlock()">On</button></div>
          </div>
          <div class="card">
            <div class="row"><div><b>Air Frost Depth</b><div class="sub">Switch window glass translucency</div></div><button class="pill" onclick="post('cycleGlass')">Cycle</button></div>
          </div>
          <div class="card">
            <div class="sub"><b>Spark Brow · Air Edition</b><br>Made by Viwin Jayaramanrani</div>
          </div>
        </div>

        <script>
        function post(msg) { window.webkit.messageHandlers.airBridge.postMessage(msg); }
        const titles = { boosts: 'Soundscapes', break: 'Take a Break', bookmarks: 'Bookmarks', air: 'Air Settings' };
        function showPane(p) {
          document.getElementById('panelTitle').textContent = titles[p] || 'Air';
          document.querySelectorAll('.tbtn').forEach(b => b.classList.toggle('on', b.dataset.p === p));
          document.querySelectorAll('.pane').forEach(el => el.classList.toggle('on', el.id === 'p-' + p));
        }
        let ctx = null, activeSound = null, masterGain = null, nodes = [], vol = 0.45;
        function stopSound() {
          nodes.forEach(n => { try { n.stop && n.stop(); n.disconnect && n.disconnect(); } catch(e){} });
          nodes = []; activeSound = null;
          ['focus','rain','waves','relax'].forEach(k => { const b = document.getElementById('b-' + k); b.textContent = 'Play'; b.classList.remove('on'); });
        }
        function setVol(v) { vol = v / 100; if (masterGain) masterGain.gain.value = vol * 0.25; }
        function toggleSound(kind) {
          if (activeSound === kind) { stopSound(); return; }
          stopSound();
          if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();
          if (ctx.state === 'suspended') ctx.resume();
          masterGain = ctx.createGain();
          masterGain.gain.value = vol * 0.25;
          masterGain.connect(ctx.destination);
          activeSound = kind;
          const b = document.getElementById('b-' + kind); b.textContent = 'Stop'; b.classList.add('on');

          if (kind === 'rain' || kind === 'waves' || kind === 'focus') {
            const buf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
            const data = buf.getChannelData(0);
            let last = 0;
            for (let i = 0; i < data.length; i++) {
              const w = Math.random() * 2 - 1;
              last = (last + 0.03 * w) / 1.03;
              data[i] = kind === 'rain' ? w * 0.35 : last * 3.2;
            }
            const src = ctx.createBufferSource(); src.buffer = buf; src.loop = true;
            const flt = ctx.createBiquadFilter(); flt.type = 'lowpass';
            flt.frequency.value = kind === 'rain' ? 1400 : (kind === 'waves' ? 420 : 650);
            src.connect(flt);
            if (kind === 'waves') {
              const lfo = ctx.createOscillator(), lg = ctx.createGain();
              lfo.frequency.value = 0.12; lg.gain.value = 260;
              lfo.connect(lg); lg.connect(flt.frequency); lfo.start(); nodes.push(lfo);
            }
            flt.connect(masterGain); src.start(); nodes.push(src, flt);
          }
          if (kind === 'focus' || kind === 'relax') {
            const base = kind === 'focus' ? 200 : 174;
            const diff = kind === 'focus' ? 40 : 10;
            const o1 = ctx.createOscillator(), o2 = ctx.createOscillator(), g = ctx.createGain();
            o1.frequency.value = base; o2.frequency.value = base + diff; g.gain.value = 0.16;
            o1.connect(g); o2.connect(g); g.connect(masterGain);
            o1.start(); o2.start(); nodes.push(o1, o2, g);
          }
        }
        let breathTimer = null, breathStep = 0;
        const steps = [['Inhale','4s','inhale'],['Hold','4s','inhale'],['Exhale','4s','exhale'],['Rest','4s','exhale']];
        function toggleBreath() {
          const btn = document.getElementById('breathBtn'), ring = document.getElementById('breathRing');
          if (breathTimer) {
            clearInterval(breathTimer); breathTimer = null;
            btn.textContent = 'Start Breathing'; ring.className = 'ring';
            document.getElementById('breathCue').textContent = 'Ready';
            document.getElementById('breathSec').textContent = 'Box 4-4-4-4';
            return;
          }
          btn.textContent = 'Stop';
          const tick = () => {
            const s = steps[breathStep % 4];
            document.getElementById('breathCue').textContent = s[0];
            document.getElementById('breathSec').textContent = s[1];
            ring.className = 'ring ' + s[2];
            breathStep++;
          };
          tick();
          breathTimer = setInterval(tick, 4000);
        }
        let remOn = false;
        function toggleRem() {
          remOn = !remOn;
          const b = document.getElementById('remBtn'); b.textContent = remOn ? '45m On' : 'Off'; b.classList.toggle('on', remOn);
          post(remOn ? 'rem:on' : 'rem:off');
        }
        let adOn = true;
        function toggleAdBlock() {
          adOn = !adOn;
          const b = document.getElementById('adBtn'); b.textContent = adOn ? 'On' : 'Off'; b.classList.toggle('on', adOn);
          post(adOn ? 'ad:on' : 'ad:off');
        }
        </script>
        </body></html>
        """
    }

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
        fileMenu.addItem(withTitle: "Focus Address Bar", action: #selector(focusUrlBar), keyEquivalent: "l")
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
        viewMenu.addItem(withTitle: "Soundscapes", action: #selector(openBoosts), keyEquivalent: "b")
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
        bootOverlay.layer?.backgroundColor = NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.09, alpha: 0.85).cgColor

        let bootWeb = WKWebView(frame: bootOverlay.bounds)
        bootWeb.setValue(false, forKey: "drawsBackground")
        bootWeb.autoresizingMask = [.width, .height]
        let bootHTML = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        body { margin:0; height:100vh; display:flex; flex-direction:column; align-items:center; justify-content:center;
          font-family:-apple-system,BlinkMacSystemFont,sans-serif; color:#fff; background:transparent; overflow:hidden; }
        .star { width:56px; height:56px; margin-bottom:16px; animation: pop 0.7s cubic-bezier(0.2,0.9,0.3,1.2) forwards; }
        @keyframes pop { 0%{ transform:scale(0.35) rotate(-25deg); opacity:0; } 100%{ transform:scale(1) rotate(0); opacity:1; } }
        h1 { margin:0; font-size:38px; letter-spacing:-1.2px; animation: up 0.65s ease forwards; }
        p { margin:8px 0 0; font-size:12px; letter-spacing:1.4px; text-transform:uppercase; color:rgba(255,255,255,0.55); animation: up 0.75s ease forwards; }
        @keyframes up { 0%{ transform:translateY(10px); opacity:0; } 100%{ transform:translateY(0); opacity:1; } }
        </style></head><body>
          <svg class="star" viewBox="0 0 64 64"><path d="M32 4 L39 25 L60 32 L39 39 L32 60 L25 39 L4 32 L25 25 Z" fill="#fff"/></svg>
          <h1>Spark Brow</h1>
          <p>Air Edition</p>
        </body></html>
        """
        bootWeb.loadHTMLString(bootHTML, baseURL: nil)
        bootOverlay.addSubview(bootWeb)
        glassRoot.addSubview(bootOverlay)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.48
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
                self.adBlockRuleList = list
                DispatchQueue.main.async {
                    self.sharedConfig.userContentController.add(list)
                }
            }
        }

        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: style, backing: .buffered, defer: false)
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

        // Full-bleed Web Container (fills the entire window behind floating Air bars)
        webContainer = NSView()
        webContainer.wantsLayer = true
        webContainer.translatesAutoresizingMaskIntoConstraints = false

        // Floating Opera Air Top Bar (centered floating pill)
        topBar = AirGlassView(material: .hudWindow, blending: .withinWindow, radius: 16)
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let backBtn = makeIconBtn("chevron.left", action: #selector(goBack))
        let fwdBtn = makeIconBtn("chevron.right", action: #selector(goForward))
        let reloadBtn = makeIconBtn("arrow.clockwise", action: #selector(reloadPage))
        let homeBtn = makeIconBtn("house", action: #selector(goHome))

        let urlPill = NSView()
        urlPill.wantsLayer = true
        urlPill.layer?.cornerRadius = 11
        urlPill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        urlPill.layer?.borderWidth = 1
        urlPill.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        urlPill.translatesAutoresizingMaskIntoConstraints = false

        urlField = NSTextField()
        urlField.placeholderString = "Search Google or enter website..."
        urlField.isBezeled = false
        urlField.drawsBackground = false
        urlField.textColor = .white
        urlField.alignment = .center
        urlField.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        urlField.delegate = self
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlPill.addSubview(urlField)

        let newTabBtn = makeIconBtn("plus", action: #selector(addNewTab))

        tabStack = NSStackView()
        tabStack.orientation = .horizontal
        tabStack.distribution = .fillEqually
        tabStack.spacing = 5
        tabStack.translatesAutoresizingMaskIntoConstraints = false

        let navRow = NSStackView(views: [backBtn, fwdBtn, reloadBtn, homeBtn, urlPill, newTabBtn])
        navRow.orientation = .horizontal
        navRow.spacing = 7
        navRow.alignment = .centerY
        navRow.translatesAutoresizingMaskIntoConstraints = false

        topBar.addSubview(navRow)
        topBar.addSubview(tabStack)

        // Floating Opera Air Left Glass Rail (positioned cleanly below traffic lights without colliding with SparkOS rail)
        leftRail = AirGlassView(material: .hudWindow, blending: .withinWindow, radius: 18)
        leftRail.translatesAutoresizingMaskIntoConstraints = false

        let rHome = makeIconBtn("sparkles", action: #selector(goHome), size: 32)
        let rBoost = makeIconBtn("waveform", action: #selector(openBoosts), size: 32)
        let rBreath = makeIconBtn("wind", action: #selector(openBreak), size: 32)
        let rBm = makeIconBtn("bookmark", action: #selector(openBookmarks), size: 32)
        let rAir = makeIconBtn("slider.horizontal.3", action: #selector(openAirSettings), size: 32)

        let railStack = NSStackView(views: [rHome, rBoost, rBreath, rBm, rAir])
        railStack.orientation = .vertical
        railStack.spacing = 8
        railStack.translatesAutoresizingMaskIntoConstraints = false
        leftRail.addSubview(railStack)

        // Floating Air Drawer
        drawerBox = AirGlassView(material: .popover, blending: .withinWindow, radius: 22)
        drawerBox.translatesAutoresizingMaskIntoConstraints = false
        drawerBox.isHidden = true

        let dCfg = WKWebViewConfiguration()
        dCfg.userContentController.add(self, name: "airBridge")
        drawerWebView = WKWebView(frame: .zero, configuration: dCfg)
        drawerWebView.setValue(false, forKey: "drawsBackground")
        drawerWebView.translatesAutoresizingMaskIntoConstraints = false
        drawerWebView.loadHTMLString(airPanelHTML(), baseURL: nil)
        drawerBox.addSubview(drawerWebView)

        glassRoot.addSubview(webContainer)
        glassRoot.addSubview(topBar)
        glassRoot.addSubview(leftRail)
        glassRoot.addSubview(drawerBox)

        NSLayoutConstraint.activate([
            webContainer.topAnchor.constraint(equalTo: glassRoot.topAnchor),
            webContainer.leadingAnchor.constraint(equalTo: glassRoot.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: glassRoot.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: glassRoot.bottomAnchor),

            topBar.topAnchor.constraint(equalTo: glassRoot.topAnchor, constant: 12),
            topBar.centerXAnchor.constraint(equalTo: glassRoot.centerXAnchor),
            topBar.leadingAnchor.constraint(greaterThanOrEqualTo: glassRoot.leadingAnchor, constant: 90),
            topBar.trailingAnchor.constraint(lessThanOrEqualTo: glassRoot.trailingAnchor, constant: -90),
            topBar.widthAnchor.constraint(lessThanOrEqualToConstant: 860),

            navRow.topAnchor.constraint(equalTo: topBar.topAnchor, constant: 7),
            navRow.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 10),
            navRow.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -10),
            urlPill.heightAnchor.constraint(equalToConstant: 26),
            urlPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            urlField.leadingAnchor.constraint(equalTo: urlPill.leadingAnchor, constant: 12),
            urlField.trailingAnchor.constraint(equalTo: urlPill.trailingAnchor, constant: -12),
            urlField.centerYAnchor.constraint(equalTo: urlPill.centerYAnchor),

            tabStack.topAnchor.constraint(equalTo: navRow.bottomAnchor, constant: 6),
            tabStack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 10),
            tabStack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -10),
            tabStack.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -7),
            tabStack.heightAnchor.constraint(equalToConstant: 22),

            leftRail.leadingAnchor.constraint(equalTo: glassRoot.leadingAnchor, constant: 16),
            leftRail.topAnchor.constraint(equalTo: glassRoot.topAnchor, constant: 70),
            leftRail.widthAnchor.constraint(equalToConstant: 48),
            railStack.topAnchor.constraint(equalTo: leftRail.topAnchor, constant: 10),
            railStack.bottomAnchor.constraint(equalTo: leftRail.bottomAnchor, constant: -10),
            railStack.centerXAnchor.constraint(equalTo: leftRail.centerXAnchor),

            drawerBox.topAnchor.constraint(equalTo: leftRail.topAnchor),
            drawerBox.leadingAnchor.constraint(equalTo: leftRail.trailingAnchor, constant: 12),
            drawerBox.widthAnchor.constraint(equalToConstant: 330),
            drawerBox.heightAnchor.constraint(equalToConstant: 430),

            drawerWebView.topAnchor.constraint(equalTo: drawerBox.topAnchor),
            drawerWebView.leadingAnchor.constraint(equalTo: drawerBox.leadingAnchor),
            drawerWebView.trailingAnchor.constraint(equalTo: drawerBox.trailingAnchor),
            drawerWebView.bottomAnchor.constraint(equalTo: drawerBox.bottomAnchor)
        ])

        createTab(request: nil)
        playBootAnimation()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func makeIconBtn(_ symbol: String, action: Selector, size: CGFloat = 26) -> NSButton {
        let b = NSButton()
        b.bezelStyle = .rounded
        b.isBordered = false
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.contentTintColor = .white
        b.target = self
        b.action = action
        b.wantsLayer = true
        b.layer?.cornerRadius = 9
        b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        b.widthAnchor.constraint(equalToConstant: size).isActive = true
        b.heightAnchor.constraint(equalToConstant: size).isActive = true
        return b
    }

    func toggleDrawer(panel: String) {
        if drawerOpen && activeDrawerPanel == panel {
            drawerOpen = false
            drawerBox.isHidden = true
        } else {
            activeDrawerPanel = panel
            drawerOpen = true
            drawerBox.isHidden = false
            drawerWebView.evaluateJavaScript("showPane('\(panel)')", completionHandler: nil)
        }
    }

    @objc func openBoosts() { toggleDrawer(panel: "boosts") }
    @objc func openBreak() { toggleDrawer(panel: "break") }
    @objc func openBookmarks() { toggleDrawer(panel: "bookmarks") }
    @objc func openAirSettings() { toggleDrawer(panel: "air") }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String else { return }
        if body == "close" {
            drawerOpen = false; drawerBox.isHidden = true
        } else if body.hasPrefix("nav:") {
            let u = String(body.dropFirst(4))
            drawerOpen = false; drawerBox.isHidden = true
            if u == "spark://home" { goHome() } else { navigate(u) }
        } else if body == "cycleGlass" {
            glassRoot.material = (glassRoot.material == .hudWindow) ? .underWindowBackground : .hudWindow
        } else if body == "ad:on" {
            if let list = adBlockRuleList { sharedConfig.userContentController.add(list) }
        } else if body == "ad:off" {
            sharedConfig.userContentController.removeAllContentRuleLists()
        } else if body == "rem:on" {
            breakTimer?.invalidate()
            breakTimer = Timer.scheduledTimer(withTimeInterval: 45 * 60, repeats: true) { _ in
                DispatchQueue.main.async { self.openBreak() }
            }
        } else if body == "rem:off" {
            breakTimer?.invalidate(); breakTimer = nil
        }
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
            tab.urlString = req.url?.absoluteString ?? ""
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
        urlField.stringValue = tabs[index].isHome ? "" : tabs[index].urlString
        refreshTabBar()
    }

    func refreshTabBar() {
        tabStack.arrangedSubviews.forEach { tabStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (i, t) in tabs.enumerated() {
            let b = NSButton(title: String(t.title.prefix(22)) + (tabs.count > 1 ? "   ×" : ""), target: self, action: #selector(tabClicked(_:)))
            b.tag = i
            b.isBordered = false
            b.wantsLayer = true
            b.font = NSFont.systemFont(ofSize: 11, weight: i == activeIndex ? .semibold : .medium)
            b.contentTintColor = i == activeIndex ? .white : NSColor.white.withAlphaComponent(0.70)
            b.layer?.cornerRadius = 7
            b.layer?.backgroundColor = (i == activeIndex ? NSColor.white.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(0.06)).cgColor
            b.heightAnchor.constraint(equalToConstant: 22).isActive = true
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
    @objc func focusUrlBar() { window.makeFirstResponder(urlField) }
    @objc func goBack() { tabs[activeIndex].webView.goBack() }
    @objc func goForward() { tabs[activeIndex].webView.goForward() }
    @objc func reloadPage() {
        if tabs[activeIndex].isHome { goHome() } else { tabs[activeIndex].webView.reload() }
    }
    @objc func goHome() {
        let tab = tabs[activeIndex]
        tab.isHome = true
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
            tabs[activeIndex].isHome = false
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

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            let newTab = BrowserTab(config: configuration)
            newTab.webView.navigationDelegate = self
            newTab.webView.uiDelegate = self
            newTab.isHome = false
            newTab.urlString = navigationAction.request.url?.absoluteString ?? ""
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
            tabs[idx].urlString = "spark://home"
            tabs[idx].title = "SparkOS"
        } else {
            tabs[idx].isHome = false
            if let u = webView.url?.absoluteString, u != "about:blank" { tabs[idx].urlString = u }
            if let title = webView.title, !title.isEmpty { tabs[idx].title = title }
        }
        if idx == activeIndex {
            urlField.stringValue = tabs[idx].isHome ? "" : tabs[idx].urlString
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
