import CKMacro
import CloudKit

protocol SynthesizedCKRecordConvertible {
    func convertToCKRecord() -> CKRecord
    init?(from ckRecord: CKRecord)
}

@convertibleToCKRecord(recordType: "FAUser")
class User: SynthesizedCKRecordConvertible {
    var name: String
    var idade: Int = Int.random(in: 10...20)
    var bool: Bool = false
    var child: Optional<Int> = 10// = User(name: "a")
    init(name: String) {
        self.name = name
    }
}
let u1 = User(name: "j")
print(u1.x)
let c1: some SynthesizedCKRecordConvertible = u1
print(c1.convertToCKRecord())
print(u1.convertToCKRecord())
var m = Mirror(reflecting: User(from: u1.convertToCKRecord())!)
print(m.children.map({ child in
    "\(child.label ?? "?"): \(child.value)"
}).joined(separator: "\n"))
