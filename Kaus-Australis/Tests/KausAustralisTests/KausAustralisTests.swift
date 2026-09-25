import XCTest
import KausMedia
@testable import KausAustralis

final class TransactionMappingTests: XCTestCase {

    func testModelFromDTO_UsesDefaultCategory_WhenCategoryIsNil() {
        let dto = TransactionDTO(
            description: "Compra Mercado",
            amount: -150.50,
            date: Date(),
            category: nil
        )

        let sut = TransactionModel(newFrom: dto)

        XCTAssertEqual(sut.category, "Geral")
        XCTAssertNil(sut.id, "A identidade deve ser atribuída pelo banco, não pelo cliente")
    }

    func testModelFromDTO_IgnoresClientProvidedID() {
        let dto = TransactionDTO(
            id: UUID(),
            description: "Salário",
            amount: 4200,
            date: Date(),
            category: "Receita"
        )

        let sut = TransactionModel(newFrom: dto)

        XCTAssertNil(sut.id)
        XCTAssertEqual(sut.category, "Receita")
    }

    func testToDTO_RoundTripsAllFields() {
        let id = UUID()
        let date = Date()
        let model = TransactionModel(
            id: id,
            description: "Aluguel",
            amount: -1800,
            category: "Moradia",
            date: date
        )

        let dto = model.toDTO()

        XCTAssertEqual(dto.id, id)
        XCTAssertEqual(dto.description, "Aluguel")
        XCTAssertEqual(dto.amount, -1800)
        XCTAssertEqual(dto.category, "Moradia")
        XCTAssertEqual(dto.date, date)
    }
}
