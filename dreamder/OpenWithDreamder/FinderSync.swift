//
//  FinderSync.swift
//  openInDreamder
//
//  Created by Wesley de Groot on 03/05/2022.
//

/**
 * For anyone working on this file.
 * print does not output to the console, use NSLog.
 * open "console.app" to debug,
 */

import Cocoa
import FinderSync
import os.log

class CEOpenWith: FIFinderSync {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "FinderSync")

    override init() {
        super.init()
        // Add finder sync
        let finderSync = FIFinderSyncController.default()
        if let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) {
            finderSync.directoryURLs = Set<URL>(mountedVolumes)
        }
        // Monitor volumes
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                finderSync.directoryURLs.insert(volumeURL)
            }
        }
    }

    /// Open in Dreamder (menu) action
    /// - Parameter sender: sender
    @objc
    func openInDreamderAction(_ sender: AnyObject?) {
        guard let items = FIFinderSyncController.default().selectedItemURLs(),
              let defaults = UserDefaults.init(suiteName: "dev.dreamder.Dreamder.shared") else {
            return
        }

        let files = items.map(\.path)

        guard let Dreamder = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "dev.dreamder.Dreamder"
        ) else { return }

        // Add files to open to openInCEFiles.
        defaults.set(files, forKey: "openInCEFiles")

        NSWorkspace.shared.open(
            [],
            withApplicationAt: Dreamder,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    // MARK: - Menu and toolbar item support
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        guard let defaults = UserDefaults.init(suiteName: "dev.dreamder.Dreamder.shared") else {
            logger.error("Unable to load defaults")
            return NSMenu(title: "")
        }

        // Register enableOpenInCE (enable Open In Dreamder
        defaults.register(defaults: ["enableOpenInCE": true])

        let menu = NSMenu(title: "")
        let menuItem = NSMenuItem(
            title: "Open in Dreamder",
            action: #selector(openInDreamderAction(_:)),
            keyEquivalent: ""
        )
        menuItem.image = NSImage.init(named: "icon")

        let enableOpenInCE = defaults.bool(forKey: "enableOpenInCE")
        logger.info("Enable Open In Dreamder value is \(enableOpenInCE, privacy: .public)")
        if enableOpenInCE {
            menu.addItem(menuItem)
        }
        return menu
    }
}
