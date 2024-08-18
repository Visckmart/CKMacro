import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros


public struct ConvertibleToCKRecordMacro: MemberMacro {
    
    typealias DeclarationInfo = (IdentifierPatternSyntax, TypeAnnotationSyntax?, String, String?)
    
    static let specialFields: [String: String] = [
        "creationDate": "Date?",
        "modificationDate": "Date?",
        "creatorUserRecordID": "CKRecord.ID?",
        "lastModifiedUserRecordID": "CKRecord.ID?",
        "recordID": "CKRecord.ID",
        "recordChangeTag": "String?"
    ]
    
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        var declarationInfo = [DeclarationInfo]()
        var declarationInfoD = [DeclarationInfo]()
        for member in declaration.memberBlock.members {
            if let member = member.decl.as(VariableDeclSyntax.self) {
//                return [">\(raw: member.bindingSpecifier.trimmed.text)"]
                for binding in member.bindings {
                    let hasAccessor = binding.accessorBlock != nil
//                    let m = member.modifiers.com
//                    let hasInitializer = binding.initializer != nil
//                    let hasSetter = binding.accessorBlock?.accessors.as(AccessorDeclListSyntax.self)?.filter({$0.accessorSpecifier == .keyword(.set)}).isEmpty ?? false
                    guard hasAccessor == false else { continue }
//                    return [
//                    #"""
//                    var b = """
//                            \#(raw: binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmed.text)
//                            \#(raw: binding.accessorBlock?.accessors.as(AccessorDeclListSyntax.self)?.filter({$0.accessorSpecifier == .keyword(.set)}).isEmpty)
//                            """
//                    """#
//                    ]
                    if let bindingPattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        declarationInfo.append((bindingPattern, binding.typeAnnotation, member.attributes.trimmedDescription, member.attributes.first?.as(AttributeSyntax.self)?.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.trimmedDescription))
                        if member.bindingSpecifier.tokenKind != .keyword(.let) || binding.initializer == nil {
//                            let firstMacroArgument = node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.trimmed.description
                            
                            declarationInfoD.append((bindingPattern, binding.typeAnnotation, member.attributes.trimmedDescription, nil))
                        }
                    }
                }
            }
        }
        
        let encodingCodeBlock = makeEncodingDeclarations(forDeclarations: declarationInfo)
        let decodingCodeBlock = makeDecodingDeclarations(forDeclarations: declarationInfoD)
        
        let firstMacroArgument = node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.trimmed.description
        let className = declaration.as(ClassDeclSyntax.self)?.name.trimmed.text
        let recordTypeName = firstMacroArgument ?? "\"\(className ?? "unknown")\""
        
        return [
            """
            //func type<T: CKRecordValue>(of v: T?) -> (any Any.Type)? { v.flatMap { type(of: $0 as Any) } }
            """,
            """
            
            required init(from ckRecord: CKRecord, fetchingNestedRecordsFrom database: CKDatabase? = nil) async throws {
                func unwrappedType<T>(of value: T) -> Any.Type {
                    if let ckRecordValue = value as? CKRecordValue {
                        ckRecordTypeOf(of: ckRecordValue)
                    } else {
                        Swift.type(of: value as Any)
                    }
                }
                func ckRecordTypeOf<T: CKRecordValue>(of v: T) -> Any.Type {
                    Swift.type(of: v as Any)
                }
                
                \(decodingCodeBlock)
                
                if let delegate = self as? SynthesizedCKRecordDelegate {
                    delegate.willFinishDecoding(ckRecord: ckRecord)
                }
            }
            """,
            """
            func convertToCKRecord(usingBaseCKRecord baseRecord: CKRecord? = nil) -> CKRecord {
                var record: CKRecord
                if let baseRecord {
                    record = baseRecord
                } else if let recordName {
                    record = CKRecord(recordType: \(raw: recordTypeName), recordID: CKRecord.ID(recordName: recordName))
                } else {
                    record = CKRecord(recordType: \(raw: recordTypeName))
                }
                
                \(encodingCodeBlock)
                
                if let delegate = self as? SynthesizedCKRecordDelegate {
                    delegate.willFinishEncoding(ckRecord: record)
                }
                
                return record
            }
            """,
            #"""
            enum CKRecordDecodingError: Error {
                
                case missingField(String)
                case fieldTypeMismatch(fieldName: String, expectedType: String, foundType: String)
                case missingDatabase(fieldName: String)
                case errorDecodingNestedField(fieldName: String, _ error: Error)
            
                var localizedDescription: String {
                    let genericMessage = "Error while trying to initialize an instance of \#(raw: className ?? "") from a CKRecord:"
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
                    }
                    return "\(genericMessage) \(specificReason)" 
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
                /// Decoding `\#(name)`
                guard let raw\#(name.firstCapitalized) = ckRecord["\#(name)"] else {
                    throw CKRecordDecodingError.missingField("\#(name)")
                }
                guard
                    let \#(name) = raw\#(name.firstCapitalized) as? CKAsset,
                    let \#(name)FileURL = \#(name).fileURL,
                    let \#(name)Content = try? Data(contentsOf: \#(name)FileURL)
                else {
                    throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "\#(type)", foundType: "\(unwrappedType(of: raw\#(name.firstCapitalized)))")
                }
                self.\#(name) = \#(name)Content
                
                """#
            } else if type == "[Data]" {
                dec = #"""
                /// Decoding `\#(name)`
                guard let raw\#(name.firstCapitalized) = ckRecord["\#(name)"] else {
                    throw CKRecordDecodingError.missingField("\#(name)")
                }
                guard let \#(name) = raw\#(name.firstCapitalized) as? [CKAsset] else {
                    throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "\#(type)", foundType: "\(unwrappedType(of: raw\#(name.firstCapitalized)))")
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
            } else if declaration.2.hasPrefix("@CKReference") {
                var filteredType = type
                if filteredType.hasSuffix("?") { filteredType = String(filteredType.dropLast()) }
                if filteredType.hasPrefix("Optional<") { filteredType = String(filteredType.dropFirst(9).dropLast()) }
                let isOptional = filteredType != type
                dec = #"""
                       /// Relationship `\#(name)`
                       guard let \#(name)Reference = ckRecord["\#(name)"] as? CKRecord.Reference\#(isOptional ? "?" : "") else {  
                        throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "CKRecord.Reference\#(isOptional ? "?" : "")", foundType: "\(unwrappedType(of: ckRecord["\#(name)"]))")
                       }
                       
                       """#
                +
                (
                    isOptional
                    ? #"""
                    if let \#(name)Reference {
                        guard let database else {
                           throw CKRecordDecodingError.missingDatabase(fieldName: "\#(name)")
                        }
                        var \#(name)Record: CKRecord?
                        do {
                            \#(name)Record = try await database.record(for: \#(name)Reference.recordID)
                        } catch CKError.unknownItem {
                            \#(name)Record = nil
                        }
                        if let \#(name)Record {
                            do {
                                let \#(name) = try await \#(filteredType)(from: \#(name)Record)
                                self.\#(name) = \#(name)
                            } catch {
                                throw CKRecordDecodingError.errorDecodingNestedField(fieldName: "\#(name)", error)
                            }
                        } else {
                            self.\#(name) = nil
                        }
                    }
                      
                    """#
                    : #"""
                    guard let database else {
                        throw CKRecordDecodingError.missingDatabase(fieldName: "\#(name)")
                    }
                    let \#(name)Record = try await database.record(for: \#(name)Reference.recordID)
                    let \#(name) = try await \#(filteredType)(from: \#(name)Record)
                    self.\#(name) = \#(name)
                    
                    """#
                 )
            } else if type.hasSuffix("?") || type.hasPrefix("Optional<") {
                dec = #"""
                /// Decoding `\#(name)`
                guard let \#(name) = ckRecord["\#(name)"] as? \#(type) else {
                    throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "\#(type)", foundType: "\(unwrappedType(of: ckRecord["\#(name)"]))")
                }
                self.\#(name) = \#(name)
                
                """#
                
            } else {
                dec = #"""
                /// Decoding `\#(name)`
                guard let raw\#(name.firstCapitalized) = ckRecord["\#(name)"] else {
                    throw CKRecordDecodingError.missingField("\#(name)")
                }
                guard let \#(name) = raw\#(name.firstCapitalized) as? \#(type) else {
                    throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "\#(type)", foundType: "\(unwrappedType(of: raw\#(name.firstCapitalized)))")
                }
                self.\#(name) = \#(name)
                
                """#
            }
            declsDec.append(dec)
        }
        
        return "\(raw: declsDec.joined(separator: "\n"))"
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
                record["\#(name)"] = CKAsset(fileURL: \#(name)TemporaryAssetURL)
                
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
                record["\#(name)"] = \#(name)Assets
                
                """#
            } else if declaration.2.hasPrefix("@CKReference") {
                enc = #"""
                    /// Relationship `\#(name)`
                    if let \#(name) {
                        let childRecord = \#(name).convertToCKRecord()
                        record["\#(name)"] = CKRecord.Reference(recordID: childRecord.recordID, action: \#(declaration.3!))
                    }
                    
                    """#
            } else {
                enc = #"record["\#(name)"] = self.\#(name)"#
                //                enc = #"record.setValue(self.\#(name), forKey: "\#(name)")"#
            }
            declsEnc.append(enc)
        }
        
        return "\(raw: declsEnc.joined(separator: "\n"))"
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
