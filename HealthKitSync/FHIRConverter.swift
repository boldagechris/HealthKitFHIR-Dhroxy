import Foundation
import HealthKit

/// Converts HealthKit data to FHIR R4 resources
struct FHIRConverter {

    /// Convert an array of HealthDataPoints to a FHIR Bundle
    static func toFHIRBundle(dataPoints: [HealthDataPoint], patientId: String? = nil) -> [String: Any] {
        let entries = dataPoints.map { toFHIRObservation($0) }

        return [
            "resourceType": "Bundle",
            "type": "collection",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "entry": entries.map { entry in
                [
                    "fullUrl": "urn:uuid:\(entry["id"] as? String ?? UUID().uuidString)",
                    "resource": entry
                ]
            }
        ]
    }

    /// Convert a single HealthDataPoint to a FHIR Observation
    static func toFHIRObservation(_ dataPoint: HealthDataPoint) -> [String: Any] {
        let (loincCode, loincDisplay, category) = mapToLOINC(dataPoint.type)

        var observation: [String: Any] = [
            "resourceType": "Observation",
            "id": dataPoint.id,
            "status": "final",
            "category": [
                [
                    "coding": [
                        [
                            "system": "http://terminology.hl7.org/CodeSystem/observation-category",
                            "code": category,
                            "display": categoryDisplay(category)
                        ]
                    ]
                ]
            ],
            "code": [
                "coding": [
                    [
                        "system": "http://loinc.org",
                        "code": loincCode,
                        "display": loincDisplay
                    ],
                    [
                        "system": "http://developer.apple.com/documentation/healthkit",
                        "code": dataPoint.type,
                        "display": dataPoint.displayName
                    ]
                ],
                "text": dataPoint.displayName
            ],
            "effectiveDateTime": ISO8601DateFormatter().string(from: dataPoint.date),
            "issued": ISO8601DateFormatter().string(from: Date()),
            "device": [
                "display": dataPoint.sourceName,
                "identifier": [
                    "system": "http://apple.com/bundle-identifier",
                    "value": dataPoint.sourceBundle
                ]
            ]
        ]

        // Add value based on type
        if dataPoint.type == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
            // Sleep is a period with start and end
            observation["effectivePeriod"] = [
                "start": ISO8601DateFormatter().string(from: dataPoint.date),
                "end": ISO8601DateFormatter().string(from: dataPoint.endDate)
            ]
            observation["valueCodeableConcept"] = [
                "coding": [
                    [
                        "system": "http://snomed.info/sct",
                        "code": sleepSnomedCode(dataPoint.unit),
                        "display": dataPoint.unit
                    ]
                ],
                "text": dataPoint.unit
            ]
            // Remove effectiveDateTime since we use effectivePeriod
            observation.removeValue(forKey: "effectiveDateTime")
        } else {
            observation["valueQuantity"] = [
                "value": dataPoint.value,
                "unit": dataPoint.unit,
                "system": "http://unitsofmeasure.org",
                "code": ucumCode(for: dataPoint.unit)
            ]
        }

        return observation
    }

    /// Map HealthKit type identifier to LOINC code
    private static func mapToLOINC(_ hkType: String) -> (code: String, display: String, category: String) {
        switch hkType {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            return ("8867-4", "Heart rate", "vital-signs")

        case HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue:
            return ("8480-6", "Systolic blood pressure", "vital-signs")

        case HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue:
            return ("8462-4", "Diastolic blood pressure", "vital-signs")

        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            return ("2708-6", "Oxygen saturation in Arterial blood", "vital-signs")

        case HKQuantityTypeIdentifier.respiratoryRate.rawValue:
            return ("9279-1", "Respiratory rate", "vital-signs")

        case HKQuantityTypeIdentifier.bodyTemperature.rawValue:
            return ("8310-5", "Body temperature", "vital-signs")

        case HKQuantityTypeIdentifier.stepCount.rawValue:
            return ("55423-8", "Number of steps", "activity")

        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            return ("55430-3", "Walking distance", "activity")

        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            return ("41981-2", "Calories burned", "activity")

        case HKQuantityTypeIdentifier.flightsClimbed.rawValue:
            return ("93833-4", "Floors climbed", "activity")

        case HKQuantityTypeIdentifier.bodyMass.rawValue:
            return ("29463-7", "Body weight", "vital-signs")

        case HKQuantityTypeIdentifier.height.rawValue:
            return ("8302-2", "Body height", "vital-signs")

        case HKQuantityTypeIdentifier.bodyMassIndex.rawValue:
            return ("39156-5", "Body mass index", "vital-signs")

        case HKQuantityTypeIdentifier.bloodGlucose.rawValue:
            return ("15074-8", "Glucose [Moles/volume] in Blood", "laboratory")

        case HKCategoryTypeIdentifier.sleepAnalysis.rawValue:
            return ("93832-4", "Sleep duration", "social-history")

        default:
            return ("unknown", hkType, "vital-signs")
        }
    }

    private static func categoryDisplay(_ category: String) -> String {
        switch category {
        case "vital-signs": return "Vital Signs"
        case "activity": return "Activity"
        case "laboratory": return "Laboratory"
        case "social-history": return "Social History"
        default: return category
        }
    }

    private static func ucumCode(for unit: String) -> String {
        switch unit {
        case "beats/min", "breaths/min": return "/min"
        case "mmHg": return "mm[Hg]"
        case "%": return "%"
        case "°C": return "Cel"
        case "steps": return "{steps}"
        case "m": return "m"
        case "kcal": return "kcal"
        case "floors": return "{floors}"
        case "kg": return "kg"
        case "cm": return "cm"
        case "kg/m²": return "kg/m2"
        case "mmol/L": return "mmol/L"
        default: return unit
        }
    }

    private static func sleepSnomedCode(_ sleepType: String) -> String {
        switch sleepType {
        case "In Bed": return "229499004"
        case "Asleep": return "248220008"
        case "Awake": return "248218005"
        case "Core Sleep": return "248220008"
        case "Deep Sleep": return "248220008"
        case "REM Sleep": return "89129007"
        default: return "248220008"
        }
    }
}
