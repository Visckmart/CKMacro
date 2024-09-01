//
//  ErrorHandling.swift
//  CKMacro
//
//  Created by Victor Martins on 27/08/24.
//

import Foundation
import SwiftSyntax
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
        MessageID(domain: "ckmacro\(Int.random(in: 1...100))", id: "\(type(of: self)).\(messageID)")
    }
    
    public var severity: DiagnosticSeverity { .error }
}

func error(_ s: String, node: SyntaxProtocol) -> Error {
    return DiagnosticsError(diagnostics: [
        Diagnostic(node: node, message: MacroError.error(s))
    ])
}

func diagnose(_ error: MacroError, node: SyntaxProtocol, fixIts: [FixIt] = []) -> Error {
    return DiagnosticsError(diagnostics: [
        Diagnostic(node: node, message: error, fixIts: fixIts)
    ])
}

enum MacroError: Error, DiagnosticMessage {
    
    case error(String)
    case warning(String)
    case fixit(String)
    
    var message: String {
        switch self {
        case .error(let string), .warning(let string):
            return "[CKMacro] " + string
        case .fixit(let string):
            return string
        }
    }
    
    var diagnosticID: SwiftDiagnostics.MessageID {
        .init(domain: "macro", id: "\(self)")
    }
    
    var severity: SwiftDiagnostics.DiagnosticSeverity {
        switch self {
        case .error: .error
        case .warning: .warning
        case .fixit: .note
        }
    }
}
extension MacroError: FixItMessage {
    var fixItID: MessageID { diagnosticID }
}


func makeTypeOptional(_ typeAnnotationSyntax: TypeAnnotationSyntax) -> TypeAnnotationSyntax? {
    guard var identifierType = typeAnnotationSyntax.type.as(IdentifierTypeSyntax.self) else {
        return nil
    }
    var optionalType = typeAnnotationSyntax
    var name = identifierType.name
    name = TokenSyntax(
        .identifier("\(name.text)?"),
        leadingTrivia: name.leadingTrivia,
        trailingTrivia: name.trailingTrivia,
        presence: name.presence
    )
    identifierType.name = name
    optionalType.type = TypeSyntax(identifierType)
    return optionalType
}


enum FixItTemplates {
    
    static func addOptional(toType typeAnnotationSyntax: TypeAnnotationSyntax) -> FixIt? {
        guard let optionalType = makeTypeOptional(typeAnnotationSyntax) else {
            return nil
        }
        return FixIt(message: MacroError.fixit("Make optional"), changes: [
            FixIt.Change.replace(oldNode: Syntax(typeAnnotationSyntax), newNode: Syntax(optionalType))
        ])
    }
    
    static func addInitializer(toDeclaration bindingDeclaration: PatternBindingSyntax) -> FixIt {
        var initializerDeclaration = bindingDeclaration
        initializerDeclaration.initializer = InitializerClauseSyntax(equal: TokenSyntax(" = "), value: ExprSyntax("<#value#>"))
        return FixIt(message: MacroError.fixit("Add initializer"), changes: [
            FixIt.Change.replace(oldNode: Syntax(bindingDeclaration), newNode: Syntax(initializerDeclaration))
        ])
    }
    
}
