import Foundation
import IcarusCore

/// The three things the app remembers about where the user is in the flow, as
/// opposed to what it knows about their skin. All false is a first launch.
public struct ProfileFlags: Codable, Sendable, Equatable {
    public var onboardingComplete: Bool
    public var disclaimerAcknowledged: Bool
    public var adConsentDone: Bool

    public init(
        onboardingComplete: Bool = false,
        disclaimerAcknowledged: Bool = false,
        adConsentDone: Bool = false
    ) {
        self.onboardingComplete = onboardingComplete
        self.disclaimerAcknowledged = disclaimerAcknowledged
        self.adConsentDone = adConsentDone
    }
}

/// Where the profile and the flow flags live.
///
/// The profile is small, single-valued and read on every screen, so it is not
/// in the history store: the history is the record of what happened (R44) and
/// this is what the user told us about themselves. `load` answers nil before
/// onboarding has saved one.
public protocol ProfileStore: Sendable {
    func load() -> Profile?
    func save(_ profile: Profile)
    func flags() -> ProfileFlags
    func setFlags(_ flags: ProfileFlags)
}

/// The store the app runs on: two JSON values in `UserDefaults`.
///
/// A value that cannot be decoded is treated as absent rather than as a crash —
/// a profile the app cannot read sends the user through onboarding again, which
/// is recoverable, where refusing to launch is not.
public struct UserDefaultsProfileStore: ProfileStore, @unchecked Sendable {
    /// The defaults keys, named once so the export and any migration agree.
    public static let profileKey = "icarus.profile"
    public static let flagsKey = "icarus.flags"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Profile? {
        guard let data = defaults.data(forKey: Self.profileKey) else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }

    public func save(_ profile: Profile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: Self.profileKey)
    }

    public func flags() -> ProfileFlags {
        guard let data = defaults.data(forKey: Self.flagsKey),
              let stored = try? JSONDecoder().decode(ProfileFlags.self, from: data)
        else { return ProfileFlags() }
        return stored
    }

    public func setFlags(_ flags: ProfileFlags) {
        guard let data = try? JSONEncoder().encode(flags) else { return }
        defaults.set(data, forKey: Self.flagsKey)
    }
}

/// The store for tests, previews and any run that must not touch the disk.
///
/// The values sit in a locked box behind the struct, so every copy of the value
/// sees the same profile — a model handed one copy and a view handed another
/// must not disagree about whether onboarding is done.
public struct MemoryProfileStore: ProfileStore {
    private let box: Box

    public init(profile: Profile?) {
        box = Box(profile: profile)
    }

    public func load() -> Profile? {
        box.profile
    }

    public func save(_ profile: Profile) {
        box.profile = profile
    }

    public func flags() -> ProfileFlags {
        box.flags
    }

    public func setFlags(_ flags: ProfileFlags) {
        box.flags = flags
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var storedProfile: Profile?
        private var storedFlags = ProfileFlags()

        init(profile: Profile?) {
            storedProfile = profile
        }

        var profile: Profile? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storedProfile
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                storedProfile = newValue
            }
        }

        var flags: ProfileFlags {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storedFlags
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                storedFlags = newValue
            }
        }
    }
}
