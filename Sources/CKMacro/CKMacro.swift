// The Swift Programming Language
// https://docs.swift.org/swift-book

/// A macro that produces both a value and a string containing the
/// source code that generated the value. For example,
///
///     #stringify(x + y)
///
/// produces a tuple `(x + y, "x + y")`.
@attached(member, names: named(x), named(convertToCKRecord), named(init(from:)), named(CKRecordDecodingError))
@attached(extension)
public macro convertibleToCKRecord(recordType: String? = nil) = #externalMacro(module: "CKMacroMacros", type: "StringifyMacro")
