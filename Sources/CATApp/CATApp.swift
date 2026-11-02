import AppKit

private let stateKey = "meowl-cat"
private let scaleKey = "meowl-cat-scale"
private let baseCatSize: CGFloat = 32

private final class CatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class MeowlController: NSObject {
    private let sprites: SpriteSheet
    private let defaults: UserDefaults
    private let panel: CatPanel
    private let spriteView: SpriteView
    private var simulation: CatSimulation
    private var catScale: CGFloat
    private var timer: Timer?
    private var screens: [CGRect] = []
    private var isSuspended = false
    private(set) var isRunning = false
    var scale: CGFloat { catScale }

    init(sprites: SpriteSheet, defaults: UserDefaults = .standard) {
        self.sprites = sprites
        self.defaults = defaults
        let storedScale = defaults.object(forKey: scaleKey) as? Double ?? 1
        self.catScale = min(max(CGFloat(storedScale), 0.5), 2.5)
        let saved = defaults.data(forKey: stateKey)
            .flatMap { try? JSONDecoder().decode(CatState.self, from: $0) }
        simulation = CatSimulation(state: saved ?? CatState())

        let catSize = baseCatSize * catScale
        panel = CatPanel(contentRect: CGRect(x: 0, y: 0, width: catSize, height: catSize),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        spriteView = SpriteView(frame: CGRect(x: 0, y: 0, width: catSize, height: catSize))
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.isMovable = false
        spriteView.setAccessibilityElement(false)
        spriteView.autoresizingMask = [.width, .height]
        panel.contentView = spriteView

        updateScreens()
        let center = simulation.state.position
        if !center.x.isFinite || !center.y.isFinite {
            simulation.state = CatState()
        }
        simulation.state.position = DesktopGeometry.constrain(
            simulation.state.position,
            screens: screens,
            inset: baseCatSize * catScale / 2,
        )
        drawCat()

        NotificationCenter.default.addObserver(self, selector: #selector(updateScreens),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let notifications = NSWorkspace.shared.notificationCenter
        notifications.addObserver(self, selector: #selector(suspend), name: NSWorkspace.willSleepNotification, object: nil)
        notifications.addObserver(self, selector: #selector(suspend), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        notifications.addObserver(self, selector: #selector(resume), name: NSWorkspace.didWakeNotification, object: nil)
        notifications.addObserver(self, selector: #selector(resume), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        notifications.addObserver(self, selector: #selector(updateActivity),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        updateScreens()
        updateActivity()
    }

    func stop() {
        isRunning = false
        updateActivity()
        saveState()
    }

    func setScale(_ scale: CGFloat) {
        catScale = min(max(scale, 0.5), 2.5)
        defaults.set(Double(catScale), forKey: scaleKey)
        simulation.state.position = DesktopGeometry.constrain(
            simulation.state.position,
            screens: screens,
            inset: baseCatSize * catScale / 2,
        )

        let catSize = baseCatSize * catScale
        spriteView.frame = CGRect(x: 0, y: 0, width: catSize, height: catSize)
        panel.setFrame(
            CGRect(x: simulation.state.position.x - catSize / 2,
                   y: simulation.state.position.y - catSize / 2,
                   width: catSize,
                   height: catSize),
            display: true,
        )
        drawCat()
    }

    func shutDown() {
        stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func updateActivity() {
        timer?.invalidate()
        timer = nil
        guard isRunning && !isSuspended else {
            panel.orderOut(nil)
            return
        }
        drawCat()
        panel.orderFrontRegardless()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            spriteView.image = sprites.frame(.idle, index: 0)
            return
        }
        // Poll the global pointer; no input hooks, Accessibility, or recording permission needed.
        let timer = Timer(timeInterval: 0.1, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func tick() {
        simulation.step(
            toward: NSEvent.mouseLocation,
            screens: screens,
            inset: baseCatSize * catScale / 2,
        )
        drawCat()
    }

    private func drawCat() {
        let state = simulation.state
        spriteView.image = sprites.frame(state.displayedAnimation, index: state.displayedFrame)
        panel.setFrameOrigin(CGPoint(x: state.position.x - baseCatSize * catScale / 2,
                                     y: state.position.y - baseCatSize * catScale / 2))
    }

    @objc private func updateScreens() {
        screens = NSScreen.screens.map(\.frame)
        guard !screens.isEmpty else { return }
        simulation.state.position = DesktopGeometry.constrain(
            simulation.state.position,
            screens: screens,
            inset: baseCatSize * catScale / 2,
        )
        drawCat()
    }

    @objc private func suspend() {
        isSuspended = true
        updateActivity()
        saveState()
    }

    @objc private func resume() {
        isSuspended = false
        updateScreens()
        updateActivity()
    }

    private func saveState() {
        guard let data = try? JSONEncoder().encode(simulation.state) else { return }
        defaults.set(data, forKey: stateKey)
    }
}

@MainActor
private final class CatSizeMenuView: NSView {
    let slider: NSSlider

    init(target: AnyObject, action: Selector, value: Double) {
        slider = NSSlider(value: value, minValue: 0.5, maxValue: 2.5, target: target, action: action)
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 48))

        let label = NSTextField(labelWithString: "Cat size")
        label.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        label.frame = NSRect(x: 12, y: 26, width: 66, height: 16)

        let minimumLabel = NSTextField(labelWithString: "½×")
        minimumLabel.font = NSFont.menuFont(ofSize: 10)
        minimumLabel.textColor = .secondaryLabelColor
        minimumLabel.frame = NSRect(x: 12, y: 8, width: 24, height: 14)

        let maximumLabel = NSTextField(labelWithString: "2.5×")
        maximumLabel.font = NSFont.menuFont(ofSize: 10)
        maximumLabel.textColor = .secondaryLabelColor
        maximumLabel.alignment = .right
        maximumLabel.frame = NSRect(x: 204, y: 8, width: 24, height: 14)

        slider.isContinuous = true
        slider.frame = NSRect(x: 78, y: 23, width: 150, height: 20)

        addSubview(label)
        addSubview(slider)
        addSubview(minimumLabel)
        addSubview(maximumLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let meowl: MeowlController
    private let menu = NSMenu()
    private let startItem = NSMenuItem(title: "Start Meowl", action: #selector(startMeowl), keyEquivalent: "")
    private let stopItem = NSMenuItem(title: "Stop Meowl", action: #selector(stopMeowl), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit Meowl", action: #selector(quit), keyEquivalent: "q")
    private lazy var sizeMenuView = CatSizeMenuView(
        target: self,
        action: #selector(sizeChanged(_:)),
        value: Double(meowl.scale),
    )

    init(meowl: MeowlController) {
        self.meowl = meowl
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Meowl")
                ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Meowl")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemPressed)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        startItem.target = self
        stopItem.target = self
        quitItem.target = self
        menu.addItem(startItem)
        menu.addItem(stopItem)
        let sizeItem = NSMenuItem()
        sizeItem.view = sizeMenuView
        menu.addItem(sizeItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        updateMenuState()
    }

    private func updateMenuState() {
        startItem.isEnabled = !meowl.isRunning
        stopItem.isEnabled = meowl.isRunning
    }

    @objc private func statusItemPressed() {
        updateMenuState()
        guard let button = statusItem.button, let event = NSApp.currentEvent else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func startMeowl() {
        meowl.start()
        updateMenuState()
    }

    @objc private func stopMeowl() {
        meowl.stop()
        updateMenuState()
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        meowl.setScale(CGFloat(sender.doubleValue))
    }

    @objc private func quit() {
        meowl.shutDown()
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var meowl: MeowlController?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        guard let url = Bundle.main.url(forResource: "Meowl", withExtension: "gif"),
              let sprites = SpriteSheet(url: url) else {
            let alert = NSAlert()
            alert.messageText = "Meowl could not start"
            alert.informativeText = "The bundled Meowl sprite sheet could not be loaded."
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }

        let meowl = MeowlController(sprites: sprites)
        self.meowl = meowl
        self.statusBar = StatusBarController(meowl: meowl)
        meowl.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        meowl?.shutDown()
    }
}

@main
@MainActor
private struct CATApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
