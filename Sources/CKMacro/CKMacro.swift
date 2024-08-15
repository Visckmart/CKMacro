// The Swift Programming Language
// https://docs.swift.org/swift-book

//@_exported import CKMacroMacros

@attached(member, names: named(x), named(convertToCKRecord), named(init(from:)), named(CKRecordDecodingError))
@attached(extension, conformances: SynthesizedCKRecordConvertible)
public macro ConvertibleToCKRecord(recordType: String? = nil) = #externalMacro(module: "CKMacroMacros", type: "ConvertibleToCKRecordMacro")

import CloudKit
public protocol SynthesizedCKRecordConvertible {
    func convertToCKRecord() -> CKRecord
    init(from ckRecord: CKRecord) throws
}
@attached(peer)
public macro Relationship() = #externalMacro(module: "CKMacroMacros", type: "RelationshipMarkerMacro")
