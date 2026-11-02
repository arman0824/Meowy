import AppKit

private let stateKey = "meowy-cat"
private let scaleKey = "meowy-cat-scale"
private let modeKey = "meowy-cat-mode"
private let speedKey = "meowy-cat-speed"
private let minimumSpeedPercent: CGFloat = 25
private let maximumSpeedPercent: CGFloat = 200
private let baseCatSize: CGFloat = 32

private final class CatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class MeowyController: NSObject {
    private let sprites: SpriteSheet
    private let defaults: UserDefaults
    private let panel: CatPanel
    private let spriteView: SpriteView
    private var simulation: CatSimulation
    private var catScale: CGFloat
    private var speedPercent: CGFloat
    private(set) var mode: CatMode
    private var timer: Timer?
    private var screens: [CGRect] = []
    private var dockBounds = CGRect.zero
    private var isSuspended = false
    private(set) var isRunning = false
    var scale: CGFloat { catScale }
    var speed: CGFloat { speedPercent }

    init(sprites: SpriteSheet, defaults: UserDefaults = .standard) {
        self.sprites = sprites
        self.defaults = defaults
        let storedScale = defaults.object(forKey: scaleKey) as? Double ?? 1
        self.catScale = min(max(CGFloat(storedScale), 0.5), 2.5)
        let storedSpeed = defaults.object(forKey: speedKey) as? Double ?? 100
        self.speedPercent = min(max(CGFloat(storedSpeed), minimumSpeedPercent), maximumSpeedPercent)
        self.mode = defaults.string(forKey: modeKey)
            .flatMap(CatMode.init(rawValue:)) ?? .cursor
        let saved = defaults.data(forKey: stateKey)
            .flatMap { try? JSONDecoder().decode(CatState.self, from: $0) }
        simulation = CatSimulation(state: saved ?? CatState())
        if mode == .dock {
            simulation.enterDockMode()
        }

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
        if !simulation.state.position.x.isFinite || !simulation.state.position.y.isFinite {
            simulation.state = CatState()
        }
        constrainPosition()
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
        updateDockBounds()
        constrainPosition()

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

    func setSpeedPercent(_ speed: CGFloat) {
        speedPercent = min(max(speed, minimumSpeedPercent), maximumSpeedPercent)
        defaults.set(Double(speedPercent), forKey: speedKey)
    }

    func setMode(_ mode: CatMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        defaults.set(mode.rawValue, forKey: modeKey)
        if mode == .dock {
            simulation.enterDockMode()
        } else {
            simulation.enterCursorMode()
        }
        constrainPosition()
        drawCat()
        saveState()
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
        let speedMultiplier = speedPercent / 100
        if mode == .dock {
            simulation.stepOnDock(in: dockBounds, speed: 8 * speedMultiplier)
        } else {
            simulation.step(
                toward: NSEvent.mouseLocation,
                screens: screens,
                inset: baseCatSize * catScale / 2,
                speed: 10 * speedMultiplier,
            )
        }
        drawCat()
    }

    private func drawCat() {
        let state = simulation.state
        spriteView.image = sprites.frame(state.displayedAnimation, index: state.displayedFrame)
        panel.setFrameOrigin(CGPoint(x: state.position.x - baseCatSize * catScale / 2,
                                     y: state.position.y - baseCatSize * catScale / 2))
    }

    private func constrainPosition() {
        guard !screens.isEmpty else { return }
        if mode == .dock {
            simulation.state.position = DesktopGeometry.constrainToDock(
                simulation.state.position,
                dock: dockBounds,
            )
        } else {
            simulation.state.position = DesktopGeometry.constrain(
                simulation.state.position,
                screens: screens,
                inset: baseCatSize * catScale / 2,
            )
        }
    }

    private func updateDockBounds() {
        guard let screen = NSScreen.screens.first(where: {
            $0.visibleFrame.minY > $0.frame.minY + 1
        }) ?? NSScreen.main ?? NSScreen.screens.first else {
            dockBounds = .zero
            return
        }

        let halfSize = baseCatSize * catScale / 2
        let minX = screen.frame.minX + halfSize
        let maxX = screen.frame.maxX - halfSize
        dockBounds = CGRect(
            x: minX,
            y: screen.visibleFrame.minY + halfSize,
            width: max(0, maxX - minX),
            height: 0,
        )
    }

    @objc private func updateScreens() {
        screens = NSScreen.screens.map(\.frame)
        guard !screens.isEmpty else { return }
        if !simulation.state.position.x.isFinite || !simulation.state.position.y.isFinite {
            simulation.state = CatState()
        }
        updateDockBounds()
        constrainPosition()
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
    private let valueLabel: NSTextField

    init(target: AnyObject, action: Selector, value: Double) {
        slider = NSSlider(value: value, minValue: 0.5, maxValue: 2.5, target: target, action: action)
        valueLabel = NSTextField(labelWithString: "")
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 64))

        valueLabel.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        valueLabel.frame = NSRect(x: 12, y: 44, width: 216, height: 16)
        updateValue(value)

        let minimumLabel = NSTextField(labelWithString: "50%")
        minimumLabel.font = NSFont.menuFont(ofSize: 10)
        minimumLabel.textColor = .secondaryLabelColor
        minimumLabel.frame = NSRect(x: 12, y: 3, width: 32, height: 14)

        let maximumLabel = NSTextField(labelWithString: "250%")
        maximumLabel.font = NSFont.menuFont(ofSize: 10)
        maximumLabel.textColor = .secondaryLabelColor
        maximumLabel.alignment = .right
        maximumLabel.frame = NSRect(x: 190, y: 3, width: 38, height: 14)

        slider.isContinuous = true
        slider.frame = NSRect(x: 12, y: 22, width: 216, height: 20)

        addSubview(valueLabel)
        addSubview(slider)
        addSubview(minimumLabel)
        addSubview(maximumLabel)
    }

    func updateValue(_ value: Double) {
        valueLabel.stringValue = "Size: \(Int((value * 100).rounded()))%"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class CatSpeedMenuView: NSView {
    let slider: NSSlider
    private let valueLabel: NSTextField

    init(target: AnyObject, action: Selector, value: Double) {
        slider = NSSlider(
            value: value,
            minValue: Double(minimumSpeedPercent),
            maxValue: Double(maximumSpeedPercent),
            target: target,
            action: action,
        )
        valueLabel = NSTextField(labelWithString: "")
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 64))

        valueLabel.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        valueLabel.frame = NSRect(x: 12, y: 44, width: 216, height: 16)
        updateValue(value)

        let minimumLabel = NSTextField(labelWithString: "25%")
        minimumLabel.font = NSFont.menuFont(ofSize: 10)
        minimumLabel.textColor = .secondaryLabelColor
        minimumLabel.frame = NSRect(x: 12, y: 3, width: 32, height: 14)

        let maximumLabel = NSTextField(labelWithString: "200%")
        maximumLabel.font = NSFont.menuFont(ofSize: 10)
        maximumLabel.textColor = .secondaryLabelColor
        maximumLabel.alignment = .right
        maximumLabel.frame = NSRect(x: 190, y: 3, width: 38, height: 14)

        slider.isContinuous = true
        slider.frame = NSRect(x: 12, y: 22, width: 216, height: 20)

        addSubview(valueLabel)
        addSubview(slider)
        addSubview(minimumLabel)
        addSubview(maximumLabel)
    }

    func updateValue(_ value: Double) {
        valueLabel.stringValue = "Speed: \(Int(value.rounded()))%"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let meowy: MeowyController
    private let menu = NSMenu()
    private let startItem = NSMenuItem(title: "Start Meowy", action: #selector(startMeowy), keyEquivalent: "")
    private let stopItem = NSMenuItem(title: "Stop Meowy", action: #selector(stopMeowy), keyEquivalent: "")
    private let cursorItem = NSMenuItem(title: "Follow Cursor", action: #selector(followCursor), keyEquivalent: "")
    private let dockItem = NSMenuItem(title: "Live on Dock", action: #selector(liveOnDock), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit Meowy", action: #selector(quit), keyEquivalent: "q")
    private lazy var sizeMenuView = CatSizeMenuView(
        target: self,
        action: #selector(sizeChanged(_:)),
        value: Double(meowy.scale),
    )
    private lazy var speedMenuView = CatSpeedMenuView(
        target: self,
        action: #selector(speedChanged(_:)),
        value: Double(meowy.speed),
    )

    init(meowy: MeowyController) {
        self.meowy = meowy
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Meowy")
                ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Meowy")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemPressed)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        startItem.target = self
        stopItem.target = self
        cursorItem.target = self
        dockItem.target = self
        quitItem.target = self
        menu.addItem(startItem)
        menu.addItem(stopItem)
        menu.addItem(.separator())
        menu.addItem(cursorItem)
        menu.addItem(dockItem)
        menu.addItem(.separator())
        let sizeItem = NSMenuItem()
        sizeItem.view = sizeMenuView
        menu.addItem(sizeItem)
        let speedItem = NSMenuItem()
        speedItem.view = speedMenuView
        menu.addItem(speedItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        updateMenuState()
    }

    private func updateMenuState() {
        startItem.isEnabled = !meowy.isRunning
        stopItem.isEnabled = meowy.isRunning
        cursorItem.state = meowy.mode == .cursor ? .on : .off
        dockItem.state = meowy.mode == .dock ? .on : .off
    }

    @objc private func statusItemPressed() {
        updateMenuState()
        guard let button = statusItem.button, let event = NSApp.currentEvent else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func startMeowy() {
        meowy.start()
        updateMenuState()
    }

    @objc private func stopMeowy() {
        meowy.stop()
        updateMenuState()
    }

    @objc private func followCursor() {
        meowy.setMode(.cursor)
        updateMenuState()
    }

    @objc private func liveOnDock() {
        meowy.setMode(.dock)
        updateMenuState()
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        meowy.setScale(CGFloat(sender.doubleValue))
        sizeMenuView.updateValue(sender.doubleValue)
    }

    @objc private func speedChanged(_ sender: NSSlider) {
        meowy.setSpeedPercent(CGFloat(sender.doubleValue))
        speedMenuView.updateValue(sender.doubleValue)
    }

    @objc private func quit() {
        meowy.shutDown()
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var meowy: MeowyController?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        guard let url = Bundle.main.url(forResource: "Meowy", withExtension: "gif"),
              let sprites = SpriteSheet(url: url) else {
            let alert = NSAlert()
            alert.messageText = "Meowy could not start"
            alert.informativeText = "The bundled Meowy sprite sheet could not be loaded."
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }

        let meowy = MeowyController(sprites: sprites)
        self.meowy = meowy
        self.statusBar = StatusBarController(meowy: meowy)
        meowy.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        meowy?.shutDown()
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
