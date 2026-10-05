import XCTest
@testable import KausMedia

final class InstallmentDescriptionTests: XCTestCase {
    func testTruncatedDescriptionsOfTheSamePurchaseMatch() {
        let variants = ["shopee*shps tecnol", "shopee*shps tecnolsao paulo bra", "shopee*shps tecnologia sao paulo bra"]
        for lhs in variants {
            for rhs in variants {
                XCTAssertTrue(InstallmentDescription.matches(lhs, rhs), "\(lhs) × \(rhs)")
            }
        }
        XCTAssertTrue(InstallmentDescription.matches("shopee *bfcolchoes", "shopee *bfcolchoessao paulo bra"))
        XCTAssertTrue(InstallmentDescription.matches("SHOPEE*BIBO SUN", "shopee*bibo sun araquari bra"))
    }

    func testDifferentStoresDoNotMatch() {
        XCTAssertFalse(InstallmentDescription.matches("shopee*bibo sun araquari bra", "shopee*shps tecnologia sao paulo bra"))
        XCTAssertFalse(InstallmentDescription.matches("shopee*guilhen e b", "shopee*zhihua yang"))
        XCTAssertFalse(InstallmentDescription.matches("netflix", "netshoes"))
    }
}
