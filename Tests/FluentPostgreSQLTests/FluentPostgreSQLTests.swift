import Async
import XCTest
import FluentBenchmark
import FluentPostgreSQL

class FluentPostgreSQLTests: XCTestCase {
    var benchmarker: Benchmarker<PostgreSQLDatabase>!
    var eventLoop: EventLoop!
    var database: PostgreSQLDatabase!

    override func setUp() {
        eventLoop = try! DefaultEventLoop(label: "codes.vapor.postgresql.test")
        database = PostgreSQLDatabase(config: .default())
        benchmarker = Benchmarker(database, on: eventLoop, onFail: XCTFail)
    }

    func testSchema() throws {
        try benchmarker.benchmarkSchema()
    }

    func testModels() throws {
        try benchmarker.benchmarkModels_withSchema()
    }

    func testRelations() throws {
        try benchmarker.benchmarkRelations_withSchema()
    }

    func testTimestampable() throws {
        try benchmarker.benchmarkTimestampable_withSchema()
    }

    func testTransactions() throws {
        try benchmarker.benchmarkTransactions_withSchema()
    }

    func testChunking() throws {
        try benchmarker.benchmarkChunking_withSchema()
    }

    func testAutoincrement() throws {
        try benchmarker.benchmarkAutoincrement_withSchema()
    }

    func testCache() throws {
        try benchmarker.benchmarkCache_withSchema()
    }

    func testJoins() throws {
        try benchmarker.benchmarkJoins_withSchema()
    }

    func testSoftDeletable() throws {
        try benchmarker.benchmarkSoftDeletable_withSchema()
    }

    func testReferentialActions() throws {
        try benchmarker.benchmarkReferentialActions_withSchema()
    }

    func testNestedStruct() throws {
        let conn = try database.makeConnection(on: eventLoop).await(on: eventLoop)
        try? User.revert(on: conn).await(on: eventLoop)
        try User.prepare(on: conn).await(on: eventLoop)
        let user = User(id: nil, name: "Tanner", pet: Pet(name: "Zizek"))
        user.favoriteColors = ["pink", "blue"]
        _ = try user.save(on: conn).await(on: eventLoop)
        if let fetched = try User.query(on: conn).first().await(on: eventLoop) {
            XCTAssertEqual(user.id, fetched.id)
            XCTAssertNil(user.age)
            XCTAssertEqual(fetched.favoriteColors, ["pink", "blue"])
        } else {
            XCTFail()
        }
        try User.revert(on: conn).await(on: eventLoop)
        conn.close()
    }

    func testIndexSupporting() throws {
        try benchmarker.benchmarkIndexSupporting_withSchema()
    }

    func testMinimumViableModelDeclaration() throws {
        /// NOTE: these must never fail to build
        struct Foo: PostgreSQLModel {
            var id: Int?
            var name: String
        }
        final class Bar: PostgreSQLModel {
            var id: Int?
            var name: String
        }
        struct Baz: PostgreSQLUUIDModel {
            var id: UUID?
            var name: String
        }
        final class Qux: PostgreSQLUUIDModel {
            var id: UUID?
            var name: String
        }
    }

    func testDefaultValue() throws {
        database.enableLogging(using: DatabaseLogger(handler: { print($0) }))
        let conn = try database.makeConnection(on: eventLoop).await(on: eventLoop)
        try? DefaultTest.revert(on: conn).await(on: eventLoop)
        try DefaultTest.prepare(on: conn).await(on: eventLoop)
        let test = DefaultTest()
        // _ = try test.save(on: conn).await(on: eventLoop)
        let builder = test.query(on: conn)
        builder.query.data = ["foo": "bar"] // there _must_ be a better way
        builder.query.action = .create
        try builder.execute().await(on: eventLoop)
        if let fetched = try DefaultTest.query(on: conn).first().await(on: eventLoop) {
            XCTAssertNotNil(fetched.date?.value)
        } else {
            XCTFail()
        }
        try DefaultTest.revert(on: conn).await(on: eventLoop)
        conn.close()
    }

    static let allTests = [
        ("testSchema", testSchema),
        ("testModels", testModels),
        ("testRelations", testRelations),
        ("testTimestampable", testTimestampable),
        ("testTransactions", testTransactions),
        ("testChunking", testChunking),
        ("testAutoincrement", testAutoincrement),
        ("testCache", testCache),
        ("testJoins", testJoins),
        ("testSoftDeletable", testSoftDeletable),
        ("testReferentialActions", testReferentialActions),
        ("testIndexSupporting", testIndexSupporting),
        ("testMinimumViableModelDeclaration", testMinimumViableModelDeclaration),
    ]
}

struct PostgreSQLDate: PostgreSQLType, Codable {
    static var postgreSQLDataType: PostgreSQLDataType {
        return .timestamp
    }

    static var postgreSQLDataArrayType: PostgreSQLDataType {
        return ._timestamp
    }

    static var postgreSQLColumn: PostgreSQLColumn {
        return PostgreSQLColumn(type: .timestamp, size: nil, default: "CURRENT_TIMESTAMP")
    }

    var value: Date?

    init(_ value: Date? = nil) {
        self.value = value
    }

    static func convertFromPostgreSQLData(_ data: PostgreSQLData) throws -> PostgreSQLDate {
        return try PostgreSQLDate(Date.convertFromPostgreSQLData(data))
    }

    func convertToPostgreSQLData() throws -> PostgreSQLData {
        return try value?.convertToPostgreSQLData() ?? PostgreSQLData(type: .timestamp, format: .binary, data: nil)
    }
}

struct DefaultTest: PostgreSQLModel, Migration {
    var id: Int?
    var date: PostgreSQLDate?
    var foo: String
    init() {
        self.id = nil
        self.date = nil
        self.foo = "bar'"
    }
}

struct Pet: PostgreSQLJSONType, Codable {
    var name: String
}

final class User: PostgreSQLModel, Migration {
    static let idKey: WritableKeyPath<User, Int?> = \User.id
    var id: Int?
    var name: String
    var age: Int?
    var favoriteColors: [String]
    var pet: Pet

    init(id: Int? = nil, name: String, pet: Pet) {
        self.favoriteColors = []
        self.id = id
        self.name = name
        self.pet = pet
    }
}

