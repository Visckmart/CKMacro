// The Swift Programming Language
// https://docs.swift.org/swift-book

//@_exported import CKMacroMacros

@attached(member, names: named(x), named(convertToCKRecord), named(init(from:fetchingNestedRecordsFrom:)), named(CKRecordDecodingError))
@attached(extension, conformances: SynthesizedCKRecordConvertible)
public macro ConvertibleToCKRecord(recordType: String? = nil) = #externalMacro(module: "CKMacroMacros", type: "ConvertibleToCKRecordMacro")

import CloudKit
public protocol SynthesizedCKRecordConvertible: CKIdentifiable {
    func convertToCKRecord(usingBaseCKRecord: CKRecord?) -> CKRecord
    init(from ckRecord: CKRecord, fetchingNestedRecordsFrom: CKDatabase?) async throws
}


public protocol CKRecordSynthetizationDelegate: SynthesizedCKRecordConvertible {
    func willFinishEncoding(ckRecord: CKRecord)
    func willFinishDecoding(ckRecord: CKRecord)
}

public extension CKRecordSynthetizationDelegate {
    public func willFinishEncoding(ckRecord: CKRecord) { }
    public func willFinishDecoding(ckRecord: CKRecord) { }
}
public protocol CKIdentifiable {
    var recordName: String? { get set }
}
@attached(peer)
public macro CKReference(action: CKRecord.ReferenceAction) = #externalMacro(module: "CKMacroMacros", type: "RelationshipMarkerMacro")
