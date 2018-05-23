//
//  Allow2FrameworkTests.swift
//  Allow2FrameworkTests
//
//  Created by Andrew Longhorn on 6/1/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//

import XCTest
@testable import Allow2

class Allow2FrameworkTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testPairing() throws {
        // use the special "test" user for testing pairing
        // first, we deliberately fail to create a pairing
        let failExpectation = XCTestExpectation(description: "Test pairing: Invalid login")

        Allow2.shared.env = .staging
        Allow2.shared.userId = nil
        Allow2.shared.pairId = nil
        //UserDefaults.standard.synchronize()
        
        Allow2.shared.pair(user: "test", password: "fail", deviceName: "Test Device Name") { (response) in
            guard case let Allow2Response.Error(Allow2Error.Other(message)) = response else {
                XCTFail("Invalid pairing login expected to fail, but did not return expected error")
                failExpectation.fulfill()
                return
            }
            XCTAssertEqual(message, "Invalid user.")
            failExpectation.fulfill()
        }

        wait(for: [failExpectation], timeout: 10.0)
        
        // Now login successfully
        let succeedExpectation = XCTestExpectation(description: "Test pairing: Valid login")
        Allow2.shared.pair(user: "test", password: "test", deviceName: "Test Device Name") { (response) in
            print(response)
            guard case let Allow2Response.PairResult(pairResult) = response else {
                XCTFail("Invalid pairing login expected to fail, but did not return expected error")
                succeedExpectation.fulfill()
                return
            }
            XCTAssertEqual(pairResult.children.count, 1, "Invalid child count")
            succeedExpectation.fulfill()
        }

        wait(for: [succeedExpectation], timeout: 10.0)
    }
    
//    func testPerformanceExample() {
//        // This is an example of a performance test case.
//        //self.measure {
//            // Put the code you want to measure the time of here.
//        }
//    }
    
}
