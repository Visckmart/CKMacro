# ``CKMacro``

Swift macro that allows classes to be encoded to- and decoded from- a `CKRecord` from `CloudKit`.

The goal of this macro is to speed up the CloudKit setup process by generating high-quality boilerplate code. Quite a few advanced uses are supported, but, at the end of the day, you can use the *Expand Macro* feature from Xcode to see the generated code, copy and use it as a foundation to your own implementation in a matter of seconds.

- Experiment: **Proof of concept:** This macro was developed and tested as an experiment to see the viability of this approach in practice.
Although at the moment it is working really well and is organized to some degree, the implementation could have problems, might stop being maintained, or might have source-breaking changes depending on the direction I want to take it.


## Features
- Capable of handling every [`CKRecord`](https://developer.apple.com/documentation/cloudkit/ckrecord) supported type (strings, numbers, data, location, ...)
- Supports enums with raw values, [`Codable`](https://developer.apple.com/documentation/swift/codable) types and [`NSCoding`](https://developer.apple.com/documentation/foundation/nscoding)-conforming types
- A [`CKRecordType`](https://developer.apple.com/documentation/cloudkit/ckrecord/3003387-recordtype) can be specified if you don't want to use the name of the class
- The [`recordName`](https://developer.apple.com/documentation/cloudkit/ckrecord/id/1500973-recordname) (which represents the CKRecord's "key") can be associated with any `String` property
- Flexible way of handling relationships, enabling transparent translation from the class' most ergonomic modeling to the ideal CloudKit modelling – [as recomended by the official CloudKit documentation](https://developer.apple.com/documentation/cloudkit/ckrecord/reference#1669672)
- The encoding and decoding can be customized and interrupted by using a delegate protocol
- Diagnostics guide your way through using the macro and are extra helpful by highlight any problems it encounters


## Usage
[Add this repository as a Swift Package to your project.](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)

1. Add the `@ConvertibleToCKRecord` macro to the top of your class declaration, before the `class` keyword
2. Add the `@CKRecordName` macro to a property of type `String` to make it the identifier (`recordName`) of the records that represent your class in CloudKit

* Attention: Pay attention to any error messages shown by the macro, they'll guide you to a working implementation.

- To save an instance use `try await myInstance.saveToCKDatabase(myDatabase)`
- To initialize an instance, fetch the `CKRecord` using CloudKit as usual and pass it to the initializer like `try await MyClass(fromCKRecord: fetchedCKRecord, fetchingRelationshipsFrom: myDatabase)`

- To encode an instance and its properties to CKRecords use `try value.convertToCKRecord()`


## Advanced Usage
### Database References
You can use the `@CKReference` macro to mark properties that store references to other classes.

To make it work, the other classes must also be marked with the `@ConvertibleToCKRecord` macro.

There are two ways to represent a reference:
1. By storing a reference to the recordName of the property (`.referencesProperty`)
2. By making the property store a reference to the current class, its owner (`.isReferencedByProperty`)

Option 1 is the most direct representation of the class as modelled in Swift, while option 2 is the recommented approach on the `CKRecord.Reference` documentation page.

The `.isReferencedByProperty` can also be customized by setting the name of the field that will store the reference to their owner.


### Additional Property Types
There are 4 additional property types to choose from using the `@CKPropertyType` macro, they are:
- `rawValue` is intended to use with enums that have a [raw value](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/enumerations/#Raw-Values), allowing their values to be stored.
- `codable` can be used with `Codable` types. Encodes the value and saves it in a CloudKit field with the [`Data`](https://developer.apple.com/documentation/foundation/data) type.
- `nsCoding` can be used with types that conform to [`NSCoding`](https://developer.apple.com/documentation/foundation/nscoding). Encodes the value and saves it in a CloudKit field with the `Data` type.
- `ignored` does not encode nor decode the values. Has to be optional or have a default value, since the every Swift initializer has to initialize all properties and this one is going to be ignored.


### Delegate
Make your class conform to the ``CKRecordSynthetizationDelegate`` to customize the encoding and decoding processes.

- By overloading the `willFinishEncoding(ckRecord: CKRecord)` you can get and set the `ckRecord`'s properties before its returned from the `convertToCKRecord` method, which is also called by the `saveToCKDatabase` method.

- By overloading the `willFinishDecoding(ckRecord: CKRecord)` you can get properties from the `ckRecord` and use them to set new values to the instance's properties during the `init(fromCKRecord:fetchingRelationshipsFrom:)` call.


### Additional methods
At the moment there are some helpful methods implemented alongside the macro, but I cannot assure that they'll stay like this. At the moment they are:

The method `fetch(withRecordName recordName: String, fromCKDatabase database: CKDatabase) async throws -> Self` can be used to fetch instances directly by doing `try await MyClass.fetch(withRecordName: "id", fromCKDatabase: myDatabase)`.

And the method `fetchAll(fromCKDatabase database: CKDatabase) async throws -> [Self]` can be used to fetch all instances of the specific class from the database, by doing `try await MyClass.fetchAll(fromCKDatabase: myDatabase)`.
