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

@attached(peer)
public macro CKRecordName() = #externalMacro(module: "CKMacroMacros", type: "CKRecordNameMacro")

public enum ReferenceType {
    case referencesProperty
    case isReferencedByProperty(named: String? = nil, weakReference: Bool = true)
//    case isStronglyReferencedByProperty
    public static let isReferencedByProperty = isReferencedByProperty()
//    case data
}
@attached(peer)
public macro CKReference(_ referenceType: ReferenceType) = #externalMacro(module: "CKMacroMacros", type: "RelationshipMarkerMacro")

public enum PropertyType {
    case rawValue
    case codable
    case nsCoding
    case ignored
}
@attached(peer)
public macro CKPropertyType(_ propertyType: PropertyType) = #externalMacro(module: "CKMacroMacros", type: "CKPropertyTypeMacro")


@dynamicMemberLookup
public struct CodableWrapper<A: NSCoding & NSObject>: Codable {
    
    var value: A
    
    public init(value: A) {
        self.value = value
    }
    public subscript<T>(dynamicMember keyPath: KeyPath<A, T>) -> T {
        return self.value[keyPath: keyPath]
    }
    
    public subscript<T>(dynamicMember keyPath: WritableKeyPath<A, T>) -> T {
        get { self.value[keyPath: keyPath] }
        set { self.value[keyPath: keyPath] = newValue }
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false)
        try container.encode(data)
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let data = try container.decode(Data.self)
        self.value = try NSKeyedUnarchiver.unarchivedObject(ofClass: A.self, from: data)!
    }
}
