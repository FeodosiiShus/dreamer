import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Observable
private final class SettingsSharedBox<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }

    var binding: Binding<Value> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}

@MainActor
private final class SettingsSharedRecorder {
    var added = 0
    var removed: [Set<UUID>?] = []
}

@MainActor
private final class SettingsSharedItemSink {
    var item: GlobPatternListItem?

    func capture(_ item: GlobPatternListItem) -> GlobPatternListItem {
        self.item = item
        return item
    }
}

private struct SettingsSharedItemProbe: View {
    @FocusState private var focus: String?
    let pattern: Binding<GlobPattern>
    let selection: Binding<Set<UUID>>
    let recorder: SettingsSharedRecorder
    let sink: SettingsSharedItemSink
    let isLast: Bool

    var body: some View {
        sink.capture(
            GlobPatternListItem(
                pattern: pattern,
                selection: selection,
                addPattern: { recorder.added += 1 },
                removePatterns: { recorder.removed.append($0) },
                focusedField: $focus,
                isLast: isLast
            )
        )
    }
}

@MainActor
@Observable
private final class SettingsSharedFontModel {
    var name: String

    init(_ name: String) {
        self.name = name
    }
}

private struct SettingsSharedFontProbe: View {
    @Bindable var model: SettingsSharedFontModel
    let defaults: UserDefaults

    var body: some View {
        MonospacedFontPicker(title: "Font", selectedFontName: $model.name, defaults: defaults)
    }
}

@MainActor
@Observable
private final class SettingsSharedVisibility {
    var shown = true
}

private struct SettingsSharedBackProbe: View {
    @Bindable var visibility: SettingsSharedVisibility
    let model: SettingsViewModel

    var body: some View {
        NavigationStack {
            Group {
                if visibility.shown {
                    Text("Body").navigationBarBackButtonVisible()
                }
            }
        }
        .environment(model)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct SettingsSharedViewsCoverageTests {
    private let size = NSSize(width: 520, height: 360)

    @Test
    func settingsFormRendersItsContentAndOffsetKeyAccumulates() async throws {
        let hosted = HostedViewFixture.host(size: size) {
            SettingsForm { Toggle("Probe", isOn: .constant(true)) }
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(150))
        #expect(hosted.renders())

        var offset = ViewOffsetKey.defaultValue
        ViewOffsetKey.reduce(value: &offset, nextValue: { 3 })
        ViewOffsetKey.reduce(value: &offset, nextValue: { 4 })
        #expect(offset == 7)
    }

    @Test
    func globPatternListShowsTheEmptyMessageOrTheRows() async throws {
        let recorder = SettingsSharedRecorder()
        let emptyHost = HostedViewFixture.host(size: size) {
            makeList(patterns: [], selection: [], recorder: recorder).list
        }
        defer { emptyHost.close() }
        let filled = [GlobPattern(value: "*.log"), GlobPattern(value: ""), GlobPattern(value: "build")]
        let filledHost = HostedViewFixture.host(size: size) {
            makeList(patterns: filled, selection: [filled[0].id], recorder: recorder).list
        }
        defer { filledHost.close() }

        try await emptyHost.settle(.milliseconds(200))
        try await filledHost.settle(.milliseconds(200))

        #expect(emptyHost.renders())
        #expect(filledHost.renders())
        #expect(HostedView.pixelsDiffer(emptyHost.snapshot(), filledHost.snapshot()))
    }

    @Test
    func globPatternListMovesDeletesFocusesAndRemoves() {
        let recorder = SettingsSharedRecorder()
        let first = GlobPattern(value: "a")
        let second = GlobPattern(value: "b")
        let third = GlobPattern(value: "c")
        let made = makeList(patterns: [first, second, third], selection: [second.id], recorder: recorder)

        made.list.focusIfEmpty(GlobPattern(value: ""))
        made.list.focusIfEmpty(first)

        made.list.movePatterns(from: IndexSet(integer: 0), to: 3)
        #expect(made.patterns.value.map(\.value) == ["b", "c", "a"])

        made.list.deletePatterns(at: IndexSet([0, 2]))
        #expect(recorder.removed == [Set([second.id, first.id])])

        made.list.focus([third.id])
        made.list.focus([UUID()])
        made.list.focus([])

        made.list.removeSelected()
        #expect(recorder.removed.count == 2)
        #expect(recorder.removed.last == Set([second.id]))
    }

    @Test
    func globPatternListContextMenuOnlyAppearsForAKnownSelection() async throws {
        let recorder = SettingsSharedRecorder()
        let pattern = GlobPattern(value: "a")
        let made = makeList(patterns: [pattern], selection: [], recorder: recorder)

        _ = made.list.menuContent(for: [])
        _ = made.list.menuContent(for: [UUID()])
        let hosted = HostedViewFixture.host(size: size) {
            made.list.menuContent(for: [pattern.id])
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(150))

        #expect(hosted.renders())

        let menu = CommandsACoverageSupport.host { made.list.menuContent(for: [pattern.id]) }
        defer { menu.close() }
        try menu.click(titled: "Edit")
        try menu.click(titled: "Add")
        #expect(recorder.added == 1)
        try menu.click(titled: "Remove")
        #expect(recorder.removed == [Set([pattern.id])])
    }

    @Test
    func globPatternListItemSubmitsFocusesAndCommitsEdits() async throws {
        let recorder = SettingsSharedRecorder()
        let pattern = GlobPattern(value: "abc")
        let other = GlobPattern(value: "other")
        let patternBox = SettingsSharedBox(pattern)
        let selectionBox = SettingsSharedBox<Set<UUID>>([])
        let lastSink = SettingsSharedItemSink()
        let notLastSink = SettingsSharedItemSink()

        let lastHost = HostedViewFixture.host(size: NSSize(width: 240, height: 60)) {
            SettingsSharedItemProbe(
                pattern: patternBox.binding,
                selection: selectionBox.binding,
                recorder: recorder,
                sink: lastSink,
                isLast: true
            )
        }
        defer { lastHost.close() }
        let notLastHost = HostedViewFixture.host(size: NSSize(width: 240, height: 60)) {
            SettingsSharedItemProbe(
                pattern: patternBox.binding,
                selection: selectionBox.binding,
                recorder: recorder,
                sink: notLastSink,
                isLast: false
            )
        }
        defer { notLastHost.close() }
        try await lastHost.settle(.milliseconds(150))
        try await notLastHost.settle(.milliseconds(150))
        #expect(lastHost.renders())

        let last = try #require(lastSink.item)
        let notLast = try #require(notLastSink.item)

        last.submit("")
        notLast.submit("x")
        #expect(recorder.added == 0)
        last.submit("x")
        #expect(recorder.added == 1)

        last.submitCurrentValue()
        #expect(recorder.added == 2)
        notLast.submitCurrentValue()
        #expect(recorder.added == 2)

        last.focusChanged(true, value: "abc")
        #expect(selectionBox.value == [pattern.id])
        selectionBox.value = [pattern.id, other.id]
        last.focusChanged(true, value: "abc")
        #expect(selectionBox.value == [pattern.id, other.id])

        last.focusChanged(false, value: "")
        #expect(recorder.removed == [Set([pattern.id, other.id])])

        last.focusChanged(false, value: "abc")
        #expect(patternBox.value.value == "abc")
        last.focusChanged(false, value: "renamed")
        #expect(patternBox.value.value == "renamed")
    }

    @Test
    func fontWeightPickerRendersTheSelectedWeightWithDefaultAndCustomLabels() async throws {
        let box = SettingsSharedBox<NSFont.Weight>(.regular)
        let defaultLabel = HostedViewFixture.host(size: NSSize(width: 420, height: 80)) {
            Form { FontWeightPicker(selection: box.binding) }
        }
        defer { defaultLabel.close() }
        let customLabel = HostedViewFixture.host(size: NSSize(width: 420, height: 80)) {
            Form { FontWeightPicker(selection: box.binding, label: "Terminal Weight") }
        }
        defer { customLabel.close() }
        try await defaultLabel.settle(.milliseconds(150))
        try await customLabel.settle(.milliseconds(150))
        let regular = defaultLabel.snapshot()
        #expect(defaultLabel.renders())
        #expect(customLabel.renders())

        box.value = .black
        try await defaultLabel.settle(.milliseconds(150))

        #expect(HostedView.pixelsDiffer(regular, defaultLabel.snapshot()))
        #expect(FontWeightPicker.options.count == 9)
    }

    @Test
    func monospacedFontPickerFiltersFamiliesAndPushesRecentFonts() {
        let resolve: (String) -> NSFont? = { name in
            switch name {
            case "Menlo": NSFont(name: "Menlo", size: 14)
            case "Helvetica Neue": NSFont(name: "Helvetica Neue", size: 14)
            default: nil
            }
        }
        let families = ["SF Mono", "Menlo", "Helvetica Neue", "Missing", "Courier"]

        let monospaced = MonospacedFontPicker.monospacedFamilyNames(
            among: families,
            excluding: ["Courier"],
            resolve: resolve
        )
        let others = MonospacedFontPicker.otherFamilyNames(
            among: families,
            excluding: ["Courier"],
            resolve: resolve
        )

        #expect(monospaced == ["Menlo"])
        #expect(others == ["Helvetica Neue"])
        #expect(MonospacedFontPicker.resolveFont("Menlo") != nil)
        #expect(MonospacedFontPicker.resolveFont("Definitely Missing Font Family") == nil)
        #expect(MonospacedFontPicker.pushed("b", onto: ["a", "b", "c"]) == ["b", "a", "c"])
        #expect(MonospacedFontPicker.pushed("d", onto: ["a", "b", "c"]) == ["d", "a", "b"])
    }

    @Test
    func monospacedFontPickerRecordsSelectedFontsInTheInjectedDefaults() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        defaults.set(["Menlo", "Monaco", "Courier"], forKey: "recentFonts")
        let model = SettingsSharedFontModel("SF Mono")

        let hosted = HostedViewFixture.host(size: NSSize(width: 420, height: 80)) {
            Form { SettingsSharedFontProbe(model: model, defaults: defaults) }
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(300))
        #expect(hosted.renders())
        #expect(defaults.stringArray(forKey: "recentFonts") == ["Menlo", "Monaco", "Courier"])

        model.name = "Helvetica Neue"
        try await eventually { defaults.stringArray(forKey: "recentFonts") == ["Helvetica Neue", "Menlo", "Monaco"] }

        model.name = "SF Mono"
        try await hosted.settle(.milliseconds(150))
        #expect(defaults.stringArray(forKey: "recentFonts") == ["Helvetica Neue", "Menlo", "Monaco"])
    }

    @Test
    func monospacedFontPickerRendersWithoutRecentFontsAndSelectsOtherFonts() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let box = SettingsSharedBox("SF Mono")
        let picker = MonospacedFontPicker(title: "Font", selectedFontName: box.binding, defaults: defaults)

        let hosted = HostedViewFixture.host(size: NSSize(width: 420, height: 80)) {
            Form { picker }
        }
        defer { hosted.close() }
        let buttonHost = HostedViewFixture.host(size: NSSize(width: 240, height: 60)) {
            picker.otherFontButton("Palatino")
        }
        defer { buttonHost.close() }
        let rowHost = HostedViewFixture.host(size: NSSize(width: 240, height: 60)) {
            picker.fontRow("Menlo")
        }
        defer { rowHost.close() }
        try await hosted.settle(.milliseconds(300))
        try await buttonHost.settle(.milliseconds(150))
        try await rowHost.settle(.milliseconds(150))
        #expect(hosted.renders())
        #expect(buttonHost.renders())
        #expect(rowHost.renders())

        picker.selectOtherFont("Palatino")
        #expect(box.value == "Palatino")

        box.value = "SF Mono"
        let menu = CommandsACoverageSupport.host { picker.otherFontButton("Palatino") }
        defer { menu.close() }
        try menu.click(titled: "Palatino")
        #expect(box.value == "Palatino")
    }

    @Test
    func warningCharactersViewListsTheConfiguredCharacters() async throws {
        typealias Config = SettingsData.TextEditingSettings.WarningCharacters
        let box = SettingsSharedBox(Config.default)
        let hosted = HostedViewFixture.host(size: NSSize(width: 640, height: 480)) {
            WarningCharactersView(warningCharacters: box.binding)
        }
        defer { hosted.close() }
        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return hosted.renders()
        }
        try await hosted.settle(.milliseconds(300))
        let populated = hosted.snapshot()

        box.value = Config(enabled: true, characters: [:])

        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return HostedView.pixelsDiffer(populated, hosted.snapshot())
        }

        WarningCharactersView(warningCharacters: box.binding).done()
        #expect(box.value == Config(enabled: true, characters: [:]))
    }

    @Test
    func invisibleCharacterListConvertsBetweenCodesAndLabels() {
        let display = InvisibleCharacterWarningList.displayItems([0x00A0: "nbsp", 0x3: "etx", 0xFFFF: "max"])
        #expect(display == ["U+00A0": "nbsp", "U+0003": "etx", "U+FFFF": "max"])

        let box = SettingsSharedBox<[UInt16: String]>([0x41: "A"])
        let list = InvisibleCharacterWarningList(items: box.binding)
        #expect(list.displayBinding.wrappedValue == ["U+0041": "A"])
        list.displayBinding.wrappedValue = ["U+0042": "B"]
        #expect(box.value == [0x42: "B"])

        let parsed = InvisibleCharacterWarningList.parseItems([
            "U+00A0": "nbsp",
            "U+0003": "etx",
            "U+FFFF": "excluded",
            "bogus": "excluded",
            "0x41": "A"
        ])
        #expect(parsed == [0x00A0: "nbsp", 0x3: "etx", 0x41: "A"])
    }

    @Test
    func invisibleCharacterListRestoresDefaultsKeepingUserEntries() async throws {
        typealias Config = SettingsData.TextEditingSettings.WarningCharacters
        let box = SettingsSharedBox<[UInt16: String]>([0x00A0: "custom note", 0x4242: "mine"])
        let list = InvisibleCharacterWarningList(items: box.binding)
        let emptyBox = SettingsSharedBox<[UInt16: String]>([:])

        list.restoreDefaults()

        #expect(box.value[0x4242] == "mine")
        #expect(box.value[0x00A0] == Config.default.characters[0x00A0])
        #expect(box.value.count == Config.default.characters.count + 1)

        let populatedHost = HostedViewFixture.host(size: NSSize(width: 520, height: 300)) {
            InvisibleCharacterWarningList(items: box.binding)
        }
        defer { populatedHost.close() }
        let emptyHost = HostedViewFixture.host(size: NSSize(width: 520, height: 300)) {
            InvisibleCharacterWarningList(items: emptyBox.binding)
        }
        defer { emptyHost.close() }
        try await populatedHost.settle(.milliseconds(200))
        try await emptyHost.settle(.milliseconds(200))

        #expect(populatedHost.renders())
        #expect(emptyHost.renders())
        #expect(HostedView.pixelsDiffer(populatedHost.snapshot(), emptyHost.snapshot()))
    }

    @Test
    func externalLinkRendersEveryInitializerVariant() async throws {
        let url = URL(fileURLWithPath: "/tmp/settings-shared-\(UUID().uuidString)")
        let hosted = HostedViewFixture.host(size: NSSize(width: 420, height: 320)) {
            VStack {
                ExternalLink("Title", destination: url, subtitle: "Subtitle")
                ExternalLink("Finder", showInFinder: true, destination: url)
                ExternalLink(destination: url) {
                    Text("Content")
                }
                ExternalLink(
                    destination: url,
                    content: { Text("Content") },
                    title: "Title",
                    subtitle: "Subtitle",
                    icon: { Image(systemName: "star") }
                )
            }
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(150))

        #expect(hosted.renders())
    }

    @Test
    func externalLinkOpensTheDestinationOrRevealsItInFinder() {
        guard DreamderHeadless.isEnabled else { return }
        let opened = URL(fileURLWithPath: "/tmp/settings-shared-open-\(UUID().uuidString)")
        let revealed = URL(fileURLWithPath: "/tmp/settings-shared-reveal-\(UUID().uuidString)")

        ExternalLink("Open", destination: opened).open()
        ExternalLink("Reveal", showInFinder: true, destination: revealed).open()

        #expect(DreamderHeadless.suppressedExternalOpens.contains(opened.absoluteString))
        #expect(DreamderHeadless.suppressedExternalOpens.contains(revealed.absoluteString))
    }

    @Test
    func settingsColorPickerRendersWithAndWithoutExtraContent() async throws {
        let box = SettingsSharedBox(Color.red)
        let plain = HostedViewFixture.host(size: NSSize(width: 420, height: 80)) {
            Form { SettingsColorPicker("Plain", color: box.binding) }
        }
        defer { plain.close() }
        let extra = HostedViewFixture.host(size: NSSize(width: 420, height: 80)) {
            Form {
                SettingsColorPicker("Extra", color: box.binding) {
                    Text("Extra content")
                }
            }
        }
        defer { extra.close() }
        try await plain.settle(.milliseconds(150))
        try await extra.settle(.milliseconds(150))

        #expect(plain.renders())
        #expect(extra.renders())
    }

    @Test
    func settingsColorPickerPublishesTheSelectedColor() {
        let box = SettingsSharedBox(Color.red)

        SettingsColorPicker("Plain", color: box.binding).applySelectedColor(.red, .blue)

        #expect(box.value == .blue)
    }

    @Test
    func constrainHeightLeavesTheContentUnconstrainedWithoutASettingsWindow() async throws {
        let recorder = IdealSizeRecorder()
        let hosted = HostedViewFixture.host(size: NSSize(width: 300, height: 400)) {
            Color.red
                .frame(width: 200, height: 40)
                .constrainHeightToWindow(of: { nil })
                .recordingIdealSize(in: recorder)
        }
        defer { hosted.close() }
        let size = try await hosted.idealSize(of: recorder)

        #expect(size == CGSize(width: 200, height: 40))
    }

    @Test
    func constrainHeightLooksUpTheSettingsWindowByDefault() async throws {
        let recorder = IdealSizeRecorder()
        let hosted = HostedViewFixture.host(size: NSSize(width: 300, height: 400)) {
            Color.red
                .frame(width: 200)
                .constrainHeightToWindow()
                .recordingIdealSize(in: recorder)
        }
        defer { hosted.close() }
        let size = try await hosted.idealSize(of: recorder)

        #expect(size.width == 200)
    }

    @Test
    func constrainHeightFollowsTheSettingsWindowFrame() async throws {
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        settingsWindow.isReleasedWhenClosed = false
        defer { settingsWindow.close() }
        let recorder = IdealSizeRecorder()
        settingsWindow.orderFront(nil)

        let hosted = HostedViewFixture.host(size: NSSize(width: 300, height: 700)) {
            Color.red
                .frame(width: 200)
                .constrainHeightToWindow(of: { settingsWindow })
                .recordingIdealSize(in: recorder)
        }
        defer { hosted.close() }
        _ = try await hosted.idealSize(of: recorder)
        let tallHeight = settingsWindow.frame.height
        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return recorder.size?.height == tallHeight - 100
        }
        #expect(hosted.renders())

        var frame = settingsWindow.frame
        frame.size.height = 300
        settingsWindow.setFrame(frame, display: false)
        let shortHeight = settingsWindow.frame.height
        #expect(shortHeight < tallHeight)

        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return recorder.size?.height == shortHeight - 100
        }

        let otherWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 900),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        otherWindow.isReleasedWhenClosed = false
        defer { otherWindow.close() }
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: otherWindow)
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: nil)
        try await hosted.settle(.milliseconds(100))
        #expect(recorder.size?.height == shortHeight - 100)
    }

    @Test
    func backButtonModifierTogglesTheViewModelFlag() async throws {
        let model = SettingsViewModel()
        let visibility = SettingsSharedVisibility()
        let hosted = HostedViewFixture.host(size: NSSize(width: 320, height: 200)) {
            SettingsSharedBackProbe(visibility: visibility, model: model)
        }
        defer { hosted.close() }

        try await eventually { model.backButtonVisible }

        visibility.shown = false
        try await eventually { !model.backButtonVisible }
    }

    @Test
    func backButtonRendersAndDismisses() async throws {
        let button = NavigationBarBackButton()
        let hosted = HostedViewFixture.host(size: NSSize(width: 120, height: 60)) { button }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(150))

        button.dismiss()
        _ = NavigationBarBackToolbar().body

        #expect(hosted.renders())
    }

    private func makeList(
        patterns: [GlobPattern],
        selection: Set<UUID>,
        recorder: SettingsSharedRecorder
    ) -> (list: GlobPatternList, patterns: SettingsSharedBox<[GlobPattern]>, selection: SettingsSharedBox<Set<UUID>>) {
        let patternBox = SettingsSharedBox(patterns)
        let selectionBox = SettingsSharedBox(selection)
        let list = GlobPatternList(
            patterns: patternBox.binding,
            selection: selectionBox.binding,
            addPattern: { recorder.added += 1 },
            removePatterns: { recorder.removed.append($0) },
            emptyMessage: "No patterns"
        )
        return (list, patternBox, selectionBox)
    }
}
