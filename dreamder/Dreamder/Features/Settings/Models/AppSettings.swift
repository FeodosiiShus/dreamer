//
//  AppSettings.swift
//  Dreamder
//
//  Created by Wouter Hennen on 12/04/2023.
//

import Foundation
import SwiftUI

nonisolated enum SettingsScope {
    @TaskLocal static var current: Settings?
}

@MainActor
final class AppSettingsStoreBox {
    var injected: Settings?

    var store: Settings {
        injected ?? SettingsScope.current ?? .shared
    }
}

@propertyWrapper
struct AppSettings<T>: DynamicProperty where T: Equatable {

    var settings: Environment<T>

    private var environmentStore: Environment<Settings>

    private let storeBox = AppSettingsStoreBox()

    let keyPath: WritableKeyPath<SettingsData, T>

    init(_ keyPath: WritableKeyPath<SettingsData, T>) {
        self.keyPath = keyPath
        let settingsKeyPath = (\EnvironmentValues.settings).appending(path: keyPath)
        self.settings = Environment(settingsKeyPath)
        self.environmentStore = Environment(\.settingsStore)
    }

    var store: Settings {
        storeBox.store
    }

    mutating func update() {
        storeBox.injected = environmentStore.wrappedValue
    }

    var wrappedValue: T {
        get {
            store.preferences[keyPath: keyPath]
        }
        nonmutating set {
            store.preferences[keyPath: keyPath] = newValue
        }
    }

    var projectedValue: Binding<T> {
        let store = store
        let keyPath = keyPath
        return Binding {
            store.preferences[keyPath: keyPath]
        } set: {
            store.preferences[keyPath: keyPath] = $0
        }
    }
}

struct SettingsDataEnvironmentKey: EnvironmentKey {
    static var defaultValue: SettingsData = .init()
}

struct SettingsStoreEnvironmentKey: EnvironmentKey {
    static var defaultValue: Settings = .shared
}

extension EnvironmentValues {
    var settings: SettingsDataEnvironmentKey.Value {
        get { self[SettingsDataEnvironmentKey.self] }
        set { self[SettingsDataEnvironmentKey.self] = newValue }
    }

    var settingsStore: Settings {
        get { self[SettingsStoreEnvironmentKey.self] }
        set { self[SettingsStoreEnvironmentKey.self] = newValue }
    }
}
