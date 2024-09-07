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
    init(fromCKRecord ckRecord: CKRecord, fetchingReferencesFrom: CKDatabase?) async throws
    func convertToCKRecord(usingBaseCKRecord: CKRecord?) throws -> (instance: CKRecord, references: [CKRecord])
    mutating func saveToCKDatabase(_ database: CKDatabase, usingBaseCKRecord: CKRecord?) async throws
    static var __recordType: String { get }
}

public extension SynthesizedCKRecordConvertible {
    func saveToCKDatabase(_ database: CKDatabase, usingBaseCKRecord baseCKRecord: CKRecord? = nil) async throws {
        let (ckRecord, referenceRecords) = try self.convertToCKRecord(usingBaseCKRecord: baseCKRecord)
        if #available(macOS 12.0, *) {
            _ = try await database.modifyRecords(
                saving: [ckRecord] + referenceRecords,
                deleting: [],
                savePolicy: .allKeys,
                atomically: true
            )
        } else {
            try await database.save(ckRecord)
            for referenceRecord in referenceRecords {
                try await database.save(referenceRecord)
            }
        }
    }
}
public enum CKRecordEncodingError: Error {
    case emptyRecordName(recordType: String, fieldName: String)
    var localizedDescription: String {
        switch self {
        case let .emptyRecordName(recordType, fieldName):
            return "Error when trying to encode instance of \(recordType) to CKRecord: '\(fieldName)' is empty; the property marked with @CKRecordName cannot be empty when encoding"
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

public enum CKRecordDecodingError: LocalizedError {
    case missingField(recordType: String, fieldName: String)
    case fieldTypeMismatch(recordType: String, fieldName: String, expectedTypeName: String, foundValue: Any?)
    case missingDatabase(recordType: String, fieldName: String)
    case errorDecodingNestedField(recordType: String, fieldName: String, _ error: Error)
    case multipleRecordsWithSameOwner(recordType: String)
    case unableToDecodeRawType(recordType: String, fieldName: String, enumType: String, rawValue: Any)
    case unableToDecodeDataType(recordType: String, fieldName: String, decodingType: String, error: Error)
    
    public var errorDescription: String? {
        let specificReason: String
        switch self {
        case let .missingField(_, fieldName):
            specificReason = "missing field '\(fieldName)' on CKRecord."
            
        case let .fieldTypeMismatch(_, fieldName, expectedType, foundType):
            specificReason = "field '\(fieldName)' has type \(unwrappedType(of: foundType)) but was expected to have type \(expectedType)."
            
        case let .missingDatabase(_, fieldName):
            specificReason = "missing database argument to fetch relationship '\(fieldName)'."
            
        case let .errorDecodingNestedField(_, fieldName, error):
            specificReason = "field '\(fieldName)' could not be decoded because of error \(error.localizedDescription)"
            
        case .multipleRecordsWithSameOwner:
            specificReason = "multiple records with the same owner"
            
        case let .unableToDecodeRawType(_, fieldName, enumType, rawValue):
            specificReason = "field '\(fieldName)' could not be decoded since '\(enumType)' could not be instantiated from raw value \(rawValue)"
            
        case let .unableToDecodeDataType(_, fieldName, decodingType, error):
            specificReason = "field '\(fieldName)' could not be decoded as a '\(decodingType)' because of: \(error)"
        }
        return "Error while trying to initialize an instance of \(self.recordType) from a CKRecord: \(specificReason)"
    }
    
    public var recordType: String {
        switch self {
        case
            let .missingField(recordType, _),
            let .fieldTypeMismatch(recordType, _, _, _),
            let .missingDatabase(recordType, _),
            let .errorDecodingNestedField(recordType, _, _),
            let .multipleRecordsWithSameOwner(recordType),
            let .unableToDecodeRawType(recordType, _, _, _),
            let .unableToDecodeDataType(recordType, _, _, _):
            
            return recordType
        }
    }
}
public extension SynthesizedCKRecordConvertible {
    static func fetch(
        withRecordName recordName: String,
        fromCKDatabase database: CKDatabase
    ) async throws -> Self {
        let fetchedRecord = try await database.record(for: CKRecord.ID(recordName: recordName))
        return try await Self(fromCKRecord: fetchedRecord, fetchingReferencesFrom: database)
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
                let newInstance = try await Self(fromCKRecord: record, fetchingReferencesFrom: database)
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
    func willFinishEncoding(ckRecord: CKRecord) throws { }
    func willFinishDecoding(ckRecord: CKRecord) throws { }
}


