import XCTest
@testable import KausMedia

final class TransactionDTOTests: XCTestCase {
    
    func testTransactionDTO_Initialization() {
        // Arrange
        let expectedId = UUID()
        let expectedDescription = "Compra Mercado"
        let expectedAmount = -150.50
        let expectedDate = Date()
        
        // Act
        let sut = TransactionDTO(
            id: expectedId,
            description: expectedDescription,
            amount: expectedAmount,
            date: expectedDate
        )
        
        // Assert
        XCTAssertEqual(sut.id, expectedId)
        XCTAssertEqual(sut.description, expectedDescription)
        XCTAssertEqual(sut.amount, expectedAmount)
        XCTAssertNil(sut.category, "A categoria deve ser nula por padrão se não for informada")
    }
}
