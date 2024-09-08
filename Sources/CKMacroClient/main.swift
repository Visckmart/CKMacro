import CKMacro
import AppKit


@ConvertibleToCKRecord(debug: false)
class User {
    
    @CKRecordName var id: String
    
    var integer: Int
    var double: Double
    var string: String
    var location: CLLocation
    
    var optionalInteger: Int?
    var optionalDouble: Double?
    var optionalString: Optional<String>
    var optionalLocation: Optional<CLLocation>
    
    @CKPropertyType(.codable) var codable: Int
    @CKPropertyType(.codable) var optionalCodable: Int?
    
    @CKPropertyType(.nsCoding) var nsCoding: NSColor
    @CKPropertyType(.nsCoding) var optionalNSCoding: NSColor?
    
    enum Enumeration: Int {
        case a, b
    }
    @CKPropertyType(.rawValue) var enumValue: Enumeration
    @CKPropertyType(.rawValue) var optionalEnumValue: Enumeration?
    
    @CKPropertyType(.ignored) var ignored: String = "ignored"
    static let ignoredStaticLet = 10
    static var ignoredStaticVar = 20
    
    class var ignoredClassGetVar: Int { 10 }
    class var ignoredClassGetSetVar: Int { get { 10 } set { } }
    var getSetVar: Int { get { 10 } set { } }
    
    init(
        id: String = UUID().uuidString,
        integer: Int = 100,
        double: Double = 200,
        string: String = "content",
        location: CLLocation = .init(latitude: 0, longitude: 0),
        optionalInteger: Int? = nil,
        optionalDouble: Double? = nil,
        optionalString: String? = nil,
        optionalLocation: CLLocation? = nil,
        codable: Int = 1000,
        optionalCodable: Int? = nil,
        nsCoding: NSColor = .red,
        optionalNSCoding: NSColor? = nil
    ) {
        self.id = id
        self.integer = integer
        self.double = double
        self.string = string
        self.location = location
        self.optionalInteger = optionalInteger
        self.optionalDouble = optionalDouble
        self.optionalString = optionalString
        self.optionalLocation = optionalLocation
        self.codable = codable
        self.optionalCodable = optionalCodable
        self.nsCoding = nsCoding
        self.optionalNSCoding = optionalNSCoding
        self.enumValue = .a
    }
    
    
    
    
}

await Task {
    do {
        let u = User(id: "a")
//        u.optionalEnumValue = .a
        let r = try u.convertToCKRecord()
//        r.0["OPTIONALint"] = nil
//        print(r.0["optionalCodable"])
//        r.0["optionalCodable"] = try! JSONEncoder().encode("a")
        r.0["optionalString"] = nil
        let u2 = try await User(fromCKRecord: r.0)
        dump(u2)
    } catch {
        print(error.localizedDescription)
    }
}.value
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
//var x = 10
//
//func a () {
//guard let x = x as? Int else {
//    
//}
//guard let x = x as? Int else {
//    
//}
//}


//class A {
//    class var x: Int { get { 10 } set { }}
//}
//class B: A {
//    override var x: Int
//    init(x: Int) {
//        self.x = x
//    }
//}
