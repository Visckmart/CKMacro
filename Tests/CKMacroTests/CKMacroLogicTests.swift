//
//  CKMacroLogicTests.swift
//  CKMacro
//
//  Created by Victor Martins on 07/09/24.
//

import XCTest
import CKMacro

import CoreLocation
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
    var optionalString: String?
    var optionalLocation: CLLocation?
    
    @CKPropertyType(.codable) var codable: Int
    @CKPropertyType(.codable) var optionalCodable: Int?
    @CKPropertyType(.nsCoding) var nsCoding: NSColor
    @CKPropertyType(.nsCoding) var optionalNSCoding: NSColor?
    
    @CKPropertyType(.ignored) var ignored: String = "ignored"
    static let ignoredStaticLet = 10
    static var ignoredStaticVar = 20
    
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
    }
    
    
    
    
}

final class CKMacroLogicTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() async throws {
        let u = User(id: "abcd")
        let r = try u.convertToCKRecord()
        let u2 = try await User(fromCKRecord: r.instance)
        print(u == u2)
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}

extension User: Equatable {
    static func == (lhs: User, rhs: User) -> Bool {
        lhs.id == rhs.id
        ||  lhs.integer == rhs.integer
        ||  lhs.double == rhs.double
        ||  lhs.string == rhs.string
        ||  lhs.location == rhs.location
        ||  lhs.optionalInteger == rhs.optionalInteger
        ||  lhs.optionalDouble == rhs.optionalDouble
        ||  lhs.optionalString == rhs.optionalString
        ||  lhs.optionalLocation == rhs.optionalLocation
        ||  lhs.codable == rhs.codable
        ||  lhs.optionalCodable == rhs.optionalCodable
        ||  lhs.nsCoding == rhs.nsCoding
        ||  lhs.optionalNSCoding == rhs.optionalNSCoding
        ||  lhs.ignored == rhs.ignored
    }
}
