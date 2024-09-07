//import CKMacro
//
//
//@ConvertibleToCKRecord(recordType: "MyAppUser")
//class User {
//    @CKRecordName var id: String = UUID().uuidString
//    @CKReference(.referencesProperty) var extra: Extra
//    var dataList: [Data] = [Data()]
//    var photo: Data = "testando".data(using: .utf8)!
//    var otherPhoto: Data = Data()
//    var name: String?
//    var idade: Int = Int.random(in: 10...20)
//    var bool: Bool = false
//    var child: Int? = 10// = User(name: "a")
////    var lastModifiedUserRecordID: CKRecord.ID?
//    var creationDate: Date? = Date()
//    var recordChangeTag: String?
//    let rawName: String
//    
//    init(name: String, sub: User? = nil) {
//        self.name = name
//        self.rawName = "1"
//        self.extra = Extra()
//    }
//}
//
//@ConvertibleToCKRecord
//class Extra {
//    @CKRecordName var a: String = "a"
//    var info: Int = 10
//    init(info: Int = 10) {
//        self.info = info
//    }
//}
//
////User(name: "a").id
//extension User: CKRecordSynthetizationDelegate {
//    func willFinishEncoding(ckRecord: CKRecord) {
//        ckRecord["name"] = "y"
//    }
//    func willFinishDecoding(ckRecord: CKRecord) {
//        if let name = ckRecord["name"] as? String, name.hasPrefix("b") {
//            self.idade = 100
//        }
//        self.name = "testing"
//    }
//}
////extension User: SynthesizedCKRecordConvertible {
////    static func willFinishDecoding(ckRecord: inout CKRecord) {
////        <#code#>
////    }
////}
//public extension CKRecord {
//    var systemFieldsData: Data {
//        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
//        encodeSystemFields(with: archiver)
//        archiver.finishEncoding()
//        return archiver.encodedData
//    }
//    
//    convenience init?(systemFieldsData: Data) {
//        guard let una = try? NSKeyedUnarchiver(forReadingFrom: systemFieldsData) else {
//            return nil
//        }
//        self.init(coder: una)
//    }
//}
//
//await Task {
//    do {
//        //    CKDatabase().record(for: <#T##CKRecord.ID#>)
//        //CKRecord.Reference(recordID: CKRecord.ID(recordName: "a"), action: .none).recordID
//        //CKRecord(recordType: "a").
//        let u1 = User(name: "j"/*, sub: User(name: "children")*/)
//        //print(u1.x)
//        let c1: some SynthesizedCKRecordConvertible = u1
//        let r1 = try c1.convertToCKRecord(usingBaseCKRecord: nil)
//        //r1.lastModifiedUserRecordID = .init(recordName: "a")
////        print(r1.creationDate)
//        print(try u1.convertToCKRecord())
////        print(u1.id)
//        let reco = try u1.convertToCKRecord()
//        print(r1.0["name"])
////        reco["name"] = true
////        print(typeWrapper(of: reco["name"]))
////        reco["name"] = "bay"
//        let b = try await User(fromCKRecord: reco.0)
//        print(b.name)
//        print(b.bool)
//        dump(r1.0["bool"])
//        //print(CKRecord(systemFieldsData: u1.convertToCKRecord().systemFieldsData))
//        //reco["child"] = "a"
//        //var m = Mirror(reflecting: try! User(from: reco))
//        //print(m.children.map({ child in
//        //    "\(child.label ?? "?"): \(child.value)"
//        //}).joined(separator: "\n"))
//    } catch let error as CKRecordDecodingError {
//        print(error.localizedDescription)
//    }
//}.value
