import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized)
struct IslandsDensityTests {
    private func withDensity(_ value: String?, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: Islands.densityKey)
        if let value {
            defaults.set(value, forKey: Islands.densityKey)
        } else {
            defaults.removeObject(forKey: Islands.densityKey)
        }
        body()
        if let previous {
            defaults.set(previous, forKey: Islands.densityKey)
        } else {
            defaults.removeObject(forKey: Islands.densityKey)
        }
    }

    @Test
    func compactIsTheDefaultWhenNothingIsStored() {
        withDensity(nil) {
            #expect(Islands.density == .compact)
        }
    }

    @Test
    func unknownStoredValueFallsBackToCompact() {
        withDensity("huge") {
            #expect(Islands.density == .compact)
        }
    }

    @Test
    func compactMetricsMatchIntelliJCompactMode() {
        withDensity("compact") {
            #expect(Islands.islandGap == 4)
            #expect(Islands.islandRadius == 8)
            #expect(Islands.tabStripHeight == 31)
            #expect(Islands.tabBarHeight == 32)
            #expect(Islands.tabPillHeight == 24)
            #expect(Islands.tabPillRadius == 4)
            #expect(Islands.tabLabelFontSize == 12)
            #expect(Islands.stripeIconSize == 16)
            #expect(Islands.stripeWidth == 33)
            #expect(Islands.treeRowHeight == 20)
            #expect(Islands.toolWindowHeaderHeight == 32)
            #expect(Islands.statusBarHeight == 22)
        }
    }

    @Test
    func defaultMetricsMatchIntelliJNewUI() {
        withDensity("default") {
            #expect(Islands.density == .default)
            #expect(Islands.islandGap == 6)
            #expect(Islands.islandRadius == 10)
            #expect(Islands.tabStripHeight == 40)
            #expect(Islands.tabBarHeight == 41)
            #expect(Islands.tabPillHeight == 30)
            #expect(Islands.stripeIconSize == 20)
            #expect(Islands.stripeWidth == 40)
            #expect(Islands.treeRowHeight == 24)
            #expect(Islands.toolWindowHeaderHeight == 41)
            #expect(Islands.statusBarHeight == 26)
        }
    }

    @Test
    func stripeIconsUseTheSizeVariantOfTheDensity() {
        withDensity("compact") {
            #expect(ToolWindowID.allCases.allSatisfy { !$0.icon.hasSuffix("_20") })
            #expect(ToolWindowID.allCases.allSatisfy { NSImage(named: $0.icon) != nil })
        }
        withDensity("default") {
            #expect(ToolWindowID.allCases.allSatisfy { $0.icon.hasSuffix("_20") })
            #expect(ToolWindowID.allCases.allSatisfy { NSImage(named: $0.icon) != nil })
        }
    }
}
