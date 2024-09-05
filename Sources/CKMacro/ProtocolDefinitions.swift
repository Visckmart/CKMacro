//
//  SynthesizedCKRecordConvertible.swift
//  CKMacro
//
//  Created by Victor Martins on 31/08/24.
//

import Foundation
import CloudKit

public protocol CKIdentifiable {
    var __recordID: CKRecord.ID { get }
    var __recordName: String { get }
}

public protocol SynthesizedCKRecordConvertible: CKIdentifiable {
    init(fromCKRecord ckRecord: CKRecord, fetchingRelationshipsFrom: CKDatabase?) async throws
    func convertToCKRecord(usingBaseCKRecord: CKRecord?) throws -> (CKRecord, [CKRecord])
    mutating func saveToCKDatabase(_ database: CKDatabase, usingBaseCKRecord: CKRecord?) async throws
    static var __recordType: String { get }
}

public extension SynthesizedCKRecordConvertible {
    func saveToCKDatabase(_ database: CKDatabase, usingBaseCKRecord baseCKRecord: CKRecord? = nil) async throws {
        let (ckRecord, relationshipRecords) = try self.convertToCKRecord(usingBaseCKRecord: baseCKRecord)
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
}
public enum CKRecordEncodingError: Error {
    case emptyRecordName(fieldName: String)
    var localizedDescription: String {
        switch self {
        case .emptyRecordName(let fieldName):
            return "Error when trying to encode instance of DataExample to CKRecord: '\(fieldName)' is empty; the property marked with @CKRecordName cannot be empty when encoding"
        }
    }
}

func unwrappedType<T>(of value: T) -> Any.Type {
    if let ckRecordValue = value as? CKRecordValue {
        ckRecordTypeOf(of: ckRecordValue)
    } else {
        Swift.type(of: value as Any)
    }
}
func ckRecordTypeOf<T: CKRecordValue>(of v: T) -> Any.Type {
    Swift.type(of: v as Any)
}
public enum CKRecordDecodingError: Error {
    case missingField(String)
    case fieldTypeMismatch(fieldName: String, expectedTypeName: String, foundValue: Any?)
    case missingDatabase(fieldName: String)
    case errorDecodingNestedField(fieldName: String, _ error: Error)
    case multipleRecordsWithSameOwner
    case unableToDecodeRawType(fieldName: String, enumType: String, rawValue: Any)
    public var localizedDescription: String? {
        let genericMessage = "Error while trying to initialize an instance of DataExample from a CKRecord:"
        let specificReason: String
        switch self {
        case let .missingField(fieldName):
            specificReason = "missing field '\(fieldName)' on CKRecord."
        case let .fieldTypeMismatch(fieldName, expectedType, foundType):
            specificReason = "field '\(fieldName)' has type \(unwrappedType(of: foundType)) but was expected to have type \(expectedType)."
        case let .missingDatabase(fieldName):
            specificReason = "missing database to fetch relationship '\(fieldName)'."
        case let .errorDecodingNestedField(fieldName, error):
            specificReason = "field '\(fieldName)' could not be decoded because of error \(error.localizedDescription)"
            
        case .multipleRecordsWithSameOwner:
            specificReason = "multiple records with the same owner"
        case let .unableToDecodeRawType(fieldName, enumType, rawValue):
            specificReason = "field '\(fieldName)' could not be decoded since '\(enumType)' could not be instantiated from raw value \(rawValue)"
        }
        return "\(genericMessage) \(specificReason)"
    }
}
public extension SynthesizedCKRecordConvertible {
    static func fetch(
        withRecordName recordName: String,
        fromCKDatabase database: CKDatabase
    ) async throws -> Self {
        let fetchedRecord = try await database.record(for: CKRecord.ID(recordName: recordName))
        return try await Self(fromCKRecord: fetchedRecord, fetchingRelationshipsFrom: database)
    }
    
    static func fetchAll(
        fromCKDatabase database: CKDatabase,
        predicate: NSPredicate? = nil
    ) async throws -> [Self] {
        let query = CKQuery(recordType: Self.__recordType, predicate: predicate ?? NSPredicate(value: true))
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

public protocol CKRecordSynthetizationDelegate: SynthesizedCKRecordConvertible {
    func willFinishEncoding(ckRecord: CKRecord) throws
    func willFinishDecoding(ckRecord: CKRecord) throws
}

public extension CKRecordSynthetizationDelegate {
    public func willFinishEncoding(ckRecord: CKRecord) throws { }
    public func willFinishDecoding(ckRecord: CKRecord) throws { }
}


