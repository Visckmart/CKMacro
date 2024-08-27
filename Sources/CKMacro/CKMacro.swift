// The Swift Programming Language
// https://docs.swift.org/swift-book

@attached(member, names: named(x), named(convertToCKRecord), named(init(fromCKRecord:fetchingRelationshipsFrom:)), named(CKRecordDecodingError), named(__recordID), named(__recordType), named(__recordZoneID), named(__recordName))
@attached(extension, conformances: SynthesizedCKRecordConvertible)
public macro ConvertibleToCKRecord(recordType: String? = nil) = #externalMacro(module: "CKMacroMacros", type: "ConvertibleToCKRecordMacro")

import CloudKit

public protocol SynthesizedCKRecordConvertible: CKIdentifiable {
    func convertToCKRecord(usingBaseCKRecord: CKRecord?) -> (CKRecord, [CKRecord])
    init(fromCKRecord ckRecord: CKRecord, fetchingRelationshipsFrom: CKDatabase?) async throws
    mutating func saveToCKDatabase(_ database: CKDatabase, usingBaseCKRecord: CKRecord?) async throws
    static var __recordType: String { get }
}

public extension SynthesizedCKRecordConvertible {
    func saveToCKDatabase(_ database: CKDatabase, usingBaseCKRecord baseCKRecord: CKRecord? = nil) async throws {
        let (ckRecord, relationshipRecords) = self.convertToCKRecord(usingBaseCKRecord: baseCKRecord)
        if #available(macOS 12.0, *) {
            let (saveResults, _) = try await database.modifyRecords(
                saving: [ckRecord] + relationshipRecords,
                deleting: [],
                savePolicy: .allKeys,
                atomically: true
            )
        } else {
            try await database.save(ckRecord)
            for relationshipRecord in relationshipRecords {
                try await database.save(relationshipRecord)
            }
        }
    }
    
    static func fecth(withRecordName recordName: String, fromCKDatabase database: CKDatabase) async throws -> Self {
        let fetchedRecord = try await database.record(for: CKRecord.ID(recordName: recordName))
        return try await Self(fromCKRecord: fetchedRecord, fetchingRelationshipsFrom: database)
    }
    
    static func fecthAll(fromCKDatabase database: CKDatabase) async throws -> [Self] {
        let query = CKQuery(recordType: Self.__recordType, predicate: NSPredicate(value: true))
        var (response, cursor) = try await database.records(matching: query)
        
        
        var decodedResults = [Self]()
        repeat {
            let fetchedRecords = response.compactMap({ try? $0.1.get() })
            for record in fetchedRecords {
                let newInstance = try await Self(fromCKRecord: record, fetchingRelationshipsFrom: database)
                decodedResults.append(newInstance)
            }
            if let currentCursor = cursor {
                (response, cursor) = try await database.records(continuingMatchFrom: currentCursor)
            }
        } while cursor != nil
        return decodedResults
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
    var __recordID: CKRecord.CodableID { get }
    var __recordName: String { get }
//    var __recordZoneID: CKRecordZone.ID? { get set }
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

public enum ReferenceType {
    case referencesProperty
    case isReferencedByProperty(weakReference: Bool)
//    case isStronglyReferencedByProperty
    public static let isReferencedByProperty = isReferencedByProperty(weakReference: true)
}
@attached(peer)
public macro CKReference(_ referenceType: ReferenceType) = #externalMacro(module: "CKMacroMacros", type: "RelationshipMarkerMacro")
@attached(peer)
public macro CKRecordName() = #externalMacro(module: "CKMacroMacros", type: "CKRecordNameMacro")
//@attached(peer)
//public macro CKEncode(with: (CKRecord) -> CKRecordValue) = #externalMacro(module: "CKMacroMacros", type: "RelationshipMarkerMacro2")
//
//@attached(peer)
//public macro CKDecode(with: () -> CKRecordValue) = #externalMacro(module: "CKMacroMacros", type: "RelationshipMarkerMacro2")
