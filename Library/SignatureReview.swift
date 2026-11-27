import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import CryptoKit

struct ExactDuplicateGroup:Identifiable {
    let digest:String
    let shots:[Shot]
    var id:String{digest}
    var suggestedKeep:Shot?{
        shots.sorted{
            if $0.rating != $1.rating{return $0.rating>$1.rating}
            if $0.date != $1.date{return $0.date<$1.date}
            return $0.id.uuidString<$1.id.uuidString
        }.first
    }
}
enum DuplicateScanner {
    static func checksum(_ url:URL)throws->String{
        let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
        var hash=SHA256()
        while let data=try handle.read(upToCount:1<<20),!data.isEmpty{hash.update(data:data)}
        return hash.finalize().map{String(format:"%02x",$0)}.joined()
    }
    static func groups(_ shots:[Shot],vault:Vault)->[ExactDuplicateGroup]{
        var byHash=[String:[Shot]]()
        for shot in shots where shot.deleted==nil{
            if Task.isCancelled{return []}
            if let hash=try? checksum(vault.picture(shot,original:true)){byHash[hash,default:[]].append(shot)}
        }
        return byHash.filter{$0.value.count>1}.map{ExactDuplicateGroup(digest:$0.key,shots:$0.value)}.sorted{$0.shots.count>$1.shots.count}
    }
}
struct DuplicateReview:View {
    @ObservedObject var model:LibraryModel
    @State private var groups=[ExactDuplicateGroup]()
    @State private var selected=Set<UUID>()
    @State private var working=false
    @State private var scanned=false
    @State private var confirm=false
    @State private var notice=""
    @State private var scanTask:Task<Void,Never>?
    private var active:[Shot]{model.shots.filter{$0.deleted==nil}}
    var body:some View{
        List{
            Section{
                Button(scanned ? "Quét lại thư viện":"Quét bản trùng chính xác"){scan()}.disabled(working)
                if working{ProgressView()}
                Text("Chỉ gom tệp ảnh gốc giống hệt theo SHA-256. Ảnh gần giống vẫn nằm trong Photo Intelligence để xem riêng. Ảnh có chỉnh màu hoặc ghi chú khác nhau vẫn có thể chung ảnh gốc; hãy kiểm tra trước khi xóa.").font(.caption).foregroundStyle(.secondary)
                if scanned{
                    Button("Đề xuất bản giữ lại"){selected=Set(groups.flatMap{g in g.shots.filter{$0.id != g.suggestedKeep?.id && $0.rating==0 && ($0.note ?? "").isEmpty && ($0.collections ?? []).isEmpty && $0.tags.isEmpty && $0.session.isEmpty}.map(\.id)})}.disabled(working)
                    Button("Bỏ chọn"){selected=[]}.disabled(working)
                }
            }
            if scanned && groups.isEmpty{Section{Text("Không còn nhóm trùng chính xác.")}}
            ForEach(groups){group in
                Section("\(group.shots.count) bản cùng ảnh gốc"){
                    ForEach(group.shots){shot in
                        Button{
                            if selected.contains(shot.id){selected.remove(shot.id)}
                            else if group.shots.filter({!selected.contains($0.id)}).count>1{selected.insert(shot.id)}
                        }label:{
                            HStack{
                                DiskImage(url:model.vault.thumbnail(shot.id),limit:180).scaledToFill().frame(width:72,height:72).clipped().clipShape(RoundedRectangle(cornerRadius:8))
                                VStack(alignment:.leading,spacing:3){
                                    Text(shot.day)
                                    Text("\(shot.rating) sao · \(shot.look.rawValue)").font(.caption)
                                    if shot.id==group.suggestedKeep?.id{Text("Gợi ý giữ lại").font(.caption2).foregroundStyle(gold)}
                                    if !shot.session.isEmpty{Text(shot.session).font(.caption2)}
                                    if let note=shot.note,!note.isEmpty{Text(note).font(.caption2).lineLimit(2)}
                                    if !shot.tags.isEmpty{Text(shot.tags).font(.caption2)}
                                    if let names=shot.collections,!names.isEmpty{Text(names.joined(separator:", ")).font(.caption2)}
                                }
                                Spacer();Image(systemName:selected.contains(shot.id) ? "checkmark.circle.fill":"circle").foregroundStyle(selected.contains(shot.id) ? gold:.secondary)
                            }
                        }.buttonStyle(.plain).disabled(working)
                    }
                }
            }
            if !selected.isEmpty{
                Section{Button("Đưa \(selected.count) ảnh vào thùng rác",role:.destructive){confirm=true}.disabled(working)}
            }
            if !notice.isEmpty{Text(notice).font(.caption)}
        }.navigationTitle("Duplicate Cleaner")
        .confirmationDialog("Đưa bản trùng đã chọn vào thùng rác? Có thể phục hồi trong 30 ngày.",isPresented:$confirm){
            Button("Chuyển vào thùng rác",role:.destructive){removeSelected()}
        }.onDisappear{scanTask?.cancel()}
    }
    private func scan(){
        working=true;selected=[];notice=""
        let shots=active,v=model.vault
        scanTask?.cancel()
        scanTask=Task{
            let result=await Task.detached(priority:.utility){DuplicateScanner.groups(shots,vault:v)}.value
            guard !Task.isCancelled else{return}
            groups=result;scanned=true;working=false
        }
    }
    private func removeSelected(){
        let ids=selected
        // Recheck that a group always retains at least one live item.
        let safe=Set(groups.flatMap{g in
            let live=g.shots.filter{s in active.contains{$0.id==s.id}}
            return live.contains{!ids.contains($0.id)} ? live.filter{ids.contains($0.id)}.map(\.id):[]
        })
        working=true
        Task{
            var count=0
            for id in safe{do{try await model.vault.edit(id,trash:true);count+=1}catch{}}
            await model.reload();notice="Đã chuyển \(count)/\(ids.count) ảnh vào thùng rác."
            scan()
            notice="Đã chuyển \(count)/\(ids.count) ảnh vào thùng rác."
        }
    }
}
enum VisualTopic:String,CaseIterable {
    case nature="Thiên nhiên",architecture="Kiến trúc",food="Ẩm thực",animals="Động vật",people="Có người",city="Đường phố",water="Biển và nước",other="Khác"
    static func classify(_ labels:[String],faces:Int)->[VisualTopic]{
        let text=labels.joined(separator:" ").lowercased()
        var result=[VisualTopic]()
        let map:[(VisualTopic,[String])]=[
            (.nature,["tree","forest","mountain","flower","landscape","plant","grass","sky"]),
            (.architecture,["architecture","building","house","temple","castle","church","bridge"]),
            (.food,["food","dish","meal","fruit","vegetable","coffee","bread","cake"]),
            (.animals,["animal","dog","cat","bird","fish","horse","insect"]),
            (.city,["street","city","urban","car","vehicle","road"]),
            (.water,["water","sea","ocean","lake","river","beach","waterfall"]),
            (.people,["person","people","human","portrait"])
        ]
        for (topic,words) in map where words.contains(where:{text.contains($0)}){result.append(topic)}
        if faces>0 && !result.contains(.people){result.append(.people)}
        return result.isEmpty ? [.other]:result
    }
}
struct VisualCollections:View{
    let shots:[Shot]
    let vault:Vault
    @State private var groups=[VisualTopic:[Shot]]()
    @State private var rawShots=[Shot]()
    @State private var scanned=false
    @State private var progress=0
    @State private var working=false
    @State private var task:Task<Void,Never>?
    var body:some View{
        List{
            Section{
                Button("Phân loại hình ảnh trên thiết bị"){scan()}.disabled(working)
                if working{ProgressView(value:Double(progress),total:Double(max(1,shots.count)))}
                Text("Nhóm theo nội dung nhìn thấy, không đoán cảm xúc thực tế hay danh tính người trong ảnh.").font(.caption).foregroundStyle(.secondary)
            }
            if scanned{
                Section("Chủ đề tự động"){
                    ForEach(VisualTopic.allCases,id:\.self){topic in
                        if let items=groups[topic],!items.isEmpty{
                            NavigationLink{VisualGallery(title:topic.rawValue,shots:items,vault:vault)}label:{row(topic.rawValue,items:items)}
                        }
                    }
                }
            }
            Section("RAW Gallery"){
                NavigationLink{VisualGallery(title:"RAW Gallery",shots:rawShots,vault:vault)}label:{row("Ảnh RAW / DNG",items:rawShots)}.disabled(rawShots.isEmpty)
                Text("Duyệt ảnh RAW đã lưu được vào Vault; không phải chế độ chụp RAW.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Visual Collections").task{
            let items=shots,v=vault
            rawShots=await Task.detached(priority:.utility){
                items.filter{s in
                    let url=v.picture(s,original:true)
                    if let type=UTType(filenameExtension:url.pathExtension),type.conforms(to:.rawImage){return true}
                    return ["dng","nef","cr2","cr3","arw","raf","rw2","orf"].contains(url.pathExtension.lowercased())
                }
            }.value
        }.onDisappear{task?.cancel()}
    }
    private func row(_ name:String,items:[Shot])->some View{
        HStack{
            if let shot=items.first{DiskImage(url:vault.thumbnail(shot.id),limit:180).scaledToFill().frame(width:58,height:58).clipped().clipShape(RoundedRectangle(cornerRadius:8))}
            Text(name);Spacer();Text("\(items.count)").foregroundStyle(.secondary)
        }
    }
    private func scan(){
        groups=[:];progress=0;working=true;scanned=false
        let items=shots,v=vault
        task?.cancel()
        task=Task{
            for s in items{
                if Task.isCancelled{working=false;return}
                let r=await Task.detached(priority:.utility){SignatureAnalyzer.assess(s,vault:v)}.value
                if let r{for topic in VisualTopic.classify(r.labels,faces:r.faces){groups[topic,default:[]].append(s)}}
                progress+=1
            }
            working=false;scanned=true
        }
    }
}
private struct VisualGallery:View{
    let title:String
    let shots:[Shot]
    let vault:Vault
    @State private var selected:Shot?
    var body:some View{
        ScrollView{
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:3),spacing:4){
                ForEach(shots){s in
                    Button{selected=s}label:{Color.clear.aspectRatio(1,contentMode:.fit).overlay{DiskImage(url:vault.thumbnail(s.id),limit:300).scaledToFill()}.clipped()}.buttonStyle(.plain)
                }
            }.padding(8)
        }.navigationTitle(title)
        .sheet(item:$selected){s in
            NavigationStack{
                VStack{
                    DiskImage(url:vault.picture(s,original:true),limit:2500).scaledToFit().frame(maxHeight:.infinity)
                    Text(s.sourceFile).font(.caption)
                    ShareLink(item:vault.picture(s,original:true)){Label("Chia sẻ bản gốc",systemImage:"square.and.arrow.up")}
                }.padding().navigationTitle(s.day).toolbar{Button("Xong"){selected=nil}}
            }
        }
    }
}
