// The Swift Programming Language
// https://docs.swift.org/swift-book

@attached(member, names: named(x), named(convertToCKRecord), named(init(from:fetchingNestedRecordsFrom:)), named(CKRecordDecodingError), named(__recordID), named(__recordType))
@attached(extension, conformances: SynthesizedCKRecordConvertible)
public macro ConvertibleToCKRecord(recordType: String? = nil) = #externalMacro(module: "CKMacroMacros", type: "ConvertibleToCKRecordMacro")

import CloudKit

public protocol SynthesizedCKRecordConvertible: CKIdentifiable {
    func convertToCKRecord(usingBaseCKRecord: CKRecord?) -> (CKRecord, [CKRecord])
    init(from ckRecord: CKRecord, fetchingNestedRecordsFrom: CKDatabase?) async throws
    func save(toDatabase database: CKDatabase, usingBaseCKRecord: CKRecord?) async throws
    static var __recordType: String { get }
}

public extension SynthesizedCKRecordConvertible {
    func save(toDatabase database: CKDatabase, usingBaseCKRecord baseCKRecord: CKRecord? = nil) async throws {
        let (ckRecord, relationshipRecords) = self.convertToCKRecord(usingBaseCKRecord: baseCKRecord)
        if #available(macOS 12.0, *) {
            try await database.modifyRecords(
                saving: [ckRecord] + relationshipRecords,
                deleting: [],
                savePolicy: .allKeys,
                atomically: true
            )
            print("modified")
        } else {
            try await database.save(ckRecord)
            for relationshipRecord in relationshipRecords {
                try await database.save(relationshipRecord)
            }
        }
    }
    
    
    
}
extension SynthesizedCKRecordConvertible where Self: Codable {
    public static func fetch(fromDatabase database: CKDatabase, key: CodingKey, value: NSObject) async throws -> (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?) {
        let predicate = NSPredicate(format: "%K = %@", NSString(string: key.stringValue), value)
        let query = CKQuery(recordType: Self.__recordType, predicate: predicate)
        return try await database.records(matching: query)
    }
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
    var __recordID: CKRecord.CodableID? { get set }
}
@dynamicMemberLookup
public struct MyID: Codable {
    public var value: CKRecord.ID
    
    public init(_ recordID: CKRecord.ID) {
        value = recordID
    }
    
    private enum CodingKeys: CodingKey {
        case data
    }
    
    public subscript<T>(dynamicMember keyPath: KeyPath<CKRecord.ID, T>) -> T {
        get { self.value[keyPath: keyPath] }
    }
    public init(from decoder: any Decoder) throws {
        let container: KeyedDecodingContainer<MyID.CodingKeys> = try decoder.container(keyedBy: MyID.CodingKeys.self)
        
        let partialData = try container.decode(Data.self, forKey: MyID.CodingKeys.data)
        self.value = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.ID.self, from: partialData)!
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: MyID.CodingKeys.self)
        
        let identifierData = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false)
        try container.encode(identifierData, forKey: .data)
    }
    //    func encode(to encoder: any Encoder) throws {
    //        var container = encoder.container(keyedBy: CodingKeys.self)
    //
    //        let identifierData = try NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: false)
    //        try container.encode(identifierData, forKey: .data)
    //    }
    //    init(from decoder: any Decoder) throws {
    //        let container = decoder.container(keyedBy: CodingKeys.self)
    //    }
    //    func decoding() {
    //        favoriteColor = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(colorData) as? Self
    //    }
    //    func encoding() throws -> Data {
    //        try NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: false)
    //    }
}


extension CKRecord {
    public typealias CodableID = MyID
}


@attached(peer)
public macro CKReference(action: CKRecord.ReferenceAction) = #externalMacro(module: "CKMacroMacros", type: "RelationshipMarkerMacro")

//@attached(peer)
//public macro CKEncode(with: (CKRecord) -> CKRecordValue) = #externalMacro(module: "CKMacroMacros", type: "RelationshipMarkerMacro2")
//
//@attached(peer)
//public macro CKDecode(with: () -> CKRecordValue) = #externalMacro(module: "CKMacroMacros", type: "RelationshipMarkerMacro2")
