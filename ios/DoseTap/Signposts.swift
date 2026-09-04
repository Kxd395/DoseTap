//
//  Signposts.swift
//  DoseTap
//
//  Lightweight os.signpost instrumentation for profiling dose actions
//  in Instruments (System Trace / Points of Interest / Custom instruments).
//
//  Signposts are emitted unconditionally — they have near-zero runtime cost
//  when nothing is listening and produce rich timeline data when Instruments
//  is attached. Per Apple guidance, all arguments are marked .public because
//  no user PHI is ever included (only action names and window states).
//

import Foundation
import os
import os.signpost

/// Subsystem used for all DoseTap signposts. Matches the `com.dosetap.app`
/// convention used by every other OSLog in the app so Instruments can
/// correlate signposts and log messages in a single filter.
private let signpostSubsystem = "com.dosetap.app"

enum DoseSignpost {
    /// Top-level log used by Instruments to group signposts.
    static let log = OSLog(subsystem: signpostSubsystem, category: "DoseActions")

    /// High-level user-visible action categories. Kept as a small fixed set
    /// so Instruments filter menus stay useful.
    enum Category: String {
        case takeDose1
        case takeDose2
        case skipDose
        case snooze
        case morningCheckIn
        case sessionTransition
    }

    /// Begin an interval signpost; returns the ID to pair with `end`.
    /// Use for async operations where start/end are meaningfully separated
    /// (e.g. takeDose2 which also schedules alarms and writes to storage).
    @inline(__always)
    static func begin(_ category: Category, _ detail: String = "") -> OSSignpostID {
        let id = OSSignpostID(log: log)
        if detail.isEmpty {
            os_signpost(.begin, log: log, name: staticName(for: category), signpostID: id)
        } else {
            os_signpost(.begin, log: log, name: staticName(for: category), signpostID: id,
                        "%{public}s", detail)
        }
        return id
    }

    /// End a previously-begun interval signpost.
    @inline(__always)
    static func end(_ category: Category, _ id: OSSignpostID, result: String = "") {
        if result.isEmpty {
            os_signpost(.end, log: log, name: staticName(for: category), signpostID: id)
        } else {
            os_signpost(.end, log: log, name: staticName(for: category), signpostID: id,
                        "%{public}s", result)
        }
    }

    /// Fire a one-shot event signpost (no interval).
    @inline(__always)
    static func event(_ category: Category, _ detail: String = "") {
        if detail.isEmpty {
            os_signpost(.event, log: log, name: staticName(for: category))
        } else {
            os_signpost(.event, log: log, name: staticName(for: category),
                        "%{public}s", detail)
        }
    }

    /// StaticString name for os_signpost. Must be static per Apple's API.
    private static func staticName(for category: Category) -> StaticString {
        switch category {
        case .takeDose1:          return "takeDose1"
        case .takeDose2:          return "takeDose2"
        case .skipDose:           return "skipDose"
        case .snooze:             return "snooze"
        case .morningCheckIn:     return "morningCheckIn"
        case .sessionTransition:  return "sessionTransition"
        }
    }
}
