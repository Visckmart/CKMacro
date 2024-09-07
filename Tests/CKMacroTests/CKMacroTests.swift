import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

import MacroTesting
// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(CKMacroMacros)
import CKMacroMacros

let testMacros: [String: Macro.Type] = [
    "stringify": ConvertibleToCKRecordMacro.self,
]
#endif

final class CKMacroTests: XCTestCase {
    let recordAll = false
    override func invokeTest() {
        withMacroTesting(
            macros: [
                ConvertibleToCKRecordMacro.self,
                CKRecordNameMacro.self,
                RelationshipMarkerMacro.self,
                CKPropertyTypeMacro.self
            ]
        ) {
            super.invokeTest()
        }
    }
    
    func testMacro() throws {
        print(try StmtSyntax(validating: "if x { a() }").debugDescription)
        #if canImport(CKMacroMacros)
        assertMacro {
            """
            @ConvertibleToCKRecord
            class User {
                @CKRecordName var id: String
            }
            """
        } diagnostics: {
            """

            """
        } expansion: {
            """
            class User {
                var id: String

                var __recordName: String {
                    get {
                        self.id
                    }
                    set {
                        self.id = newValue
                    }
                }

                var __recordID: CKRecord.ID {
                    get {
                        return CKRecord.ID(recordName: self.__recordName)
                    }

                    set {
                        self.__recordName = newValue.recordName
                    }
                }

                static let __recordType: String = "User"

                required init(fromCKRecord ckRecord: CKRecord, fetchingReferencesFrom database: CKDatabase? = nil) async throws {
                    let recordType = "User"
                    self.id = ckRecord.recordID.recordName

                    if let delegate = (self as Any) as? CKRecordSynthetizationDelegate {
                        try delegate.willFinishDecoding(ckRecord: ckRecord)
                    }
                }

                func convertToCKRecord(usingBaseCKRecord baseRecord: CKRecord? = nil) throws -> (instance: CKRecord, references: [CKRecord]) {
                    let record: CKRecord
                    if let baseRecord {
                        record = baseRecord
                    } else {
                        guard self.__recordName.isEmpty == false else {
                            throw CKRecordEncodingError.emptyRecordName(recordType: "User", fieldName: "id")
                        }
                        record = CKRecord(recordType: "User", recordID: __recordID)
                    }

                    if let delegate = (self as Any) as? CKRecordSynthetizationDelegate {
                        try delegate.willFinishEncoding(ckRecord: record)
                    }
                    return (instance: record, references: [])
                }
            }

            extension User: SynthesizedCKRecordConvertible {
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMultipleIDs() throws {
        assertMacro {
            """
            @ConvertibleToCKRecord
            class User {
                @CKRecordName var id: String
                @CKRecordName var id2: String
            }
            """
        } diagnostics: {
            """
            @ConvertibleToCKRecord
            class User {
                @CKRecordName var id: String
                ┬────────────
                ╰─ 🛑 [CKMacro] Multiple properties marked with @CKRecordName
                   ✏️ Remove marker from 'id' property
                @CKRecordName var id2: String
                ┬────────────
                ╰─ 🛑 [CKMacro] Multiple properties marked with @CKRecordName
                   ✏️ Remove marker from 'id2' property
            }
            """
        } fixes: {
            """
            @ConvertibleToCKRecord
            class User {var id: Stringvar id2: String
            }
            """
        }
    }
    
    func testCustomRecordType() {
        assertMacro {
            """
            @ConvertibleToCKRecord(recordType: "MY_RECORD_TYPE")
            class User {
                @CKRecordName var id: String
            }
            """
        } diagnostics: {
            """

            """
        } expansion: {
            """
            class User {
                var id: String

                var __recordName: String {
                    get {
                        self.id
                    }
                    set {
                        self.id = newValue
                    }
                }

                var __recordID: CKRecord.ID {
                    get {
                        return CKRecord.ID(recordName: self.__recordName)
                    }

                    set {
                        self.__recordName = newValue.recordName
                    }
                }

                static let __recordType: String = "MY_RECORD_TYPE"

                required init(fromCKRecord ckRecord: CKRecord, fetchingReferencesFrom database: CKDatabase? = nil) async throws {
                    let recordType = "MY_RECORD_TYPE"
                    self.id = ckRecord.recordID.recordName

                    if let delegate = (self as Any) as? CKRecordSynthetizationDelegate {
                        try delegate.willFinishDecoding(ckRecord: ckRecord)
                    }
                }

                func convertToCKRecord(usingBaseCKRecord baseRecord: CKRecord? = nil) throws -> (instance: CKRecord, references: [CKRecord]) {
                    let record: CKRecord
                    if let baseRecord {
                        record = baseRecord
                    } else {
                        guard self.__recordName.isEmpty == false else {
                            throw CKRecordEncodingError.emptyRecordName(recordType: "MY_RECORD_TYPE", fieldName: "id")
                        }
                        record = CKRecord(recordType: "MY_RECORD_TYPE", recordID: __recordID)
                    }

                    if let delegate = (self as Any) as? CKRecordSynthetizationDelegate {
                        try delegate.willFinishEncoding(ckRecord: record)
                    }
                    return (instance: record, references: [])
                }
            }

            extension User: SynthesizedCKRecordConvertible {
            }
            """
        }
    }
    
    func testNoRecordName() {
        assertMacro {
            """
            @ConvertibleToCKRecord
            class User {
                var id: String
            }
            """
        } diagnostics: {
            """
            @ConvertibleToCKRecord
            class User {
                  ┬───
                  ╰─ 🛑 [CKMacro] Missing property marked with @CKRecordName in 'User' class
                var id: String
            }
            """
        }
    }
}
