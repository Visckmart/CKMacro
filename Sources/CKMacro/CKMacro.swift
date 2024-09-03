// The Swift Programming Language
// https://docs.swift.org/swift-book
import Foundation

@_exported import CloudKit

@attached(member, names: named(x),
          named(init(fromCKRecord:fetchingRelationshipsFrom:)), named(convertToCKRecord), named(__recordType),
          named(CKRecordEncodingError), named(CKRecordDecodingError),
          named(__recordID), named(__recordZoneID), named(__recordName), named(__storedCKRecord))
@attached(extension, conformances: SynthesizedCKRecordConvertible)
public macro ConvertibleToCKRecord(recordType: String? = nil, debug: Bool = false) = #externalMacro(module: "CKMacroMacros", type: "ConvertibleToCKRecordMacro")


/// Marks the property that will be used by the `@ConvertibleToCKRecord` macro as the `recordName` field
/// on the generated `CKRecord`s.
///
/// - Remark: This macro can only be attached to properties of `String` type.
@attached(peer)
public macro CKRecordName() = #externalMacro(module: "CKMacroMacros", type: "CKRecordNameMacro")


public enum ReferenceType {
    /// Generates a field on this instance's `CKRecord` with a reference to the `recordName`
    /// of the property.
    case referencesProperty
    
    /// Generates a new field on the CKRecord of the property pointing to this instance's `recordName`.
    /// The name of the field is specified by the argument `named`.
    case isReferencedByProperty(named: String?)
    
    /// Generates a new field on the CKRecord of the property pointing to this instance's `recordName`.
    public static let isReferencedByProperty = isReferencedByProperty(named: nil)
}
/// Marks the property that should act as a reference.
@attached(peer)
public macro CKReference(_ referenceType: ReferenceType) = #externalMacro(module: "CKMacroMacros", type: "RelationshipMarkerMacro")


public enum PropertyType {
    /// Intended to use with enums. Encodes and decodes the value of the enum as its raw value.
    /// The enum type must have a raw value defined.
    case rawValue
    
    /// Intended to use with Codable types.
    /// Encodes and decodes the value as Data.
    case codable
    
    /// Intended to use with types conforming to the NSCoding protocol.
    /// Encodes and decodes the value as Data.
    case nsCoding
    
    /// Is ignored by the macro. Must be an optional or have a default value.
    case ignored
}
/// Marks the property with a special way of encoding and decoding.
@attached(peer)
public macro CKPropertyType(_ propertyType: PropertyType) = #externalMacro(module: "CKMacroMacros", type: "CKPropertyTypeMacro")
