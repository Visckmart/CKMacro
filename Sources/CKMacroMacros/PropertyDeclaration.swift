//
//  File.swift
//  CKMacro
//
//  Created by Victor Martins on 30/08/24.
//

import Foundation
import SwiftSyntax
import SwiftDiagnostics

struct PropertyDeclaration {
    
    var parentVariableDeclaration: VariableDeclSyntax
    var bindingDeclaration: PatternBindingSyntax
    
    var identifierSyntax: TokenSyntax
    var identifier: String
    
    var typeAnnotationSyntax: TypeAnnotationSyntax
    var type: String
    
    var recordNameMarker: AttributeSyntax?
    var relationshipMarker: (node: AttributeSyntax, referenceType: String, named: String?)?
    var propertyTypeMarker: (node: AttributeSyntax, propertyType: String)?
    
    var bindingSpecifier: TokenSyntax
    var isConstant: Bool
    var isAlreadyInitialized: Bool
    
    init?(parentVariableDeclaration: VariableDeclSyntax, bindingDeclaration: PatternBindingSyntax) throws {
        self.parentVariableDeclaration = parentVariableDeclaration
        self.bindingDeclaration = bindingDeclaration
        
        // Check static
        func isModifierStatic(_ modifier: DeclModifierListSyntax.Element) -> Bool {
            guard let modifier = modifier.as(DeclModifierSyntax.self) else { return false }
            return modifier.name.trimmed.text == "static"
        }
        let isStatic = parentVariableDeclaration.modifiers.contains(where: isModifierStatic)
        guard isStatic == false else { return nil }
        
        // Check computed
        if let accessors = bindingDeclaration.accessorBlock?.accessors.as(CodeBlockItemListSyntax.self) {
            return nil
        }
        
        if let accessors = bindingDeclaration.accessorBlock?.accessors.as(AccessorDeclListSyntax.self) {
            func hasGetOrSetSpecifier(_ token: AccessorDeclListSyntax.Element) -> Bool {
                token.accessorSpecifier.text == "get"
                || token.accessorSpecifier.text == "set"
            }
            let isComputed = accessors.contains(where: hasGetOrSetSpecifier)
            
            
            guard isComputed == false else { return nil }
        }
        
        // Get identifier
        guard
            let identifierSyntax = bindingDeclaration.pattern.as(IdentifierPatternSyntax.self)?.identifier,
            let identifier = identifierSyntax.identifier
        else {
            return nil
        }
        self.identifierSyntax = identifierSyntax
        self.identifier = identifier.name
        
        
        // Get type
        guard let typeAnnotationSyntax = bindingDeclaration.typeAnnotation else {
            var newBindingDeclaration = bindingDeclaration
            newBindingDeclaration.typeAnnotation = TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: " <#Type#> "), trailingTrivia: bindingDeclaration.trailingTrivia)
            newBindingDeclaration.pattern = newBindingDeclaration.pattern.trimmed
            throw diagnose(.error("Missing type annotation"), node: bindingDeclaration, fixIts: [
                FixIt(message: MacroError.fixit("Add type annotation"), changes: [FixIt.Change.replace(oldNode: Syntax(bindingDeclaration), newNode: Syntax(newBindingDeclaration))])
            ])
        }
        self.typeAnnotationSyntax = typeAnnotationSyntax
        self.type = typeAnnotationSyntax.type.trimmed.description
        
        // Get markers
        for attribute in parentVariableDeclaration.attributes.compactMap { $0.as(AttributeSyntax.self) } {
            guard let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text else {
                continue
            }
            if identifier == "CKRecordName" {
                guard recordNameMarker == nil else {
                    throw diagnose(
                        .error("Duplicate @CKRecordName marker on property '\(identifier)'"),
                        node: attribute
                    )
                }
                recordNameMarker = attribute
            } else if identifier == "CKReference" {
                guard relationshipMarker == nil else {
                    throw diagnose(
                        .error("Duplicate @CKReference marker on property '\(identifier)'"),
                        node: attribute
                    )
                }
                guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
                    throw error("Unable to get reference type for @CKReference", node: attribute)
                }
                
                
                if let firstArgumentExpression = arguments.first?.expression.as(FunctionCallExprSyntax.self) {
                    let relationshipInfo = firstArgumentExpression.arguments.as(LabeledExprListSyntax.self)
                    
                    guard
                        let declarationExpression = firstArgumentExpression.calledExpression.as(MemberAccessExprSyntax.self),
                        let declarationName = declarationExpression.declName.baseName.identifier?.name
                    else {
                        throw error("Unable to get reference type for @CKReference", node: attribute)
                    }
                    
                    let namedExpression = relationshipInfo?.first(where: {$0.label?.text == "named"})?.expression
                    guard let namedExpression = namedExpression?.as(StringLiteralExprSyntax.self) else {
                        throw error("Field name must be a string literal", node: attribute)
                    }
                    relationshipMarker = (attribute, declarationName, namedExpression.representedLiteralValue)
                } else if
                    let firstArgument = arguments.first?.expression.as(MemberAccessExprSyntax.self),
                    let declarationName = firstArgument.declName.baseName.identifier?.name
                {
                    relationshipMarker = (attribute, declarationName, nil)
                } else {
                    throw error("Unable to get reference type for @CKReference", node: attribute)
                }
                
//                throw error("\(arguments.first?.expression.as(FunctionCallExprSyntax.self))", node: attribute)
//                relationshipMarker = (attribute, declarationName)
            } else if identifier == "CKPropertyType" {
                guard propertyTypeMarker == nil else {
                    throw diagnose(
                        .error("Duplicate @CKPropertyType markers on property '\(identifier)'"),
                        node: attribute
                    )
                }
                if
                    let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
                    let firstArgument = arguments.first?.expression.as(MemberAccessExprSyntax.self),
                    let declarationName = firstArgument.declName.baseName.identifier?.name
                {
                    guard declarationName != "ignored" else {
                        let guaranteedInitialization = type.looksLikeOptionalType || bindingDeclaration.initializer != nil
                        guard guaranteedInitialization else {
                            var fixIts: [FixIt] = []
                            if let optionalFixIt = FixItTemplates.addOptional(toType: typeAnnotationSyntax) {
                                fixIts.append(optionalFixIt)
                            }
                            let initializerFixIt = FixItTemplates.addInitializer(toDeclaration: bindingDeclaration)
                            fixIts.append(initializerFixIt)
                            
                            throw diagnose(
                                .error("Ignored property '\(self.identifier)' must be an optional or have an initializer"),
                                node: propertyTypeMarker?.node ?? parentVariableDeclaration,
                                fixIts: fixIts
                            )
                        }
                        
                        return nil
                    }
                    propertyTypeMarker = (attribute, declarationName)
                } else {
                    throw error("Unable to get reference type for @CKRecordType", node: attribute)
                }
            }
        }
        
        
        self.bindingSpecifier = parentVariableDeclaration.bindingSpecifier
        self.isConstant = bindingSpecifier == .keyword(.let)
        self.isAlreadyInitialized = isConstant && bindingDeclaration.initializer != nil
        
        guard [recordNameMarker, relationshipMarker?.node, propertyTypeMarker?.node].compactMap { $0 }.count <= 1 else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: parentVariableDeclaration, message: MacroError.error("A property cannot be marked with multiple markers simultaneously"), highlights: [recordNameMarker, relationshipMarker?.node, propertyTypeMarker?.node].compactMap { Syntax($0) })
            ])
//            throw error(
//                "A property cannot be marked with multiple markers simultaneously",
//                node: parentVariableDeclaration
//            )
        }
    }
}
