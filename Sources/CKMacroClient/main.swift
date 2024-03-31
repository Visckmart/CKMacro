import CKMacro
import CloudKit

protocol SynthesizedCKRecordConvertible {
    func convertToCKRecord() -> CKRecord
    init(from ckRecord: CKRecord) throws
}

@ConvertibleToCKRecord(recordType: "FAUser")
class User: SynthesizedCKRecordConvertible {
    @Relationship var sub: User? = nil
    var dataList: [Data] = [Data()]
    var photo: Data = "testando".data(using: .utf8)!
    var otherPhoto: Data = Data()
    var name: String
    var idade: Int = Int.random(in: 10...20)
    var bool: Bool = false
    var child: Int? = 10// = User(name: "a")
    var lastModifiedUserRecordID: CKRecord.ID?
    var creationDate: Date? = Date()
    var recordChangeTag: String?
    var rawName: String = "10"
    init(name: String, sub: User? = nil) {
        self.name = name
        self.sub = sub
    }
}

//CKRecord(recordType: "a").
let u1 = User(name: "j", sub: User(name: "children"))
print(u1.x)
let c1: some SynthesizedCKRecordConvertible = u1
print(c1.convertToCKRecord())
print(u1.convertToCKRecord())
let reco = u1.convertToCKRecord()
//reco["child"] = "a"
var m = Mirror(reflecting: try! User(from: reco))
print(m.children.map({ child in
    "\(child.label ?? "?"): \(child.value)"
}).joined(separator: "\n"))
