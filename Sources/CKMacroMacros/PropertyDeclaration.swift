//
//  File.swift
//  CKMacro
//
//  Created by Victor Martins on 30/08/24.
//

import Foundation
import SwiftSyntax

struct PropertyDeclaration {
    
    var parentVariableDeclaration: VariableDeclSyntax
    var bindingDeclaration: PatternBindingSyntax
    
    var identifierSyntax: TokenSyntax
    var identifier: String
    
    var typeAnnotationSyntax: TypeAnnotationSyntax
    var type: String
    
    var recordNameMarker: AttributeSyntax?
    var relationshipMarker: (node: AttributeSyntax, referenceType: String)?
    
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
            return nil
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
                guard recordNameMarker == nil else {
                    throw diagnose(
                        .error("Duplicate @CKReference marker on property '\(identifier)'"),
                        node: attribute
                    )
                }
                if
                    let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
                    let firstArgument = arguments.first?.expression.as(MemberAccessExprSyntax.self),
                    let declarationName = firstArgument.declName.baseName.identifier?.name
                {
                    relationshipMarker = (attribute, declarationName)
                } else {
                    throw error("Unable to get reference type for @CKReference", node: attribute)
                }
                
            }
        }
        
        
        self.bindingSpecifier = parentVariableDeclaration.bindingSpecifier
        self.isConstant = bindingSpecifier == .keyword(.let)
        self.isAlreadyInitialized = isConstant && bindingDeclaration.initializer != nil
        
        guard recordNameMarker == nil || relationshipMarker == nil else {
            throw error(
                "A property cannot be marked with @CKRecordName and @CKReference simultaneously",
                node: parentVariableDeclaration
            )
        }
    }
}
