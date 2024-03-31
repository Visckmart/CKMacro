// The Swift Programming Language
// https://docs.swift.org/swift-book

@attached(member, names: named(x), named(convertToCKRecord), named(init(from:)), named(CKRecordDecodingError))
@attached(extension)
public macro ConvertibleToCKRecord(recordType: String? = nil) = #externalMacro(module: "CKMacroMacros", type: "StringifyMacro")

@attached(peer)
public macro Relationship() = #externalMacro(module: "CKMacroMacros", type: "RelationshipMarkerMacro")
