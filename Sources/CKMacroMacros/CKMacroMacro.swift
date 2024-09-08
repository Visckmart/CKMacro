import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder
import SwiftDiagnostics

import CloudKit

public struct ConvertibleToCKRecordMacro: MemberMacro {
    static var debugNode = AttributeSyntax("")
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        debugNode = node
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            throw diagnose(.warning("Macro has to be used in a class"), node: node)
        }
        let className = classDecl.name.trimmed.text
        
        let recordTypeName: String
        var debugMode = false
        
        
        // Process arguments
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            // Get `recordType` argument
            if let firstMacroArgument = arguments.first(where: { $0.label?.text == "recordType" }) {
                guard let stringValue = firstMacroArgument.expression.as(StringLiteralExprSyntax.self) else {
                    throw diagnose(.error("Record type must be defined by a string literal"), node: declaration)
                }
                recordTypeName = stringValue.description
            } else {
                recordTypeName = "\"\(className)\""
            }
            
            // Get `debug` argument
            if let debugArgument = arguments.first(where: { $0.label?.text == "debug" }) {
                guard let debugExpression = debugArgument.expression.as(BooleanLiteralExprSyntax.self) else {
                    throw diagnose(.error("Debug mode must be defined by a boolean literal"), node: debugArgument)
                }
                debugMode = debugExpression.literal.tokenKind == .keyword(.true)
            }
        } else {
            recordTypeName = "\"\(className)\""
        }
        
        // Process property declarations
        var propertyDeclarations = [PropertyDeclaration]()
        for member in declaration.memberBlock.members {
            guard let variableDeclaration = member.decl.as(VariableDeclSyntax.self) else { continue }
            
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
        
        let hasReference = propertyDeclarations.contains(where: { $0.referenceMarker != nil })
        
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
        
        let recordNameProperty = try getRecordName()
        
        if debugMode {
            context.diagnose(Diagnostic(node: declaration,
                                        message: MacroError.warning("Record type: \(recordTypeName)")))
            
            context.diagnose(Diagnostic(node: recordNameProperty.bindingDeclaration,
                                        message: MacroError.warning("Record name")))
            for propertyDeclaration in propertyDeclarations {
                context.diagnose(Diagnostic(node: propertyDeclaration.bindingDeclaration,
                                            message: MacroError.warning("\(propertyDeclaration)")))
            }
        }
        
        guard recordNameProperty.type == "String" else {
            throw diagnose(
                .error("Cannot set property of type '\(recordNameProperty.type)' as record name; the record name has to be a 'String'"),
                node: recordNameProperty.typeAnnotationSyntax
            )
        }
//        throw error(">\(recordNameProperty.identifier)<", node: node)
        let recordProperties = try Self.makeRecordProperties(
            recordNameProperty: recordNameProperty.identifier,
            recordType: recordTypeName,
            getOnly: recordNameProperty.isConstant
        )
//        throw error("\(recordProperties[0].debugDescription)", node: node)
        let initFromCKRecord = try InitializerDeclSyntax(
            "required init(fromCKRecord ckRecord: CKRecord, fetchingReferencesFrom database: CKDatabase? = nil) async throws"
        ) {
            try DeclSyntax(validating: "let recordType = \(raw: recordTypeName)")
            
            try ExprSyntax(validating: "self.\(raw: recordNameProperty.identifier) = ckRecord.recordID.recordName")
                .with(\.trailingTrivia, .newlines(2))
            
            try makeDecodingDeclarations(forDeclarations: propertyDeclarations, mainName: recordTypeName)
            
            callWillFinishDecoding
        }
        
        let initializeCKRecord = try CodeBlockItemListSyntax(validating: """
            let record: CKRecord
            if let baseRecord {
                record = baseRecord
            } else {
                guard self.__recordName.isEmpty == false else {
                    throw CKRecordEncodingError.emptyRecordName(recordType: \(raw: recordTypeName), fieldName: \(literal: recordNameProperty.identifier))
                }
                record = CKRecord(recordType: \(raw: recordTypeName), recordID: __recordID)
            }
            """)
            .with(\.trailingTrivia, .newlines(2))
        
        let convertToCKRecordMethod = try FunctionDeclSyntax(
            "func convertToCKRecord(usingBaseCKRecord baseRecord: CKRecord? = nil) throws -> (instance: CKRecord, references: [CKRecord])"
        ) {
            initializeCKRecord
            
            if hasReference {
                try DeclSyntax(validating: "var referenceRecords: [CKRecord] = []")
            }
            
            try makeEncodingDeclarations(forDeclarations: propertyDeclarations, mainName: recordTypeName)
            
            Self.callWillFinishEncoding
            
            let referencesExpr = try ExprSyntax(validating: hasReference ? "referenceRecords" : "[]")
            try StmtSyntax(validating: "return (instance: record, references: \(referencesExpr))")
        }
        
        return recordProperties + [
            DeclSyntax(initFromCKRecord),
            DeclSyntax(convertToCKRecordMethod),
        ]
        
    }
    
    
    static func makeRecordProperties(recordNameProperty: String, recordType: String, getOnly: Bool) throws -> [DeclSyntax] {
        let synthesizedRecordNameProperty: DeclSyntax = """
            var __recordName: String {
                get {
                    self.\(raw: recordNameProperty)
                }
                set {
                    self.\(raw: recordNameProperty) = newValue
                }
            }
            """
        
        let synthesizedRecordIDProperty: DeclSyntax = """
            var __recordID: CKRecord.ID {
                get {
                    return CKRecord.ID(recordName: self.__recordName)
                }
                
                set {
                    self.__recordName = newValue.recordName
                }
            }
            """
        
        let synthesizedRecordTypeProperty = try VariableDeclSyntax(
            "static let __recordType: String = \(raw: recordType)"
        )
        
        return [
            DeclSyntax(synthesizedRecordNameProperty),
            DeclSyntax(synthesizedRecordIDProperty),
            DeclSyntax(synthesizedRecordTypeProperty)
        ]
    }
    
    
    static func makeDecodingDeclarations(forDeclarations declarations: [PropertyDeclaration], mainName: String) throws -> CodeBlockItemListSyntax {
        var declsDec: CodeBlockItemListSyntax = .init()
        for declaration in declarations where declaration.recordNameMarker == nil {
            let name = declaration.identifier
            let type = declaration.type
            var dec: CodeBlockItemListSyntax
            
            let isOptional = declaration.typeIsOptional
            //let questionMarkIfOptional = isOptional ? "?" : ""
            let wrappedTypeName = declaration.typeAnnotationSyntax.type.wrappedInOptional?.trimmed.description ?? type
//            if name == "optionalString" {
//                throw error("\(declaration.typeAnnotationSyntax.type.wrappedInOptional)", node: debugNode)
//            }
            var headerComment: Trivia = [.docLineComment("/// Decoding `\(name)`"), .newlines(1)]
            
            if type == "Data" {
                dec = ""
                declsDec.append(#"""
                /// Decoding `\#(raw: name)`
                guard let raw\#(raw: name.firstCapitalized) = ckRecord["\#(raw: name)"] else {
                    \#(throwMissingField(fieldName: name))
                }
                guard
                    let \#(raw: name) = raw\#(raw: name.firstCapitalized) as? CKAsset,
                    let \#(raw: name)FileURL = \#(raw: name).fileURL,
                    let \#(raw: name)Content = try? Data(contentsOf: \#(raw: name)FileURL)
                else {
                        \#(throwFieldTypeMismatch(fieldName: name, expectedType: type, foundValue: #"raw\#(name.firstCapitalized)"#))
                }
                self.\#(raw: name) = \#(raw: name)Content
                
                """#)
            } else if type == "[Data]" {
                dec = #"""
                /// Decoding `\#(raw: name)`
                guard let raw\#(raw: name.firstCapitalized) = ckRecord["\#(raw: name)"] else {
                    throw CKRecordDecodingError.throwMissingField(recordType: \#(raw: mainName), fieldName: "\#(raw: name)")
                }
                guard let \#(raw: name) = raw\#(raw: name.firstCapitalized) as? [CKAsset] else {
                    \#(throwFieldTypeMismatch(fieldName: name, expectedType: type, foundValue: #"raw\#(name.firstCapitalized)"#))
                }
                var \#(raw: name)AssetContents = [Data]()
                for asset in \#(raw: name) {
                    guard
                        let \#(raw: name)FileURL = asset.fileURL,
                        let \#(raw: name)Content = try? Data(contentsOf: \#(raw: name)FileURL)
                    else {
                        continue
                    }
                    \#(raw: name)AssetContents.append(\#(raw: name)Content)
                }
                self.\#(raw: name) = \#(raw: name)AssetContents
                
                """#
            } else if let referenceMarker = declaration.referenceMarker {
                let databaseCheck: CodeBlockSyntax  = #"""
                    // Check if database argument is present to fetch reference 
                    guard let \#(raw: name)Database = database else {
                        throw CKRecordDecodingError.missingDatabase(recordType: \#(raw: mainName), fieldName: "\#(raw: name)")
                    }
                    """#
                
                if referenceMarker.referenceType == "referencesProperty" {
                    dec = ""
                    let ckReferenceType = "CKRecord.Reference" + (isOptional ? "?" : "")
                    // Decode reference
                    declsDec.append(#"""
                        /// Decoding reference `\#(raw: name)`
                        guard let \#(raw: name)Reference = ckRecord["\#(raw: name)"] as? \#(raw: ckReferenceType) else {
                            \#(throwFieldTypeMismatch(fieldName: name, expectedType: ckReferenceType, foundValue: #"ckRecord["\#(name)"]"#))
                        }
                        """#)
                    
                    // Fetch if reference is found
                    let fetchOptionallyReferencedProperty: CodeBlockItemListSyntax = #"""
                        if let \#(raw: name)Reference {
                            \#(databaseCheck)
                            var \#(raw: name)Record: CKRecord?
                            do {
                                // Fetch CKRecord from reference
                                \#(raw: name)Record = try await \#(raw: name)Database.record(for: \#(raw: name)Reference.recordID)
                            } catch CKError.unknownItem {
                                \#(raw: name)Record = nil
                            }
                            if let \#(raw: name)Record {
                                do {
                                    // Decode `\#(raw: wrappedTypeName)` from `CKRecord`
                                    self.\#(raw: name) = try await \#(raw: wrappedTypeName)(fromCKRecord: \#(raw: name)Record, fetchingReferencesFrom: \#(raw: name)Database)
                                } catch {
                                    throw CKRecordDecodingError.errorDecodingNestedField(recordType: \#(raw: mainName), fieldName: "\#(raw: name)", error)
                                }
                            } else {
                                self.\#(raw: name) = nil
                            }
                        }
                          
                        """#
                    
                    // Fetch reference
                    let fetchReferencedProperty: CodeBlockItemListSyntax = #"""
                        \#(databaseCheck)
                        let \#(raw: name)Record = try await \#(raw: name)Database.record(for: \#(raw: name)Reference.recordID)
                        self.\#(raw: name) = try await \#(raw: wrappedTypeName)(fromCKRecord: \#(raw: name)Record, fetchingReferencesFrom: \#(raw: name)Database)
                        """#
                    
                    declsDec.append(contentsOf: isOptional
                                                ? fetchOptionallyReferencedProperty
                                                : fetchReferencedProperty)
                } else if referenceMarker.referenceType == "isReferencedByProperty" {
                    let ownedFieldName = referenceMarker.named ?? "\(mainName.dropFirst().dropLast())Owner"
                    dec =
                    isOptional
                    ? #"""
                    /// Decoding reference `\#(raw: name)`
                    \#(raw: databaseCheck)
                    let \#(raw: name)OwnerReference = CKRecord.Reference(recordID: ckRecord.recordID, action: .none)
                    let \#(raw: name)Query = CKQuery(recordType: \#(raw: wrappedTypeName).__recordType, predicate: NSPredicate(format: "\#(raw: ownedFieldName) == %@", \#(raw: name)OwnerReference))
                    do {
                        let \#(raw: name)FetchResponse = try await \#(raw: name)Database.records(matching: \#(raw: name)Query)
                        guard \#(raw: name)FetchResponse.matchResults.count <= 1 else {
                            throw CKRecordDecodingError.multipleRecordsWithSameOwner(recordType: \#(raw: mainName))
                        }
                        let \#(raw: name)FetchedRecords = try \#(raw: name)FetchResponse.matchResults.compactMap({ try $0.1.get() })
                        if let record = \#(raw: name)FetchedRecords.first {
                            self.\#(raw: name) = try await \#(raw: wrappedTypeName)(fromCKRecord: record, fetchingReferencesFrom: \#(raw: name)Database)
                        } else {
                            self.\#(raw: name) = nil
                        }
                    } catch CKError.unknownItem {
                        self.\#(raw: name) = nil
                    } catch CKError.invalidArguments {
                        self.\#(raw: name) = nil
                    }
                      
                    """#
                    :
                    #"""
                    /// Decoding reference `\#(raw: name)`
                    \#(raw: databaseCheck)
                    let \#(raw: name)OwnerReference = CKRecord.Reference(recordID: ckRecord.recordID, action: .none)
                    let \#(raw: name)Query = CKQuery(recordType: \#(raw: wrappedTypeName).__recordType, predicate: NSPredicate(format: "\#(raw: ownedFieldName) == %@", \#(raw: name)OwnerReference))
                    do {
                        let \#(raw: name)FetchResponse = try await \#(raw: name)Database.records(matching: \#(raw: name)Query)
                        guard \#(raw: name)FetchResponse.0.count <= 1 else {
                            throw CKRecordDecodingError.multipleRecordsWithSameOwner
                        }
                        let \#(raw: name)FetchedRecords = try \#(raw: name)FetchResponse.0.compactMap({ try $0.1.get() })
                        if let record = \#(raw: name)FetchedRecords.first {
                            self.\#(raw: name) = try await \#(raw: wrappedTypeName)(fromCKRecord: record, fetchingReferencesFrom: \#(raw: name)Database)
                        } else {
                            \#(throwMissingField(fieldName: name))
                        }
                    } catch CKError.unknownItem {
                        \#(throwMissingField(fieldName: name))
                    }
                    
                    """#
                } else {
                    throw diagnose(.error("Unknown reference mode"), node: referenceMarker.node)
                }
            } else if let propertyTypeMarker = declaration.propertyTypeMarker {
                let dataDecodingErrorCatch = try CatchClauseSyntax(validating: #"""
                    catch {
                        throw CKRecordDecodingError.unableToDecodeDataType(
                            recordType: recordType, 
                            fieldName: \#(literal: name), 
                            decodingType: \#(literal: propertyTypeMarker.propertyType), 
                            error: error
                        )
                    }
                    """#)
                
                if propertyTypeMarker.propertyType == "rawValue" {
                    let rawValueVarName = "rawValue\(name.firstCapitalized)"
                    
                    dec = try CodeBlockItemListSyntax {
                        if !isOptional {
                            try checkPresence(ofField: name, andStoreIn: name)
                        }
                        try guardType(
                            of: isOptional ? #"ckRecord["\#(raw: name)"]"# : "\(raw: name)",
                            is: "\(wrappedTypeName).RawValue", optional: isOptional,
                            andStoreIn: rawValueVarName,
                            forField: name
                        )
                        
                        if isOptional {
                            try CodeBlockItemListSyntax(validating: #"""
                                if let \#(raw: rawValueVarName),
                                   let \#(raw: name) = \#(raw: wrappedTypeName)(rawValue: \#(raw: rawValueVarName)) {
                                    self.\#(raw: name) = \#(raw: name)
                                }
                                """#)
                        } else {
                            try CodeBlockItemListSyntax(validating: #"""
                                guard let \#(raw: name) = \#(raw: wrappedTypeName)(rawValue: \#(raw: rawValueVarName)) else {
                                    throw CKRecordDecodingError.unableToDecodeRawType(
                                        recordType: \#(raw: mainName), 
                                        fieldName: "\#(raw: name)", 
                                        enumType: "\#(raw: type)", 
                                        rawValue: \#(raw: rawValueVarName)
                                    )
                                }
                                self.\#(raw: name) = \#(raw: name)
                                """#)
                        }
                        
                        
                    }
                } else if propertyTypeMarker.propertyType == "codable" {
                    let dataVarName = "\(name)Data"
                    
                    dec = try CodeBlockItemListSyntax {
                        if isOptional {
                            try guardType(
                                of: #"ckRecord["\#(raw: name)"]"#, is: "Data", optional: isOptional,
                                andStoreIn: dataVarName,
                                forField: name
                            )
                        } else {
                            try checkPresence(ofField: name)
                            try guardType(
                                of: "\(raw: name)", is: "Data", optional: isOptional,
                                andStoreIn: dataVarName,
                                forField: name
                            )
                        }
                        
                        try wrapInIfLet(dataVarName, if: isOptional) {
                            try DoStmtSyntax(catchClauses: [dataDecodingErrorCatch]) {
                                try ExprSyntax(validating: #"""
                                self.\#(raw: name) = try JSONDecoder().decode(\#(raw: wrappedTypeName).self, from: \#(raw: name)Data)
                                """#)
                            }
                        } else: {
                            try ExprSyntax(validating: "self.\(raw: name) = nil")
                        }
                    }
                    //.with(\.leadingTrivia, headerComment)
                } else if propertyTypeMarker.propertyType == "nsCoding" {
                    let dataVarName = "\(name)Data"
                    let arrayElementType = declaration.typeAnnotationSyntax.type.arrayElementType
                    
                    let unarchiveCall: ExprSyntax
                    if let arrayElementType {
                        unarchiveCall = try ExprSyntax(validating: #"""
                            NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: \#(raw: arrayElementType.description).self, from: \#(raw: dataVarName))!
                            """#)
                    } else {
                        unarchiveCall = try ExprSyntax(validating: #"""
                            NSKeyedUnarchiver.unarchivedObject(ofClass: \#(raw: wrappedTypeName).self, from: \#(raw: dataVarName))!
                            """#)
                    }
                    
                    dec = try CodeBlockItemListSyntax {
                        if isOptional {
                            try guardType(
                                of: #"ckRecord["\#(raw: name)"]"#, is: "Data", optional: isOptional,
                                andStoreIn: dataVarName,
                                forField: name
                            )
                        } else {
                            try checkPresence(ofField: name)
                            try guardType(
                                of: "\(raw: name)", is: "Data", optional: isOptional,
                                andStoreIn: dataVarName,
                                forField: name
                            )
                        }
                        
                        try wrapInIfLet(dataVarName, if: isOptional) {
                            try DoStmtSyntax(catchClauses: [dataDecodingErrorCatch]) {
                                try ExprSyntax(validating: #"""
                                    self.\#(raw: name) = try \#(unarchiveCall)
                                """#)
                            }
                        } else: {
                            try ExprSyntax(validating: "self.\(raw: name) = nil")
                        }
                    }
                } else {
                    throw diagnose(.error("Unknown property type"), node: propertyTypeMarker.node)
                }
            } else if isOptional {
                dec = try CodeBlockItemListSyntax {
                    try guardType(of: #"ckRecord["\#(raw: name)"]"#, is: wrappedTypeName, optional: isOptional, andStoreIn: name, forField: name)
                    try ExprSyntax(validating: #"""
                        self.\#(raw: name) = \#(raw: name)
                        """#)
                }
            } else {
                dec = try CodeBlockItemListSyntax {
                    try checkPresence(ofField: name)
                    try guardType(of: #"\#(raw: name)"#, is: type, optional: false, andStoreIn: name, forField: name)
                    try ExprSyntax(validating: #"""
                        self.\#(raw: name) = \#(raw: name)
                        """#)
                }
            }
            declsDec.append(contentsOf: dec.with(\.trailingTrivia, .newlines(2)))
        }
        
        return declsDec
    }
    
    static func makeEncodingDeclarations(forDeclarations declarations: [PropertyDeclaration], mainName: String) throws -> CodeBlockItemListSyntax {
        var declsEnc = CodeBlockItemListSyntax()
        for declaration in declarations where declaration.recordNameMarker == nil {
            let name = declaration.identifier
            let type = declaration.type
            let enc: CodeBlockItemListSyntax
            let isOptional = declaration.typeIsOptional
            let questionMarkIfOptional = isOptional ? "?" : ""
            var addNewLine = true
            if type == "Data" {
                enc = #"""
                /// Encoding `\#(raw: name)`
                let \#(raw: name)TemporaryAssetURL = URL(fileURLWithPath: NSTemporaryDirectory().appending(UUID().uuidString+".data"))
                do {
                    try self.\#(raw: name).write(to: \#(raw: name)TemporaryAssetURL)
                } catch let error as NSError {
                    debugPrint("Error creating asset for \#(raw: name): \(error)")
                }
                record["\#(raw: name)"] = CKAsset(fileURL: \#(raw: name)TemporaryAssetURL)
                
                """#
            } else if type == "[Data]" {
                enc = #"""
                /// Encoding `\#(raw: name)`
                var \#(raw: name)Assets = [CKAsset]()
                for data in self.\#(raw: name) {
                    let \#(raw: name)TemporaryAssetURL = URL(fileURLWithPath: NSTemporaryDirectory().appending(UUID().uuidString+".data"))
                    do {
                        try data.write(to: \#(raw: name)TemporaryAssetURL)
                        \#(raw: name)Assets.append(CKAsset(fileURL: \#(raw: name)TemporaryAssetURL))
                    } catch let error as NSError {
                        debugPrint("Error creating assets for \#(raw: name): \(error)")
                    }
                }
                record["\#(raw: name)"] = \#(raw: name)Assets
                
                """#
            } else if let referenceMarker = declaration.referenceMarker {
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
                        record["\#(name)"] = CKRecord.Reference(recordID: childRecord.instance.recordID, action: .none)
                        referenceRecords.append(contentsOf: [childRecord.instance] + childRecord.references)
                        """#
                    enc = #"""
                        /// Encoding reference `\#(raw: name)`
                        \#(raw: isOptional ? ifLetWrapper(content: rela) : rela)
                        
                        """#
                } else if referenceMarker.referenceType == "isReferencedByProperty" {
                    let ownedFieldName = referenceMarker.named ?? "\(mainName.dropFirst().dropLast())Owner"
                    let rela = #"""
                            let childRecord = try \#(name).convertToCKRecord()
                            childRecord.instance["\#(ownedFieldName)"] = CKRecord.Reference(recordID: record.recordID, action: .deleteSelf)
                            referenceRecords.append(contentsOf: [childRecord.instance] + childRecord.references)
                            """#
                    enc = #"""
                        /// Encoding reference `\#(raw: name)`
                        \#(raw: isOptional ? ifLetWrapper(content: rela) : rela)
                        
                        """#
                } else {
                    throw diagnose(.error("Unknown reference mode"), node: referenceMarker.node)
                }
            } else if let propertyTypeMarker = declaration.propertyTypeMarker {
                if propertyTypeMarker.propertyType == "rawValue" {
                    enc = #"record["\#(raw: name)"] = self.\#(raw: name)\#(raw: questionMarkIfOptional).rawValue"#
                } else if propertyTypeMarker.propertyType == "codable" {
                    if isOptional {
                        enc = #"""
                    /// Encoding `\#(raw: name)`
                    if let \#(raw: name) {
                        let encoded\#(raw: name.firstCapitalized) = try JSONEncoder().encode(\#(raw: name))
                        record["\#(raw: name)"] = encoded\#(raw: name.firstCapitalized)
                    }
                    """#
                    } else {
                        enc = #"""
                    /// Encoding `\#(raw: name)`
                    let encoded\#(raw: name.firstCapitalized) = try JSONEncoder().encode(self.\#(raw: name))
                    record["\#(raw: name)"] = encoded\#(raw: name.firstCapitalized)
                    
                    """#
                        }
                } else if propertyTypeMarker.propertyType == "nsCoding" {
                    if isOptional {
                        enc = #"""
                        /// Encoding `\#(raw: name)`
                        if let \#(raw: name) {
                            record["\#(raw: name)"] = try\#(raw: questionMarkIfOptional) NSKeyedArchiver.archivedData(withRootObject: \#(raw :name), requiringSecureCoding: false)
                        }
                        
                        """#
                    } else {
                        enc = #"""
                        /// Encoding `\#(raw: name)`
                        record["\#(raw: name)"] = try\#(raw: questionMarkIfOptional) NSKeyedArchiver.archivedData(withRootObject: self.\#(raw :name), requiringSecureCoding: false)
                        
                        """#
                    }
                } else {
                    throw diagnose(.error("Unknown reference mode"), node: propertyTypeMarker.node)
                }
            } else {
                enc = #"record["\#(raw: name)"] = self.\#(raw: name)"#
                addNewLine = false
            }
            
            declsEnc.append(contentsOf: try CodeBlockItemListSyntax(validating: enc).with(\.trailingTrivia, addNewLine ? .newlines(2) : .newline))
        }
        
        return try CodeBlockItemListSyntax(validating: declsEnc)
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

@main
struct CKMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ConvertibleToCKRecordMacro.self,
        RelationshipMarkerMacro.self,
        CKRecordNameMacro.self,
        CKPropertyTypeMacro.self
    ]
}


extension CodeBlockItemSyntax {
    func wrappedInIfLet(_ name: String, if isOptional: Bool) throws -> CodeBlockItemListSyntax {
        return try CodeBlockItemListSyntax {
            if isOptional {
                try IfExprSyntax("if let \(raw: name)") {
                    self
                }
            } else {
                self
            }
        }
    }
}
