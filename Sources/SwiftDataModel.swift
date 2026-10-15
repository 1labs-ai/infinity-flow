import Observation
import SwiftData

/// The models spell out what SwiftData's `@Model` macro would generate, so Infinity Flow builds with the Command Line
/// Tools alone (`swift build`): the macro's implementation ships only with Xcode. Each persisted property reads and
/// writes through its backing data and reports access to observation, exactly like the macro's expansion.
///
/// For the same reason, views hold a stored `Query<Model, [Model]>` and read its `wrappedValue` instead of using `@Query`.
///
/// To add a property: declare it with an `init` accessor and a `_name` placeholder like its neighbours, set the
/// placeholder in `init(backingData:)`, and list it in `schemaMetadata`.
protocol ExpandedModel: PersistentModel {
    var _$observationRegistrar: ObservationRegistrar { get }
}

/// Stands in for the storage of a persisted property; the value lives in the backing data.
struct _SwiftDataNoType {}

extension ExpandedModel {
    @_disfavoredOverload
    func read<Value: Decodable>(_ key: KeyPath<Self, Value>) -> Value {
        _$observationRegistrar.access(self, keyPath: key)
        return getValue(forKey: key)
    }

    @_disfavoredOverload
    func write<Value: Encodable>(_ key: KeyPath<Self, Value>, _ value: Value) {
        _$observationRegistrar.withMutation(of: self, keyPath: key) { setValue(forKey: key, to: value) }
    }

    /// A to-one relationship.
    func read<Value: PersistentModel>(_ key: KeyPath<Self, Value?>) -> Value? {
        _$observationRegistrar.access(self, keyPath: key)
        return getValue(forKey: key)
    }

    func write<Value: PersistentModel>(_ key: KeyPath<Self, Value?>, _ value: Value?) {
        _$observationRegistrar.withMutation(of: self, keyPath: key) { setValue(forKey: key, to: value) }
    }

    /// A to-many relationship.
    func read<Value: RelationshipCollection>(_ key: KeyPath<Self, Value>) -> Value {
        _$observationRegistrar.access(self, keyPath: key)
        return getValue(forKey: key)
    }

    func write<Value: RelationshipCollection>(_ key: KeyPath<Self, Value>, _ value: Value) {
        _$observationRegistrar.withMutation(of: self, keyPath: key) { setValue(forKey: key, to: value) }
    }
}
