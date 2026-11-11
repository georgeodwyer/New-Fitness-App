import Foundation

/// Version of the engine's generation logic. Stored with each plan so
/// plans made by older logic can be recognised (and regenerated if needed).
public enum TrainingEngine {
    /// The plan logic's version. Bump it whenever a change to how plans are built should reach
    /// plans people already have: on their next launch the app rebuilds their plan from the
    /// following Monday with the new logic (this week, done sessions and gym weights are kept).
    public static let version = "0.3.0"
}
