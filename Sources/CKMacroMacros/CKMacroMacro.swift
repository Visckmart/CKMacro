import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

import CloudKit


public struct ConvertibleToCKRecordMacro: MemberMacro {
    
    typealias DeclarationInfo = (IdentifierPatternSyntax, TypeAnnotationSyntax?, String, String?, VariableDeclSyntax?)
    
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
        guard let className = declaration.as(ClassDeclSyntax.self)?.name.trimmed.text else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: node, message: MacroError.simple("Macro has to be used in a class"))
            ])
        }
        let firstMacroArgument = node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.trimmed.description
        let recordTypeName = firstMacroArgument ?? "\"\(className ?? "unknown")\""
        
        var declarationInfo = [DeclarationInfo]()
        var declarationInfoD = [DeclarationInfo]()
        for member in declaration.memberBlock.members {
            if let member = member.decl.as(VariableDeclSyntax.self) {
                for binding in member.bindings {
                    let isStatic = member.modifiers.filter { $0.as(DeclModifierSyntax.self)?.name.trimmed.text == "static" }.isEmpty == false
                    guard isStatic == false else { continue }
                    let accessorSpecifiers = binding.accessorBlock?.accessors.as(AccessorDeclListSyntax.self)?.compactMap(\.accessorSpecifier)
//                    let getSetAccessors: [TokenSyntax]? =
                    let isComputed = (accessorSpecifiers?.filter({$0 == .keyword(.set) || $0 == .keyword(.get)}) ?? []).isEmpty == false
                    guard isComputed == false else { continue }
                    
                    if let bindingPattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        declarationInfo.append((bindingPattern, binding.typeAnnotation, member.attributes.trimmedDescription, member.attributes.first?.as(AttributeSyntax.self)?.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.trimmedDescription, member))
                        if member.bindingSpecifier.tokenKind != .keyword(.let) || binding.initializer == nil {
                            declarationInfoD.append((bindingPattern, binding.typeAnnotation, member.attributes.trimmedDescription, nil, member))
                        }
                    }
                }
            }
        }
        
        func getRecordName() throws -> DeclarationInfo {
            let recordNameProperties = declarationInfo.filter { $0.2 == "@CKRecordName" }
            guard recordNameProperties.count <= 1 else {
                let diagnostics = recordNameProperties.map {
                    Diagnostic(
                        node: $0.4!,
                        message: MacroError.simple("Multiple properties marked with @CKRecordName")
                    )
                }
                throw DiagnosticsError(diagnostics: diagnostics)
            }
            
            guard let recordNamePropertyFull = recordNameProperties.first else {
                throw DiagnosticsError(diagnostics: [
                    Diagnostic(
                        node: declaration.introducer,
                        message: MacroError.simple("Missing property marked with @CKRecordName")
                    )
                ])
            }
            return recordNamePropertyFull
        }
        
        let recordNamePropertyFull = try getRecordName()
        let recordNameProperty = recordNamePropertyFull.0.identifier.trimmed.text
        let recordNameType = recordNamePropertyFull.1!.type.trimmedDescription
        let recordNameGetOnly = recordNamePropertyFull.4?.bindingSpecifier.text == "let"
        let recordNameIsOptional = recordNameType.hasSuffix("?") || recordNameType.hasPrefix("Optional<")
        guard recordNameType == "String" else {
            let diagnostic = Diagnostic(
                node: recordNamePropertyFull.4!.attributes.first!,
                //                node: recordNamePropertyFull.1!.type,
                message: MacroError.simple("Cannot set property of type '\(recordNameType)' as record name; the record name has to be a 'String'")
            )
            throw DiagnosticsError(diagnostics: [diagnostic])
        }
        
        declarationInfo = declarationInfo.filter { $0.2 != "@CKRecordName" }
        declarationInfoD = declarationInfoD.filter { $0.2 != "@CKRecordName" }
        let encodingCodeBlock = try makeEncodingDeclarations(forDeclarations: declarationInfo, mainName: recordTypeName)
        let decodingCodeBlock = makeDecodingDeclarations(forDeclarations: declarationInfoD, mainName: recordTypeName)
        let localizedDescriptionProperty = try VariableDeclSyntax("var localizedDescription: String") {
            #"""
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
            """#
        }
        
        let decodingError = try EnumDeclSyntax("enum CKRecordDecodingError: Error") {
            """
            case missingField(String)
            case fieldTypeMismatch(fieldName: String, expectedType: String, foundType: String)
            case missingDatabase(fieldName: String)
            case errorDecodingNestedField(fieldName: String, _ error: Error)
            """
            localizedDescriptionProperty
        }
        
        let localizedDescriptionEncoding = try VariableDeclSyntax("var localizedDescription: String") {
            #"""
            var localizedDescription: String {
                switch self {
                case .emptyRecordName(let fieldName):
                    return "Error when trying to encode instance of \#(raw: className ?? "") to CKRecord: '\(fieldName)' is empty; the property marked with @CKRecordName cannot be empty when encoding"
                }
            }            
            """#
        }
        
        let encodingError = try EnumDeclSyntax("enum CKRecordEncodingError: Error") {
            "case emptyRecordName(fieldName: String)"
            localizedDescriptionEncoding
        }
        
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
        let callWillFinishDecoding = DeclSyntax(
            """
            if let delegate = (self as Any) as? CKRecordSynthetizationDelegate {
                try delegate.willFinishDecoding(ckRecord: ckRecord)
            }
            """
        )
        let callWillFinishEncoding = DeclSyntax(
            """
            if let delegate = (self as Any) as? CKRecordSynthetizationDelegate {
                try delegate.willFinishEncoding(ckRecord: record)
            }
            """
        )
        let recordNameGetAccessor = try AccessorDeclSyntax("get") {
            "self.\(raw: recordNameProperty)"
        }
        let recordNameSetAccessor = try AccessorDeclSyntax("set") {
            "self.\(raw: recordNameProperty) = newValue"
        }
        
        let recordNameSynthesizedProperty = try VariableDeclSyntax("var __recordName: String") {
            recordNameGetAccessor
            if !recordNameGetOnly {
                recordNameSetAccessor
            }
        }
        let recordIDGetAccessor = try AccessorDeclSyntax("set") {
            "self.__recordName = newValue.recordName"
        }
        let recordIDSetAccessor = try AccessorDeclSyntax("get") {
            "return CKRecord.ID(recordName: self.__recordName)"
        }
        let recordIDSynthesizedProperty = try VariableDeclSyntax("var __recordID: CKRecord.ID") {
            recordIDGetAccessor
            if !recordNameGetOnly {
                recordIDSetAccessor
            }
        }
        let recordTypeSynthesizedProperty = try VariableDeclSyntax(
            "static let __recordType: String = \(raw: recordTypeName)"
        )
        return [
            """
            
            required init(fromCKRecord ckRecord: CKRecord, fetchingRelationshipsFrom database: CKDatabase? = nil) async throws {
                \(unwrappedTypeFunc)
                \(ckRecordTypeOfFunc)
                
                self.\(raw: recordNameProperty) = ckRecord.recordID.recordName
                
                \(decodingCodeBlock)
                
                \(callWillFinishDecoding)
            }
            """,
            """
            func convertToCKRecord(usingBaseCKRecord baseRecord: CKRecord? = nil) throws -> (CKRecord, [CKRecord]) {
                var relationshipRecords: [CKRecord] = []
                relationshipRecords = []
                guard self.__recordName.isEmpty == false else {
                    throw CKRecordEncodingError.emptyRecordName(fieldName: \(literal: recordNameProperty))
                }
                var record: CKRecord
                if let baseRecord {
                    record = baseRecord
                } else {
                    record = CKRecord(recordType: \(raw: recordTypeName), recordID: __recordID)
                }
                
                \(encodingCodeBlock)
                
                \(callWillFinishEncoding)
                
                return (record, relationshipRecords)
            }
            """,
            DeclSyntax(recordTypeSynthesizedProperty),
            DeclSyntax(recordIDSynthesizedProperty),
            DeclSyntax(recordNameSynthesizedProperty),
            DeclSyntax(encodingError),
            DeclSyntax(decodingError),
        ]
    }
    
    static func makeDecodingDeclarations(forDeclarations declarations: [DeclarationInfo], mainName: String) -> DeclSyntax {
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
                dec =
//                       #"""
//                       /// Relationship `\#(name)`
//                       guard let \#(name)Reference = ckRecord["\#(name)"] as? CKRecord.Reference\#(isOptional ? "?" : "") else {  
//                        throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "CKRecord.Reference\#(isOptional ? "?" : "")", foundType: "\(unwrappedType(of: ckRecord["\#(name)"]))")
//                       }
//                       
//                       """#
//                +
                (
                    isOptional
                    ? #"""
                    let \#(name)OwnerReference = CKRecord.Reference(recordID: ckRecord.recordID, action: .none)
                    let \#(name)Query = CKQuery(recordType: \#(filteredType).__recordType, predicate: NSPredicate(format: "\#(mainName.dropFirst().dropLast())Owner == %@", \#(name)OwnerReference))
                    do {
                        let \#(name)FetchResponse = try await database?.records(matching: \#(name)Query)
                        guard let \#(name)FetchedRecords = \#(name)FetchResponse?.0.compactMap({try? $0.1.get()}) else {
                            throw CKRecordDecodingError.missingField("erro curriculum")
                        }
                        if let record = \#(name)FetchedRecords.first {
                            \#(name) = try await \#(filteredType)(fromCKRecord: record, fetchingRelationshipsFrom: database)
                        }
                    } catch CKError.invalidArguments {
                        print("invalid arguments")
                        \#(name) = nil
                    }
                      
                    """#
                    : #"""
                    guard let database else {
                        throw CKRecordDecodingError.missingDatabase(fieldName: "\#(name)")
                    }
                    let \#(name)Record = try await database.record(for: \#(name)Reference.recordID)
                    let \#(name) = try await \#(filteredType)(fromCKRecord: \#(name)Record, fetchingRelationshipsFrom: database)
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
    
    static func makeEncodingDeclarations(forDeclarations declarations: [DeclarationInfo], mainName: String) throws -> DeclSyntax {
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
                let isOptional = type?.trimmedDescription.hasSuffix("?") ?? false || type?.trimmedDescription.hasPrefix("Optional<") ?? false
                let referenceType = declaration.4?.attributes.first?.as(AttributeSyntax.self)?.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.identifier?.name
                var action = ""
                if referenceType == "referencesProperty" {
                    action = ".none"
                } else if referenceType == "isReferencedByProperty" {
                    action = ".deleteSelf"
                }
                if referenceType == "referencesProperty" {
                    if isOptional {
                        enc = #"""
                        /// Relationship `\#(name)`
                        if let \#(name) {
                            let childRecord = try \#(name).convertToCKRecord()
                            record["\#(name)"] = CKRecord.Reference(recordID: childRecord.0.recordID, action:   \#(action))
                            relationshipRecords.append(contentsOf: [childRecord.0] + childRecord.1)
                        }
                        
                        """#
                    } else {
                        enc = #"""
                        /// Relationship `\#(name)`
                        let childRecord = try \#(name).convertToCKRecord()
                        record["\#(name)"] = CKRecord.Reference(recordID: childRecord.0.recordID, action: \#(action))
                        relationshipRecords.append(contentsOf: [childRecord.0] + childRecord.1)
                        """#
                    }
                } else {
                    if isOptional {
                        enc = #"""
                        /// Relationship `\#(name)`
                        if let \#(name) {
                            let childRecord = try \#(name).convertToCKRecord()
                            childRecord.0["\#(mainName.dropFirst().dropLast())Owner"] = CKRecord.Reference(recordID: record.recordID, action: \#(action))
                            //record["\#(name)"] = CKRecord.Reference(recordID: childRecord.0.recordID, action: \#(declaration.3!))
                            relationshipRecords.append(contentsOf: [childRecord.0] + childRecord.1)
                        }
                        
                        """#
                    } else {
                        enc = #"""
                        /// Relationship `\#(name)`
                        let childRecord = try \#(name).convertToCKRecord()
                        childRecord.0["\#(mainName.dropFirst().dropLast())Owner"] = CKRecord.Reference(recordID: record.recordID, action: \#(action))
                        //record["\#(name)"] = CKRecord.Reference(recordID: childRecord.0.recordID, action: \#(declaration.3!))
                        relationshipRecords.append(contentsOf: [childRecord.0] + childRecord.1)
                        """#
                    }
                }
            } else {
//                enc = #"""
//                if let \#(name)A = \#(name) as? CKRecordValue { 
//                    record["\#(name)"] = \#(name)A
//                }
//                """#
//                if let type {
//                    let c = NSClassFromString(type.trimmedDescription)
//                    if c as? CKRecordValue != nil {
//                        throw StaticParserError("'\(name)' is not CKRecordValue")
//                    }
//                }
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

public struct CKRecordNameMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}


@main
struct CKMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ConvertibleToCKRecordMacro.self,
        RelationshipMarkerMacro.self,
        CKRecordNameMacro.self
    ]
}
