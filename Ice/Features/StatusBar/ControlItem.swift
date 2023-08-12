//
//  ControlItem.swift
//  Ice
//

import Cocoa
import Combine

final class ControlItem: ObservableObject {
    static let standardLength: CGFloat = 25

    static let expandedLength: CGFloat = 10_000

    private let statusItem: NSStatusItem

    /// The position of the control item in the status bar.
    @Published private(set) var position: CGFloat?

    /// The control item's autosave name.
    let autosaveName: String

    /// The state of the control item.
    ///
    /// Setting this value marks the item as needing an update.
    var state: State {
        didSet {
            updateStatusItem()
        }
    }

    /// The status bar associated with the control item.
    weak var statusBar: StatusBar? {
        didSet {
            updateStatusItem()
        }
    }

    /// The index of the control item in relation to the other control
    /// items in the status bar.
    var index: Int? {
        statusBar?.sortedControlItems.firstIndex(of: self)
    }

    /// The control item's section in the status bar.
    var section: StatusBar.Section? {
        statusBar?.section(for: self)
    }

    init(autosaveName: String? = nil, position: CGFloat? = nil, state: State? = nil) {
        let autosaveName = autosaveName ?? UUID().uuidString
        let state = state ?? .showItems
        self.statusItem = {
            // set the preferred position first or the status item won't
            // recognize when it's been set
            PreferredPosition[autosaveName] = position
            let statusItem = NSStatusBar.system.statusItem(withLength: 0)
            // set the autosave name to associate the status item with the
            // preferred position
            statusItem.autosaveName = autosaveName
            return statusItem
        }()
        self.autosaveName = autosaveName
        self.position = position
        self.state = state
        configureStatusItem()
    }

    /// Sets the initial configuration for the status item.
    private func configureStatusItem() {
        defer {
            updateStatusItem()
        }

        guard let button = statusItem.button else {
            return
        }
        button.target = self
        button.action = #selector(performAction)
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])

        guard let window = button.window else {
            return
        }
        window.publisher(for: \.frame)
            .combineLatest(window.publisher(for: \.screen))
            .compactMap { [weak statusItem] frame, screen in
                // only publish when status item has a standard length and
                // window is at least partially onscreen
                guard
                    statusItem?.length == Self.standardLength,
                    let screenFrame = screen?.frame,
                    screenFrame.intersects(frame)
                else {
                    return nil
                }
                // calculate position relative to trailing edge of screen
                return screenFrame.maxX - frame.maxX
            }
            .removeDuplicates()
            .assign(to: &$position)
    }

    /// Updates the control item's status item to match its current state.
    func updateStatusItem() {
        func updateLength(section: StatusBar.Section) {
            if section == .alwaysVisible {
                // item for always-visible section should never be expanded
                statusItem.length = Self.standardLength
                return
            }
            switch state {
            case .showItems, .hideItems(isExpanded: false):
                statusItem.length = Self.standardLength
            case .hideItems(isExpanded: true):
                statusItem.length = Self.expandedLength
            }
        }

        func updateButton(section: StatusBar.Section) {
            guard let button = statusItem.button else {
                return
            }
            if state == .hideItems(isExpanded: true) {
                // prevent the cell from highlighting while expanded
                button.cell?.isEnabled = false
                // the cell still sometimes briefly highlights while
                // expanding; manually unhighlighting seems to fix it
                button.isHighlighted = false
                button.image = nil
                return
            }
            // enable the cell, as it may have been previously disabled
            button.cell?.isEnabled = true
            switch section {
            case .hidden:
                button.image = Images.largeChevron
            case .alwaysHidden:
                button.image = Images.smallChevron
            case .alwaysVisible:
                switch state {
                case .hideItems:
                    button.image = Images.circleFilled
                case .showItems:
                    button.image = Images.circleStroked
                }
            }
        }

        guard let section else {
            return
        }

        updateLength(section: section)
        updateButton(section: section)

        statusBar?.needsSaveControlItems = true
    }

    @objc private func performAction() {
        guard
            let statusBar,
            let event = NSApp.currentEvent
        else {
            return
        }
        switch event.type {
        case .leftMouseDown where NSEvent.modifierFlags == .option:
            statusBar.show(section: .alwaysHidden)
        case .leftMouseDown:
            guard let section else {
                return
            }
            statusBar.toggle(section: section)
        case .rightMouseUp:
            statusItem.showMenu(statusBar.menu)
        default:
            break
        }
    }

    deinit {
        // removing the status item has the unwanted side effect of deleting
        // the preferred position; cache and restore after removing
        let cached = PreferredPosition[autosaveName]
        defer {
            PreferredPosition[autosaveName] = cached
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}

// MARK: ControlItem: Codable
extension ControlItem: Codable {
    private struct AutosaveNameCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = Int(stringValue)
        }

        init(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    private enum PropertiesCodingKeys: String, CodingKey {
        case position = "Position"
        case state = "State"
    }

    convenience init(from decoder: Decoder) throws {
        let topLevelContainer = try decoder.container(keyedBy: AutosaveNameCodingKey.self)
        var keys = topLevelContainer.allKeys
        guard
            let key = keys.popLast(),
            keys.isEmpty
        else {
            let keyCount = topLevelContainer.allKeys.count
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a single keyed value but found \(keyCount)."
                )
            )
        }
        let propertiesContainer = try topLevelContainer.nestedContainer(
            keyedBy: PropertiesCodingKeys.self,
            forKey: key
        )
        try self.init(
            autosaveName: key.stringValue,
            position: propertiesContainer.decode(CGFloat.self, forKey: .position),
            state: propertiesContainer.decode(State.self, forKey: .state)
        )
    }

    func encode(to encoder: Encoder) throws {
        var topLevelContainer = encoder.container(keyedBy: AutosaveNameCodingKey.self)
        var propertiesContainer = topLevelContainer.nestedContainer(
            keyedBy: PropertiesCodingKeys.self,
            forKey: AutosaveNameCodingKey(stringValue: autosaveName)
        )
        try propertiesContainer.encode(position, forKey: .position)
        try propertiesContainer.encode(state, forKey: .state)
    }
}

// MARK: ControlItem: Equatable
extension ControlItem: Equatable {
    static func == (lhs: ControlItem, rhs: ControlItem) -> Bool {
        lhs.statusItem == rhs.statusItem &&
        lhs.position == rhs.position &&
        lhs.autosaveName == rhs.autosaveName &&
        lhs.state == rhs.state
    }
}

// MARK: ControlItem: Hashable
extension ControlItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(statusItem)
        hasher.combine(position)
        hasher.combine(autosaveName)
        hasher.combine(state)
    }
}

// MARK: - State
extension ControlItem {
    enum State: RawRepresentable, Hashable, Codable {
        /// Hide all status items in the section.
        case hideItems(isExpanded: Bool)
        /// Show all status items in the section.
        case showItems

        var rawValue: Int {
            switch self {
            case .hideItems(isExpanded: false): return 0
            case .hideItems(isExpanded: true): return 1
            case .showItems: return 2
            }
        }

        init?(rawValue: Int) {
            switch rawValue {
            case 0: self = .hideItems(isExpanded: false)
            case 1: self = .hideItems(isExpanded: true)
            case 2: self = .showItems
            default: return nil
            }
        }
    }
}

// MARK: - PreferredPosition
extension ControlItem {
    /// A proxy getter and setter for a control item's preferred position.
    enum PreferredPosition {
        private static func key(for autosaveName: String) -> String {
            return "NSStatusItem Preferred Position \(autosaveName)"
        }

        /// Accesses the preferred position associated with the specified autosave name.
        static subscript(autosaveName: String) -> CGFloat? {
            get {
                // use object(forKey:) because double(forKey:) returns 0 if no value
                // is stored; we need to differentiate between "a stored value of 0"
                // and "no stored value"
                UserDefaults.standard.object(forKey: key(for: autosaveName)) as? CGFloat
            }
            set {
                UserDefaults.standard.set(newValue, forKey: key(for: autosaveName))
            }
        }
    }
}

// MARK: - Images
extension ControlItem {
    /// Namespace for control item images.
    enum Images {
        static let circleFilled: NSImage = {
            let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { bounds in
                NSColor.black.setFill()
                NSBezierPath(ovalIn: bounds).fill()
                return true
            }
            image.isTemplate = true
            return image
        }()

        static let circleStroked: NSImage = {
            let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { bounds in
                let lineWidth: CGFloat = 1.5
                let path = NSBezierPath(ovalIn: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
                path.lineWidth = lineWidth
                NSColor.black.setStroke()
                path.stroke()
                return true
            }
            image.isTemplate = true
            return image
        }()

        static let (largeChevron, smallChevron): (NSImage, NSImage) = {
            func chevron(size: NSSize, lineWidth: CGFloat = 2) -> NSImage {
                let image = NSImage(size: size, flipped: false) { bounds in
                    let insetBounds = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: (insetBounds.midX + insetBounds.maxX) / 2, y: insetBounds.maxY))
                    path.line(to: NSPoint(x: (insetBounds.minX + insetBounds.midX) / 2, y: insetBounds.midY))
                    path.line(to: NSPoint(x: (insetBounds.midX + insetBounds.maxX) / 2, y: insetBounds.minY))
                    path.lineWidth = lineWidth
                    path.lineCapStyle = .butt
                    NSColor.black.setStroke()
                    path.stroke()
                    return true
                }
                image.isTemplate = true
                return image
            }
            let largeChevron = chevron(size: NSSize(width: 12, height: 12))
            let smallChevron = chevron(size: NSSize(width: 7, height: 7))
            return (largeChevron, smallChevron)
        }()
    }
}