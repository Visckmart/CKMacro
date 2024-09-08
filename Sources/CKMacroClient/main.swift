import CKMacro
import AppKit

@ConvertibleToCKRecord
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
        let user = User(id: "a")
        let (instanceRecord, _) = try user.convertToCKRecord()
        let recreatedUser = try await User(fromCKRecord: instanceRecord)
        dump(recreatedUser)
    } catch {
        print(error.localizedDescription)
    }
}.value
