import Foundation

/// Pure medication inventory calculation. The engine has no persistence, UI,
/// notification, network, or process-global clock dependency.
public struct MedicationInventoryForecast {
    public typealias NowProvider = @Sendable () -> Date

    private let now: NowProvider
    private let forecastHorizonDays: Int

    public init(
        forecastHorizonDays: Int = 3_660,
        now: @escaping NowProvider
    ) {
        precondition(forecastHorizonDays > 0)
        self.forecastHorizonDays = forecastHorizonDays
        self.now = now
    }

    public func evaluate(
        _ request: MedicationInventoryForecastRequest
    ) throws -> MedicationInventoryForecastResult {
        let asOf = now()
        try validate(request)

        var issues: [MedicationInventoryForecastIssue] = []
        let plans = try normalizePlans(
            request.planVersions,
            calculationUnit: request.calculationUnit,
            conversions: request.conversions,
            issues: &issues
        )

        let quantities = try containerQuantities(
            request: request,
            at: asOf,
            issues: &issues
        )

        let usableBeforeConsumption = sumContainers(
            usableContainers(request.containers, at: asOf),
            quantities: quantities
        )
        let orderedNotReceived = sumContainers(
            request.containers.filter { $0.state == .orderedNotReceived },
            quantities: quantities
        )

        let targetRemaining = try prescriptionRemaining(
            request: request,
            quantities: quantities,
            plans: plans,
            asOf: asOf,
            usage: .target,
            issues: &issues
        )
        let maximumRemaining = try prescriptionRemaining(
            request: request,
            quantities: quantities,
            plans: plans,
            asOf: asOf,
            usage: .maximum,
            issues: &issues
        )
        let ledgerRemaining = try ledgerRemaining(
            request: request,
            quantities: quantities,
            asOf: asOf,
            issues: &issues
        )

        let activeRemainingValue = conservativeRemaining(
            prescriptionTarget: targetRemaining,
            ledger: ledgerRemaining
        )

        let targetProjection = try targetRemaining.flatMap {
            try project(
                quantity: nonnegative($0),
                from: asOf,
                plans: plans,
                usage: .target,
                issues: &issues
            )
        }
        let maximumProjection = try maximumRemaining.flatMap {
            try project(
                quantity: nonnegative($0),
                from: asOf,
                plans: plans,
                usage: .maximum,
                issues: &issues
            )
        }
        let ledgerProjection = try ledgerRemaining.flatMap {
            try project(
                quantity: nonnegative($0),
                from: asOf,
                plans: plans,
                usage: .target,
                issues: &issues
            )
        }
        let activeProjection = try activeRemainingValue.flatMap {
            try project(
                quantity: nonnegative($0),
                from: asOf,
                plans: plans,
                usage: .target,
                issues: &issues
            )
        }

        let earlyBottleReview = try evaluateBottleAction(
            request: request,
            plans: plans,
            issues: &issues
        )

        let finalIssues = sortedUniqueIssues(issues)
        let completeness = completeness(for: finalIssues)
        let amount: (Decimal?) -> MedicationInventoryAmount? = { value in
            value.map {
                MedicationInventoryAmount(value: $0, unit: request.calculationUnit)
            }
        }
        let provenance = provenance(for: request, asOf: asOf)
        let explanation = explanation(
            request: request,
            asOf: asOf,
            completeness: completeness,
            issues: finalIssues,
            usableBeforeConsumption: usableBeforeConsumption,
            orderedNotReceived: orderedNotReceived,
            targetRemaining: targetRemaining,
            maximumRemaining: maximumRemaining,
            ledgerRemaining: ledgerRemaining,
            activeRemaining: activeRemainingValue,
            targetProjection: targetProjection,
            maximumProjection: maximumProjection,
            ledgerProjection: ledgerProjection,
            activeProjection: activeProjection,
            earlyBottleReview: earlyBottleReview,
            provenance: provenance
        )

        return MedicationInventoryForecastResult(
            medicationID: request.medicationID,
            asOf: asOf,
            calculationUnit: request.calculationUnit,
            completeness: completeness,
            issues: finalIssues,
            usableQuantityBeforeConsumption: amount(usableBeforeConsumption),
            orderedNotReceivedQuantity: amount(orderedNotReceived),
            prescriptionTargetRemaining: amount(targetRemaining),
            prescriptionMaximumRemaining: amount(maximumRemaining),
            ledgerRemaining: amount(ledgerRemaining),
            activeForecastRemaining: amount(activeRemainingValue),
            targetProjection: targetProjection,
            maximumProjection: maximumProjection,
            ledgerProjection: ledgerProjection,
            activeProjection: activeProjection,
            earlyBottleReview: earlyBottleReview,
            provenance: provenance,
            explanation: explanation
        )
    }
}

// MARK: - Validation and normalization

private extension MedicationInventoryForecast {
    enum UsageBasis: Equatable {
        case target
        case maximum
    }

    struct NormalizedPlan {
        let source: MedicationInventoryPlanVersion
        let targetPerDose: Decimal?
        let maximumPerDose: Decimal?
        let targetPerSession: Decimal?
        let maximumPerSession: Decimal?

        func amount(for usage: UsageBasis) -> Decimal? {
            switch usage {
            case .target: return targetPerSession
            case .maximum: return maximumPerSession
            }
        }
    }

    struct HistoricalUsage {
        let quantity: Decimal
        let sessionCount: Int
        let planVersionIDs: [String]
    }

    func validate(_ request: MedicationInventoryForecastRequest) throws {
        let allIDs =
            request.planVersions.map(\.id)
            + request.containers.map(\.id)
            + request.adjustments.map(\.id)
            + request.allocations.map(\.id)
            + request.conversions.map(\.id)
            + [request.tolerancePolicy.id]
        var seen: Set<String> = []
        for id in allIDs {
            guard !id.isEmpty, seen.insert(id).inserted else {
                throw MedicationInventoryForecastError.duplicateRecordID(id)
            }
        }

        guard request.containers.filter({ $0.state == .openActive }).count <= 1 else {
            throw MedicationInventoryForecastError.multipleActiveContainers
        }

        for container in request.containers {
            if let receivedAt = container.receivedAt,
               let openedAt = container.openedAt,
               receivedAt > openedAt {
                throw MedicationInventoryForecastError.invalidBottleActionTimeline(
                    containerID: container.id
                )
            }
            if let amount = container.startingUsableQuantity {
                try validateAmount(
                    amount.value,
                    recordID: container.id,
                    field: "startingUsableQuantity",
                    rule: .positive
                )
            }
        }

        for adjustment in request.adjustments {
            try validateAmount(
                adjustment.quantityChange.value,
                recordID: adjustment.id,
                field: "quantityChange",
                rule: .nonzero
            )
        }

        for allocation in request.allocations {
            if let quantity = allocation.quantity {
                try validateAmount(
                    quantity.value,
                    recordID: allocation.id,
                    field: "quantity",
                    rule: .positive
                )
            }
        }

        let policy = request.tolerancePolicy
        try validateAmount(
            policy.percentOfStartingQuantity,
            recordID: policy.id,
            field: "percentOfStartingQuantity",
            rule: .nonnegative
        )
        try validateAmount(
            policy.smallestMeaningfulIncrement.value,
            recordID: policy.id,
            field: "smallestMeaningfulIncrement",
            rule: .positive
        )
        if let measurement = policy.measurementTolerance {
            try validateAmount(
                measurement.value,
                recordID: policy.id,
                field: "measurementTolerance",
                rule: .nonnegative
            )
        }

        for conversion in request.conversions {
            guard conversion.fromUnit != conversion.toUnit,
                  conversion.multiplier.isFinite,
                  conversion.multiplier > 0 else {
                throw MedicationInventoryForecastError.invalidConversion(conversion.id)
            }
        }

        let sortedPlans = request.planVersions.sorted(by: planSort)
        for plan in sortedPlans {
            if let end = plan.effectiveUntil, end <= plan.effectiveFrom {
                throw MedicationInventoryForecastError.invalidPlanRange(plan.id)
            }
            try validateSchedule(plan.schedule, planID: plan.id)
            try validateOptionalPositive(plan.targetPerDose, planID: plan.id, field: "targetPerDose")
            try validateOptionalPositive(plan.maximumPerDose, planID: plan.id, field: "maximumPerDose")
            try validateOptionalPositive(plan.targetPerSession, planID: plan.id, field: "targetPerSession")
            try validateOptionalPositive(plan.maximumPerSession, planID: plan.id, field: "maximumPerSession")
        }

        if sortedPlans.count > 1 {
            for index in 1..<sortedPlans.count {
                let previous = sortedPlans[index - 1]
                let current = sortedPlans[index]
                if previous.effectiveUntil == nil
                    || current.effectiveFrom < previous.effectiveUntil! {
                    throw MedicationInventoryForecastError.overlappingPlanVersions(
                        first: previous.id,
                        second: current.id
                    )
                }
            }
        }
    }

    enum AmountRule {
        case positive
        case nonnegative
        case nonzero
    }

    func validateAmount(
        _ value: Decimal,
        recordID: String,
        field: String,
        rule: AmountRule
    ) throws {
        let valid: Bool
        switch rule {
        case .positive: valid = value.isFinite && value > 0
        case .nonnegative: valid = value.isFinite && value >= 0
        case .nonzero: valid = value.isFinite && value != 0
        }
        guard valid else {
            throw MedicationInventoryForecastError.invalidAmount(
                recordID: recordID,
                field: field
            )
        }
    }

    func validateOptionalPositive(
        _ amount: MedicationInventoryAmount?,
        planID: String,
        field: String
    ) throws {
        guard let amount else { return }
        try validateAmount(amount.value, recordID: planID, field: field, rule: .positive)
    }

    func validateSchedule(
        _ schedule: MedicationInventorySchedule,
        planID: String
    ) throws {
        switch schedule {
        case .daily(let hour, let minute, _):
            guard (0...23).contains(hour), (0...59).contains(minute) else {
                throw MedicationInventoryForecastError.invalidSchedule(planID: planID)
            }
        case .selectedWeekdays(let weekdays, let hour, let minute, _):
            guard !weekdays.isEmpty,
                  Set(weekdays).count == weekdays.count,
                  weekdays.allSatisfy({ (1...7).contains($0) }),
                  (0...23).contains(hour),
                  (0...59).contains(minute) else {
                throw MedicationInventoryForecastError.invalidSchedule(planID: planID)
            }
        case .irregular:
            break
        }
    }

    func normalizePlans(
        _ sourcePlans: [MedicationInventoryPlanVersion],
        calculationUnit: AmountUnit,
        conversions: [MedicationInventoryUnitConversion],
        issues: inout [MedicationInventoryForecastIssue]
    ) throws -> [NormalizedPlan] {
        guard !sourcePlans.isEmpty else {
            issues.append(issue(.plan, .missingPlan))
            return []
        }

        var normalized: [NormalizedPlan] = []
        for plan in sourcePlans.sorted(by: planSort) {
            let targetPerDose = try normalizePlanAmount(
                plan.targetPerDose,
                missingCode: .missingTargetPerDose,
                planID: plan.id,
                field: "targetPerDose",
                calculationUnit: calculationUnit,
                conversions: conversions,
                issues: &issues
            )
            let maximumPerDose = try normalizeOptionalAmount(
                plan.maximumPerDose,
                recordID: plan.id,
                field: "maximumPerDose",
                calculationUnit: calculationUnit,
                conversions: conversions,
                issues: &issues
            )
            let targetPerSession = try normalizePlanAmount(
                plan.targetPerSession,
                missingCode: .missingTargetPerSession,
                planID: plan.id,
                field: "targetPerSession",
                calculationUnit: calculationUnit,
                conversions: conversions,
                issues: &issues
            )
            let maximumPerSession = try normalizePlanAmount(
                plan.maximumPerSession,
                missingCode: .missingMaximumPerSession,
                planID: plan.id,
                field: "maximumPerSession",
                calculationUnit: calculationUnit,
                conversions: conversions,
                issues: &issues
            )

            switch plan.schedule {
            case .irregular:
                issues.append(issue(.plan, .irregularSchedule, recordID: plan.id, field: "schedule"))
            case .daily(_, _, let identifier),
                 .selectedWeekdays(_, _, _, let identifier):
                if TimeZone(identifier: identifier) == nil {
                    issues.append(issue(.plan, .unknownTimeZone, recordID: plan.id, field: "schedule"))
                }
            }

            if let targetPerDose, let maximumPerDose, targetPerDose > maximumPerDose {
                throw MedicationInventoryForecastError.invalidPlanRelationship(
                    planID: plan.id,
                    field: "targetPerDose>maximumPerDose"
                )
            }
            if let targetPerSession, let maximumPerSession,
               targetPerSession > maximumPerSession {
                throw MedicationInventoryForecastError.invalidPlanRelationship(
                    planID: plan.id,
                    field: "targetPerSession>maximumPerSession"
                )
            }
            if let targetPerDose, let targetPerSession,
               targetPerDose > targetPerSession {
                throw MedicationInventoryForecastError.invalidPlanRelationship(
                    planID: plan.id,
                    field: "targetPerDose>targetPerSession"
                )
            }
            if let maximumPerDose, let maximumPerSession,
               maximumPerDose > maximumPerSession {
                throw MedicationInventoryForecastError.invalidPlanRelationship(
                    planID: plan.id,
                    field: "maximumPerDose>maximumPerSession"
                )
            }

            normalized.append(
                NormalizedPlan(
                    source: plan,
                    targetPerDose: targetPerDose,
                    maximumPerDose: maximumPerDose,
                    targetPerSession: targetPerSession,
                    maximumPerSession: maximumPerSession
                )
            )
        }
        return normalized
    }

    func normalizePlanAmount(
        _ amount: MedicationInventoryAmount?,
        missingCode: MedicationInventoryForecastIssueCode,
        planID: String,
        field: String,
        calculationUnit: AmountUnit,
        conversions: [MedicationInventoryUnitConversion],
        issues: inout [MedicationInventoryForecastIssue]
    ) throws -> Decimal? {
        guard let amount else {
            issues.append(issue(.plan, missingCode, recordID: planID, field: field))
            return nil
        }
        return try normalizeOptionalAmount(
            amount,
            recordID: planID,
            field: field,
            calculationUnit: calculationUnit,
            conversions: conversions,
            issues: &issues
        )
    }

    func normalizeOptionalAmount(
        _ amount: MedicationInventoryAmount?,
        recordID: String,
        field: String,
        calculationUnit: AmountUnit,
        conversions: [MedicationInventoryUnitConversion],
        issues: inout [MedicationInventoryForecastIssue]
    ) throws -> Decimal? {
        guard let amount else { return nil }
        guard let value = try convert(
            amount,
            to: calculationUnit,
            conversions: conversions,
            recordID: recordID,
            field: field
        ) else {
            issues.append(issue(.plan, .missingUnitConversion, recordID: recordID, field: field))
            return nil
        }
        return value
    }
}

// MARK: - Quantity calculations

private extension MedicationInventoryForecast {
    struct ContainerQuantities {
        var values: [String: Decimal]
        var incompleteIDs: Set<String>
    }

    func containerQuantities(
        request: MedicationInventoryForecastRequest,
        at date: Date,
        issues: inout [MedicationInventoryForecastIssue]
    ) throws -> ContainerQuantities {
        var result = ContainerQuantities(values: [:], incompleteIDs: [])
        let containersByID = Dictionary(uniqueKeysWithValues: request.containers.map { ($0.id, $0) })

        for container in request.containers {
            if container.state.isUsableOnHand && container.receivedAt == nil {
                issues.append(
                    issue(
                        .inventory,
                        .missingReceivedAt,
                        recordID: container.id,
                        field: "receivedAt"
                    )
                )
            }
            guard let starting = container.startingUsableQuantity else {
                issues.append(
                    issue(
                        .inventory,
                        .missingStartingQuantity,
                        recordID: container.id,
                        field: "startingUsableQuantity"
                    )
                )
                result.incompleteIDs.insert(container.id)
                continue
            }
            guard let normalized = try convert(
                starting,
                to: request.calculationUnit,
                conversions: request.conversions,
                recordID: container.id,
                field: "startingUsableQuantity"
            ) else {
                issues.append(
                    issue(
                        .plan,
                        .missingUnitConversion,
                        recordID: container.id,
                        field: "startingUsableQuantity"
                    )
                )
                result.incompleteIDs.insert(container.id)
                continue
            }
            result.values[container.id] = normalized
        }

        for adjustment in request.adjustments where adjustment.occurredAt <= date {
            guard containersByID[adjustment.containerID] != nil else {
                issues.append(
                    issue(
                        .inventory,
                        .unknownAdjustmentContainer,
                        recordID: adjustment.id,
                        field: "containerID"
                    )
                )
                continue
            }
            guard !result.incompleteIDs.contains(adjustment.containerID),
                  let normalized = try convert(
                    adjustment.quantityChange,
                    to: request.calculationUnit,
                    conversions: request.conversions,
                    recordID: adjustment.id,
                    field: "quantityChange"
                  ) else {
                if !result.incompleteIDs.contains(adjustment.containerID) {
                    issues.append(
                        issue(
                            .plan,
                            .missingUnitConversion,
                            recordID: adjustment.id,
                            field: "quantityChange"
                        )
                    )
                    result.incompleteIDs.insert(adjustment.containerID)
                    result.values.removeValue(forKey: adjustment.containerID)
                }
                continue
            }
            result.values[adjustment.containerID, default: 0] += normalized
        }
        return result
    }

    func sumContainers(
        _ containers: [MedicationInventoryContainer],
        quantities: ContainerQuantities
    ) -> Decimal? {
        guard containers.allSatisfy({ !quantities.incompleteIDs.contains($0.id) }) else {
            return nil
        }
        return containers.reduce(Decimal.zero) { partial, container in
            partial + (quantities.values[container.id] ?? 0)
        }
    }

    func prescriptionRemaining(
        request: MedicationInventoryForecastRequest,
        quantities: ContainerQuantities,
        plans: [NormalizedPlan],
        asOf: Date,
        usage: UsageBasis,
        issues: inout [MedicationInventoryForecastIssue]
    ) throws -> Decimal? {
        let availableContainers = usableContainers(request.containers, at: asOf)
        guard availableContainers.allSatisfy({ !quantities.incompleteIDs.contains($0.id) }) else {
            return nil
        }

        var remaining = Decimal.zero
        for container in availableContainers {
            guard let available = quantities.values[container.id] else { return nil }
            switch container.state {
            case .unopened:
                remaining += available
            case .openActive:
                guard let openedAt = container.openedAt else {
                    issues.append(
                        issue(
                            .inventory,
                            .missingOpenedAt,
                            recordID: container.id,
                            field: "openedAt"
                        )
                    )
                    return nil
                }
                guard openedAt <= asOf else {
                    throw MedicationInventoryForecastError.invalidBottleActionTimeline(
                        containerID: container.id
                    )
                }
                guard let historical = historicalUsage(
                    from: openedAt,
                    to: asOf,
                    plans: plans,
                    usage: usage,
                    issues: &issues
                ) else {
                    return nil
                }
                let containerRemaining = available - historical.quantity
                if containerRemaining < 0 {
                    issues.append(
                        issue(
                            .inventory,
                            .negativePlanBalance,
                            recordID: container.id
                        )
                    )
                }
                remaining += containerRemaining
            case .orderedNotReceived, .unavailable:
                break
            }
        }

        if remaining < 0 {
            issues.append(issue(.inventory, .negativePlanBalance))
        }
        return remaining
    }

    func ledgerRemaining(
        request: MedicationInventoryForecastRequest,
        quantities: ContainerQuantities,
        asOf: Date,
        issues: inout [MedicationInventoryForecastIssue]
    ) throws -> Decimal? {
        let availableContainers = usableContainers(request.containers, at: asOf)
        guard sumContainers(availableContainers, quantities: quantities) != nil else {
            return nil
        }
        let containersByID = Dictionary(uniqueKeysWithValues: request.containers.map { ($0.id, $0) })
        var balances = Dictionary(
            uniqueKeysWithValues: availableContainers.compactMap { container in
                quantities.values[container.id].map { (container.id, $0) }
            }
        )
        var complete = true

        for allocation in request.allocations where allocation.occurredAt <= asOf {
            guard let containerID = allocation.containerID else {
                issues.append(
                    issue(
                        .inventory,
                        .unallocatedDose,
                        recordID: allocation.id,
                        field: "containerID"
                    )
                )
                complete = false
                continue
            }
            guard let container = containersByID[containerID],
                  isContainerUsable(container, at: asOf) else {
                issues.append(
                    issue(
                        .inventory,
                        .unknownAllocationContainer,
                        recordID: allocation.id,
                        field: "containerID"
                    )
                )
                complete = false
                continue
            }
            guard let quantity = allocation.quantity else {
                issues.append(
                    issue(
                        .doseHistory,
                        .missingDoseAmount,
                        recordID: allocation.id,
                        field: "quantity"
                    )
                )
                complete = false
                continue
            }
            guard let normalized = try convert(
                quantity,
                to: request.calculationUnit,
                conversions: request.conversions,
                recordID: allocation.id,
                field: "quantity"
            ) else {
                issues.append(
                    issue(
                        .plan,
                        .missingUnitConversion,
                        recordID: allocation.id,
                        field: "quantity"
                    )
                )
                complete = false
                continue
            }
            balances[containerID, default: 0] -= normalized
        }

        guard complete else { return nil }
        for (containerID, balance) in balances where balance < 0 {
            issues.append(
                issue(
                    .inventory,
                    .negativeLedgerBalance,
                    recordID: containerID
                )
            )
        }
        let remaining = balances.values.reduce(Decimal.zero, +)
        if remaining < 0 {
            issues.append(issue(.inventory, .negativeLedgerBalance))
        }
        return remaining
    }

    func conservativeRemaining(
        prescriptionTarget: Decimal?,
        ledger: Decimal?
    ) -> Decimal? {
        switch (prescriptionTarget, ledger) {
        case let (prescription?, ledger?): return min(prescription, ledger)
        case let (prescription?, nil): return prescription
        case let (nil, ledger?): return ledger
        case (nil, nil): return nil
        }
    }
}

// MARK: - Plan usage and future projection

private extension MedicationInventoryForecast {
    func historicalUsage(
        from start: Date,
        to end: Date,
        plans: [NormalizedPlan],
        usage: UsageBasis,
        issues: inout [MedicationInventoryForecastIssue]
    ) -> HistoricalUsage? {
        guard end >= start else { return nil }
        guard end > start else {
            return HistoricalUsage(quantity: 0, sessionCount: 0, planVersionIDs: [])
        }

        var cursor = start
        var total = Decimal.zero
        var sessionCount = 0
        var usedPlanIDs: [String] = []

        for plan in plans where overlaps(plan.source, start: start, end: end) {
            let phaseStart = max(cursor, plan.source.effectiveFrom)
            if phaseStart > cursor {
                issues.append(issue(.plan, .planCoverageGap, recordID: plan.source.id))
                return nil
            }
            let phaseEnd = minDate(end, plan.source.effectiveUntil)
            guard phaseEnd > phaseStart else { continue }
            guard let amount = plan.amount(for: usage) else {
                let code: MedicationInventoryForecastIssueCode = usage == .target
                    ? .missingTargetPerSession
                    : .missingMaximumPerSession
                issues.append(
                    issue(
                        .plan,
                        code,
                        recordID: plan.source.id,
                        field: usage == .target ? "targetPerSession" : "maximumPerSession"
                    )
                )
                return nil
            }
            guard let dates = scheduledDates(
                for: plan.source.schedule,
                from: phaseStart,
                to: phaseEnd
            ) else {
                appendScheduleIssue(for: plan.source, to: &issues)
                return nil
            }
            total += amount * Decimal(dates.count)
            sessionCount += dates.count
            if !dates.isEmpty {
                usedPlanIDs.append(plan.source.id)
            }
            cursor = phaseEnd
            if cursor >= end { break }
        }

        guard cursor >= end else {
            issues.append(issue(.plan, .planCoverageGap))
            return nil
        }
        return HistoricalUsage(
            quantity: total,
            sessionCount: sessionCount,
            planVersionIDs: stableUnique(usedPlanIDs)
        )
    }

    func project(
        quantity: Decimal,
        from start: Date,
        plans: [NormalizedPlan],
        usage: UsageBasis,
        issues: inout [MedicationInventoryForecastIssue]
    ) throws -> MedicationInventoryProjection? {
        if quantity <= 0 {
            return MedicationInventoryProjection(fullTreatmentSessions: 0, runoutAt: start)
        }

        let horizon = start.addingTimeInterval(TimeInterval(forecastHorizonDays) * 86_400)
        let futurePlans = plans.filter { plan in
            plan.source.effectiveUntil == nil || plan.source.effectiveUntil! > start
        }
        guard !futurePlans.isEmpty else {
            issues.append(issue(.plan, .planCoverageGap))
            return nil
        }

        var cursor = start
        var remaining = quantity
        var completedSessions = 0

        for plan in futurePlans {
            if plan.source.effectiveFrom > cursor {
                issues.append(issue(.plan, .planCoverageGap, recordID: plan.source.id))
                return nil
            }

            let phaseStart = max(cursor, plan.source.effectiveFrom)
            let phaseEnd = minDate(horizon, plan.source.effectiveUntil)
            guard phaseEnd > phaseStart, let amount = plan.amount(for: usage) else {
                return nil
            }

            if case .irregular = plan.source.schedule {
                if plan.source.effectiveUntil == nil {
                    return MedicationInventoryProjection(
                        fullTreatmentSessions: decimalFloor(remaining / amount),
                        runoutAt: nil
                    )
                }
                return nil
            }

            guard let dates = scheduledDates(
                for: plan.source.schedule,
                from: phaseStart,
                to: phaseEnd
            ) else {
                return nil
            }

            for date in dates {
                if remaining < amount {
                    return MedicationInventoryProjection(
                        fullTreatmentSessions: completedSessions,
                        runoutAt: date
                    )
                }
                remaining -= amount
                completedSessions += 1
                if remaining == 0 {
                    return MedicationInventoryProjection(
                        fullTreatmentSessions: completedSessions,
                        runoutAt: date
                    )
                }
            }

            cursor = phaseEnd
            if cursor >= horizon { break }
        }

        let hasOpenEndedCoverage = futurePlans.last?.source.effectiveUntil == nil
        if hasOpenEndedCoverage {
            issues.append(issue(.engine, .forecastHorizonExceeded))
        } else {
            issues.append(issue(.plan, .planCoverageGap))
        }
        return nil
    }

    func scheduledDates(
        for schedule: MedicationInventorySchedule,
        from start: Date,
        to end: Date
    ) -> [Date]? {
        guard end > start else { return [] }

        let hour: Int
        let minute: Int
        let timeZoneIdentifier: String
        let weekdays: Set<Int>?
        switch schedule {
        case .daily(let scheduledHour, let scheduledMinute, let identifier):
            hour = scheduledHour
            minute = scheduledMinute
            timeZoneIdentifier = identifier
            weekdays = nil
        case .selectedWeekdays(
            let scheduledWeekdays,
            let scheduledHour,
            let scheduledMinute,
            let identifier
        ):
            hour = scheduledHour
            minute = scheduledMinute
            timeZoneIdentifier = identifier
            weekdays = Set(scheduledWeekdays)
        case .irregular:
            return nil
        }

        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone

        var day = calendar.startOfDay(for: start)
        let finalDay = calendar.startOfDay(for: end)
        var result: [Date] = []

        while day <= finalDay {
            let weekday = calendar.component(.weekday, from: day)
            if weekdays == nil || weekdays!.contains(weekday),
               let scheduled = scheduledDate(
                    onLocalDay: day,
                    hour: hour,
                    minute: minute,
                    calendar: calendar
               ),
               scheduled >= start,
               scheduled < end {
                result.append(scheduled)
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
                  nextDay > day else {
                break
            }
            day = nextDay
        }
        return result
    }

    func scheduledDate(
        onLocalDay day: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.era, .year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = calendar.timeZone

        if let exact = calendar.date(from: components),
           calendar.isDate(exact, inSameDayAs: day) {
            return exact
        }

        var match = DateComponents()
        match.hour = hour
        match.minute = minute
        match.second = 0
        match.timeZone = calendar.timeZone
        let searchStart = day.addingTimeInterval(-1)
        guard let adjusted = calendar.nextDate(
            after: searchStart,
            matching: match,
            matchingPolicy: .nextTimePreservingSmallerComponents,
            repeatedTimePolicy: .first,
            direction: .forward
        ), calendar.isDate(adjusted, inSameDayAs: day) else {
            return nil
        }
        return adjusted
    }

    func appendScheduleIssue(
        for plan: MedicationInventoryPlanVersion,
        to issues: inout [MedicationInventoryForecastIssue]
    ) {
        switch plan.schedule {
        case .irregular:
            issues.append(
                issue(
                    .plan,
                    .irregularSchedule,
                    recordID: plan.id,
                    field: "schedule"
                )
            )
        case .daily(_, _, let identifier),
             .selectedWeekdays(_, _, _, let identifier):
            if TimeZone(identifier: identifier) == nil {
                issues.append(
                    issue(
                        .plan,
                        .unknownTimeZone,
                        recordID: plan.id,
                        field: "schedule"
                    )
                )
            }
        }
    }
}

// MARK: - Early-bottle review

private extension MedicationInventoryForecast {
    func evaluateBottleAction(
        request: MedicationInventoryForecastRequest,
        plans: [NormalizedPlan],
        issues: inout [MedicationInventoryForecastIssue]
    ) throws -> MedicationInventoryEarlyBottleReview? {
        guard let action = request.proposedBottleAction else { return nil }

        switch action {
        case .receiveUnopened(let containerID):
            var localIssues: [MedicationInventoryForecastIssue] = []
            if request.containers.first(where: { $0.id == containerID }) == nil {
                localIssues.append(
                    issue(
                        .inventory,
                        .proposedContainerNotFound,
                        recordID: containerID
                    )
                )
            }
            issues.append(contentsOf: localIssues)
            return MedicationInventoryEarlyBottleReview(
                classification: .notApplicable,
                previousContainerID: nil,
                availableQuantity: nil,
                remainingAtTarget: nil,
                remainingAtMaximum: nil,
                ledgerRemaining: nil,
                tolerance: nil,
                scheduledTreatmentSessions: nil,
                planVersionIDs: [],
                issues: sortedUniqueIssues(localIssues)
            )

        case .start(let containerID, let previousContainerID, let startAt):
            var localIssues: [MedicationInventoryForecastIssue] = []
            guard request.containers.contains(where: { $0.id == containerID }) else {
                localIssues.append(
                    issue(
                        .inventory,
                        .proposedContainerNotFound,
                        recordID: containerID
                    )
                )
                issues.append(contentsOf: localIssues)
                return incompleteBottleReview(
                    previousContainerID: previousContainerID,
                    unit: request.calculationUnit,
                    issues: localIssues
                )
            }
            guard let previous = request.containers.first(where: { $0.id == previousContainerID }) else {
                localIssues.append(
                    issue(
                        .inventory,
                        .previousContainerNotFound,
                        recordID: previousContainerID
                    )
                )
                issues.append(contentsOf: localIssues)
                return incompleteBottleReview(
                    previousContainerID: previousContainerID,
                    unit: request.calculationUnit,
                    issues: localIssues
                )
            }
            guard let openedAt = previous.openedAt else {
                localIssues.append(
                    issue(
                        .inventory,
                        .missingOpenedAt,
                        recordID: previous.id,
                        field: "openedAt"
                    )
                )
                issues.append(contentsOf: localIssues)
                return incompleteBottleReview(
                    previousContainerID: previous.id,
                    unit: request.calculationUnit,
                    issues: localIssues
                )
            }
            guard startAt >= openedAt else {
                throw MedicationInventoryForecastError.invalidBottleActionTimeline(
                    containerID: previous.id
                )
            }
            guard let available = try availableQuantity(
                for: previous,
                at: startAt,
                request: request,
                issues: &localIssues
            ) else {
                issues.append(contentsOf: localIssues)
                return incompleteBottleReview(
                    previousContainerID: previous.id,
                    unit: request.calculationUnit,
                    issues: localIssues
                )
            }

            guard let targetUse = historicalUsage(
                from: openedAt,
                to: startAt,
                plans: plans,
                usage: .target,
                issues: &localIssues
            ), let maximumUse = historicalUsage(
                from: openedAt,
                to: startAt,
                plans: plans,
                usage: .maximum,
                issues: &localIssues
            ) else {
                issues.append(contentsOf: localIssues)
                return incompleteBottleReview(
                    previousContainerID: previous.id,
                    available: available,
                    unit: request.calculationUnit,
                    issues: localIssues
                )
            }

            let planIDs = stableUnique(targetUse.planVersionIDs + maximumUse.planVersionIDs)
            guard let tolerance = try tolerance(
                previousContainer: previous,
                applicablePlanIDs: planIDs,
                at: startAt,
                request: request,
                plans: plans,
                issues: &localIssues
            ) else {
                issues.append(contentsOf: localIssues)
                return incompleteBottleReview(
                    previousContainerID: previous.id,
                    available: available,
                    unit: request.calculationUnit,
                    planVersionIDs: planIDs,
                    issues: localIssues
                )
            }

            let remainingAtTarget = available - targetUse.quantity
            let remainingAtMaximum = available - maximumUse.quantity
            let ledger = try bottleLedgerRemaining(
                container: previous,
                available: available,
                from: openedAt,
                to: startAt,
                request: request,
                issues: &localIssues
            )

            let classification: MedicationInventoryEarlyBottleClassification
            if remainingAtMaximum > tolerance {
                classification = .strongWarning
            } else if remainingAtTarget > tolerance {
                classification = .caution
            } else {
                classification = .noWarning
            }

            let sortedLocalIssues = sortedUniqueIssues(localIssues)
            issues.append(contentsOf: sortedLocalIssues)
            let unit = request.calculationUnit
            return MedicationInventoryEarlyBottleReview(
                classification: classification,
                previousContainerID: previous.id,
                availableQuantity: MedicationInventoryAmount(value: available, unit: unit),
                remainingAtTarget: MedicationInventoryAmount(value: remainingAtTarget, unit: unit),
                remainingAtMaximum: MedicationInventoryAmount(value: remainingAtMaximum, unit: unit),
                ledgerRemaining: ledger.map { MedicationInventoryAmount(value: $0, unit: unit) },
                tolerance: MedicationInventoryAmount(value: tolerance, unit: unit),
                scheduledTreatmentSessions: targetUse.sessionCount,
                planVersionIDs: planIDs,
                issues: sortedLocalIssues
            )
        }
    }

    func incompleteBottleReview(
        previousContainerID: String,
        available: Decimal? = nil,
        unit: AmountUnit,
        planVersionIDs: [String] = [],
        issues: [MedicationInventoryForecastIssue]
    ) -> MedicationInventoryEarlyBottleReview {
        MedicationInventoryEarlyBottleReview(
            classification: .reviewRequired,
            previousContainerID: previousContainerID,
            availableQuantity: available.map {
                MedicationInventoryAmount(value: $0, unit: unit)
            },
            remainingAtTarget: nil,
            remainingAtMaximum: nil,
            ledgerRemaining: nil,
            tolerance: nil,
            scheduledTreatmentSessions: nil,
            planVersionIDs: planVersionIDs,
            issues: sortedUniqueIssues(issues)
        )
    }

    func availableQuantity(
        for container: MedicationInventoryContainer,
        at date: Date,
        request: MedicationInventoryForecastRequest,
        issues: inout [MedicationInventoryForecastIssue]
    ) throws -> Decimal? {
        guard let starting = container.startingUsableQuantity else {
            issues.append(
                issue(
                    .inventory,
                    .missingStartingQuantity,
                    recordID: container.id,
                    field: "startingUsableQuantity"
                )
            )
            return nil
        }
        guard var result = try convert(
            starting,
            to: request.calculationUnit,
            conversions: request.conversions,
            recordID: container.id,
            field: "startingUsableQuantity"
        ) else {
            issues.append(
                issue(
                    .plan,
                    .missingUnitConversion,
                    recordID: container.id,
                    field: "startingUsableQuantity"
                )
            )
            return nil
        }
        for adjustment in request.adjustments
            where adjustment.containerID == container.id && adjustment.occurredAt <= date {
            guard let normalized = try convert(
                adjustment.quantityChange,
                to: request.calculationUnit,
                conversions: request.conversions,
                recordID: adjustment.id,
                field: "quantityChange"
            ) else {
                issues.append(
                    issue(
                        .plan,
                        .missingUnitConversion,
                        recordID: adjustment.id,
                        field: "quantityChange"
                    )
                )
                return nil
            }
            result += normalized
        }
        return result
    }

    func tolerance(
        previousContainer: MedicationInventoryContainer,
        applicablePlanIDs: [String],
        at date: Date,
        request: MedicationInventoryForecastRequest,
        plans: [NormalizedPlan],
        issues: inout [MedicationInventoryForecastIssue]
    ) throws -> Decimal? {
        let applicablePlans: [NormalizedPlan]
        if applicablePlanIDs.isEmpty {
            applicablePlans = plans.filter { $0.source.isEffective(at: date) }
        } else {
            applicablePlans = plans.filter { applicablePlanIDs.contains($0.source.id) }
        }
        let perDoseValues = applicablePlans.compactMap(\.targetPerDose)
        guard let perDose = perDoseValues.max() else { return nil }
        guard let starting = previousContainer.startingUsableQuantity,
              let normalizedStarting = try convert(
                starting,
                to: request.calculationUnit,
                conversions: request.conversions,
                recordID: previousContainer.id,
                field: "startingUsableQuantity"
              ) else {
            return nil
        }

        let policy = request.tolerancePolicy
        guard let increment = try convert(
            policy.smallestMeaningfulIncrement,
            to: request.calculationUnit,
            conversions: request.conversions,
            recordID: policy.id,
            field: "smallestMeaningfulIncrement"
        ) else {
            issues.append(
                issue(
                    .plan,
                    .missingUnitConversion,
                    recordID: policy.id,
                    field: "smallestMeaningfulIncrement"
                )
            )
            return nil
        }
        let measurement: Decimal
        if let configured = policy.measurementTolerance {
            guard let normalized = try convert(
                configured,
                to: request.calculationUnit,
                conversions: request.conversions,
                recordID: policy.id,
                field: "measurementTolerance"
            ) else {
                issues.append(
                    issue(
                        .plan,
                        .missingUnitConversion,
                        recordID: policy.id,
                        field: "measurementTolerance"
                    )
                )
                return nil
            }
            measurement = normalized
        } else {
            measurement = 0
        }
        let percent = normalizedStarting * policy.percentOfStartingQuantity
        return roundUp(max(perDose, percent, measurement), increment: increment)
    }

    func bottleLedgerRemaining(
        container: MedicationInventoryContainer,
        available: Decimal,
        from start: Date,
        to end: Date,
        request: MedicationInventoryForecastRequest,
        issues: inout [MedicationInventoryForecastIssue]
    ) throws -> Decimal? {
        var consumed = Decimal.zero
        var complete = true
        for allocation in request.allocations
            where allocation.occurredAt >= start && allocation.occurredAt < end {
            guard let containerID = allocation.containerID else {
                issues.append(
                    issue(
                        .inventory,
                        .unallocatedDose,
                        recordID: allocation.id,
                        field: "containerID"
                    )
                )
                complete = false
                continue
            }
            guard containerID == container.id else { continue }
            guard let quantity = allocation.quantity else {
                issues.append(
                    issue(
                        .doseHistory,
                        .missingDoseAmount,
                        recordID: allocation.id,
                        field: "quantity"
                    )
                )
                complete = false
                continue
            }
            guard let normalized = try convert(
                quantity,
                to: request.calculationUnit,
                conversions: request.conversions,
                recordID: allocation.id,
                field: "quantity"
            ) else {
                issues.append(
                    issue(
                        .plan,
                        .missingUnitConversion,
                        recordID: allocation.id,
                        field: "quantity"
                    )
                )
                complete = false
                continue
            }
            consumed += normalized
        }
        return complete ? available - consumed : nil
    }
}

// MARK: - Conversion, issue, and explanation helpers

private extension MedicationInventoryForecast {
    func convert(
        _ amount: MedicationInventoryAmount,
        to targetUnit: AmountUnit,
        conversions: [MedicationInventoryUnitConversion],
        recordID: String,
        field: String
    ) throws -> Decimal? {
        if amount.unit == targetUnit { return amount.value }
        guard let conversionID = amount.conversionID,
              let conversion = conversions.first(where: { $0.id == conversionID }) else {
            return nil
        }
        guard (conversion.fromUnit == amount.unit && conversion.toUnit == targetUnit)
            || (conversion.toUnit == amount.unit && conversion.fromUnit == targetUnit) else {
            throw MedicationInventoryForecastError.invalidConversion(conversion.id)
        }
        let result: Decimal
        if conversion.fromUnit == amount.unit {
            result = amount.value * conversion.multiplier
        } else {
            result = amount.value / conversion.multiplier
        }
        guard result.isFinite else {
            throw MedicationInventoryForecastError.invalidAmount(
                recordID: recordID,
                field: field
            )
        }
        return result
    }

    func issue(
        _ domain: MedicationInventoryForecastIssueDomain,
        _ code: MedicationInventoryForecastIssueCode,
        recordID: String? = nil,
        field: String? = nil
    ) -> MedicationInventoryForecastIssue {
        MedicationInventoryForecastIssue(
            domain: domain,
            code: code,
            recordID: recordID,
            field: field
        )
    }

    func sortedUniqueIssues(
        _ issues: [MedicationInventoryForecastIssue]
    ) -> [MedicationInventoryForecastIssue] {
        Array(Set(issues)).sorted {
            let left = [$0.domain.rawValue, $0.code.rawValue, $0.recordID ?? "", $0.field ?? ""]
            let right = [$1.domain.rawValue, $1.code.rawValue, $1.recordID ?? "", $1.field ?? ""]
            return left.lexicographicallyPrecedes(right)
        }
    }

    func completeness(
        for issues: [MedicationInventoryForecastIssue]
    ) -> MedicationInventoryForecastCompleteness {
        if issues.contains(where: { $0.domain == .plan || $0.domain == .engine }) {
            return .planNeedsReview
        }
        if issues.contains(where: { $0.domain == .inventory }) {
            return .inventoryNeedsReview
        }
        if issues.contains(where: { $0.domain == .doseHistory }) {
            return .planBased
        }
        return .complete
    }

    func provenance(
        for request: MedicationInventoryForecastRequest,
        asOf: Date
    ) -> MedicationInventoryForecastProvenance {
        let inputIDs = (
            request.containers.map(\.id)
                + request.adjustments.map(\.id)
                + request.allocations.map(\.id)
        ).sorted()
        let planIDs = request.planVersions.sorted(by: planSort).map(\.id)
        let referencedConversionIDs = referencedConversionIDs(in: request)
        let conversionVersions = Dictionary(
            uniqueKeysWithValues: request.conversions
                .filter { referencedConversionIDs.contains($0.id) }
                .map { ($0.id, $0.version) }
        )
        return MedicationInventoryForecastProvenance(
            asOf: asOf,
            inputRecordIDs: inputIDs,
            planVersionIDs: planIDs,
            conversionIDs: referencedConversionIDs,
            conversionVersions: conversionVersions,
            tolerancePolicyID: request.tolerancePolicy.id,
            tolerancePolicyVersion: request.tolerancePolicy.version
        )
    }

    func referencedConversionIDs(
        in request: MedicationInventoryForecastRequest
    ) -> [String] {
        var amounts: [MedicationInventoryAmount] = []
        for plan in request.planVersions {
            amounts.append(contentsOf: [
                plan.targetPerDose,
                plan.maximumPerDose,
                plan.targetPerSession,
                plan.maximumPerSession
            ].compactMap { $0 })
        }
        amounts.append(contentsOf: request.containers.compactMap(\.startingUsableQuantity))
        amounts.append(contentsOf: request.adjustments.map(\.quantityChange))
        amounts.append(contentsOf: request.allocations.compactMap(\.quantity))
        amounts.append(request.tolerancePolicy.smallestMeaningfulIncrement)
        if let measurement = request.tolerancePolicy.measurementTolerance {
            amounts.append(measurement)
        }
        return Array(Set(amounts.compactMap(\.conversionID))).sorted()
    }

    func explanation(
        request: MedicationInventoryForecastRequest,
        asOf: Date,
        completeness: MedicationInventoryForecastCompleteness,
        issues: [MedicationInventoryForecastIssue],
        usableBeforeConsumption: Decimal?,
        orderedNotReceived: Decimal?,
        targetRemaining: Decimal?,
        maximumRemaining: Decimal?,
        ledgerRemaining: Decimal?,
        activeRemaining: Decimal?,
        targetProjection: MedicationInventoryProjection?,
        maximumProjection: MedicationInventoryProjection?,
        ledgerProjection: MedicationInventoryProjection?,
        activeProjection: MedicationInventoryProjection?,
        earlyBottleReview: MedicationInventoryEarlyBottleReview?,
        provenance: MedicationInventoryForecastProvenance
    ) -> MedicationInventoryForecastExplanation {
        let unit = request.calculationUnit.rawValue
        let conversionReferences = provenance.conversionIDs.map { id in
            let version = provenance.conversionVersions[id] ?? "missing"
            return "\(id)@\(version)"
        }.joined(separator: ",")
        var lines = [
            "As of: \(iso8601(asOf))",
            "Calculation unit: \(unit)",
            "Plan versions: \(provenance.planVersionIDs.joined(separator: ","))",
            "Conversions: \(conversionReferences)",
            "Tolerance policy: \(provenance.tolerancePolicyID)@\(provenance.tolerancePolicyVersion)"
        ]

        appendAmountLine("Usable before consumption", usableBeforeConsumption, unit: unit, to: &lines)
        appendAmountLine("Ordered, not received", orderedNotReceived, unit: unit, to: &lines)
        appendAmountLine("Prescription target remaining", targetRemaining, unit: unit, to: &lines)
        appendAmountLine("Prescription maximum remaining", maximumRemaining, unit: unit, to: &lines)
        appendAmountLine("Ledger remaining", ledgerRemaining, unit: unit, to: &lines)
        appendAmountLine("Active conservative remaining", activeRemaining, unit: unit, to: &lines)
        appendProjectionLine("Target projection", targetProjection, to: &lines)
        appendProjectionLine("Maximum projection", maximumProjection, to: &lines)
        appendProjectionLine("Ledger projection", ledgerProjection, to: &lines)
        appendProjectionLine("Active projection", activeProjection, to: &lines)

        if let review = earlyBottleReview {
            lines.append("Early-bottle classification: \(review.classification.rawValue)")
            if let remaining = review.remainingAtTarget {
                lines.append("Early-bottle target remainder: \(decimalString(remaining.value)) \(unit)")
            }
            if let remaining = review.remainingAtMaximum {
                lines.append("Early-bottle maximum remainder: \(decimalString(remaining.value)) \(unit)")
            }
            if let tolerance = review.tolerance {
                lines.append("Inventory discrepancy tolerance: \(decimalString(tolerance.value)) \(unit)")
            }
        }

        if issues.isEmpty {
            lines.append("Issues: none")
        } else {
            for item in issues {
                let record = item.recordID.map { " record=\($0)" } ?? ""
                let field = item.field.map { " field=\($0)" } ?? ""
                lines.append("Issue: \(item.domain.rawValue).\(item.code.rawValue)\(record)\(field)")
            }
        }

        let summary: String
        switch completeness {
        case .complete:
            summary = "Inventory forecast is complete for the supplied records."
        case .planBased:
            summary = "Inventory forecast uses the entered plan because dose history is incomplete."
        case .inventoryNeedsReview:
            summary = "Inventory records need review before the ledger forecast is complete."
        case .planNeedsReview:
            summary = "The entered plan, schedule, or unit conversion needs review."
        }
        return MedicationInventoryForecastExplanation(summary: summary, lines: lines)
    }

    func appendAmountLine(
        _ label: String,
        _ value: Decimal?,
        unit: String,
        to lines: inout [String]
    ) {
        if let value {
            lines.append("\(label): \(decimalString(value)) \(unit)")
        } else {
            lines.append("\(label): unavailable")
        }
    }

    func appendProjectionLine(
        _ label: String,
        _ projection: MedicationInventoryProjection?,
        to lines: inout [String]
    ) {
        guard let projection else {
            lines.append("\(label): unavailable")
            return
        }
        let sessions = projection.fullTreatmentSessions.map(String.init) ?? "unknown"
        let runout = projection.runoutAt.map(iso8601) ?? "unavailable"
        lines.append("\(label): sessions=\(sessions) runout=\(runout)")
    }

    func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

// MARK: - Small deterministic helpers

private extension MedicationInventoryForecast {
    func usableContainers(
        _ containers: [MedicationInventoryContainer],
        at date: Date
    ) -> [MedicationInventoryContainer] {
        containers.filter { isContainerUsable($0, at: date) }
    }

    func isContainerUsable(
        _ container: MedicationInventoryContainer,
        at date: Date
    ) -> Bool {
        guard container.state.isUsableOnHand else { return false }
        return container.receivedAt.map { $0 <= date } ?? true
    }

    func planSort(
        _ left: MedicationInventoryPlanVersion,
        _ right: MedicationInventoryPlanVersion
    ) -> Bool {
        if left.effectiveFrom != right.effectiveFrom {
            return left.effectiveFrom < right.effectiveFrom
        }
        return left.id < right.id
    }

    func overlaps(
        _ plan: MedicationInventoryPlanVersion,
        start: Date,
        end: Date
    ) -> Bool {
        plan.effectiveFrom < end && (plan.effectiveUntil == nil || plan.effectiveUntil! > start)
    }

    func minDate(_ required: Date, _ optional: Date?) -> Date {
        optional.map { min(required, $0) } ?? required
    }

    func nonnegative(_ value: Decimal) -> Decimal {
        max(0, value)
    }

    func decimalFloor(_ value: Decimal) -> Int {
        var source = value
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &source, 0, .down)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    func roundUp(_ value: Decimal, increment: Decimal) -> Decimal {
        var quotient = value / increment
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &quotient, 0, .up)
        return rounded * increment
    }

    func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
