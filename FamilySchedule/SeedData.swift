import Foundation
import SwiftData

// Schedule data no longer lives in code.
// - Live schedule: iCloud (CloudKit), shared with the family.
// - Bulk edits: CSV files in iCloud Drive → Activities → + → Import CSV…
// New devices start empty and pull the shared schedule on first sync.

enum SeedData {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        // Intentionally empty: nothing is seeded, so family devices
        // never create local copies that duplicate the shared schedule.
    }
}
