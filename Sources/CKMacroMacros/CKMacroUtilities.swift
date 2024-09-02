//
//  File.swift
//  CKMacro
//
//  Created by Victor Martins on 29/08/24.
//

import Foundation
import SwiftSyntax
import SwiftDiagnostics

extension ConvertibleToCKRecordMacro {
    
    static func makeErrorEnums(className: String) throws -> [DeclSyntax] {
        [
            try makeEncodingErrorEnum(className: className),
            try makeDecodingErrorEnum(className: className)
        ]
    }
    
    static func makeTypeUnwrappingFunc() throws -> [DeclSyntax] {
        let unwrappedTypeFunc = try FunctionDeclSyntax(
            """
            func unwrappedType<T>(of value: T) -> Any.Type {
                if let ckRecordValue = value as? CKRecordValue {
                    ckRecordTypeOf(of: ckRecordValue)
                } else {
                    Swift.type(of: value as Any)
                }
            }
            """
        )
        
        let ckRecordTypeOfFunc = try FunctionDeclSyntax(
            """
            func ckRecordTypeOf<T: CKRecordValue>(of v: T) -> Any.Type {
                Swift.type(of: v as Any)
            }
            """
        )
        return [
            DeclSyntax(unwrappedTypeFunc),
            DeclSyntax(ckRecordTypeOfFunc)
        ]
    }
    
    static let callWillFinishDecoding = DeclSyntax(
            """
            if let delegate = (self as Any) as? CKRecordSynthetizationDelegate {
                try delegate.willFinishDecoding(ckRecord: ckRecord)
            }
            """
    )
    
    static let callWillFinishEncoding = DeclSyntax(
            """
            if let delegate = (self as Any) as? CKRecordSynthetizationDelegate {
                try delegate.willFinishEncoding(ckRecord: record)
            }
            """
    )
    static func makeEncodingErrorEnum(className: String) throws -> DeclSyntax {
        let localizedDescriptionEncoding = try VariableDeclSyntax("var localizedDescription: String") {
            #"""
            switch self {
            case .emptyRecordName(let fieldName):
                return "Error when trying to encode instance of \#(raw: className) to CKRecord: '\(fieldName)' is empty; the property marked with @CKRecordName cannot be empty when encoding"
            }
            """#
        }
        
        let encodingError = try EnumDeclSyntax("enum CKRecordEncodingError: Error") {
            "case emptyRecordName(fieldName: String)"
            localizedDescriptionEncoding
        }
        
        return DeclSyntax(encodingError)
    }
    
    static func makeDecodingErrorEnum(className: String) throws -> DeclSyntax {
        let localizedDescriptionProperty = try VariableDeclSyntax("var localizedDescription: String?") {
            #"""
            let genericMessage = "Error while trying to initialize an instance of \#(raw: className) from a CKRecord:"
            let specificReason: String
            switch self {
            case let .missingField(fieldName):
                specificReason = "missing field '\(fieldName)' on CKRecord."
            case let .fieldTypeMismatch(fieldName, expectedType, foundType):
                specificReason = "field '\(fieldName)' has type \(foundType) but was expected to have type \(expectedType)."
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
            """#
        }
        
        let decodingError = try EnumDeclSyntax("enum CKRecordDecodingError: Error") {
            """
            case missingField(String)
            case fieldTypeMismatch(fieldName: String, expectedType: String, foundType: String)
            case missingDatabase(fieldName: String)
            case errorDecodingNestedField(fieldName: String, _ error: Error)
            case multipleRecordsWithSameOwner
            case unableToDecodeRawType(fieldName: String, enumType: String, rawValue: Any)
            """
            localizedDescriptionProperty
        }
        
        return DeclSyntax(decodingError)
    }
}
