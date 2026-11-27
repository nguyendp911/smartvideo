import XCTest
import UIKit
import ImageIO
import AVFoundation
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
    func testTimelineGroupsAndFilters() throws {
        let day1=Date(timeIntervalSince1970:10), day2=Date(timeIntervalSince1970:20)
        let a=Shot(id:UUID(),date:day1,day:"2025-01-01",session:"Hội An",rating:5,tags:"Đêm",deleted:nil,light:.night,look:.neutral,sourceFile:"original.jpg",enhanced:false,lens:"")
        let b=Shot(id:UUID(),date:day2,day:"2025-02-01",session:"Hội An",rating:1,tags:"Sáng",deleted:nil,light:.natural,look:.neutral,sourceFile:"original.jpg",enhanced:false,lens:"")
        let c=Shot(id:UUID(),date:day1,day:"2025-01-01",session:"Hội An",rating:2,tags:"",deleted:nil,light:.natural,look:.neutral,sourceFile:"original.jpg",enhanced:false,lens:"")
        let d=Shot(id:UUID(),date:day2,day:"2025-03-01",session:"Khác",rating:5,tags:"",deleted:day2,light:.natural,look:.neutral,sourceFile:"original.jpg",enhanced:false,lens:"")
        let shots=[a,b,c,d]
        XCTAssertEqual(TimelineIndex.filter(shots,scope:.all,query:"hoi an dem",minimumRating:4).count,1)
        XCTAssertEqual(TimelineIndex.filter(shots,scope:.trash).map(\.id),[d.id])
        XCTAssertEqual(TimelineIndex.filter(shots,scope:.all,period:"2025-02").map(\.id),[b.id])
        let grouped=TimelineIndex.group([a,b,c],period:.month,newest:true)
        XCTAssertEqual(grouped.map(\.key),["2025-02","2025-01"])
        XCTAssertEqual(grouped.last?.items.count,2)
        XCTAssertEqual(grouped.last?.cover.rating,5)
        XCTAssertEqual(TimelineIndex.albums(shots).first?.items.count,3)
    }
    func testIndependentCollectionsAndNotesRoundTrip() async throws {
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:temp)}
        let vault=Vault(root:temp),bytes=try patch()
        let shot=try await vault.add(bytes,look:.mono,session:"Original session")
        try await vault.edit(shot.id,addCollection:"Travel",note:"Đêm đẹp")
        try await vault.edit(shot.id,addCollection:"Favorite")
        try await vault.edit(shot.id,addCollection:"Travel")
        let shots=try await vault.all()
        XCTAssertEqual(shots.first?.session,"Original session")
        XCTAssertEqual(shots.first?.collections,["Favorite","Travel"])
        XCTAssertEqual(TimelineIndex.filter(shots,scope:.all,query:"dem dep",collection:"Travel",look:.mono).count,1)
        XCTAssertEqual(TimelineIndex.collections(shots).count,2)
        try await vault.edit(shot.id,removeCollection:"Travel")
        let reopened=Vault(root:temp)
        let restored=try await reopened.all()
        XCTAssertEqual(restored.first?.collections,["Favorite"])
        XCTAssertEqual(restored.first?.note,"Đêm đẹp")
        XCTAssertEqual(try Data(contentsOf:reopened.picture(shot,original:true)),bytes)
    }
    func testSignatureEventsAndMemoryRecord() throws {
        let a=Shot(id:UUID(),date:Date(timeIntervalSince1970:100),day:"2025-01-01",session:"Travel",rating:0,tags:"",deleted:nil,light:.natural,look:.neutral,sourceFile:"original.jpg",enhanced:false,lens:"")
        let b=Shot(id:UUID(),date:a.date.addingTimeInterval(60),day:a.day,session:a.session,rating:0,tags:"",deleted:nil,light:.natural,look:.neutral,sourceFile:"original.jpg",enhanced:false,lens:"")
        let c=Shot(id:UUID(),date:a.date.addingTimeInterval(8000),day:a.day,session:a.session,rating:0,tags:"",deleted:nil,light:.natural,look:.neutral,sourceFile:"original.jpg",enhanced:false,lens:"")
        XCTAssertEqual(SignatureIndex.events([a,b,c]).map{$0.shots.count},[1,2])
        let record=MemoryRecord(kind:.capsule,title:"Memory",note:"A note",date:Date(),unlock:Date().addingTimeInterval(3600),photos:[a.id],cover:a.id)
        let decoded=try JSONDecoder().decode(MemoryRecord.self,from:JSONEncoder().encode(record))
        XCTAssertTrue(decoded.locked);XCTAssertEqual(decoded.photos,[a.id])
    }
    func testCreativeExportAndSimilarity() async throws {
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:temp)}
        let vault=Vault(root:temp),bytes=try patch()
        let a=try await vault.add(bytes,look:.neutral,session:"")
        let b=try await vault.add(bytes,look:.neutral,session:"")
        var r=CreativeRecipe();r.crop="1:1";r.exposure=0.4
        let result=try XCTUnwrap(CreativeEngine.render(vault.picture(a,original:true),recipe:r,maxSize:200,format:"PNG",quality:1,metadata:false))
        let source=try XCTUnwrap(CGImageSourceCreateWithData(result as CFData,nil))
        let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        XCTAssertEqual(image.width,200);XCTAssertEqual(image.height,200)
        XCTAssertEqual(try Data(contentsOf:vault.picture(a,original:true)),bytes)
        let aa=try XCTUnwrap(SignatureAnalyzer.assess(a,vault:vault)),bb=try XCTUnwrap(SignatureAnalyzer.assess(b,vault:vault))
        XCTAssertEqual(aa.digest,bb.digest)
        XCTAssertEqual(SignatureAnalyzer.similar([aa,bb]).first?.count,2)
    }
    func testMemoryMovieCreatesVideo() async throws {
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:temp)}
        let vault=Vault(root:temp)
        let s=try await vault.add(patch(),look:.neutral,session:"")
        let url=try await MemoryMovie.make([s],vault:vault,width:320,height:240,seconds:1,title:"Memory")
        defer{try? FileManager.default.removeItem(at:url)}
        let asset=AVURLAsset(url:url)
        let tracks=try await asset.loadTracks(withMediaType:.video)
        XCTAssertEqual(tracks.count,1)
        let duration=try await asset.load(.duration)
        XCTAssertGreaterThan(CMTimeGetSeconds(duration),0.8)
    }
    func testSignatureBackupMergeAndTopics() throws {
        let a=MemoryRecord(kind:.life,title:"Local",note:"",date:Date(),unlock:nil,photos:[UUID()],cover:nil)
        var changed=a;changed.title="Imported"
        let b=MemoryRecord(kind:.daily,title:"New",note:"",date:Date(),unlock:nil,photos:[UUID()],cover:nil)
        let merged=SignatureBackup.mergeRecords([a],[changed,b,b])
        XCTAssertEqual(merged.map(\.title),["Local","New"])
        let v=CreativeVersion(name:"Warm",date:Date(),recipe:CreativeRecipe(),photoIDs:a.photos)
        let archive=SignatureBackup(version:1,records:merged,versions:[v],preset:v.recipe)
        let decoded=try JSONDecoder().decode(SignatureBackup.self,from:JSONEncoder().encode(archive))
        XCTAssertEqual(decoded.versions.first?.id,v.id)
        XCTAssertEqual(SignatureBackup.mergeVersions([v],[v]).count,1)
        XCTAssertTrue(VisualTopic.classify(["forest","mountain"],faces:0).contains(.nature))
        XCTAssertTrue(VisualTopic.classify([],faces:1).contains(.people))
    }
    func testExactDuplicateScannerKeepsOriginal() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let vault=Vault(root:root),bytes=try patch()
        let a=try await vault.add(bytes,look:.neutral,session:"")
        let b=try await vault.add(bytes,look:.mono,session:"")
        try await vault.edit(b.id,rating:5)
        let shots=try await vault.all()
        let groups=DuplicateScanner.groups(shots,vault:vault)
        XCTAssertEqual(groups.count,1)
        XCTAssertEqual(groups.first?.shots.count,2)
        XCTAssertEqual(groups.first?.suggestedKeep?.id,b.id)
        XCTAssertEqual(try Data(contentsOf:vault.picture(a,original:true)),bytes)
    }
    func testAnimatedMemoryMovie() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let vault=Vault(root:root),bytes=try patch()
        let a=try await vault.add(bytes,look:.neutral,session:"")
        let b=try await vault.add(bytes,look:.amber,session:"")
        let url=try await MemoryMovie.make([a,b],vault:vault,width:320,height:240,seconds:1,title:"Signature",motion:.zoom,transition:.dissolve)
        defer{try? FileManager.default.removeItem(at:url)}
        let asset=AVURLAsset(url:url)
        let duration=try await asset.load(.duration)
        XCTAssertGreaterThan(CMTimeGetSeconds(duration),1.8)
        let tracks=try await asset.loadTracks(withMediaType:.video)
        XCTAssertEqual(tracks.count,1)
    }
    func testTimelineTreeHierarchy() {
        let a=Shot(id:UUID(),date:Date(timeIntervalSince1970:10),day:"2025-01-01",session:"",rating:0,tags:"",deleted:nil,light:.natural,look:.neutral,sourceFile:"original.jpg",enhanced:false,lens:"")
        let b=Shot(id:UUID(),date:Date(timeIntervalSince1970:20),day:"2025-01-02",session:"",rating:0,tags:"",deleted:nil,light:.natural,look:.neutral,sourceFile:"original.jpg",enhanced:false,lens:"")
        let c=Shot(id:UUID(),date:Date(timeIntervalSince1970:30),day:"2026-02-01",session:"",rating:0,tags:"",deleted:nil,light:.natural,look:.neutral,sourceFile:"original.jpg",enhanced:false,lens:"")
        let tree=TimelineTreeIndex.build([a,b,c],newest:true)
        XCTAssertEqual(tree.map(\.id),["2026","2025"])
        XCTAssertEqual(tree.last?.months.first?.id,"2025-01")
        XCTAssertEqual(tree.last?.months.first?.days.map(\.key),["2025-01-02","2025-01-01"])
        XCTAssertEqual(tree.flatMap(\.months).flatMap(\.days).flatMap(\.items).count,3)
    }
    @MainActor func testStoryArchiveDraftSaveMerge() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let archive=StoryArchive(root:root)
        var story=StoryEntry(id:"period:2026-11-27")
        story.title="Một ngày đẹp";story.body="Đà Lạt bình yên";story.mood = .peaceful
        try archive.save(story,draft:true)
        XCTAssertNil(archive.entry(story.id))
        XCTAssertEqual(archive.drafts[story.id]?.title,story.title)
        try archive.save(story,draft:false)
        XCTAssertNil(archive.drafts[story.id])
        let reopened=StoryArchive(root:root)
        XCTAssertEqual(reopened.entry(story.id)?.body,story.body)
        var changed=story;changed.body="Imported"
        try reopened.merge(JSONEncoder().encode(StoryArchivePackage(version:1,entries:[changed],drafts:[])))
        XCTAssertEqual(reopened.entry(story.id)?.body,story.body)
        let shot=Shot(id:UUID(),date:Date(),day:"2026-11-27",session:"",rating:0,tags:"",deleted:nil,light:.natural,look:.neutral,sourceFile:"original.jpg",enhanced:false,lens:"")
        XCTAssertTrue(reopened.matching("da lat",shot:shot))
        try reopened.remove(story.id)
        XCTAssertNil(reopened.entry(story.id))
    }
    func testVineThemesAndStoryFormats(){
        XCTAssertEqual(VineTheme.allCases.count,15)
        XCTAssertEqual(StoryFormat.allCases.count,5)
    }
    func testLivingGardenAndStoryCanvasModels()throws{
        XCTAssertEqual(StoryEffect.allCases.count,14)
        XCTAssertEqual(GardenBackground.season("2026-11",fallback:.emerald),.autumn)
        XCTAssertEqual(GardenBackground.season("2026-03",fallback:.emerald),.sakura)
        var story=StoryEntry(id:"photo:"+UUID().uuidString)
        var design=MemoryCanvasDesign()
        design.layers=[MemoryCanvasLayer(kind:.text,text:"Ký ức")]
        story.canvas=design;story.textEffect = .typewriter;story.chapters=["Chương đầu"]
        let decoded=try JSONDecoder().decode(StoryEntry.self,from:JSONEncoder().encode(story))
        XCTAssertEqual(decoded.canvas,design)
        XCTAssertEqual(decoded.chapters,["Chương đầu"])
        XCTAssertTrue(decoded.hasContent)
    }
    func testStoryProductionSoundscape()throws{
        XCTAssertNil(StorySoundscape.none.generate())
        let sound=try XCTUnwrap(StorySoundscape.rain.generate())
        XCTAssertEqual(String(data:sound.prefix(4),encoding:.ascii),"RIFF")
        XCTAssertGreaterThan(sound.count,100000)
        let player=try AVAudioPlayer(data:sound)
        XCTAssertEqual(player.duration,8,accuracy:0.1)
        XCTAssertTrue(StoryWritingAssistant.template(facts:"Đi Đà Lạt",mood:"Bình yên").contains("Đi Đà Lạt"))
    }
    @MainActor func testLifeSyncEmptyDayAndMood()throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let story=StoryArchive(root:root.appendingPathComponent("story"))
        let life=LifeArchive(root:root.appendingPathComponent("life"))
        let day="2026-11-27"
        let target=MemorySync.target(day:day,shots:[])
        XCTAssertEqual(target.id,"period:"+day)
        var draft=StoryEntry(id:target.id);draft.body="Bản nháp"
        try story.save(draft,draft:true)
        try MemorySync.setMood(.peaceful,day:day,shots:[],archive:story)
        XCTAssertEqual(story.entry(target.id)?.mood,.peaceful)
        XCTAssertEqual(story.drafts[target.id]?.body,"Bản nháp")
        try life.update{$0.milestones.append(LifeMilestone(title:"Cột mốc",date:"2025-01-02"))}
        let days=MemorySync.activeDays(shots:[],stories:story,life:life)
        XCTAssertEqual(days,Set([day,"2025-01-02"]))
        let tree=TimelineTreeIndex.build([],newest:true,extraDays:days)
        XCTAssertEqual(tree.map(\.id),["2026","2025"])
        XCTAssertEqual(tree.first?.months.first?.days.first?.key,day)
        XCTAssertTrue(tree.first?.group.items.isEmpty ?? false)
    }
    func testLifeCalendarAndRanges(){
        let date=LifeDate.date("2026-11-27")!
        XCTAssertEqual(LifeDate.monthCells(date).compactMap{$0}.count,30)
        XCTAssertEqual(LifeReflectionRange.month(date).storyID,"period:2026-11")
        XCTAssertTrue(LifeReflectionRange.month(date).contains("2026-11-30"))
        XCTAssertFalse(LifeReflectionRange.month(date).contains("2026-12-01"))
        XCTAssertFalse(FutureMemoryLetter(title:"A",content:"B",opens:date).isOpen(at:date.addingTimeInterval(-1)))
    }
    @MainActor func testVineGrowthPersistsUniqueUsageDays()throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let life=LifeArchive(root:root)
        let date=LifeDate.date("2026-11-27")!
        XCTAssertEqual(life.gardenDays,0)
        try life.recordGardenUse(date);try life.recordGardenUse(date)
        XCTAssertEqual(life.gardenDays,1)
        for i in 1..<7{try life.recordGardenUse(LifeDate.calendar.date(byAdding:.day,value:i,to:date)!)}
        XCTAssertEqual(LifeArchive(root:root).gardenDays,7)
        XCTAssertEqual(VineGrowth(days:life.gardenDays).stage,.sprout)
        try life.merge(life.exportData())
        XCTAssertEqual(life.gardenDays,7)
        try life.update{$0.milestones=[]}
        XCTAssertEqual(life.gardenDays,7)
    }
    func testVineGrowthStages(){
        XCTAssertEqual(VineGrowth(days:1).stage,.seed)
        XCTAssertFalse(VineGrowth(days:1).hasBuds)
        XCTAssertEqual(VineGrowth(days:30).stage,.young)
        XCTAssertTrue(VineGrowth(days:90).hasBuds)
        XCTAssertFalse(VineGrowth(days:179).hasFlowers)
        XCTAssertTrue(VineGrowth(days:180).hasFlowers)
        XCTAssertEqual(VineGrowth(days:365).stage,.mature)
        XCTAssertGreaterThan(VineGrowth(days:365).leafDensity,VineGrowth(days:1).leafDensity)
    }
    func testNaturalGardenStableSamples(){
        let seed=NaturalSample.seed("2026-11-27")
        XCTAssertEqual(seed,NaturalSample.seed("2026-11-27"))
        XCTAssertNotEqual(seed,NaturalSample.seed("2026-11-28"))
        for i in 0..<100{
            let n=NaturalSample.value(i,seed)
            XCTAssertGreaterThanOrEqual(n,0)
            XCTAssertLessThanOrEqual(n,1)
        }
        XCTAssertEqual(NaturalSample.fraction(-0.2),0.8,accuracy:0.000001)
    }
    @MainActor func testBotanicalAssetsAreBundledAndGrowthUsesYoungTexture() {
        for name in BotanicalAssets.names {
            let image=UIImage(named:name)
            XCTAssertNotNil(image,"Missing asset \(name)")
            XCTAssertGreaterThan(image?.size.width ?? 0,0)
            XCTAssertGreaterThan(image?.size.height ?? 0,0)
        }
        for theme in VineTheme.allCases{
            XCTAssertEqual(BotanicalAssets.rail(theme:theme,age:VineGrowth(days:0)),"botanical_young")
            XCTAssertEqual(BotanicalAssets.rail(theme:theme,age:VineGrowth(days:179)),"botanical_young")
        }
        XCTAssertEqual(BotanicalAssets.rail(theme:.emerald,age:VineGrowth(days:180)),"botanical_bloom")
        XCTAssertEqual(BotanicalAssets.rail(theme:.autumn,age:VineGrowth(days:365)),"botanical_autumn")
    }
}
