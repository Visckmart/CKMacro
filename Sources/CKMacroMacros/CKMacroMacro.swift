import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros


public struct ConvertibleToCKRecordMacro: MemberMacro {
    
    typealias DeclarationInfo = (IdentifierPatternSyntax, TypeAnnotationSyntax?, String)
    
    static let specialFields: [String: String] = [
        "creationDate": "Date?",
        "modificationDate": "Date?",
        "creatorUserRecordID": "CKRecord.ID?",
        "lastModifiedUserRecordID": "CKRecord.ID?",
        "recordID": "CKRecord.ID",
        "recordChangeTag": "String?"
    ]
    
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        var declarationInfo = [DeclarationInfo]()
        for member in declaration.memberBlock.members {
            if let member = member.decl.as(VariableDeclSyntax.self) {
                for binding in member.bindings {
                    if let bindingPattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        declarationInfo.append((bindingPattern, binding.typeAnnotation, member.attributes.trimmedDescription))
                    }
                }
            }
        }
        
        let encodingCodeBlock = makeEncodingDeclarations(forDeclarations: declarationInfo)
        let decodingCodeBlock = makeDecodingDeclarations(forDeclarations: declarationInfo)
        
        let firstMacroArgument = node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.trimmed.description
        let className = declaration.as(ClassDeclSyntax.self)?.name.trimmed.text
        let recordTypeName = firstMacroArgument ?? "\"\(className ?? "unknown")\""
        
        return [
            """
            func convertToCKRecord() -> CKRecord {
                let record = CKRecord(recordType: \(raw: recordTypeName))
                
            \(encodingCodeBlock)
            
                return record
            }
            """,
            """
            required init(from ckRecord: CKRecord) throws {
                \(decodingCodeBlock)
            }
            """,
            #"""
            enum CKRecordDecodingError: Error {
                case missingField(String)
                case fieldTypeMismatch(fieldName: String, expectedType: String, foundType: String)
                
                var localizedDescription: String {
                    var genericError = "Error while trying to initialize an instance of \#(raw: className ?? "") from a CKRecord:"
                    switch self {
                        case let .missingField(fieldName):
                            return "\(genericError) missing field '\(fieldName)' on CKRecord."
                        case let .fieldTypeMismatch(fieldName, expectedType, foundType):
                            return "\(genericError) field '\(fieldName)' has type \(foundType) but was expected to have type \(expectedType)."
                    }
                }
            }
            """#,
        ]
    }
    
    static func makeDecodingDeclarations(forDeclarations declarations: [DeclarationInfo]) -> DeclSyntax {
        var declsDec: [String] = []
        for declaration in declarations {
            let name = declaration.0.identifier.trimmed.text
            let type = declaration.1!.type.trimmedDescription
            let dec: String
            
            
            if specialFields.keys.contains(name) {
                dec = #"self.\#(name) = ckRecord.\#(name)"#
            } else if type == "Data" {
                dec = #"""
                /// Decoding \#(name)
                guard let raw\#(name.firstCapitalized) = ckRecord["\#(name)"] else {
                    throw CKRecordDecodingError.missingField("\#(name)")
                }
                guard
                    let \#(name) = raw\#(name.firstCapitalized) as? CKAsset,
                    let \#(name)FileURL = \#(name).fileURL,
                    let \#(name)Content = try? Data(contentsOf: \#(name)FileURL)
                else {
                    throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "\#(type)", foundType: "\(type(of: raw\#(name.firstCapitalized)))")
                }
                self.\#(name) = \#(name)Content
                
                """#
            } else if type == "[Data]" {
                dec = #"""
                /// Decoding \#(name)
                guard let raw\#(name.firstCapitalized) = ckRecord["\#(name)"] else {
                    throw CKRecordDecodingError.missingField("\#(name)")
                }
                guard
                    let \#(name) = raw\#(name.firstCapitalized) as? [CKAsset]
                else {
                    throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "\#(type)", foundType: "\(type(of: raw\#(name.firstCapitalized)))")
                }
                var \#(name)AssetContents = [Data]()
                for asset in \#(name) {
                    guard
                        let \#(name)FileURL = asset.fileURL,
                        let \#(name)Content = try? Data(contentsOf: \#(name)FileURL)
                    else {
                        continue
                    }
                    \#(name)AssetContents.append(\#(name)Content)
                }
                self.\#(name) = \#(name)AssetContents
                
                """#
            } else if type.hasSuffix("?") || type.hasPrefix("Optional<") {
                dec = #"""
                /// Decoding \#(name)
                guard let \#(name) = ckRecord["\#(name)"] as? \#(type) else {
                    throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "\#(type)", foundType: "\(type(of: ckRecord["\#(name)"]))")
                }
                self.\#(name) = \#(name)
                
                """#
                
            } else {
                dec = #"""
                /// Decoding \#(name)
                guard let raw\#(name.firstCapitalized) = ckRecord["\#(name)"] else {
                    throw CKRecordDecodingError.missingField("\#(name)")
                }
                guard let \#(name) = raw\#(name.firstCapitalized) as? \#(type) else {
                    throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "\#(type)", foundType: "\(type(of: raw\#(name.firstCapitalized)))")
                }
                self.\#(name) = \#(name)
                
                """#
            }
            declsDec.append(dec)
        }
        
        return """
               \(raw: declsDec.joined(separator: "\n"))
               """
    }
    
    static func makeEncodingDeclarations(forDeclarations declarations: [DeclarationInfo]) -> DeclSyntax {
        var declsEnc: [String] = []
        for declaration in declarations {
            let name = declaration.0.identifier.trimmed.text
            let type = declaration.1
            let enc: String
            guard specialFields.keys.contains(name) == false else {
                continue
            }
            if type?.type.trimmedDescription == "Data" {
                enc = #"""
                let \#(name)TemporaryAssetURL = URL(fileURLWithPath: NSTemporaryDirectory().appending(UUID().uuidString+".data"))
                do {
                    try self.\#(name).write(to: \#(name)TemporaryAssetURL)
                } catch let error as NSError {
                    debugPrint("Error creating asset for \#(name): \(error)")
                }
                \#trecord["\#(name)"] = CKAsset(fileURL: \#(name)TemporaryAssetURL)
                
                """#
            } else if type?.type.trimmedDescription == "[Data]" {
                enc = #"""
                var \#(name)Assets = [CKAsset]()
                for data in self.\#(name) {
                    let \#(name)TemporaryAssetURL = URL(fileURLWithPath: NSTemporaryDirectory().appending(UUID().uuidString+".data"))
                    do {
                        try data.write(to: \#(name)TemporaryAssetURL)
                        \#(name)Assets.append(CKAsset(fileURL: \#(name)TemporaryAssetURL))
                    } catch let error as NSError {
                        debugPrint("Error creating assets for \#(name): \(error)")
                    }
                }
                \#trecord["\#(name)"] = \#(name)Assets
                
                """#
            } else if declaration.2 == "@Relationship" {
                enc = #"""
                // Relationship \#(name)
                if let \#(name) {
                let childRecord = \#(name).convertToCKRecord()
                record["\#(name)"] = CKRecord.Reference(recordID: childRecord.recordID, action: .none)
                }
                """#
            } else {
                enc = #"\#trecord["\#(name)"] = self.\#(name)"#
                //                enc = #"record.setValue(self.\#(name), forKey: "\#(name)")"#
            }
            declsEnc.append(enc)
        }
        return """
               \(raw: declsEnc.joined(separator: "\n"))
               """
    }
}

extension ConvertibleToCKRecordMacro: ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
//        context.addDiagnostics(from: MyError(errorDescription: "\(protocols.description)"), node: node)
        let equatableExtension = try ExtensionDeclSyntax("extension \(type.trimmed): SynthesizedCKRecordConvertible {}")
        return [
            equatableExtension
//            try ExtensionDeclSyntax("extension \(declaration.as(ClassDeclSyntax.self)?.name.trimmed ?? "unknown") { static let i = 20 }")
        ]
    }
}

import Foundation

struct MyError: LocalizedError {
    var errorDescription: String?
}


extension String {
    var firstCapitalized: String {
        let firstLetter = self.prefix(1).capitalized
        let remainingLetters = self.dropFirst()
        return firstLetter + remainingLetters
    }
}



public struct RelationshipMarkerMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}

@main
struct CKMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ConvertibleToCKRecordMacro.self,
        RelationshipMarkerMacro.self
    ]
}
