import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

struct Shot: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var day: String
    var session: String
    var rating: Int
    var tags: String
    var deleted: Date?
    var light: Light
    var look: Look
    var sourceFile: String
    var enhanced: Bool
    var lens: String
    var collections: [String]? = nil
    var note: String? = nil
}
actor Vault {
    static let shared = Vault(root: FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("VieLens",isDirectory:true))
    nonisolated let root: URL
    private let fm = FileManager.default
    private var loaded = false
    private var records: [UUID:Shot] = [:]
    init(root:URL) { self.root=root }
    nonisolated func directory(_ id:UUID) -> URL { root.appendingPathComponent(id.uuidString,isDirectory:true) }
    nonisolated func picture(_ shot:Shot, original:Bool=false) -> URL {
        directory(shot.id).appendingPathComponent(original || !shot.enhanced ? shot.sourceFile : "finished.jpg")
    }
    nonisolated func thumbnail(_ id:UUID) -> URL { directory(id).appendingPathComponent("thumb.jpg") }

    private func persist(_ shot:Shot, in folder:URL) throws {
        try JSONEncoder().encode(shot).write(to:folder.appendingPathComponent("shot.json"),options:.atomic)
    }
    private func load() throws {
        guard !loaded else { return }
        try fm.createDirectory(at:root, withIntermediateDirectories:true)
        for dir in try fm.contentsOfDirectory(at:root, includingPropertiesForKeys:nil) {
            guard UUID(uuidString:dir.lastPathComponent) != nil,
                  let data=try? Data(contentsOf:dir.appendingPathComponent("shot.json")),
                  let shot=try? JSONDecoder().decode(Shot.self,from:data),
                  shot.id.uuidString==dir.lastPathComponent else { continue }
            if let deleted=shot.deleted, Date().timeIntervalSince(deleted)>30*86400 {
                if (try? fm.removeItem(at:dir)) != nil { continue }
            }
            records[shot.id]=shot
        }
        loaded=true
    }
    func all() throws -> [Shot] {
        try load()
        return records.values.sorted { $0.date == $1.date ? $0.id.uuidString > $1.id.uuidString : $0.date > $1.date }
    }
    static func captureDate(_ exif:[String:Any]?, fallback:Date) -> (Date,String) {
        let formatter=DateFormatter()
        formatter.locale=Locale(identifier:"en_US_POSIX")
        formatter.calendar=Calendar(identifier:.gregorian)
        formatter.timeZone = .current
        formatter.dateFormat="yyyy:MM:dd HH:mm:ss"
        if let value=exif?["DateTimeOriginal"] as? String {
            if let offset=exif?["OffsetTimeOriginal"] as? String {
                let iso=ISO8601DateFormatter()
                let part=value.prefix(10).replacingOccurrences(of:":",with:"-")
                if value.count>=19, let date=iso.date(from:part+"T"+String(value.suffix(8))+offset) { return (date,part) }
            }
            if let date=formatter.date(from:value) { return (date,String(value.prefix(10)).replacingOccurrences(of:":",with:"-")) }
        }
        formatter.dateFormat="yyyy-MM-dd"
        return (fallback,formatter.string(from:fallback))
    }
    func add(_ data:Data, look:Look, session:String, time:Date = Date(), lens:String="") throws -> Shot {
        try load()
        guard let source=CGImageSourceCreateWithData(data as CFData,nil), let uti=CGImageSourceGetType(source),
              let thumb=PhotoEngine.thumbnail(data) else { throw CameraError.unreadable }
        let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any]
        let moment=Self.captureDate(props?[kCGImagePropertyExifDictionary as String] as? [String:Any],fallback:time)
        let ext=UTType(uti as String)?.preferredFilenameExtension ?? "img"
        var shot=Shot(id:UUID(),date:moment.0,day:moment.1,session:session,rating:0,tags:"",deleted:nil,light:.natural,look:look,
                      sourceFile:"original."+ext,enhanced:false,lens:lens)
        let stage=root.appendingPathComponent(".stage-"+shot.id.uuidString)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false)
        defer { try? fm.removeItem(at:stage) }
        try data.write(to:stage.appendingPathComponent(shot.sourceFile))
        try thumb.write(to:stage.appendingPathComponent("thumb.jpg"))
        try persist(shot,in:stage)
        let dir=directory(shot.id)
        try fm.moveItem(at:stage,to:dir)
        records[shot.id]=shot
        // The original is durably discoverable even if rendering fails or iOS stops the process.
        if let result=try? PhotoEngine.render(data,look:look) {
            do {
                try result.jpeg.write(to:dir.appendingPathComponent("finished.jpg"),options:.atomic)
                try result.thumbnail.write(to:thumbnail(shot.id),options:.atomic)
                shot.light=result.light; shot.enhanced=true
                try persist(shot,in:dir)
                records[shot.id]=shot
            } catch { return records[shot.id]! }
        }
        return shot
    }
    func edit(_ id:UUID, rating:Int?=nil, tags:String?=nil, session:String?=nil, trash:Bool?=nil, addCollection:String?=nil, removeCollection:String?=nil, note:String?=nil) throws {
        try load()
        guard var item=records[id] else { throw CameraError.unreadable }
        if let rating { item.rating=min(5,max(0,rating)) }
        if let tags { item.tags=tags }
        if let session { item.session=session }
        if let trash { item.deleted=trash ? Date() : nil }
        if let addCollection {
            let name=String(addCollection.trimmingCharacters(in:.whitespacesAndNewlines).prefix(100))
            if !name.isEmpty {item.collections=Array(Set((item.collections ?? [])+[name])).sorted()}
        }
        if let removeCollection {item.collections=(item.collections ?? []).filter{$0 != removeCollection}}
        if let note {item.note=note}
        try persist(item,in:directory(id)); records[id]=item
    }
    struct BackupItem: Codable { let id:UUID; let files:[String:String] }
    struct Backup: Codable { let version:Int; let items:[BackupItem] }
    private func digest(_ url:URL) throws -> String {
        let handle=try FileHandle(forReadingFrom:url); defer { try? handle.close() }
        var sha=SHA256()
        while let chunk=try handle.read(upToCount:1<<20), !chunk.isEmpty { sha.update(data:chunk) }
        return sha.finalize().map { String(format:"%02x",$0) }.joined()
    }
    func backup(to parent:URL) throws -> Int {
        try load()
        let items=records.values.filter{$0.deleted==nil}
        let folder=parent.appendingPathComponent("VieLens-"+UUID().uuidString.prefix(8))
        let stage=parent.appendingPathComponent(".VieLens-"+UUID().uuidString)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false)
        defer { try? fm.removeItem(at:stage) }
        var manifest=[BackupItem]()
        for item in items {
            let target=stage.appendingPathComponent(item.id.uuidString)
            try fm.createDirectory(at:target,withIntermediateDirectories:false)
            let files=[item.sourceFile,"shot.json","thumb.jpg"]+(item.enhanced ? ["finished.jpg"] : [])
            var sums=[String:String]()
            for file in files {
                let out=target.appendingPathComponent(file)
                try fm.copyItem(at:directory(item.id).appendingPathComponent(file),to:out)
                sums[file]=try digest(out)
            }
            manifest.append(BackupItem(id:item.id,files:sums))
        }
        try JSONEncoder().encode(Backup(version:1,items:manifest)).write(to:stage.appendingPathComponent("VieLens.json"),options:.atomic)
        try fm.moveItem(at:stage,to:folder)
        return items.count
    }
    func restore(from folder:URL) throws -> (Int,Int) {
        try load()
        let book=try JSONDecoder().decode(Backup.self,from:Data(contentsOf:folder.appendingPathComponent("VieLens.json")))
        guard book.version==1 else { throw CameraError.unreadable }
        var count=0,skipped=0
        for item in book.items {
            if records[item.id] != nil { skipped+=1; continue }
            let source=folder.appendingPathComponent(item.id.uuidString)
            let stage=root.appendingPathComponent(".restore-"+UUID().uuidString)
            try fm.createDirectory(at:stage,withIntermediateDirectories:false)
            defer { try? fm.removeItem(at:stage) }
            for (name,sum) in item.files {
                guard name.range(of:"^(original\\.[A-Za-z0-9]{1,12}|shot\\.json|thumb\\.jpg|finished\\.jpg)$",options:.regularExpression) != nil else { throw CameraError.unreadable }
                let src=source.appendingPathComponent(name)
                guard (try src.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true else { throw CameraError.unreadable }
                let dst=stage.appendingPathComponent(name)
                try fm.copyItem(at:src,to:dst)
                guard try digest(dst)==sum else { throw CameraError.unreadable }
            }
            let shot=try JSONDecoder().decode(Shot.self,from:Data(contentsOf:stage.appendingPathComponent("shot.json")))
            guard shot.id==item.id,shot.sourceFile.hasPrefix("original."),item.files[shot.sourceFile] != nil,
                  item.files["thumb.jpg"] != nil, !shot.enhanced || item.files["finished.jpg"] != nil else { throw CameraError.unreadable }
            try fm.moveItem(at:stage,to:directory(item.id));records[item.id]=shot;count+=1
        }
        return (count,skipped)
    }
}
