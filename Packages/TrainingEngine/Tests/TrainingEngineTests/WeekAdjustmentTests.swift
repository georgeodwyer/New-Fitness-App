import XCTest
@testable import TrainingEngine

final class WeekAdjustmentTests: XCTestCase {
    func testRepsSessionLosesARep() {
        var segments = [RunSegment(kind: .warmUp, length: .duration(seconds: 600))]
        for index in 0..<5 {
            segments.append(RunSegment(kind: .work, length: .distance(meters: 800)))
            if index < 4 { segments.append(RunSegment(kind: .recovery, length: .duration(seconds: 90))) }
        }
        segments.append(RunSegment(kind: .coolDown, length: .duration(seconds: 600)))
        let lighter = WeekAdjustment.scaled(RunStructure(segments: segments), by: 0.9)
        XCTAssertEqual(lighter.segments.filter { $0.kind == .work }.count, 4)
        XCTAssertEqual(lighter.segments.filter { $0.kind == .recovery }.count, 3)
        XCTAssertEqual(lighter.segments.last?.kind, .coolDown)
        XCTAssertEqual(WeekAdjustment.scaled(RunStructure(segments: segments), by: 1.05), RunStructure(segments: segments),
                       "Harder weeks don't add reps")
    }

    func testSteadyRunScalesButNotWarmUp() {
        let run = RunStructure(segments: [RunSegment(kind: .steady, length: .distance(meters: 10_000))])
        XCTAssertEqual(WeekAdjustment.scaled(run, by: 0.9).segments.first?.length, .distance(meters: 9000))
        XCTAssertEqual(WeekAdjustment.scaled(run, by: 1.05).segments.first?.length, .distance(meters: 10_500))
    }

    func testLighterGymDropsAccessorySets() {
        let prescription = StrengthPrescription(exercises: [
            ExercisePrescription(exerciseId: "squat", name: "Squat", role: .main, sets: 4, repRange: RepRange(5, 6), weightKg: 100, restSeconds: 180),
            ExercisePrescription(exerciseId: "curl", name: "Curl", role: .accessory, sets: 3, repRange: RepRange(10, 12), weightKg: 12, restSeconds: 60),
            ExercisePrescription(exerciseId: "plank", name: "Plank", role: .accessory, sets: 2, repRange: RepRange(30, 45), weightKg: nil, restSeconds: 60)
        ])
        XCTAssertEqual(WeekAdjustment.lighter(prescription).exercises.map(\.sets), [4, 2, 2])
    }
}
