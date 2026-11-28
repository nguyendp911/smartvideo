import XCTest
import UIKit
import ImageIO
import CoreImage
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
    func testContinuousBotanicalTilePlan(){
        let whole=BotanicalTilePlan.tiles(height:260,offset:0,tileHeight:100)
        let sliced=BotanicalTilePlan.tiles(height:140,offset:120,tileHeight:100)
        XCTAssertEqual(whole.map(\.index),[0,1,2])
        XCTAssertEqual(sliced.map(\.index),[1,2])
        XCTAssertEqual(sliced.first?.top,-20)
        XCTAssertEqual(sliced.first?.mirrored,true)
        XCTAssertEqual(BotanicalTilePlan.extraLeaves(age:VineGrowth(days:0),density:1.8),0)
        XCTAssertGreaterThan(BotanicalTilePlan.extraLeaves(age:VineGrowth(days:365),density:1),BotanicalTilePlan.extraLeaves(age:VineGrowth(days:7),density:1))
        XCTAssertEqual(BotanicalTilePlan.edgeFade(0),0)
        XCTAssertEqual(BotanicalTilePlan.edgeFade(0.5),1)
        XCTAssertEqual(BotanicalTilePlan.edgeFade(1),0)
        XCTAssertLessThan(GardenRenderQuality.automatic.rate(lowPower:true),GardenRenderQuality.automatic.rate(lowPower:false))
        XCTAssertEqual(GardenDaylight.title(hour:18),"Hoàng hôn")
    }
    func testMemoryEcosystemRulesAndDirection()throws{
        let dna=MemoryDNA(photos:12,stories:1,voices:1,favorites:1,milestones:1,chapters:1,letters:1)
        XCTAssertEqual(dna.creatures.count,8)
        let empty=MemoryDNA(photos:0,stories:0,voices:0,favorites:0,milestones:0,chapters:0,letters:0)
        XCTAssertTrue(empty.creatures.isEmpty)
        let data=EcosystemData(gardens:[PersonalGarden(title:"Gia đình",kind:.family)])
        XCTAssertEqual(try JSONDecoder().decode(EcosystemData.self,from:JSONEncoder().encode(data)),data)
        XCTAssertEqual(MemoryPortalIndex.prompt("2026-11-28"),MemoryPortalIndex.prompt("2026-11-28"))
        XCTAssertEqual(StoryDirection().voiceVolume,1)
    }
    @MainActor func testEcosystemCreatureAssetsAndRollingYear(){
        for item in MemoryCreature.allCases{
            guard let asset=item.asset else{XCTFail("Missing name for \(item.rawValue)");continue}
            XCTAssertNotNil(UIImage(named:asset),"Missing bundled \(asset)")
        }
        let range=LifeReflectionRange.rolling(LifeDate.date("2026-11-28")!)
        XCTAssertTrue(range.contains("2026-11-28"))
        XCTAssertFalse(range.contains("2026-11-29"))
        XCTAssertEqual(LifeDate.calendar.dateComponents([.day],from:range.interval.start,to:range.interval.end).day,365)
        XCTAssertTrue(MemorySearchView.tokens("Tìm ký ức Đà Lạt 2025").contains("da"))
    }
    func testPhotoSignatureRecipeCompatibilityAndRotation()throws{
        let legacy=Data(#"{"exposure":0,"contrast":1,"saturation":1,"warmth":0,"crop":"Gốc"}"#.utf8)
        var recipe=try JSONDecoder().decode(CreativeRecipe.self,from:legacy)
        XCTAssertNil(recipe.sharpness)
        recipe.rotation=90;recipe.sharpness=0.2;recipe.shadows=0.15
        let url=try CreativeEngine.exportURL(patch(),extension:"jpg")
        defer{try? FileManager.default.removeItem(at:url)}
        let data=try XCTUnwrap(CreativeEngine.render(url,recipe:recipe,maxSize:100000,format:"PNG",quality:1,metadata:false))
        let source=try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil))
        let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        XCTAssertEqual(image.width,300)
        XCTAssertEqual(image.height,420)
        XCTAssertEqual(CreativeEngine.fileExtension("HEIC"),"heic")
    }
    func testPremiumCollectionAndLightingAssets()throws{
        XCTAssertEqual(LightAssets.entries(scene:true,pack:"fixture").first?.id,"pack:fixture:window_morning")
        XCTAssertThrowsError(try LightingCollectionPackage(version:1,scene:["invalid"],light:["invalid"]).decoded())
        XCTAssertEqual(PremiumPresets.all.count,32)
        XCTAssertEqual(Set(PremiumPresets.all.map(\.id)).count,32)
        XCTAssertEqual(Set(PremiumPresets.all.map(\.collection)).count,8)
        XCTAssertEqual(LightAssets.scenes.count,16)
        XCTAssertEqual(LightAssets.textures.count,8)
        for asset in LightAssets.scenes{XCTAssertNotNil(LightAssets.image(asset.id,scene:true))}
        for asset in LightAssets.textures{XCTAssertNotNil(LightAssets.image(asset.id,scene:false))}
        let preset=try XCTUnwrap(PremiumPresets.find("sea.01"))
        XCTAssertEqual(PremiumColorEngine.cube(preset,strength:0.8).count,32*32*32*4*MemoryLayout<Float>.size)
        let url=try CreativeEngine.exportURL(patch(),extension:"jpg")
        defer{try? FileManager.default.removeItem(at:url)}
        let baseline=try XCTUnwrap(CreativeEngine.render(url,recipe:CreativeRecipe(),maxSize:420,format:"PNG",quality:1,metadata:false))
        var recipe=CreativeRecipe()
        recipe.premiumID="sea.01";recipe.premiumStrength=0.8
        let colored=try XCTUnwrap(CreativeEngine.render(url,recipe:recipe,maxSize:420,format:"PNG",quality:1,metadata:false))
        XCTAssertNotEqual(baseline,colored)
        var light=LightMockupRecipe();light.textureID="window_sun";light.opacity=0.6
        recipe.lighting=light
        let lit=try XCTUnwrap(CreativeEngine.render(url,recipe:recipe,maxSize:420,format:"PNG",quality:1,metadata:false))
        XCTAssertNotEqual(colored,lit)
        XCTAssertEqual(try JSONDecoder().decode(CreativeRecipe.self,from:JSONEncoder().encode(recipe)),recipe)
    }
    func testMaskingOnlyChangesSelectedArea()throws{
        let url=try CreativeEngine.exportURL(patch(),extension:"jpg")
        defer{try? FileManager.default.removeItem(at:url)}
        let original=try XCTUnwrap(CIImage(contentsOf:url))
        var layer=PhotoMaskLayer(name:"Cọ",kind:.brush)
        layer.feather=0
        layer.strokes=[MaskStroke(size:0.4,points:[MaskPoint(x:0.25,y:0.5)])]
        layer.grade.exposure=1
        let key=SemanticMaskEngine.sourceKey(url)
        let doc=PhotoMaskDocument(source:key,layers:[layer])
        let changed=try SemanticMaskEngine.apply(original,original:original,document:doc,key:key)
        func pixel(_ image:CIImage,_ x:Int,_ y:Int)->[UInt8]{
            var bytes=[UInt8](repeating:0,count:4)
            bytes.withUnsafeMutableBytes{p in SemanticMaskEngine.context.render(image,toBitmap:p.baseAddress!,rowBytes:4,bounds:CGRect(x:x,y:y,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))}
            return bytes
        }
        XCTAssertNotEqual(pixel(changed,105,150),pixel(original,105,150))
        let a=pixel(changed,350,150),b=pixel(original,350,150)
        for i in 0..<3{XCTAssertLessThanOrEqual(abs(Int(a[i])-Int(b[i])),1)}
        XCTAssertEqual(try JSONDecoder().decode(PhotoMaskDocument.self,from:JSONEncoder().encode(doc)),doc)
    }
    func testSkyModelBundledAndRuns()throws{
        XCTAssertTrue(SemanticMaskEngine.skyAvailable)
        let url=try CreativeEngine.exportURL(patch(),extension:"jpg")
        defer{try? FileManager.default.removeItem(at:url)}
        let image=try XCTUnwrap(CIImage(contentsOf:url))
        let mask=try SemanticMaskEngine.mask(image,layer:PhotoMaskLayer(name:"Sky",kind:.sky),key:SemanticMaskEngine.sourceKey(url))
        XCTAssertEqual(mask.extent,image.extent)
    }
    func testTasteLearnsConfirmedStylesWithoutCopyingMasks()throws{
        let scene=TasteContext(scene:.beach,brightness:0.6)
        var profile=TasteProfile()
        var recipe=CreativeRecipe();recipe.premiumID="sea.01";recipe.exposure=0.4;recipe.crop="1:1";recipe.rotation=90
        var layer=PhotoMaskLayer(name:"Sky",kind:.sky);layer.grade.saturation=1.4
        layer.strokes=[MaskStroke(size:0.2,points:[MaskPoint(x:0.1,y:0.2)])]
        recipe.masking=[PhotoMaskDocument(source:"old",layers:[layer])]
        let id=UUID(),sample=TasteSample(photo:id,context:scene,recipe:recipe,source:"old")
        profile.record(sample);profile.record(sample)
        XCTAssertEqual(profile.samples.count,1)
        XCTAssertNil(sample.global.masking);XCTAssertNil(sample.global.rotation);XCTAssertEqual(sample.global.crop,"Gốc")
        XCTAssertEqual(sample.regions.first?.grade.saturation,1.4)
        XCTAssertTrue(profile.suggest(scene)?.regions.isEmpty ?? false)
        recipe.exposure=0.6
        profile.record(TasteSample(photo:UUID(),context:scene,recipe:recipe,source:"old"))
        let suggestion=try XCTUnwrap(profile.suggest(scene))
        XCTAssertEqual(suggestion.global.exposure,0.5,accuracy:0.0001)
        XCTAssertEqual(suggestion.regions.count,1)
        XCTAssertNil(profile.suggest(TasteContext(scene:.night,brightness:0.6)))
        var target=CreativeRecipe();target.crop="4:5"
        let applied=suggestion.applying(to:target,source:"new",verified:suggestion.regions)
        XCTAssertEqual(applied.crop,"4:5")
        XCTAssertEqual(applied.masking?.first?.source,"new")
        XCTAssertTrue(applied.masking?.first?.layers.first?.strokes.isEmpty ?? false)
        XCTAssertNil(applied.masking?.first?.layers.first?.replacement)
        XCTAssertEqual(try JSONDecoder().decode(TasteProfile.self,from:JSONEncoder().encode(profile)),profile)
        recipe.exposure=0.9;profile.record(TasteSample(photo:id,context:scene,recipe:recipe,source:"old"))
        XCTAssertEqual(profile.samples.count,2)
        XCTAssertEqual(TasteScene.classify(["beach","person"]),.beach)
    }
    func testMaskSkillLearnsFromCorrectionsOnHeldOutImages()throws{
        func example(_ key:String)->MaskTrainingExample{
            let p=MaskTrainingPoint(features:[0.42,0.2,0.4,0.9,0.5,0.7,0.85,0.6,0.8,0.02,0.45],positive:true)
            let n=MaskTrainingPoint(features:[0.58,0.6,0.5,0.2,0.43,0.4,0.3,0.45,0.25,0.35,0.55],positive:false)
            return MaskTrainingExample(key:key,kind:.sky,points:Array(repeating:p,count:24)+Array(repeating:n,count:24))
        }
        var profile=MaskSkillProfile()
        profile.ingest([example("a"),example("b")])
        XCTAssertNil(profile.models[PhotoMaskKind.sky.rawValue])
        profile.ingest([example("c")])
        let model=try XCTUnwrap(profile.models[PhotoMaskKind.sky.rawValue])
        XCTAssertLessThan(model.validationLoss,model.baselineLoss)
        XCTAssertGreaterThan(model.probability(example("new").points[0]),0.42)
        XCTAssertLessThan(model.probability(example("new").points[47]),0.58)
        profile.ingest([example("a")]);XCTAssertEqual(profile.examples.count,3)
        XCTAssertNil(profile.models[PhotoMaskKind.subject.rawValue])
        XCTAssertEqual(try JSONDecoder().decode(MaskSkillProfile.self,from:JSONEncoder().encode(profile)),profile)
    }
    func testMaskCorrectionBrushLabelsLastStrokeWins(){
        let point=MaskPoint(x:0.5,y:0.2)
        let a=MaskStroke(size:0.4,points:[point]),b=MaskStroke(subtract:true,size:0.1,points:[point])
        let labels=MaskCorrectionPixels.labels(width:100,height:100,strokes:[a,b])
        XCTAssertEqual(labels[79*100+49],0)
        XCTAssertEqual(labels[79*100+60],1)
        XCTAssertEqual(labels[10],-1)
    }
    func testLearnedCorrectionChangesActualMaskPixels(){
        let rect=CGRect(x:0,y:0,width:32,height:32)
        let source=CIImage(color:CIColor(red:0.3,green:0.5,blue:0.7)).cropped(to:rect)
        let data=Array(repeating:Float(0.5),count:32*32*4).enumerated().map{$0.offset%4==3 ? Float(1):$0.element}
        let bytes=data.withUnsafeBytes{Data($0)}
        let base=CIImage(bitmapData:bytes,bytesPerRow:32*16,size:rect.size,format:.RGBAf,colorSpace:nil)
        func average(_ image:CIImage)->Float{
            var value=[Float](repeating:0,count:4)
            let pixel=CGRect(x:16,y:16,width:1,height:1)
            value.withUnsafeMutableBytes{p in SemanticMaskEngine.context.render(image,toBitmap:p.baseAddress!,rowBytes:16,bounds:pixel,format:.RGBAf,colorSpace:nil)}
            return value[0]
        }
        let up=MaskCorrectionModel(weights:[2]+Array(repeating:0,count:11),imageCount:3,baselineLoss:1,validationLoss:0.8)
        let down=MaskCorrectionModel(weights:[-2]+Array(repeating:0,count:11),imageCount:3,baselineLoss:1,validationLoss:0.8)
        let raised=MaskCorrectionPixels.refine(image:source,base:base,model:up)
        let lowered=MaskCorrectionPixels.refine(image:source,base:base,model:down)
        XCTAssertEqual(raised.extent,rect)
        XCTAssertGreaterThan(average(raised),average(base)+0.1)
        XCTAssertLessThan(average(lowered),average(base)-0.1)
    }
    func testAdaptiveEditingRegressorAndCompositionLearning()throws{
        let f=EditingFeatures(brightness:0.4,contrast:0.16,dark:0.1,bright:0.01,saturation:0.22,edge:0.1,aspect:1.5)
        let base=LearnedEditParameter.exposure.value(f.baseline())
        let examples=(0..<6).map{_ in (f,base+0.45)}
        let model=try XCTUnwrap(EditSkillRegressor.validated(examples,parameter:.exposure))
        XCTAssertLessThan(model.heldOutError,model.baselineError)
        XCTAssertGreaterThan(model.predict(f,.exposure),base)
        XCTAssertNil(EditSkillRegressor.validated(Array(examples.prefix(2)),parameter:.exposure))
        var recipe=CreativeRecipe();recipe.crop="4:5"
        var light=LightMockupRecipe();light.textureID="window";light.x=0.7;recipe.lighting=light
        let sample=TasteSample(photo:UUID(),context:TasteContext(scene:.portrait,brightness:0.4,features:f),recipe:recipe,source:"test")
        XCTAssertEqual(sample.compositionCrop,"4:5")
        XCTAssertEqual(sample.lightStyle?.x,0)
        XCTAssertNil(sample.global.lighting)
        XCTAssertTrue(PhotoMaskKind.eyes.canLearn)
        XCTAssertTrue(PhotoMaskKind.person.canLearn)
        XCTAssertFalse(PhotoMaskKind.brush.canLearn)
        XCTAssertEqual(try JSONDecoder().decode(TasteSample.self,from:JSONEncoder().encode(sample)),sample)
    }
    func testCompositionAnchorBounds(){
        let rect=CGRect(x:10,y:20,width:400,height:200)
        let left=CompositionAnchor(x:0,y:0.5).rect(in:rect,ratio:1)
        let right=CompositionAnchor(x:1,y:0.5).rect(in:rect,ratio:1)
        XCTAssertEqual(left.minX,10);XCTAssertEqual(right.maxX,410)
        XCTAssertEqual(left.width,200);XCTAssertEqual(right.height,200)
        let a=CompositionAnchor.fromFocus(x:0.85,y:0.5,width:400,height:200,crop:"1:1")
        XCTAssertEqual(a.x,1)
    }
    func testMockupSceneCoverNeverLeavesGaps(){
        let target=CGRect(x:17,y:11,width:420,height:760),source=CGRect(x:0,y:0,width:1500,height:900)
        for zoom in [1.0,1.2,2.5,3.0]{for x in [-1.0,0,1.0]{for y in [-1.0,0,1.0]{
            let r=LightMockupEngine.sceneRect(source:source,target:target,zoom:zoom,x:x,y:y)
            XCTAssertLessThanOrEqual(r.minX,target.minX+0.0001);XCTAssertLessThanOrEqual(r.minY,target.minY+0.0001)
            XCTAssertGreaterThanOrEqual(r.maxX,target.maxX-0.0001);XCTAssertGreaterThanOrEqual(r.maxY,target.maxY-0.0001)
        }}}
    }
    func testMockupTextureFadeAndAlpha(){
        let rect=CGRect(x:0,y:0,width:100,height:100)
        let white=CIImage(color:CIColor.white).cropped(to:rect)
        let faded=LightMockupEngine.softTexture(white,fade:0.2)
        func alpha(_ image:CIImage,_ x:Int,_ y:Int)->UInt8{
            var bytes=[UInt8](repeating:0,count:4)
            bytes.withUnsafeMutableBytes{p in SemanticMaskEngine.context.render(image,toBitmap:p.baseAddress!,rowBytes:4,bounds:CGRect(x:x,y:y,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))}
            return bytes[3]
        }
        XCTAssertLessThan(alpha(faded,1,50),64)
        XCTAssertGreaterThan(alpha(faded,50,50),245)
        var recipe=LightMockupRecipe();recipe.scope = .subject;recipe.edgeFade=0.2
        XCTAssertEqual(try! JSONDecoder().decode(LightMockupRecipe.self,from:JSONEncoder().encode(recipe)),recipe)
    }
    func testMockupPNGOverlayKeepsTransparentPixelsAndColor()throws{
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=false
        let png=try XCTUnwrap(UIGraphicsImageRenderer(size:CGSize(width:100,height:100),format:format).image{c in
            UIColor.red.setFill();c.fill(CGRect(x:0,y:0,width:50,height:100))
        }.pngData())
        var recipe=LightMockupRecipe();recipe.customTexture=png;recipe.blend = .overlay;recipe.opacity=1;recipe.edgeFade=0
        let rect=CGRect(x:0,y:0,width:100,height:100)
        let base=CIImage(color:CIColor(red:0,green:0,blue:1)).cropped(to:rect)
        let image=try XCTUnwrap(LightMockupEngine.apply(base,original:base,recipe:recipe))
        func pixel(_ x:Int)->[UInt8]{
            var p=[UInt8](repeating:0,count:4)
            p.withUnsafeMutableBytes{b in SemanticMaskEngine.context.render(image,toBitmap:b.baseAddress!,rowBytes:4,bounds:CGRect(x:x,y:50,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))}
            return p
        }
        XCTAssertGreaterThan(pixel(25)[0],245);XCTAssertLessThan(pixel(25)[2],10)
        XCTAssertGreaterThan(pixel(75)[2],245);XCTAssertLessThan(pixel(75)[0],10)
    }
    func testPreviewThumbnailBoundAndOriginalExport()throws{
        let source=try patch(),url=try CreativeEngine.exportURL(source,extension:"jpg")
        defer{try? FileManager.default.removeItem(at:url)}
        var r=CreativeRecipe();r.premiumID="sea.01"
        let preview=try XCTUnwrap(CreativeEngine.render(url,recipe:r,maxSize:120,format:"JPEG",quality:0.9,metadata:false,thumbnailOnly:true))
        let output=try XCTUnwrap(CreativeEngine.render(url,recipe:r,maxSize:100000,format:"PNG",quality:1,metadata:false))
        let previewImage=try XCTUnwrap(UIImage(data:preview)?.cgImage),full=try XCTUnwrap(UIImage(data:output)?.cgImage)
        XCTAssertLessThanOrEqual(max(previewImage.width,previewImage.height),120)
        XCTAssertEqual(full.width,420);XCTAssertEqual(full.height,300)
        XCTAssertEqual(try Data(contentsOf:url),source)
        XCTAssertNil(CreativeEngine.render(url,recipe:r,maxSize:0,format:"JPEG",quality:0.9,metadata:false))
    }
    func testMasterPresetCubeRangeAndNeutralRamp()throws{
        for preset in PremiumPresets.all{
            let data=PremiumColorEngine.cube(preset,strength:1,dimension:16)
            let floats=data.withUnsafeBytes{Array($0.bindMemory(to:Float.self))}
            XCTAssertEqual(floats.count,16*16*16*4)
            XCTAssertTrue(floats.allSatisfy{$0.isFinite && $0>=0 && $0<=1},preset.id)
            var previous:Float = -1
            for i in 0..<16{
                let k=(i*16*16+i*16+i)*4
                XCTAssertEqual(floats[k],floats[k+1],accuracy:0.0001,preset.id)
                XCTAssertEqual(floats[k],floats[k+2],accuracy:0.0001,preset.id)
                XCTAssertGreaterThanOrEqual(floats[k],previous,preset.id);previous=floats[k]
            }
        }
    }
    func testMasterDownsampleBoundsAndMaskCoverage(){
        let rect=CGRect(x:-25,y:17,width:421,height:301)
        let source=CIImage(color:CIColor(red:0.3,green:0.5,blue:0.7)).cropped(to:rect)
        let out=MasterImageQuality.downsample(source,maxSize:120)
        XCTAssertEqual(out.extent.minX,0);XCTAssertEqual(out.extent.minY,0)
        XCTAssertEqual(out.extent.width,120);XCTAssertEqual(out.extent.height,85)
        XCTAssertEqual(LightMockupEngine.maskCoverage(CIImage(color:CIColor.black).cropped(to:rect)),0,accuracy:0.001)
        XCTAssertEqual(LightMockupEngine.maskCoverage(CIImage(color:CIColor.white).cropped(to:rect)),1,accuracy:0.001)
    }
    func testMaskValidationHandlesInvalidFeatureRows(){
        let point=MaskTrainingPoint(features:[],positive:true)
        XCTAssertEqual(point.prior,0.5)
        XCTAssertEqual(MaskCorrectionModel.loss([point],model:nil),0)
    }
}
