import XCTest
@testable import R6Camera

final class SettingsMigrationTests: XCTestCase {
    func testLegacyMissingFieldsAndVersionedCurrentPresetsRoundTrip() throws {
        let name = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        defaults.set(Data("{\"program\":\"M\",\"storedExperimentalHardwareShutter\":false}".utf8), forKey: "camera.current")
        XCTAssertEqual(store.load()?.program, .manual)
        XCTAssertEqual(store.load()?.experimentalHardwareShutter, false)
        XCTAssertEqual(store.load()?.focusArea.mode, .whole)
        var settings = CameraSettings(); settings.experimentalHardwareShutter = false
        settings.focusArea.mode = .flexible2; settings.focusArea.resize(width: 0.4, height: 0.5)
        settings.focusArea.wholeAreaTracking = false
        for key in ["current", "C1", "C2", "C3"] {
            XCTAssertTrue(store.save(settings, key: key)); XCTAssertEqual(store.load(key), settings)
            let data = try XCTUnwrap(defaults.data(forKey: "camera.\(key)"))
            XCTAssertEqual((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? Int, 1)
        }
    }
    func testCorruptAndUnknownVersionCannotBeOverwrittenWithoutRecovery() throws {
        let name = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        defaults.set("unexpected storage type", forKey: "camera.C3")
        XCTAssertNotNil(store.inspect("C3").diagnostic)
        XCTAssertFalse(store.save(CameraSettings(), key: "C3"))
        for (key, data) in [("current", Data("broken".utf8)), ("C2", Data("{\"version\":99,\"settings\":{}}".utf8))] {
            defaults.set(data, forKey: "camera.\(key)")
            XCTAssertNil(store.load(key)); XCTAssertNotNil(store.inspect(key).diagnostic)
            XCTAssertFalse(store.save(CameraSettings(), key: key))
            XCTAssertEqual(defaults.data(forKey: "camera.\(key)"), data)
        }
        store.recoverInvalid()
        let backups = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("camera.recovery.") }
        XCTAssertEqual(backups.count, 3)
        XCTAssertTrue(backups.values.contains { ($0 as? Data) == Data("broken".utf8) })
        XCTAssertTrue(store.save(CameraSettings())); XCTAssertNil(store.diagnostics)
    }
    func testBooleanVersionIsNotAnIntegerSchemaVersion() throws {
        let name = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        for json in ["{\"version\":true,\"settings\":{}}", "{\"settings\":{\"program\":\"M\"}}", "{\"version\":1}"] {
            let bytes = Data(json.utf8)
            defaults.set(bytes, forKey: "camera.current")
            XCTAssertNil(store.load()); XCTAssertFalse(store.save(CameraSettings()))
            XCTAssertEqual(defaults.data(forKey: "camera.current"), bytes)
        }
    }
}
