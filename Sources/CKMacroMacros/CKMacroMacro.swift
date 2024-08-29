import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

import CloudKit


public struct ConvertibleToCKRecordMacro: MemberMacro {
    
    typealias DeclarationInfo = (
        identifier: IdentifierPatternSyntax,
        type: TypeAnnotationSyntax?,
        marker: String,
        referenceFirstArgument: String?,
        variableDeclaration: VariableDeclSyntax?
    )
    
    struct PropertyDeclaration {
        
        var parentVariableDeclaration: VariableDeclSyntax
        var bindingDeclaration: PatternBindingSyntax
        
        var identifierSyntax: TokenSyntax
        var typeAnnotationSyntax: TypeAnnotationSyntax
        var identifier: String
        var type: String
        //        var markers: [(PropertyMarker, AttributeSyntax)] = []
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
            if let accessors = bindingDeclaration.accessorBlock?.accessors.as(AccessorDeclListSyntax.self) {
                func hasGetOrSetSpecifier(_ token: AccessorDeclListSyntax.Element) -> Bool {
                    token.accessorSpecifier == .keyword(.get)
                    || token.accessorSpecifier == .keyword(.set)
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
                    recordNameMarker = attribute
                } else if identifier == "CKReference" {
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
    
    static let specialFields: [String: String] = [
        "creationDate": "Date?",
        "modificationDate": "Date?",
        "creatorUserRecordID": "CKRecord.ID?",
        "lastModifiedUserRecordID": "CKRecord.ID?",
        "recordID": "CKRecord.ID",
        "recordChangeTag": "String?"
    ]
    
    static func error(_ s: String, node: SyntaxProtocol) -> Error {
        return DiagnosticsError(diagnostics: [
            Diagnostic(node: node, message: MacroError.simple(s))
        ])
    }
    
    static func warning(_ s: String, node: SyntaxProtocol, context: MacroExpansionContext) throws {
        context.addDiagnostics(from: MacroError.warning(s), node: node)
    }
    
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
        var propertyDeclarations = [PropertyDeclaration]()
        
//        var declarationInfo = [DeclarationInfo]()
//        var declarationInfoD = [DeclarationInfo]()
        
        for member in declaration.memberBlock.members {
            guard let member = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }
            for binding in member.bindings {
                let propertyDeclaration = try PropertyDeclaration(
                    parentVariableDeclaration: member,
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
                        message: MacroError.simple("Multiple properties marked with @CKRecordName")
                    )
                }
                throw DiagnosticsError(diagnostics: diagnostics)
            }
            
            guard let recordNamePropertyFull = recordNameProperties.first else {
                throw DiagnosticsError(diagnostics: [
                    Diagnostic(
                        node: declaration.introducer,
                        message: MacroError.simple("Missing property marked with @CKRecordName \(recordNameProperties.map(\.1))")
                    )
                ])
            }
            return recordNamePropertyFull.0
        }
        
        let recordNamePropertyFull = try getRecordName()
        let recordNameIsOptional = recordNamePropertyFull.type.hasSuffix("?") || recordNamePropertyFull.type.hasPrefix("Optional<")
        guard recordNamePropertyFull.type == "String" else {
            let diagnostic = Diagnostic(
                node: recordNamePropertyFull.typeAnnotationSyntax,
                //                node: recordNamePropertyFull.1!.type,
                message: MacroError.simple("Cannot set property of type '\(recordNamePropertyFull.type)' as record name; the record name has to be a 'String'")
            )
            throw DiagnosticsError(diagnostics: [diagnostic])
        }
        
        propertyDeclarations = propertyDeclarations.filter { $0.recordNameMarker == nil }
        let encodingCodeBlock = try makeEncodingDeclarations(forDeclarations: propertyDeclarations, mainName: recordTypeName)
        let decodingCodeBlock = try makeDecodingDeclarations(forDeclarations: propertyDeclarations, mainName: recordTypeName)
        
        
        let initFromCKRecord = try InitializerDeclSyntax(
            "required init(fromCKRecord ckRecord: CKRecord, fetchingRelationshipsFrom database: CKDatabase? = nil) async throws"
        ) {
            try Self.makeTypeUnwrappingFunc()
            
            "self.\(raw: recordNamePropertyFull.identifier) = ckRecord.recordID.recordName"
            
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
    
    static func makeErrorEnums(className: String) throws -> [DeclSyntax] {
        [
            try makeEncodingErrorEnum(className: className),
            try makeDecodingErrorEnum(className: className)
        ]
    }
    
    static func makeTypeUnwrappingFunc() throws -> [DeclSyntax] {
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
        return [
            DeclSyntax(unwrappedTypeFunc),
            DeclSyntax(ckRecordTypeOfFunc)
        ]
    }
    
    static let callWillFinishDecoding = DeclSyntax(
            """
            if let delegate = (self as Any) as? CKRecordSynthetizationDelegate {
                try delegate.willFinishDecoding(ckRecord: ckRecord)
            }
            """
    )
    
    static let callWillFinishEncoding = DeclSyntax(
            """
            if let delegate = (self as Any) as? CKRecordSynthetizationDelegate {
                try delegate.willFinishEncoding(ckRecord: record)
            }
            """
    )
    
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
    
    static func makeEncodingErrorEnum(className: String) throws -> DeclSyntax {
        let localizedDescriptionEncoding = try VariableDeclSyntax("var localizedDescription: String") {
            #"""
            switch self {
            case .emptyRecordName(let fieldName):
                return "Error when trying to encode instance of \#(raw: className) to CKRecord: '\(fieldName)' is empty; the property marked with @CKRecordName cannot be empty when encoding"
            }
            """#
        }
        
        let encodingError = try EnumDeclSyntax("enum CKRecordEncodingError: Error") {
            "case emptyRecordName(fieldName: String)"
            localizedDescriptionEncoding
        }
        
        return DeclSyntax(encodingError)
    }
    
    static func makeDecodingErrorEnum(className: String) throws -> DeclSyntax {
        let localizedDescriptionProperty = try VariableDeclSyntax("var localizedDescription: String") {
            #"""
            let genericMessage = "Error while trying to initialize an instance of \#(raw: className) from a CKRecord:"
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
        
        return DeclSyntax(decodingError)
    }
    
    static func makeDecodingDeclarations(forDeclarations declarations: [PropertyDeclaration], mainName: String) throws -> DeclSyntax {
        var declsDec: [String] = []
        for declaration in declarations {
            let name = declaration.identifier
            let type = declaration.type
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
            } else if let referenceMarker = declaration.relationshipMarker {
                
                var filteredType = type
                if filteredType.hasSuffix("?") {
                    filteredType = String(filteredType.dropLast())
                }
                if filteredType.hasPrefix("Optional<") {
                    filteredType = String(filteredType.dropFirst(9).dropLast())
                }
                
                let isOptional = filteredType != type
//                let referenceType = declaration.4?.attributes.first?.as(AttributeSyntax.self)?.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.identifier?.name
                let referenceType = referenceMarker.referenceType
                var action = ""
                if referenceType == "referencesProperty" {
                    action = ".none"
                } else if referenceType == "isReferencedByProperty" {
                    action = ".deleteSelf"
                } else if referenceType == "data" {
                    action = "data"
                } else {
                    throw DiagnosticsError(diagnostics: [Diagnostic(node: referenceMarker.node, message: MacroError.simple("Unknown reference mode"))])
                }
                if referenceType == "referencesProperty" {
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
                                let \#(name) = try await \#(filteredType)(fromCKRecord: \#(name)Record, fetchingRelationshipsFrom: database)
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
                    let \#(name) = try await \#(filteredType)(fromCKRecord: \#(name)Record, fetchingRelationshipsFrom: database)
                    self.\#(name) = \#(name)
                    
                    """#
                    )
                } else if referenceType == "isReferencedByProperty" {
                    dec =
                    isOptional
                    ? """
                    // \(referenceType)
                    let \(name)OwnerReference = CKRecord.Reference(recordID: ckRecord.recordID, action: .none)
                    let \(name)Query = CKQuery(recordType: \(filteredType).__recordType, predicate: NSPredicate(format: "\(mainName.dropFirst().dropLast())Owner == %@", \(name)OwnerReference))
                    do {
                        let \(name)FetchResponse = try await database?.records(matching: \(name)Query)
                        guard let \(name)FetchedRecords = \(name)FetchResponse?.0.compactMap({try? $0.1.get()}) else {
                            throw CKRecordDecodingError.missingField("erro curriculum")
                        }
                        if let record = \(name)FetchedRecords.first {
                            \(name) = try await \(filteredType)(fromCKRecord: record, fetchingRelationshipsFrom: database)
                        }
                    } catch CKError.invalidArguments {
                        print("invalid arguments")
                        \(name) = nil
                    }
                      
                    """
                    : #"""
                    guard let database else {
                        throw CKRecordDecodingError.missingDatabase(fieldName: "\#(name)")
                    }
                    let \#(name)Record = try await database.record(for: \#(name)Reference.recordID)
                    let \#(name) = try await \#(filteredType)(fromCKRecord: \#(name)Record, fetchingRelationshipsFrom: database)
                    self.\#(name) = \#(name)
                    
                    """#
                } else {
                    dec = #"""
                    guard \#(name)Data = ckRecord["\#(name)"] as? Data\#(isOptional ? "?" : "") else {
                        throw CKRecordDecodingError.fieldTypeMismatch(fieldName: "\#(name)", expectedType: "\#(type)", foundType: "\(unwrappedType(of: ckRecord["\#(name)"]))")
                    }
                    self.\#(name) = try JSONDecoder().decode(\#(filteredType).self, from: \#(name)Data)
                    """#
                }
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
    
    static func makeEncodingDeclarations(forDeclarations declarations: [PropertyDeclaration], mainName: String) throws -> DeclSyntax {
        var declsEnc: [String] = []
        for declaration in declarations {
            let name = declaration.identifier
            let type = declaration.type
            let enc: String
            guard specialFields.keys.contains(name) == false else {
                continue
            }
            if type == "Data" {
                enc = #"""
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
                let isOptional = type.hasSuffix("?") ?? false || type.hasPrefix("Optional<") ?? false
                let referenceType = referenceMarker.referenceType
                var action = ""
                if referenceType == "referencesProperty" {
                    action = ".none"
                } else if referenceType == "isReferencedByProperty" {
                    action = ".deleteSelf"
                } else if referenceType == "data" {
                    action = "data"
                } else {
                    throw DiagnosticsError(diagnostics: [Diagnostic(node: referenceMarker.node, message: MacroError.simple("Unknown reference mode"))])
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
                } else if referenceType == "isReferencedByProperty" {
                    if isOptional {
                        enc = #"""
                        /// Relationship `\#(name)`
                        if let \#(name) {
                            let childRecord = try \#(name).convertToCKRecord()
                            childRecord.0["\#(mainName.dropFirst().dropLast())Owner"] = CKRecord.Reference(recordID: record.recordID, action: \#(action))
                            relationshipRecords.append(contentsOf: [childRecord.0] + childRecord.1)
                        }
                        
                        """#
                    } else {
                        enc = #"""
                        /// Relationship `\#(name)`
                        let childRecord = try \#(name).convertToCKRecord()
                        childRecord.0["\#(mainName.dropFirst().dropLast())Owner"] = CKRecord.Reference(recordID: record.recordID, action: \#(action))
                        relationshipRecords.append(contentsOf: [childRecord.0] + childRecord.1)
                        
                        """#
                    }
                } else {
                    enc = """
                    /// Relationship `\(name)`
                    let encoded\(name) = try JSONEncoder().encode(\(name))
                    record["\(name)"] = encoded\(name)
                    
                    """
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
