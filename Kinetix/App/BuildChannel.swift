import Foundation

/// Where this build came from: Xcode, TestFlight or the App Store.
enum BuildChannel {
    /// A development or TestFlight build (testing tools are shown); false on the App Store.
    static var isTesting: Bool {
        #if DEBUG
        return true
        #else
        // TestFlight builds carry a sandbox receipt; App Store builds don't.
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
