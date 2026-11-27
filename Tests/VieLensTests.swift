import XCTest
import UIKit
import ImageIO
@testable import VieLens

final class VieLensTests:XCTestCase {
    func patch() throws -> Data {
        let fmt=UIGraphicsImageRendererFormat();fmt.scale=1
        let im=UIGraphicsImageRenderer(size:CGSize(width:420,height:300),format:fmt).image{c in
            UIColor(red:0.17,green:0.12,blue:0.10,alpha:1).setFill();c.fill(CGRect(x:0,y:0,width:420,height:300))
            UIColor(red:0.87,green:0.83,blue:0.76,alpha:1).setFill();c.fill(CGRect(x:220,y:0,width:200,height:300))
        }
        return try XCTUnwrap(im.jpegData(compressionQuality:0.94))
    }
    func testFullResolutionAndOriginal() throws {
        let bytes=try patch(), shot=try PhotoEngine.render(bytes,look:.neutral)
        let ref=try XCTUnwrap(CGImageSourceCreateWithData(shot.jpeg as CFData,nil))
        let im=try XCTUnwrap(CGImageSourceCreateImageAtIndex(ref,0,nil))
        XCTAssertEqual(im.width,420);XCTAssertEqual(im.height,300)
        XCTAssertNotNil(UIImage(data:shot.thumbnail))
        XCTAssertNotEqual(try PhotoEngine.render(bytes,look:.street).jpeg,shot.jpeg)
    }
    func testDatePreservesOriginalDay() {
        let exif=["DateTimeOriginal":"2025:01:01 00:12:00","OffsetTimeOriginal":"+07:00"]
        let result=Vault.captureDate(exif,fallback:.distantPast)
        XCTAssertEqual(result.1,"2025-01-01")
        XCTAssertEqual(result.0,ISO8601DateFormatter().date(from:"2024-12-31T17:12:00Z"))
    }
    func testBackupRoundTripAndTrash() async throws {
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:temp)}
        let a=Vault(root:temp.appendingPathComponent("a")),b=Vault(root:temp.appendingPathComponent("b"))
        let data=try patch()
        let s=try await a.add(data,look:.amber,session:"Hội An")
        XCTAssertTrue(s.enhanced);XCTAssertEqual(try Data(contentsOf:a.picture(s,original:true)),data)
        try await a.edit(s.id,rating:5,tags:"đêm")
        let n=try await a.backup(to:temp);XCTAssertEqual(n,1)
        let path=try XCTUnwrap(try FileManager.default.contentsOfDirectory(at:temp,includingPropertiesForKeys:nil).first{$0.lastPathComponent.hasPrefix("VieLens-")})
        let res=try await b.restore(from:path);XCTAssertEqual(res.0,1)
        let repeated=try await b.restore(from:path);XCTAssertEqual(repeated.1,1)
        let loaded=try await b.all();XCTAssertEqual(loaded.first?.rating,5);XCTAssertEqual(loaded.first?.session,"Hội An")
        try await b.edit(s.id,trash:true);let trash=try await b.all();XCTAssertNotNil(trash.first?.deleted)
        try await b.edit(s.id,trash:false);let restored=try await b.all();XCTAssertNil(restored.first?.deleted)
    }
    func testInvalidPhotoDoesNotCreateRecord() async throws {
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:temp)}
        let vault=Vault(root:temp)
        do {_=try await vault.add(Data([1,2,3]),look:.neutral,session:"");XCTFail("Expected decode failure")} catch {}
        let all=try await vault.all();XCTAssertTrue(all.isEmpty)
    }
}
