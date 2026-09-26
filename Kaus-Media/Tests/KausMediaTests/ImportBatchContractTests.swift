import XCTest
@testable import KausMedia

final class ImportBatchContractTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func testImportBatchRoundTrip() throws {
        let batch = ImportBatchDTO(
            id: UUID(),
            accountID: UUID(),
            filename: "fatura.csv",
            createdAt: DateParser.parse("15/01/2025"),
            transactionCount: 12,
            confirmedCount: 3
        )

        let decoded = try decoder.decode(ImportBatchDTO.self, from: try encoder.encode(batch))

        XCTAssertEqual(decoded, batch)
    }

    func testImportReportCarriesBatchIdentifier() throws {
        let id = UUID()
        let report = ImportReportDTO(imported: 4, batchID: id)

        let decoded = try decoder.decode(ImportReportDTO.self, from: try encoder.encode(report))

        XCTAssertEqual(decoded.batchID, id)
    }

    /// Relatórios gravados antes do lote existir continuam legíveis.
    func testImportReportDecodesWithoutBatchIdentifier() throws {
        let json = Data(#"{"imported":2,"duplicates":1,"projectedInstallments":0,"confirmedInstallments":0,"failures":[]}"#.utf8)

        let decoded = try decoder.decode(ImportReportDTO.self, from: json)

        XCTAssertNil(decoded.batchID)
        XCTAssertEqual(decoded.imported, 2)
    }

    func testBulkDeleteRoundTrip() throws {
        let request = BulkDeleteRequest(ids: [UUID(), UUID()])

        let decoded = try decoder.decode(BulkDeleteRequest.self, from: try encoder.encode(request))

        XCTAssertEqual(decoded.ids, request.ids)
    }

    func testBulkDeleteResponseDefaultsRestoredToZero() {
        XCTAssertEqual(BulkDeleteResponse(deleted: 5).restored, 0)
    }
}
