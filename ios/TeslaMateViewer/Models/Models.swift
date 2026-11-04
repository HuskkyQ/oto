import Foundation

struct CarsResponse: Decodable {
    let cars: [Car]
}

struct Car: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String?
    let model: String?
    let trimBadging: String?
    let marketingName: String?
    let exteriorColor: String?
    let wheelType: String?
    let spoilerType: String?

    var displayName: String { name?.isEmpty == false ? name! : "Tesla \(model ?? "")" }
}

struct GeoPoint: Decodable, Equatable {
    let latitude: Double
    let longitude: Double
}

struct ActiveRoute: Decodable, Equatable {
    let destination: String?
    let energyAtArrival: Double?
    let milesToArrival: Double?
    let minutesToArrival: Double?
    let trafficMinutesDelay: Double?
    let location: GeoPoint?
    let error: String?
}

struct LiveResponse: Decodable {
    let car: Car
    let mqttConnected: Bool
    let values: LiveValues
    let receivedAt: Date?
    let oldestReceivedAt: Date?
    let stale: Bool
    let lastError: String?
    let lastPositionAt: Date?
    let serverTime: Date
}

struct LiveValues: Decodable {
    let state: String?
    let since: String?
    let healthy: Bool?
    let version: String?
    let updateAvailable: Bool?
    let updateVersion: String?
    let downloadPerc: Double?
    let installPerc: Double?

    let displayName: String?
    let model: String?
    let trimBadging: String?
    let marketingName: String?
    let exteriorColor: String?
    let wheelType: String?
    let spoilerType: String?
    let geofence: String?

    let latitude: Double?
    let longitude: Double?
    let location: GeoPoint?
    let shiftState: String?
    let power: Double?
    let speed: Double?
    let heading: Double?
    let elevation: Double?
    let odometer: Double?

    let batteryLevel: Int?
    let usableBatteryLevel: Int?
    let idealBatteryRangeKm: Double?
    let estBatteryRangeKm: Double?
    let ratedBatteryRangeKm: Double?
    let batteryHeater: Bool?
    let batteryHeaterOn: Bool?
    let batteryHeaterNoPower: Bool?

    let pluggedIn: Bool?
    let chargePortDoorOpen: Bool?
    let chargingState: String?
    let chargeEnergyAdded: Double?
    let chargeLimitSoc: Int?
    let chargerActualCurrent: Double?
    let chargerPhases: Int?
    let chargerPilotCurrent: Double?
    let chargerPower: Double?
    let chargerVoltage: Double?
    let chargeCurrentRequest: Double?
    let chargeCurrentRequestMax: Double?
    let scheduledChargingStartTime: String?
    let timeToFullCharge: Double?

    let tpmsPressureFl: Double?
    let tpmsPressureFr: Double?
    let tpmsPressureRl: Double?
    let tpmsPressureRr: Double?
    let tpmsSoftWarningFl: Bool?
    let tpmsSoftWarningFr: Bool?
    let tpmsSoftWarningRl: Bool?
    let tpmsSoftWarningRr: Bool?

    let activeRouteDestination: String?
    let activeRouteLatitude: Double?
    let activeRouteLongitude: Double?
    let activeRoute: ActiveRoute?

    let centerDisplayState: Int?
    let serviceMode: Bool?
    let locked: Bool?
    let sentryMode: Bool?
    let windowsOpen: Bool?
    let driverFrontWindowOpen: Bool?
    let driverRearWindowOpen: Bool?
    let passengerFrontWindowOpen: Bool?
    let passengerRearWindowOpen: Bool?
    let doorsOpen: Bool?
    let driverFrontDoorOpen: Bool?
    let driverRearDoorOpen: Bool?
    let passengerFrontDoorOpen: Bool?
    let passengerRearDoorOpen: Bool?
    let sunRoofState: String?
    let sunRoofInstalled: Bool?
    let sunRoofPercentOpen: Double?
    let trunkOpen: Bool?
    let frunkOpen: Bool?

    let isClimateOn: Bool?
    let isPreconditioning: Bool?
    let climateKeeperMode: String?
    let insideTemp: Double?
    let outsideTemp: Double?
    let isUserPresent: Bool?
    let fanStatus: Int?
    let driverTempSetting: Double?
    let passengerTempSetting: Double?
    let isFrontDefrosterOn: Bool?
    let isRearDefrosterOn: Bool?

    var coordinate: GeoPoint? {
        if let location { return location }
        if let latitude, let longitude { return GeoPoint(latitude: latitude, longitude: longitude) }
        return nil
    }

    var stateLabel: String {
        switch state {
        case "online": return "在线"
        case "asleep": return "休眠"
        case "offline": return "离线"
        case "charging": return "充电中"
        case "driving": return "行驶中"
        case "updating": return "更新中"
        case "suspended": return "已暂停"
        default: return state ?? "未知"
        }
    }
}

struct PositionsResponse: Decodable {
    let carId: Int
    let from: Date
    let to: Date
    let maxPoints: Int
    let points: [Position]
}

struct Position: Decodable, Identifiable {
    let driveId: Int?
    let date: Date
    let latitude: Double
    let longitude: Double
    let elevation: Int?
    let speed: Int?
    let power: Int?
    let odometer: Double?
    let batteryLevel: Int?
    let usableBatteryLevel: Int?

    var id: Date { date }
    var coordinate: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }
}

struct DrivesResponse: Decodable {
    let carId: Int
    let from: Date
    let to: Date
    let limit: Int
    let offset: Int
    let nextBeforeId: Int?
    let drives: [Drive]
}

struct Drive: Decodable, Identifiable {
    let id: Int
    let startDate: Date
    let endDate: Date?
    let distanceKm: Double?
    let durationMin: Int?
    let speedMax: Int?
    let powerMax: Int?
    let powerMin: Int?
    let startKm: Double?
    let endKm: Double?
    let startIdealRangeKm: Double?
    let endIdealRangeKm: Double?
    let startRatedRangeKm: Double?
    let endRatedRangeKm: Double?
    let startBatteryLevel: Int?
    let endBatteryLevel: Int?
    let outsideTempAvg: Double?
    let insideTempAvg: Double?
    let ascent: Int?
    let descent: Int?
    let startAddress: String?
    let startAddressDisplay: String?
    let endAddress: String?
    let endAddressDisplay: String?
    let startGeofence: String?
    let endGeofence: String?

    var startTitle: String {
        startGeofence ?? startAddress ?? startAddressDisplay ?? "未知地点"
    }

    var endTitle: String {
        endGeofence ?? endAddress ?? endAddressDisplay ?? "未知地点"
    }

    var rangeUsedKm: Double? {
        guard let startRatedRangeKm, let endRatedRangeKm else { return nil }
        return startRatedRangeKm - endRatedRangeKm
    }

    /// Distance ÷ duration — the average the drive actually held, not `speed_max`.
    var averageSpeedKmh: Double? {
        guard let distanceKm, let durationMin, durationMin > 0 else { return nil }
        return distanceKm / (Double(durationMin) / 60)
    }

    /// 达成率 — how far the car went for the ideal range it spent. 100 % means the drive
    /// covered exactly the range the battery lost; over 100 % means it beat the estimate.
    var achievementPercent: Int? {
        guard let distanceKm, distanceKm >= 0.5,
              let startIdealRangeKm, let endIdealRangeKm else { return nil }
        let used = startIdealRangeKm - endIdealRangeKm
        guard used >= 0.5 else { return nil }
        return Int((distanceKm / used * 100).rounded())
    }

    var batteryTransition: String? {
        guard let startBatteryLevel, let endBatteryLevel else { return nil }
        return "\(startBatteryLevel)% → \(endBatteryLevel)%"
    }
}

struct DriveDetailResponse: Decodable {
    let carId: Int
    let drive: Drive
    let positions: [Position]
    let energyKwh: Double?
}

struct ChargesResponse: Decodable {
    let carId: Int
    let from: Date
    let to: Date
    let limit: Int
    let offset: Int
    let nextBeforeId: Int?
    let charges: [ChargingSession]
}

struct ChargingSession: Decodable, Identifiable {
    let id: Int
    let startDate: Date
    let endDate: Date?
    let chargeEnergyAdded: Double?
    let chargeEnergyUsed: Double?
    let startBatteryLevel: Int?
    let endBatteryLevel: Int?
    let durationMin: Int?
    let startIdealRangeKm: Double?
    let endIdealRangeKm: Double?
    let startRatedRangeKm: Double?
    let endRatedRangeKm: Double?
    let outsideTempAvg: Double?
    let cost: Double?
    let address: String?
    let addressDisplay: String?
    let geofence: String?

    var title: String {
        geofence ?? address ?? addressDisplay ?? "未知地点"
    }
}

struct ChargeDetailResponse: Decodable {
    let carId: Int
    let charge: ChargingSession
    let samples: [ChargeSample]
}

struct ChargeSample: Decodable, Identifiable {
    let date: Date
    let batteryLevel: Int?
    let usableBatteryLevel: Int?
    let chargeEnergyAdded: Double?
    let chargerActualCurrent: Int?
    let chargerPhases: Int?
    let chargerPilotCurrent: Int?
    let chargerPower: Double?
    let chargerVoltage: Int?
    let connChargeCable: String?
    let fastChargerPresent: Bool?
    let fastChargerBrand: String?
    let fastChargerType: String?
    let idealBatteryRangeKm: Double?
    let ratedBatteryRangeKm: Double?
    let outsideTemp: Double?

    var id: Date { date }
}

struct StatesResponse: Decodable {
    let carId: Int
    let from: Date
    let to: Date
    let states: [StatePeriod]
}

struct StatePeriod: Decodable, Identifiable {
    let state: String
    let startDate: Date
    let endDate: Date?

    var id: Date { startDate }
}

struct UpdatesResponse: Decodable {
    let carId: Int
    let updates: [SoftwareUpdate]
}

struct SoftwareUpdate: Decodable, Identifiable {
    let version: String?
    let startDate: Date
    let endDate: Date?

    var id: Date { startDate }
}

struct StatsResponse: Decodable {
    let carId: Int
    let from: Date
    let to: Date
    let bucket: String
    let buckets: [StatsBucket]
}

struct StatsBucket: Decodable, Identifiable {
    let bucket: Date
    let driveCount: Int
    let distanceKm: Double
    let durationMin: Int
    let chargeCount: Int
    let chargeEnergyKwh: Double
    let chargeCost: Double?

    var id: Date { bucket }
}

// MARK: - Derived history

struct EnergyResponse: Decodable {
    let carId: Int
    let from: Date
    let to: Date
    let group: String
    let totalKm: Double
    let averageWhPerKm: Int?
    let best: EnergyBest?
    /// Newest software-version group, only set for `group=version`.
    let latestKey: String?
    let groups: [EnergyGroup]
}

struct EnergyBest: Decodable {
    let key: String
    let label: String
    let spreadPercent: Double
}

struct EnergyGroup: Decodable, Identifiable {
    let key: String
    let label: String
    let whPerKm: Int
    let km: Double
    let driveCount: Int
    let fromDate: Date
    let toDate: Date

    var id: String { key }
}

struct RegenResponse: Decodable {
    let carId: Int
    let from: Date
    let to: Date
    let today: RegenDay?
    let days: [RegenDay]
    let totalRegenKwh: Double
    /// Recovered ÷ (recovered + consumed) over the range.
    let share: Double?
    let weekPeakKw: Double
    let versions: [RegenVersion]
}

struct RegenDay: Decodable, Identifiable {
    let date: Date
    let regenKwh: Double
    let consumedKwh: Double
    let minutes: Int
    let peakKw: Double

    var id: Date { date }
}

struct RegenVersion: Decodable, Identifiable {
    let version: String?
    let peakKw: Double
    let regenKwh: Double

    var id: String { version ?? "__unknown__" }
    var label: String { version ?? "未知版本" }
}

struct ParkingResponse: Decodable {
    let carId: Int
    let from: Date
    let to: Date
    let totalMinutes: Int
    let totalEnergyKwh: Double?
    let averagePowerW: Int?
    let sessions: [ParkingSession]
}

struct ParkingSession: Decodable, Identifiable {
    let startDate: Date
    let endDate: Date
    let place: String?
    let durationMin: Int
    let energyKwh: Double?
    let averagePowerW: Int?
    let startBatteryLevel: Int?
    let endBatteryLevel: Int?
    let startRangeKm: Double?
    let endRangeKm: Double?
    let rangeLossKm: Double?
    let rangeLossPerHourKm: Double?
    let stateMinutes: [ParkingStateMinutes]
    let outsideTempAvg: Double?
    let odometerKm: Double?

    var id: Date { startDate }

    var title: String { place ?? "未知地点" }
}

struct ParkingStateMinutes: Decodable, Identifiable {
    let state: String
    let minutes: Int

    var id: String { state }
}

struct BatteryReport: Decodable {
    let carId: Int
    let sampleCount: Int
    let capacityKwh: Double?
    let fullRangeKm: Int?
    let baselineCapacityKwh: Double?
    let baselineRangeKm: Int?
    let capacityRetention: Double?
    let rangeRetention: Double?
    let score: Int?
    let rating: String?
    let lastChargeDate: Date?
    let odometerKm: Double?

    /// Percent lost against the best the car ever showed.
    var capacityLossPercent: Double? {
        capacityRetention.map { (1 - $0) * 100 }
    }

    var rangeLossPercent: Double? {
        rangeRetention.map { (1 - $0) * 100 }
    }
}
