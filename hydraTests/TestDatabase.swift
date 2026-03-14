import Foundation
import GRDB
@testable import hydra

enum TestDatabase {
    static func make() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue(configuration: .init())
        return try AppDatabase(dbQueue)
    }
}
