import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `stringify` macro, which takes an expression
/// of any type and produces a tuple containing the value of that expression
/// and the source code that produced the value. For example
///
///     #stringify(x + y)
///
///  will expand to
///
///     (x + y, "x + y")
public struct StringifyMacro: MemberMacro {
    
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        var print = [String]()
        var decls = [(IdentifierPatternSyntax, TypeAnnotationSyntax?)]()
        for member in declaration.memberBlock.members ?? [] {
//            let member = member.as(NamedDeclSyntax.self)
            print.append("\(member.as(MemberBlockItemSyntax.self)?.decl)")
            if let member = member.decl.as(VariableDeclSyntax.self) {
                for binding in member.bindings {
                    if let bindingPattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        print.append(bindingPattern.identifier.trimmed.text)
                        decls.append((bindingPattern, binding.typeAnnotation))
                    }
                }
            }
        }
//        let ck = CKRecord(recordType: "a")
//        ck.lastModifiedUserRecordID
        
        let specialFields: [String: String] = [
            "creationDate": "Date?",
            "modificationDate": "Date?",
            "creatorUserRecordID": "CKRecord.ID?",
            "lastModifiedUserRecordID": "CKRecord.ID?",
            "recordID": "CKRecord.ID",
            "recordChangeTag": "String?"
        ]
        
        var declsEnc: [String] = []
        for declaration in decls {
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
            } else {
                enc = #"\#trecord["\#(name)"] = self.\#(name)"#
//                enc = #"record.setValue(self.\#(name), forKey: "\#(name)")"#
            }
            declsEnc.append(enc)
        }
        
        var declsDec: [String] = []
        for declaration in decls {
            let name = declaration.0.identifier.trimmed.text
            let type = declaration.1!.type.trimmedDescription
            let dec: String
            
            
            if let entry = specialFields[name] {
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
                    throw CKRecordDecodingError.fieldWrongType("\#(name)", "\(type(of: raw\#(name.firstCapitalized)))", "\#(type)")
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
                    throw CKRecordDecodingError.fieldWrongType("\#(name)", "\(type(of: raw\#(name.firstCapitalized)))", "\#(type)")
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
                    throw CKRecordDecodingError.fieldWrongType("\#(name)", "\(type(of: ckRecord["\#(name)"]))", "\#(type)")
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
                    throw CKRecordDecodingError.fieldWrongType("\#(name)", "\(type(of: raw\#(name.firstCapitalized)))", "\#(type)")
                }
                self.\#(name) = \#(name)
                
                """#
            }
            declsDec.append(dec)
        }
        let s = node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.trimmed.description ?? "\"\(declaration.as(ClassDeclSyntax.self)?.name.trimmed.text ?? "unknown")\""
        return [
//            #"var x = "\#(node.arguments?.firstToken(viewMode: .all) ?? "a")""#,
            """
            func convertToCKRecord() -> CKRecord {
                let record = CKRecord(recordType: \(raw: s))
                
                \(raw: declsEnc.joined(separator: "\n"))
            
                return record
            }
            """,
            """
            required init(from ckRecord: CKRecord) throws {
                \(raw: declsDec.joined(separator: "\n"))
            }
            """,
            """
            enum CKRecordDecodingError: Error {
                case missingField(String)
                case fieldWrongType(String, String, String)
            }
            """,
            #"var x = """\#n\#n""""#
//            #"var x = """\#n\#(raw: s)\#n""""#
//            #"var x = """\#n\#(raw: print.joined(separator: "\n--------\n"))\#n""""#
        ]
    }
}

extension StringifyMacro: ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        return [
//            try ExtensionDeclSyntax("extension \(declaration.as(ClassDeclSyntax.self)?.name.trimmed ?? "unknown") { static let i = 20 }")
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
        StringifyMacro.self,
    ]
}
