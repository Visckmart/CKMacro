//
//  File.swift
//  CKMacro
//
//  Created by Victor Martins on 29/08/24.
//

import Foundation
import SwiftSyntax
import SwiftDiagnostics
import SwiftSyntaxBuilder

extension ConvertibleToCKRecordMacro {
    
    static func checkPresence(ofField field: String, andStoreIn variable: String? = nil) throws -> CodeBlockItemSyntax {
        try CodeBlockItemSyntax(validating: #"""
            guard let \#(raw: variable ?? field) = ckRecord["\#(raw: field)"] else {
                \#(throwMissingField(fieldName: field))
            }
            """#
        )
    }
    
    static func guardType(
        of expression: ExprSyntax,
        is type: String,
        optional isOptional: Bool = false,
        andStoreIn variable: String,
        forField fieldName: String
    ) throws -> CodeBlockItemSyntax {
        try CodeBlockItemSyntax(validating: #"""
            guard let \#(raw: variable) = \#(raw: expression) as? \#(raw: type)\#(raw: isOptional ? "?" : "") else {
                \#(throwFieldTypeMismatch(fieldName: fieldName, expectedType: type, foundValue: "\(expression.formatted())"))
            }
            """#)
    }
    
    static func wrapInIfLet(
        _ name: String,
        if isOptional: Bool,
        @CodeBlockItemListBuilder bodyBuilder: () throws -> CodeBlockItemListSyntax,
        @CodeBlockItemListBuilder else: () throws -> CodeBlockItemListSyntax
    ) throws -> CodeBlockItemListSyntax {
        
        return try CodeBlockItemListSyntax {
            if isOptional {
                try IfExprSyntax("if let \(raw: name)") {
                    try bodyBuilder()
                } else: {
                    try `else`()
                }
            } else {
                try bodyBuilder()
            }
        }
    }
    
    static func throwMissingField(fieldName: String) -> Syntax {
        let throwExpr = try! ExprSyntax(validating: #"""
            CKRecordDecodingError.missingField(recordType: recordType, fieldName: "\#(raw: fieldName)")
            """#)
        return ThrowStmtSyntax(expression: throwExpr).formatted()
    }
    
    
    static func throwFieldTypeMismatch(fieldName: String, expectedType: String, foundValue: String) -> Syntax {
        let errorExpr = try! ExprSyntax(validating: #"""
            CKRecordDecodingError.fieldTypeMismatch(
                recordType: recordType, 
                fieldName: "\#(raw: fieldName)", 
                expectedTypeName: \#(literal: expectedType), 
                foundValue: \#(raw: foundValue)
            )
            """#)
        return ThrowStmtSyntax(expression: errorExpr).formatted()
    }
    
    
    
    static let callWillFinishDecoding = try! CodeBlockItemSyntax(validating: 
        """
        if let delegate = (self as Any) as? CKRecordSynthetizationDelegate {
            try delegate.willFinishDecoding(ckRecord: ckRecord)
        }
        """
    )
    
    static let callWillFinishEncoding = try! CodeBlockItemSyntax(validating: 
        """
        if let delegate = (self as Any) as? CKRecordSynthetizationDelegate {
            try delegate.willFinishEncoding(ckRecord: record)
        }
        """
    )
    
}
