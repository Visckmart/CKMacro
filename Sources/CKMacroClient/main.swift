import CKMacro
import CloudKit

@ConvertibleToCKRecord
class User {
    
//    @CKReference(action: .deleteSelf) var sub: User? = nil
    @CKReference(action: .deleteSelf) var extra: Extra
    var dataList: [Data] = [Data()]
    var photo: Data = "testando".data(using: .utf8)!
    var otherPhoto: Data = Data()
    var name: String?
    var idade: Int = Int.random(in: 10...20)
    var bool: Bool = false
    var child: Int? = 10// = User(name: "a")
    var lastModifiedUserRecordID: CKRecord.ID?
    var creationDate: Date? = Date()
    var recordChangeTag: String?
    let rawName: String
//    var id: CKRecord.ID? { get { __recordID } }
//    var recordName: String? { get { }}
    
    init(name: String, sub: User? = nil) {
        self.name = name
        self.rawName = "1"
        self.extra = Extra()
    }
}

@ConvertibleToCKRecord
class Extra {
    var info: Int = 10
    init(info: Int = 10) {
        self.info = info
    }
}

//User(name: "a").id
extension User: CKRecordSynthetizationDelegate {
    func willFinishEncoding(ckRecord: CKRecord) {
        ckRecord["name"] = "y"
    }
    func willFinishDecoding(ckRecord: CKRecord) {
        if let name = ckRecord["name"] as? String, name.hasPrefix("b") {
            self.idade = 100
        }
        self.name = "testing"
    }
}
//extension User: SynthesizedCKRecordConvertible {
//    static func willFinishDecoding(ckRecord: inout CKRecord) {
//        <#code#>
//    }
//}
public extension CKRecord {
    var systemFieldsData: Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }
    
    convenience init?(systemFieldsData: Data) {
        guard let una = try? NSKeyedUnarchiver(forReadingFrom: systemFieldsData) else {
            return nil
        }
        self.init(coder: una)
    }
}

await Task {
    do {
        //    CKDatabase().record(for: <#T##CKRecord.ID#>)
        //CKRecord.Reference(recordID: CKRecord.ID(recordName: "a"), action: .none).recordID
        //CKRecord(recordType: "a").
        let u1 = User(name: "j"/*, sub: User(name: "children")*/)
        //print(u1.x)
        let c1: some SynthesizedCKRecordConvertible = u1
        let r1 = c1.convertToCKRecord(usingBaseCKRecord: nil)
        //r1.lastModifiedUserRecordID = .init(recordName: "a")
        print(r1.creationDate)
        print(u1.convertToCKRecord())
//        print(u1.id)
        let reco = u1.convertToCKRecord()
        print(r1["name"])
//        reco["name"] = true
//        print(typeWrapper(of: reco["name"]))
//        reco["name"] = "bay"
        let b = try await User(from: reco)
        print(b.name)
        print(b.bool)
        dump(r1["bool"])
        //print(CKRecord(systemFieldsData: u1.convertToCKRecord().systemFieldsData))
        //reco["child"] = "a"
        //var m = Mirror(reflecting: try! User(from: reco))
        //print(m.children.map({ child in
        //    "\(child.label ?? "?"): \(child.value)"
        //}).joined(separator: "\n"))
    } catch let error as User.CKRecordDecodingError {
        print(error.localizedDescription)
    }
}.value
//
//func opening<T: CKRecordValue>(x: T?) -> Any.Type? {
//    x.flatMap { type(of: $0 as Any) }
//}
//func typeWrapper<T>(of value: T) -> Any.Type {
//    if let ckRecordValue = value as? CKRecordValue {
//        ckRecordTypeOf(of: ckRecordValue)
//    } else {
//        Swift.type(of: value as Any)
//    }
//}
//func ckRecordTypeOf<T: CKRecordValue>(of v: T) -> Any.Type {
//    Swift.type(of: v as Any)
//}

//@ConvertibleToCKRecord
class ModularDefinition {
    var integer: Int
    init(integer: Int = 10) {
        self.integer = integer
    }
    static func decodeInteger(ckRecord: CKRecord) throws -> Int {
        /// Decoding `integer`
        guard let rawInteger = ckRecord["integer"] else {
            throw CKRecordDecodingError.missingField("integer")
        }
        guard let integer = rawInteger as? Int else {
            throw CKRecordDecodingError.missingField("integer2")
        }
        let x: PartialKeyPath<Self> = \.integer
        return 100
    }
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
        
        self.__recordID = ckRecord.recordID
        
        
        self.integer = try Self.decodeInteger(ckRecord: ckRecord)
        
        
        if let delegate = self as? CKRecordSynthetizationDelegate {
            delegate.willFinishDecoding(ckRecord: ckRecord)
        }
    }
    
    func convertToCKRecord(usingBaseCKRecord baseRecord: CKRecord? = nil) -> CKRecord {
        var record: CKRecord
        if let baseRecord {
            record = baseRecord
        } else if let __recordID {
            record = CKRecord(recordType: "ModularDefinition", recordID: __recordID)
        } else {
            record = CKRecord(recordType: "ModularDefinition")
        }
        
        record["integer"] = self.integer
        
        if let delegate = self as? CKRecordSynthetizationDelegate {
            delegate.willFinishEncoding(ckRecord: record)
        }
        
        return record
    }
    
    var __recordID: CKRecord.ID?
    
    enum CKRecordDecodingError: Error {
        
        case missingField(String)
        case fieldTypeMismatch(fieldName: String, expectedType: String, foundType: String)
        case missingDatabase(fieldName: String)
        case errorDecodingNestedField(fieldName: String, _ error: Error)
        
        var localizedDescription: String {
            let genericMessage = "Error while trying to initialize an instance of ModularDefinition from a CKRecord:"
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
}

let m = ModularDefinition(integer: 11)
let c = m.convertToCKRecord()
do {
    let m2 = try await ModularDefinition(from: c)
    print(m2.integer)
} catch {
    print(error)
}
