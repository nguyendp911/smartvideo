import SwiftUI
import ImageIO
import Vision
import CryptoKit
import MapKit

struct SignatureEvent:Identifiable {
    let id:UUID
    let shots:[Shot]
    var title:String {
        let names=Set(shots.map(\.session).filter{!$0.isEmpty})
        return names.count==1 ? (names.first ?? "Khoảnh khắc") : TimelineIndex.label(shots.first?.day ?? "")
    }
}
enum SignatureIndex {
    static func events(_ shots:[Shot],gap:TimeInterval=7200)->[SignatureEvent]{
        var groups=[[Shot]]()
        for shot in shots.filter({$0.deleted==nil}).sorted(by:{$0.date<$1.date}){
            if let last=groups.last?.last,shot.day==last.day,shot.date.timeIntervalSince(last.date)<=gap {groups[groups.count-1].append(shot)}
            else{groups.append([shot])}
        }
        return groups.reversed().compactMap{items in items.first.map{SignatureEvent(id:$0.id,shots:items)}}
    }
    static func location(_ url:URL)->CLLocationCoordinate2D? {
        guard let src=CGImageSourceCreateWithURL(url as CFURL,nil),
              let props=CGImageSourceCopyPropertiesAtIndex(src,0,nil) as? [String:Any],
              let gps=props[kCGImagePropertyGPSDictionary as String] as? [String:Any],
              let lat=gps["Latitude"] as? Double,let lon=gps["Longitude"] as? Double else{return nil}
        let p=CLLocationCoordinate2D(latitude:gps["LatitudeRef"] as? String=="S" ? -abs(lat):lat,longitude:gps["LongitudeRef"] as? String=="W" ? -abs(lon):lon)
        return CLLocationCoordinate2DIsValid(p) ? p:nil
    }
}
struct SignatureAssessment:Identifiable {
    let id:UUID
    let sharpness:Double
    let brightness:Double
    let faces:Int
    let labels:[String]
    let hash:UInt64
    let digest:String
    let bytes:Int64
    var score:Double {min(1,sharpness*12)*0.65+(1-min(1,abs(brightness-0.5)*2))*0.35}
}
enum SignatureAnalyzer {
    static func assess(_ shot:Shot,vault:Vault)->SignatureAssessment? {
        let url=vault.picture(shot,original:true)
        guard let bytes=try? Data(contentsOf:url,options:.mappedIfSafe),let cg=PhotoEngine.thumb(bytes,limit:384) else{return nil}
        var gray=[UInt8](repeating:0,count:64*64)
        let drawn=gray.withUnsafeMutableBytes{p->Bool in
            guard let ctx=CGContext(data:p.baseAddress,width:64,height:64,bitsPerComponent:8,bytesPerRow:64,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else{return false}
            ctx.draw(cg,in:CGRect(x:0,y:0,width:64,height:64));return true
        }
        guard drawn else{return nil}
        var edges=0.0
        for y in 1..<63 {for x in 1..<63 {let i=y*64+x;edges+=abs(Double(gray[i])*4-Double(gray[i-1])-Double(gray[i+1])-Double(gray[i-64])-Double(gray[i+64]))}}
        let mean=gray.reduce(0.0){$0+Double($1)}/Double(gray.count)/255
        var hash:UInt64=0
        for y in 0..<8{for x in 0..<8{
            let i=(y*8+4)*64+x*7
            if gray[i]>gray[i+6]{hash |= UInt64(1) << (y*8+x)}
        }}
        let face=VNDetectFaceRectanglesRequest(),classify=VNClassifyImageRequest()
        let handler=VNImageRequestHandler(cgImage:cg,options:[:])
        try? handler.perform([face,classify])
        let labels=(classify.results ?? []).filter{$0.confidence>=0.15}.prefix(8).map(\.identifier)
        let digest=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
        return SignatureAssessment(id:shot.id,sharpness:edges/(62*62*255),brightness:mean,faces:face.results?.count ?? 0,labels:labels,hash:hash,digest:digest,bytes:Int64(bytes.count))
    }
    static func similar(_ rows:[SignatureAssessment])->[[UUID]]{
        var groups=[[UUID]](),used=Set<UUID>()
        for (i,a) in rows.enumerated() where !used.contains(a.id){
            var ids=[a.id]
            for b in rows.dropFirst(i+1) where !used.contains(b.id){
                if a.digest==b.digest || (a.hash ^ b.hash).nonzeroBitCount<=5 {ids.append(b.id)}
            }
            if ids.count>1{groups.append(ids);used.formUnion(ids)}
        }
        return groups
    }
}
struct SignatureAtlas:View {
    let shots:[Shot]
    let vault:Vault
    @State private var pins=[Pin]()
    @State private var selected:UUID?
    @State private var loaded=false
    private struct Pin:Identifiable {let id:UUID;let coordinate:CLLocationCoordinate2D;let shot:Shot}
    var body:some View{
        VStack{
            if !loaded{ProgressView("Đọc GPS từ ảnh gốc…")}
            else if pins.isEmpty{ContentUnavailableView("Chưa có tọa độ GPS",systemImage:"map",description:Text("Chỉ hiện ảnh có GPS trong metadata gốc. Không suy đoán vị trí."))}
            else{
                Map(selection:$selected){
                    ForEach(pins){p in Marker(p.shot.session.isEmpty ? p.shot.day:p.shot.session,coordinate:p.coordinate).tag(p.id)}
                }.mapStyle(.standard).frame(maxHeight:.infinity)
                if let pin=pins.first(where:{$0.id==selected}){
                    HStack{DiskImage(url:vault.thumbnail(pin.id),limit:180).scaledToFill().frame(width:86,height:86).clipped().clipShape(RoundedRectangle(cornerRadius:10))
                        VStack(alignment:.leading){Text(pin.shot.session.isEmpty ? TimelineIndex.label(pin.shot.day):pin.shot.session);Text(String(format:"%.5f, %.5f",pin.coordinate.latitude,pin.coordinate.longitude)).font(.caption).foregroundStyle(.secondary)}
                        Spacer()
                    }.padding()
                }else{Text("\(pins.count) ảnh có tọa độ").font(.caption).padding()}
            }
        }.navigationTitle("Memory Atlas").task{
            let source=shots,v=vault
            pins=await Task.detached(priority:.utility){source.compactMap{s in SignatureIndex.location(v.picture(s,original:true)).map{Pin(id:s.id,coordinate:$0,shot:s)}}}.value
            loaded=true
        }
    }
}
struct SignatureIntelligence:View {
    let shots:[Shot]
    let vault:Vault
    @State private var rows=[SignatureAssessment]()
    @State private var scanning=false
    @State private var scanned=false
    @State private var query=""
    @State private var mode="best"
    @State private var progress=0
    private var matches:[SignatureAssessment]{
        switch mode {
        case "blur":return rows.sorted{$0.sharpness<$1.sharpness}.filter{$0.sharpness<0.035}
        case "search":return rows.filter{query.isEmpty || $0.labels.joined(separator:" ").localizedCaseInsensitiveContains(query)}
        case "faces":return rows.filter{$0.faces>0}
        default:return rows.sorted{$0.score>$1.score}
        }
    }
    var body:some View{
        List{
            Section{
                Button(scanned ? "Phân tích lại":"Phân tích ảnh trên thiết bị"){Task{await scan()}}.disabled(scanning)
                if scanning{ProgressView(value:Double(progress),total:Double(max(1,shots.count))){Text("\(progress)/\(shots.count) ảnh")}}
                Text("Phân tích độ nét, độ sáng và nhãn hình ảnh bằng Vision. Điểm ảnh chỉ là gợi ý kỹ thuật, không tự xóa ảnh.").font(.caption).foregroundStyle(.secondary)
            }
            if scanned{
                Section("Dung lượng ảnh gốc đã đọc"){
                    Text(ByteCountFormatter.string(fromByteCount:rows.reduce(Int64(0)){$0+$1.bytes},countStyle:.file))
                    Text("\(rows.count)/\(shots.count) ảnh phân tích được").font(.caption)
                }
                Section{
                    Picker("Công cụ",selection:$mode){
                        Text("Best Shot").tag("best");Text("Ảnh mờ").tag("blur");Text("Tìm nội dung").tag("search");Text("Có khuôn mặt").tag("faces");Text("Ảnh giống").tag("duplicates")
                    }
                    if mode=="search"{TextField("Nhãn Vision (tiếng Anh)",text:$query)}
                }
                if mode=="duplicates"{
                    let groups=SignatureAnalyzer.similar(rows)
                    Section("Nhóm nghi trùng / gần giống"){
                        if groups.isEmpty{Text("Không tìm thấy nhóm.")}
                        ForEach(groups.indices,id:\.self){i in
                            ScrollView(.horizontal){HStack{ForEach(groups[i],id:\.self){id in DiskImage(url:vault.thumbnail(id),limit:140).scaledToFill().frame(width:94,height:94).clipped()}}}
                        }
                    }
                }else{
                    Section("Kết quả"){
                        if matches.isEmpty{Text("Không có ảnh phù hợp.")}
                        ForEach(matches){r in
                            if let shot=shots.first(where:{$0.id==r.id}){
                                HStack(alignment:.top){
                                    DiskImage(url:vault.thumbnail(r.id),limit:140).scaledToFill().frame(width:72,height:72).clipped().clipShape(RoundedRectangle(cornerRadius:6))
                                    VStack(alignment:.leading,spacing:4){
                                        Text(shot.day).font(.headline)
                                        Text("Điểm \(Int(r.score*100))/100 · \(r.faces) mặt").font(.caption)
                                        Text(r.labels.joined(separator:", ")).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }.navigationTitle("Photo Intelligence")
    }
    @MainActor private func scan() async {
        scanning=true;scanned=false;rows=[];progress=0
        defer{scanning=false;scanned=true}
        for shot in shots{
            if Task.isCancelled{return}
            let v=vault
            if let r=await Task.detached(priority:.utility,operation:{SignatureAnalyzer.assess(shot,vault:v)}).value{rows.append(r)}
            progress+=1
        }
    }
}
