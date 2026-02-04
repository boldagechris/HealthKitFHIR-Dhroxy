import Foundation
import HealthKit

/// Manager for accessing HealthKit data
@MainActor
class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var lastError: String?

    // Data types we want to read
    private let readTypes: Set<HKSampleType> = {
        var types = Set<HKSampleType>()

        // Vital signs
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let bloodPressureSystolic = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic) {
            types.insert(bloodPressureSystolic)
        }
        if let bloodPressureDiastolic = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) {
            types.insert(bloodPressureDiastolic)
        }
        if let oxygenSaturation = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            types.insert(oxygenSaturation)
        }
        if let respiratoryRate = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) {
            types.insert(respiratoryRate)
        }
        if let bodyTemperature = HKQuantityType.quantityType(forIdentifier: .bodyTemperature) {
            types.insert(bodyTemperature)
        }

        // Activity
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distance)
        }
        if let activeEnergy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }
        if let flightsClimbed = HKQuantityType.quantityType(forIdentifier: .flightsClimbed) {
            types.insert(flightsClimbed)
        }

        // Body measurements
        if let weight = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            types.insert(weight)
        }
        if let height = HKQuantityType.quantityType(forIdentifier: .height) {
            types.insert(height)
        }
        if let bmi = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            types.insert(bmi)
        }

        // Sleep
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }

        // Blood glucose
        if let glucose = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) {
            types.insert(glucose)
        }

        return types
    }()

    /// Check if HealthKit is available on this device
    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Request authorization to read HealthKit data
    func requestAuthorization() async {
        guard isHealthKitAvailable else {
            lastError = "HealthKit er ikke tilgængelig på denne enhed"
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            lastError = nil
        } catch {
            lastError = "Kunne ikke få adgang til HealthKit: \(error.localizedDescription)"
            isAuthorized = false
        }
    }

    /// Fetch health data from the last N days
    func fetchHealthData(days: Int = 7) async -> [HealthDataPoint] {
        var dataPoints: [HealthDataPoint] = []

        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        for sampleType in readTypes {
            if let quantityType = sampleType as? HKQuantityType {
                let samples = await fetchQuantitySamples(type: quantityType, predicate: predicate)
                dataPoints.append(contentsOf: samples)
            } else if let categoryType = sampleType as? HKCategoryType {
                let samples = await fetchCategorySamples(type: categoryType, predicate: predicate)
                dataPoints.append(contentsOf: samples)
            }
        }

        return dataPoints.sorted { $0.date > $1.date }
    }

    private func fetchQuantitySamples(type: HKQuantityType, predicate: NSPredicate) async -> [HealthDataPoint] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                let dataPoints = samples.compactMap { sample -> HealthDataPoint? in
                    let (value, unit) = self.extractValue(from: sample)
                    return HealthDataPoint(
                        id: sample.uuid.uuidString,
                        type: type.identifier,
                        value: value,
                        unit: unit,
                        date: sample.startDate,
                        endDate: sample.endDate,
                        sourceName: sample.sourceRevision.source.name,
                        sourceBundle: sample.sourceRevision.source.bundleIdentifier
                    )
                }
                continuation.resume(returning: dataPoints)
            }
            healthStore.execute(query)
        }
    }

    private func fetchCategorySamples(type: HKCategoryType, predicate: NSPredicate) async -> [HealthDataPoint] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                guard let samples = samples as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                let dataPoints = samples.map { sample in
                    let valueString = self.categoryValueString(for: sample)
                    return HealthDataPoint(
                        id: sample.uuid.uuidString,
                        type: type.identifier,
                        value: Double(sample.value),
                        unit: valueString,
                        date: sample.startDate,
                        endDate: sample.endDate,
                        sourceName: sample.sourceRevision.source.name,
                        sourceBundle: sample.sourceRevision.source.bundleIdentifier
                    )
                }
                continuation.resume(returning: dataPoints)
            }
            healthStore.execute(query)
        }
    }

    private func extractValue(from sample: HKQuantitySample) -> (Double, String) {
        let type = sample.quantityType

        switch type.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            return (sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())), "beats/min")

        case HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue,
             HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue:
            return (sample.quantity.doubleValue(for: HKUnit.millimeterOfMercury()), "mmHg")

        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            return (sample.quantity.doubleValue(for: HKUnit.percent()) * 100, "%")

        case HKQuantityTypeIdentifier.respiratoryRate.rawValue:
            return (sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())), "breaths/min")

        case HKQuantityTypeIdentifier.bodyTemperature.rawValue:
            return (sample.quantity.doubleValue(for: HKUnit.degreeCelsius()), "°C")

        case HKQuantityTypeIdentifier.stepCount.rawValue:
            return (sample.quantity.doubleValue(for: HKUnit.count()), "steps")

        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            return (sample.quantity.doubleValue(for: HKUnit.meter()), "m")

        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            return (sample.quantity.doubleValue(for: HKUnit.kilocalorie()), "kcal")

        case HKQuantityTypeIdentifier.flightsClimbed.rawValue:
            return (sample.quantity.doubleValue(for: HKUnit.count()), "floors")

        case HKQuantityTypeIdentifier.bodyMass.rawValue:
            return (sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo)), "kg")

        case HKQuantityTypeIdentifier.height.rawValue:
            return (sample.quantity.doubleValue(for: HKUnit.meterUnit(with: .centi)), "cm")

        case HKQuantityTypeIdentifier.bodyMassIndex.rawValue:
            return (sample.quantity.doubleValue(for: HKUnit.count()), "kg/m²")

        case HKQuantityTypeIdentifier.bloodGlucose.rawValue:
            return (sample.quantity.doubleValue(for: HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter())), "mmol/L")

        default:
            return (0, "unknown")
        }
    }

    private func categoryValueString(for sample: HKCategorySample) -> String {
        if sample.categoryType.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
            switch sample.value {
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                return "In Bed"
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                return "Asleep"
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                return "Awake"
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                return "Core Sleep"
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                return "Deep Sleep"
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                return "REM Sleep"
            default:
                return "Sleep"
            }
        }
        return "category"
    }
}

/// Represents a single health data point
struct HealthDataPoint: Identifiable, Codable {
    let id: String
    let type: String
    let value: Double
    let unit: String
    let date: Date
    let endDate: Date
    let sourceName: String
    let sourceBundle: String

    var displayName: String {
        switch type {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            return "Puls"
        case HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue:
            return "Blodtryk (systolisk)"
        case HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue:
            return "Blodtryk (diastolisk)"
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            return "Iltmætning"
        case HKQuantityTypeIdentifier.respiratoryRate.rawValue:
            return "Vejrtrækning"
        case HKQuantityTypeIdentifier.bodyTemperature.rawValue:
            return "Temperatur"
        case HKQuantityTypeIdentifier.stepCount.rawValue:
            return "Skridt"
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            return "Distance"
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            return "Aktiv energi"
        case HKQuantityTypeIdentifier.flightsClimbed.rawValue:
            return "Etager"
        case HKQuantityTypeIdentifier.bodyMass.rawValue:
            return "Vægt"
        case HKQuantityTypeIdentifier.height.rawValue:
            return "Højde"
        case HKQuantityTypeIdentifier.bodyMassIndex.rawValue:
            return "BMI"
        case HKQuantityTypeIdentifier.bloodGlucose.rawValue:
            return "Blodsukker"
        case HKCategoryTypeIdentifier.sleepAnalysis.rawValue:
            return "Søvn"
        default:
            return type
        }
    }

    var formattedValue: String {
        if type == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
            let duration = endDate.timeIntervalSince(date)
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)t \(minutes)m (\(unit))"
        }

        if value == value.rounded() {
            return "\(Int(value)) \(unit)"
        }
        return String(format: "%.1f %@", value, unit)
    }
}
