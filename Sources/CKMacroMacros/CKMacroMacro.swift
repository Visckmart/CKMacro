import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

import CloudKit

public struct ConvertibleToCKRecordMacro: MemberMacro {
    
    
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            throw diagnose(.warning("Macro has to be used in a class"), node: node)
        }
        let className = classDecl.name.trimmed.text
        
        let recordTypeName: String
        var debugMode = false
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            if let firstMacroArgument = arguments.first {
                guard let stringValue = firstMacroArgument.expression.as(StringLiteralExprSyntax.self) else {
                    throw diagnose(.error("Record type must be defined by a string literal"), node: declaration)
                }
                recordTypeName = stringValue.description
            } else {
                recordTypeName = "\"\(className)\""
            }
            if let debugArgument = arguments.first(where: { $0.label?.text == "debug" }) {
                guard let debugExpression = debugArgument.expression.as(BooleanLiteralExprSyntax.self) else {
                    throw diagnose(.error("Debug mode must be defined by a boolean literal"), node: debugArgument)
                }
                debugMode = debugExpression.literal.tokenKind == .keyword(.true)
            }
        } else {
            recordTypeName = "\"\(className)\""
        }
        
        var propertyDeclarations = [PropertyDeclaration]()
        
        for member in declaration.memberBlock.members {
            guard let variableDeclaration = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }
            for binding in variableDeclaration.bindings {
                let propertyDeclaration = try PropertyDeclaration(
                    parentVariableDeclaration: variableDeclaration,
                    bindingDeclaration: binding
                )
                if let propertyDeclaration {
                    propertyDeclarations.append(propertyDeclaration)
                }
            }
        }
        
        func getRecordName() throws -> PropertyDeclaration {
            let recordNameProperties = propertyDeclarations.compactMap { propertyDeclaration in
                if let markerAttribute = propertyDeclaration.recordNameMarker {
                    return (propertyDeclaration: propertyDeclaration, markerAttribute: markerAttribute)
                }
                return nil
            }
            guard recordNameProperties.count <= 1 else {
                let diagnostics = recordNameProperties.map {
                    Diagnostic(
                        node: $0.markerAttribute,
                        message: MacroError.error("Multiple properties marked with @CKRecordName"),
                        fixIt: FixIt(message: MacroError.fixit("Remove marker from '\($0.propertyDeclaration.identifier)' property"), changes: [
                            FixIt.Change.replace(oldNode: Syntax($0.markerAttribute), newNode: Syntax(ExprSyntax("")))
                        ])
                    )
                }
                throw DiagnosticsError(diagnostics: diagnostics)
            }
            
            guard let recordNamePropertyFull = recordNameProperties.first else {
                throw diagnose(.error("Missing property marked with @CKRecordName in '\(className)' class"), node: classDecl.name)
            }
            return recordNamePropertyFull.propertyDeclaration
        }
        
        let recordNamePropertyFull = try getRecordName()
        
        if debugMode {
            context.diagnose(Diagnostic(node: recordNamePropertyFull.bindingDeclaration,
                                        message: MacroError.warning("Record name")))
            for propertyDeclaration in propertyDeclarations {
                context.diagnose(Diagnostic(node: propertyDeclaration.bindingDeclaration,
                                            message: MacroError.warning("\(propertyDeclaration)")))
            }
        }
        
        guard recordNamePropertyFull.type == "String" else {
            throw diagnose(
                .error("Cannot set property of type '\(recordNamePropertyFull.type)' as record name; the record name has to be a 'String'"),
                node: recordNamePropertyFull.typeAnnotationSyntax
            )
        }
        
        propertyDeclarations = propertyDeclarations.filter { $0.recordNameMarker == nil }
        let encodingCodeBlock = try makeEncodingDeclarations(forDeclarations: propertyDeclarations, mainName: recordTypeName)
        let decodingCodeBlock = try makeDecodingDeclarations(forDeclarations: propertyDeclarations, mainName: recordTypeName)
        
        
        let initFromCKRecord = try InitializerDeclSyntax(
            "required init(fromCKRecord ckRecord: CKRecord, fetchingRelationshipsFrom database: CKDatabase? = nil) async throws"
        ) {
            try Self.makeTypeUnwrappingFunc()
            
            ExprSyntax("self.\(raw: recordNamePropertyFull.identifier) = ckRecord.recordID.recordName\n")
            
            decodingCodeBlock
            
            callWillFinishDecoding
            
        }
        
        let convertToCKRecordSetup = try CodeBlockSyntax(
            """
            guard self.__recordName.isEmpty == false else {
                throw CKRecordEncodingError.emptyRecordName(fieldName: \(literal: recordNamePropertyFull.identifier))
            }
            var record: CKRecord
            if let baseRecord {
                record = baseRecord
            } else {
                record = CKRecord(recordType: \(raw: recordTypeName), recordID: __recordID)
            }            
            var relationshipRecords: [CKRecord] = []
            relationshipRecords = []
            """
        )
        
        let methodConvertToCKRecord = try FunctionDeclSyntax(
            "func convertToCKRecord(usingBaseCKRecord baseRecord: CKRecord? = nil) throws -> (CKRecord, [CKRecord])"
        ) {
            """
            \(convertToCKRecordSetup)
            
            \(encodingCodeBlock)
            
            \(Self.callWillFinishEncoding)
            
            return (record, relationshipRecords)
            """
        }
        
        let recordProperties = try Self.makeRecordProperties(
            recordNameProperty: (name: recordNamePropertyFull.identifier, type: recordNamePropertyFull.type),
            recordType: recordTypeName,
            getOnly: recordNamePropertyFull.isConstant
        )
        
        let encodingAndDecodingDeclarations = [
            DeclSyntax(initFromCKRecord),
            DeclSyntax(methodConvertToCKRecord),
        ]
        
        let errorEnums = try Self.makeErrorEnums(className: className ?? "")
        
        return recordProperties + encodingAndDecodingDeclarations + errorEnums
        
    }
    
    static func makeRecordProperties(recordNameProperty: (name: String, type: String), recordType: String, getOnly: Bool) throws -> [DeclSyntax] {
        let synthesizedRecordNameProperty =
            try VariableDeclSyntax("var __recordName: String") {
                try AccessorDeclSyntax("get") {
                    "self.\(raw: recordNameProperty.name)"
                }
                if !getOnly {
                    try AccessorDeclSyntax("set") {
                        "self.\(raw: recordNameProperty.name) = newValue"
                    }
                }
            }
        
        let synthesizedRecordIDProperty =
            try VariableDeclSyntax("var __recordID: CKRecord.ID") {
                try AccessorDeclSyntax("get") {
                    "return CKRecord.ID(recordName: self.__recordName)"
                }
                if !getOnly {
                    try AccessorDeclSyntax("set") {
                        "self.__recordName = newValue.recordName"
                    }
                }
            }
        
        let synthesizedRecordTypeProperty = try VariableDeclSyntax(
            "static let __recordType: String = \(raw: recordType)"
        )
        
        return [
            DeclSyntax(synthesizedRecordNameProperty),
            DeclSyntax(synthesizedRecordIDProperty),
            DeclSyntax(synthesizedRecordTypeProperty)
        ]
    }
    
    static func makeDecodingDeclarations(forDeclarations declarations: [PropertyDeclaration], mainName: String) throws -> DeclSyntax {
        var declsDec: [String] = []
        for declaration in declarations {
            let name = declaration.identifier
            let type = declaration.type
            let dec: String
            
            if type == "Data" {
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
            } else if let referenceMarker = declaration.relationshipMarker {
                
                var filteredType = type.wrappedTypeName
                let isOptional = type.looksLikeOptionalType
                let databaseCheck = #"""
                    guard let \#(name)Database = database else {
                        throw CKRecordDecodingError.missingDatabase(fieldName: "\#(name)")
                    }
                    """#
                
                if referenceMarker.referenceType == "referencesProperty" {
                    let getReference = #"""
                        /// Relationship `\#(name)`
                        guard let \#(name)Reference = ckRecord["\#(name)"] as? CKRecord.Reference\#(isOptional ? "?" : "") else {  
                            throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "CKRecord.Reference\#(isOptional ? "?" : "")", foundType: "\(unwrappedType(of: ckRecord["\#(name)"]))")
                        }
                        
                        """#
                    
                    let fetchOptionallyReferencedProperty = #"""
                        if let \#(name)Reference {
                            \#(databaseCheck)
                            var \#(name)Record: CKRecord?
                            do {
                                \#(name)Record = try await \#(name)Database.record(for: \#(name)Reference.recordID)
                            } catch CKError.unknownItem {
                                \#(name)Record = nil
                            }
                            if let \#(name)Record {
                                do {
                                    let \#(name) = try await \#(filteredType)(fromCKRecord: \#(name)Record, fetchingRelationshipsFrom: \#(name)Database)
                                    self.\#(name) = \#(name)
                                } catch {
                                    throw CKRecordDecodingError.errorDecodingNestedField(fieldName: "\#(name)", error)
                                }
                            } else {
                                self.\#(name) = nil
                            }
                        }
                          
                        """#
                    
                    let fetchReferencedProperty = #"""
                        \#(databaseCheck)
                        let \#(name)Record = try await \#(name)Database.record(for: \#(name)Reference.recordID)
                        let \#(name) = try await \#(filteredType)(fromCKRecord: \#(name)Record, fetchingRelationshipsFrom: \#(name)Database)
                        self.\#(name) = \#(name)
                        
                        """#
                    
                    dec = getReference + (isOptional
                                          ? fetchOptionallyReferencedProperty
                                          : fetchReferencedProperty)
                } else if referenceMarker.referenceType == "isReferencedByProperty" {
                    let ownedFieldName = referenceMarker.named ?? "\(mainName.dropFirst().dropLast())Owner"
                    dec =
                    isOptional
                    ? """
                    /// Decoding relationship `\(name)`
                    \(databaseCheck)
                    let \(name)OwnerReference = CKRecord.Reference(recordID: ckRecord.recordID, action: .none)
                    let \(name)Query = CKQuery(recordType: \(filteredType).__recordType, predicate: NSPredicate(format: "\(ownedFieldName) == %@", \(name)OwnerReference))
                    do {
                        let \(name)FetchResponse = try await \(name)Database.records(matching: \(name)Query)
                        guard \(name)FetchResponse.0.count <= 1 else {
                            throw CKRecordDecodingError.multipleRecordsWithSameOwner
                        }
                        let \(name)FetchedRecords = try \(name)FetchResponse.0.compactMap({ try $0.1.get() })
                        if let record = \(name)FetchedRecords.first {
                            self.\(name) = try await \(filteredType)(fromCKRecord: record, fetchingRelationshipsFrom: \(name)Database)
                        } else {
                            self.\(name) = nil
                        }
                    } catch CKError.unknownItem {
                        self.\(name) = nil
                    } catch CKError.invalidArguments {
                        self.\(name) = nil
                    }
                      
                    """
                    :
                    #"""
                    /// Decoding relationship `\#(name)`
                    \#(databaseCheck)
                    let \#(name)OwnerReference = CKRecord.Reference(recordID: ckRecord.recordID, action: .none)
                    let \#(name)Query = CKQuery(recordType: \#(filteredType).__recordType, predicate: NSPredicate(format: "\#(ownedFieldName) == %@", \#(name)OwnerReference))
                    do {
                        let \#(name)FetchResponse = try await \#(name)Database.records(matching: \#(name)Query)
                        guard \#(name)FetchResponse.0.count <= 1 else {
                            throw CKRecordDecodingError.multipleRecordsWithSameOwner
                        }
                        let \#(name)FetchedRecords = try \#(name)FetchResponse.0.compactMap({ try $0.1.get() })
                        if let record = \#(name)FetchedRecords.first {
                            self.\#(name) = try await \#(filteredType)(fromCKRecord: record, fetchingRelationshipsFrom: \#(name)Database)
                        } else {
                            throw CKRecordDecodingError.missingField("\#(name)")
                        }
                    } catch CKError.unknownItem {
                        throw CKRecordDecodingError.missingField("\#(name)")
                    }
                    
                    """#
                } else {
                    throw diagnose(.error("Unknown reference mode"), node: referenceMarker.node)
                }
            } else if let propertyTypeMarker = declaration.propertyTypeMarker {
                if propertyTypeMarker.propertyType == "rawValue" {
                    if type.looksLikeOptionalType {
                        dec = #"""
                        /// Decoding `\#(name)`
                        guard let rawValue\#(name.firstCapitalized) = ckRecord["\#(name)"] as? \#(type.wrappedTypeName).RawValue else {
                            throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "\#(type.wrappedTypeName).RawValue", foundType: "\(unwrappedType(of: ckRecord["\#(name)"]))")
                        }
                        if let \#(name) = \#(type.wrappedTypeName)(rawValue: rawValue\#(name.firstCapitalized)) {
                            self.\#(name) = \#(name)
                        }
                        
                        """#
                        
                    } else {
                        dec = #"""
                        /// Decoding `\#(name)`
                        guard let stored\#(name.firstCapitalized) = ckRecord["\#(name)"] else {
                            throw CKRecordDecodingError.missingField("\#(name)")
                        }
                        guard let rawValue\#(name.firstCapitalized) = stored\#(name.firstCapitalized) as? \#(type.wrappedTypeName).RawValue else {
                            throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "\#(type)", foundType: "\(unwrappedType(of: stored\#(name.firstCapitalized)))")
                        }
                        guard let \#(name) = \#(type.wrappedTypeName)(rawValue: rawValue\#(name.firstCapitalized)) else {
                            throw CKRecordDecodingError.unableToDecodeRawType(fieldName: "\#(name)", enumType: "\#(type)", rawValue: rawValue\#(name.firstCapitalized))
                        }
                        self.\#(name) = \#(name)
                        
                        """#
                    }
                } else if propertyTypeMarker.propertyType == "codable" {
                    dec = #"""
                    /// Decoding relationship `\#(name)`
                    guard let \#(name)Data = ckRecord["\#(name)"] as? Data\#(type.looksLikeOptionalType ? "?" : "") else {
                        throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "\#(type)", foundType: "\(unwrappedType(of: ckRecord["\#(name)"]))")
                    }
                    self.\#(name) = try JSONDecoder().decode(\#(type.wrappedTypeName).self, from: \#(name)Data)
                    
                    """#
                } else if propertyTypeMarker.propertyType == "nsCoding" {
                    dec = #"""
                    /// Decoding relationship `\#(name)`
                    guard let \#(name)Data = ckRecord["\#(name)"] as? Data\#(type.looksLikeOptionalType ? "?" : "") else {
                        throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "\#(type)", foundType: "\(unwrappedType(of: ckRecord["\#(name)"]))")
                    }
                    self.\#(name) = try\#(type.looksLikeOptionalType ? "?" : "") NSKeyedUnarchiver.unarchivedObject(ofClass: \#(type.wrappedTypeName).self, from: \#(name)Data)!
                    
                    """#
                } else {
                    throw diagnose(.error("Unknown property type"), node: propertyTypeMarker.node)
                }
            } else if type.looksLikeOptionalType {
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
    
    static func makeEncodingDeclarations(forDeclarations declarations: [PropertyDeclaration], mainName: String) throws -> DeclSyntax {
        var declsEnc: [String] = []
        for declaration in declarations {
            let name = declaration.identifier
            let type = declaration.type
            let enc: String
            
            if type == "Data" {
                enc = #"""
                /// Encoding `\#(name)`
                let \#(name)TemporaryAssetURL = URL(fileURLWithPath: NSTemporaryDirectory().appending(UUID().uuidString+".data"))
                do {
                    try self.\#(name).write(to: \#(name)TemporaryAssetURL)
                } catch let error as NSError {
                    debugPrint("Error creating asset for \#(name): \(error)")
                }
                record["\#(name)"] = CKAsset(fileURL: \#(name)TemporaryAssetURL)
                
                """#
            } else if type == "[Data]" {
                enc = #"""
                /// Encoding `\#(name)`
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
            } else if let referenceMarker = declaration.relationshipMarker {
                func ifLetWrapper(content: String) -> String {
                    """
                    if let \(name) {
                    \(content)
                    }
                    """
                }
                if referenceMarker.referenceType == "referencesProperty" {
                    let rela = #"""
                        let childRecord = try \#(name).convertToCKRecord()
                        record["\#(name)"] = CKRecord.Reference(recordID: childRecord.0.recordID, action: .none)
                        relationshipRecords.append(contentsOf: [childRecord.0] + childRecord.1)
                        """#
                    enc = """
                        /// Encoding relationship `\(name)`
                        \(type.looksLikeOptionalType ? ifLetWrapper(content: rela) : rela)
                        
                        """
                } else if referenceMarker.referenceType == "isReferencedByProperty" {
                    let ownedFieldName = referenceMarker.named ?? "\(mainName.dropFirst().dropLast)Owner"
                    let rela = #"""
                            let childRecord = try \#(name).convertToCKRecord()
                            childRecord.0["\#(ownedFieldName)"] = CKRecord.Reference(recordID: record.recordID, action: .deleteSelf)
                            relationshipRecords.append(contentsOf: [childRecord.0] + childRecord.1)
                            """#
                    enc = """
                        /// Encoding relationship `\(name)`
                        \(type.looksLikeOptionalType ? ifLetWrapper(content: rela) : rela)
                        
                        """
                } else {
                    throw diagnose(.error("Unknown reference mode"), node: referenceMarker.node)
                }
            } else if let propertyTypeMarker = declaration.propertyTypeMarker {
                if propertyTypeMarker.propertyType == "rawValue" {
                    enc = #"record["\#(name)"] = self.\#(name)\#(type.looksLikeOptionalType ? "?" : "").rawValue"#
                } else if propertyTypeMarker.propertyType == "codable" {
                    enc = """
                    /// Encoding relationship `\(name)`
                    let encoded\(name.firstCapitalized) = try JSONEncoder().encode(self.\(name))
                    record["\(name)"] = encoded\(name.firstCapitalized)
                    
                    """
                } else if propertyTypeMarker.propertyType == "nsCoding" {
                    enc = """
                    /// Encoding relationship `\(name)`
                    record["\(name)"] = try\(type.looksLikeOptionalType ? "?" : "") NSKeyedArchiver.archivedData(withRootObject: self.\(name), requiringSecureCoding: false)
                    
                    """
                } else {
                    throw diagnose(.error("Unknown reference mode"), node: propertyTypeMarker.node)
                }
            } else {
                enc = #"record["\#(name)"] = self.\#(name)"#
            }
            declsEnc.append(enc)
        }
        
        return "\(raw: declsEnc.joined(separator: "\n"))"
    }
}

extension ConvertibleToCKRecordMacro: ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        let equatableExtension = try ExtensionDeclSyntax("extension \(type.trimmed): SynthesizedCKRecordConvertible {}")
        return [
            equatableExtension
        ]
    }
}

extension String {
    var firstCapitalized: String {
        let firstLetter = self.prefix(1).capitalized
        let remainingLetters = self.dropFirst()
        return firstLetter + remainingLetters
    }
}


extension String {
    var looksLikeOptionalType: Bool {
        (self.hasSuffix("?") || self.hasPrefix("Optional<")) && self.count > 1
    }
    
    var wrappedTypeName: String {
        var filteredType = self
        if filteredType.hasSuffix("?") {
            filteredType = String(filteredType.dropLast())
        }
        if filteredType.hasPrefix("Optional<") {
            filteredType = String(filteredType.dropFirst(9).dropLast())
        }
        return filteredType
    }
}

@main
struct CKMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ConvertibleToCKRecordMacro.self,
        RelationshipMarkerMacro.self,
        CKRecordNameMacro.self,
        CKPropertyTypeMacro.self
    ]
}
