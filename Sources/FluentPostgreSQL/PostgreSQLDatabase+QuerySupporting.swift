import Async
import CodableKit
import FluentSQL
import Foundation

/// Adds ability to do basic Fluent queries using a `PostgreSQLDatabase`.
extension PostgreSQLDatabase: QuerySupporting {
    /// See `QuerySupporting.execute`
    public static func execute<I, D>(query: DatabaseQuery<PostgreSQLDatabase>, into stream: I, on connection: PostgreSQLConnection)
        where I: Async.InputStream, D: Decodable, D == I.Input
    {
        let future = Future<Void>.flatMap {
            // Convert Fluent `DatabaseQuery` to generic FluentSQL `DataQuery`
            var (sqlQuery, bindValues) = query.makeDataQuery()

            // If the query has an Encodable model attached serialize it.
            // Dictionary keys should be added to the DataQuery as columns.
            // Dictionary values should be added to the parameterized array.
            let modelData: [PostgreSQLData]
            if let model = query.data {
                let encoder = PostgreSQLRowEncoder()
                try model.encode(to: encoder)
                sqlQuery.columns += encoder.data.keys.map { key in
                    return DataColumn(table: query.entity, name: key)
                }
                modelData = .init(encoder.data.values)
            } else {
                modelData = []
            }

            // Create a PostgreSQL-flavored SQL serializer to create a SQL string
            let sqlSerializer = PostgreSQLSQLSerializer()
            let sqlString = sqlSerializer.serialize(data: sqlQuery)

            // Combine the query data with bind values from filters.
            // All bind values must come _after_ the columns section of the query.
            let parameters = try modelData + bindValues.map { bind in
                let encodable = bind.encodable
                guard let convertible = encodable as? PostgreSQLDataCustomConvertible else {
                    let type = Swift.type(of: encodable)
                    throw PostgreSQLError(
                        identifier: "convertible",
                        reason: "Unsupported encodable type: \(type)",
                        suggestedFixes: [
                            "Conform \(type) to PostgreSQLDataCustomConvertible"
                        ],
                        source: .capture()
                    )
                }
                return try convertible.convertToPostgreSQLData()
            }

            // Create a push stream to accept the psql output
            // FIXME: connect streams directly instead?
            let pushStream = PushStream<D>()
            pushStream.output(to: stream)

            // Run the query
            return try connection.query(sqlString, parameters) { row in
                do {
                    let decoded = try D.init(from: PostgreSQLRowDecoder(row: row))
                    pushStream.push(decoded)
                } catch {
                    pushStream.error(error)
                }
            }
        }

        /// Convert Future completion / error to stream
        future.do {
            // Query is complete
            stream.close()
        }.catch { error in
            // Query failed
            stream.error(error)
            stream.close()
        }
    }

    /// See `QuerySupporting.modelEvent`
    public static func modelEvent<M>(event: ModelEvent, model: M, on connection: PostgreSQLConnection) -> Future<M>
        where PostgreSQLDatabase == M.Database, M: Model
    {
        switch event {
        case .willCreate:
            if M.ID.self == UUID.self {
                var model = model
                model.fluentID = UUID() as? M.ID
                return Future(model)
            }
        case .didCreate:
            if M.ID.self == Int.self {
                return connection.simpleQuery("SELECT LASTVAL();").map(to: M.self) { row in
                    var model = model
                    try model.fluentID = row[0]["lastval"]?.decode(Int.self) as? M.ID
                    return model
                }
            }
        default: break
        }
        
        return Future(model)
    }
}
