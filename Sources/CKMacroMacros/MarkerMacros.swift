//
//  File.swift
//  CKMacro
//
//  Created by Victor Martins on 29/08/24.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

public struct RelationshipMarkerMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}

public struct CKRecordNameMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}
