import Foundation

/// Version of the engine's generation logic. Stored with each plan so
/// plans made by older logic can be recognised (and regenerated if needed).
public enum TrainingEngine {
    public static let version = "0.1.0"
}
