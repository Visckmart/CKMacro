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
        var decls = [(IdentifierPatternSyntax, IdentifierTypeSyntax)]()
        for member in declaration.memberBlock.members ?? [] {
//            let member = member.as(NamedDeclSyntax.self)
            print.append("\(member.as(MemberBlockItemSyntax.self)?.decl)")
            if let member = member.decl.as(VariableDeclSyntax.self) {
                for binding in member.bindings {
                    if let bindingPattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        print.append(bindingPattern.identifier.trimmed.text)
                        decls.append((bindingPattern, binding.typeAnnotation!.type.as(IdentifierTypeSyntax.self)!))
                    }
                }
            }
        }
        
        
        var declsEnc: [String] = []
        for declaration in decls {
            let name = declaration.0.identifier.trimmed.text
            let type = declaration.1
            let enc: String
//            if type.trimmed.name.text == "Optional" {
//                enc = #"if let \#(name) {\#n\#trecord["\#(name)"] = \#(name) }"#
//            } else {
                enc = #"\#trecord["\#(name)"] = self.\#(name)"#
//                \#(type.name) \#(type.trimmed.name == "Optional")
//            }
//            let enc = #"\#trecord["\#(name)"] = self.\#(name)"#
            declsEnc.append(enc)
        }
        
        var declsDec: [String] = []
        for declaration in decls {
            let name = declaration.0.identifier.trimmed.text
            let type = declaration.1
            let dec: String
//            if type.name == "Optional" {
//                dec = #"if let \#(name) = ckRecord["\#(name)"] as? \#(type) {\#n\#t\#tself.\#(name) = \#(name) }"#
//            } else {
//                dec = #"\#tself.\#(name) = ckRecord["\#(name)"] as! \#(type)"#
//            }
            dec = #"\#tguard let \#(name) = ckRecord["\#(name)"] as? \#(type.trimmed) else {\#nreturn nil }\#nself.\#(name) = \#(name)"#
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
            required init?(from ckRecord: CKRecord) {
            \(raw: declsDec.joined(separator: "\n"))
            }
            """,
            #"var x = """\#n\#(raw: decls.map{$0.1.description}.joined(separator: "\n"))\#n""""#
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

@main
struct CKMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StringifyMacro.self,
    ]
}
