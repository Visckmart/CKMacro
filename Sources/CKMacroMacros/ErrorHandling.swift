//
//  ErrorHandling.swift
//  CKMacro
//
//  Created by Victor Martins on 27/08/24.
//

import Foundation
import SwiftDiagnostics

enum CustomError: Error, CustomStringConvertible {
    case message(String)
    
    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

/// A parser error with a static message.
public struct StaticParserError: Error, DiagnosticMessage {
    public let message: String
    private let messageID: String
    
    /// This should only be called within a static var on DiagnosticMessage, such
    /// as the examples below. This allows us to pick up the messageID from the
    /// var name.
    init(_ message: String, messageID: String = #function) {
        self.message = message
        self.messageID = messageID
    }
    
    public var diagnosticID: MessageID {
        MessageID(domain: "ckmacro", id: "\(type(of: self)).\(messageID)")
    }
    
    public var severity: DiagnosticSeverity { .error }
}

enum MacroError: Error, DiagnosticMessage {
    
    case error(String)
    case warning(String)
    
    var message: String {
        switch self {
        case .error(let string), .warning(let string):
            return string
        }
    }
    
    var diagnosticID: SwiftDiagnostics.MessageID {
        .init(domain: "macro", id: "\(self)")
    }
    
    var severity: SwiftDiagnostics.DiagnosticSeverity {
        switch self {
        case .error(let string): .error
        case .warning(let string): .warning
        }
    }
}

//extension MacroError: ExpressibleByStringLiteral {
//    init(stringLiteral value: StringLiteralType) {
//        self = .simple(value)
//    }
//}
