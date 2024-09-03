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


