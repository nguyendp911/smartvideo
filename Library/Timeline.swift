import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private enum Scope:String,CaseIterable {case all="Tất cả",picks="Đã chọn",trash="Thùng rác"}
private enum Scale:String,CaseIterable {case day="Ngày",month="Tháng",year="Năm"}
private enum Transfer {case backup,restore}
struct Timeline:View {
    @ObservedObject var model:LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var search="",session="",scope=Scope.all,scale=Scale.day
    @State private var selection:Shot?,imported=[PhotosPickerItem](),importing=false,working=false
    @State private var pickFolder=false,transfer=Transfer.backup
    @State private var compare=false,chosen=[UUID](),pair=false
    @State private var newest=true
    private var active:[Shot]{model.shots.filter{$0.deleted==nil}}
    private var filtered:[Shot] {
        let items=model.shots.filter { s in
            (scope == .trash ? s.deleted != nil : s.deleted==nil) && (scope != .picks || s.rating>=4)
            && (session.isEmpty || s.session==session)
            && (search.isEmpty || [s.day,s.session,s.tags,s.light.rawValue,s.look.rawValue,s.lens].joined(separator:" ").localizedCaseInsensitiveContains(search))
        }
        return newest ? items:Array(items.reversed())
    }
    private var sections:[(key:String,items:[Shot])] {
        let count=scale == .day ? 10 : (scale == .month ? 7 : 4)
        var groups:[(key:String,items:[Shot])]=[]
        for shot in filtered {
            let key=String(shot.day.prefix(count))
            if groups.last?.key==key {groups[groups.count-1].items.append(shot)} else {groups.append((key,[shot]))}
        }
        return groups
    }
    private var columns:[GridItem] {Array(repeating:GridItem(.flexible(),spacing:3),count:scale == .day ? 3 : (scale == .month ? 4:5))}
    private func dateLabel(_ key:String)->String {
        let p=key.split(separator:"-")
        if p.count==3 {return "\(p[2]) tháng \(Int(p[1]) ?? 1), \(p[0])"}
        if p.count==2 {return "Tháng \(Int(p[1]) ?? 1), \(p[0])"}
        return key
    }
    var body:some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:0) {
                HStack {Text("Timeline").font(.system(size:36,weight:.medium,design:.serif));Spacer()
                    Button {dismiss()} label:{Image(systemName:"camera.fill").frame(width:44,height:44)}.accessibilityLabel("Về máy ảnh")
                }.padding(.horizontal,17)
                HStack {
                    Picker("Khoảng thời gian",selection:$scale){ForEach(Scale.allCases,id:\.self){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented)
                    Menu {
                        Picker("Loại ảnh",selection:$scope){ForEach(Scope.allCases,id:\.self){Text($0.rawValue).tag($0)}}
                        Picker("Phiên chụp",selection:$session){Text("Mọi phiên").tag("");ForEach(Array(Set(active.map(\.session).filter{!$0.isEmpty})).sorted(),id:\.self){Text($0).tag($0)}}
                        Button(newest ? "Cũ nhất trước":"Mới nhất trước"){newest.toggle()}
                    } label:{Image(systemName:scope == .all && session.isEmpty ? "line.3.horizontal.decrease.circle":"line.3.horizontal.decrease.circle.fill").font(.title3).frame(width:40,height:40)}
                    Menu {
                        Button("Nhập ảnh",systemImage:"photo.badge.plus"){importing=true}
                        Button(compare ? "Hủy so sánh":"So sánh hai ảnh",systemImage:"rectangle.split.2x1"){compare.toggle();chosen=[]}
                        Button("Sao lưu vào Tệp",systemImage:"square.and.arrow.up"){transfer = .backup;pickFolder=true}
                        Button("Phục hồi từ thư mục",systemImage:"arrow.counterclockwise"){transfer = .restore;pickFolder=true}
                    } label:{Image(systemName:"ellipsis.circle").font(.title3).frame(width:36,height:40)}
                }.padding(.horizontal,16)
                HStack {
                    Image(systemName:"magnifyingglass");TextField("Tìm ngày, phiên, nhãn, ánh sáng…",text:$search).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !search.isEmpty {Button {search=""} label:{Image(systemName:"xmark.circle.fill")}}
                }.font(.subheadline).foregroundStyle(.secondary).padding(10).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:11)).padding(.horizontal,16).padding(.vertical,5)
                if scope != .all || !session.isEmpty || compare {
                    Text(compare ? "Chọn hai ảnh để đối chiếu · \(chosen.count)/2" : [scope.rawValue,session].filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption).foregroundStyle(gold).padding(.horizontal,18).padding(.vertical,5)
                }
                if working {ProgressView("Đang xử lý…").frame(maxWidth:.infinity).padding(8)}
                if filtered.isEmpty {
                    Spacer()
                    ContentUnavailableView {Label(scope == .trash ? "Thùng rác trống":"Chưa có ảnh ở đây",systemImage:"photo.stack")} description:{Text(search.isEmpty && scope == .all ? "Chụp ảnh hoặc nhập từ Ảnh để bắt đầu dòng thời gian.":"Thử đổi bộ lọc hoặc từ khóa.")} actions:{
                        if scope == .all {Button("Nhập ảnh"){importing=true}.buttonStyle(.bordered)}
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:3,pinnedViews:[.sectionHeaders]){
                            ForEach(sections,id:\.key){group in
                                Section {
                                    LazyVGrid(columns:columns,spacing:3){
                                        ForEach(group.items){shot in
                                            Button {
                                                if compare {
                                                    if let i=chosen.firstIndex(of:shot.id){chosen.remove(at:i)}else{chosen.append(shot.id)}
                                                    if chosen.count==2 {pair=true}
                                                } else {selection=shot}
                                            } label:{
                                                Color.white.opacity(0.04).aspectRatio(1,contentMode:.fit).overlay{DiskImage(url:model.vault.thumbnail(shot.id),limit:400).scaledToFill()}.clipped()
                                                    .overlay(alignment:.bottomTrailing){if shot.rating>=4 {Image(systemName:"star.fill").foregroundStyle(gold).font(.caption).padding(5).shadow(radius:2)}}
                                                    .overlay {if chosen.contains(shot.id){Rectangle().strokeBorder(gold,lineWidth:3)}}
                                            }.buttonStyle(.plain).accessibilityLabel("Ảnh \(shot.day), \(shot.light.rawValue), \(shot.rating) sao")
                                        }
                                    }
                                } header:{HStack{Text(dateLabel(group.key)).font(.headline);Spacer();Text("\(group.items.count)").font(.caption).foregroundStyle(.secondary)}.padding(.horizontal,16).padding(.vertical,9).background(night)}
                            }
                        }
                    }
                }
            }.background(night).toolbar(.hidden,for:.navigationBar)
        }.task{await model.reload()}
        .sheet(item:$selection){shot in ShotDetail(model:model,shot:shot)}
        .sheet(isPresented:$pair,onDismiss:{chosen=[];compare=false}){
            CompareView(shots:chosen.compactMap{id in model.shots.first{$0.id==id}},vault:model.vault)
        }
        .photosPicker(isPresented:$importing,selection:$imported,maxSelectionCount:20,matching:.images)
        .onChange(of:imported){_,items in
            guard !items.isEmpty else{return}
            Task {
                working=true;defer{working=false;imported=[]}
                var failures=0
                for item in items {
                    do {guard let data=try await item.loadTransferable(type:Data.self) else {throw CameraError.unreadable}
                        _=try await model.vault.add(data,look:.neutral,session:session,time:Date(),lens:"Ảnh nhập")
                    } catch {failures+=1}
                }
                await model.reload()
                if failures>0 {model.message="Có \(failures) ảnh không nhập được."}
            }
        }
        .fileImporter(isPresented:$pickFolder,allowedContentTypes:[.folder]) {result in
            guard case .success(let url)=result else{return}
            let action=transfer
            Task {
                let access=url.startAccessingSecurityScopedResource();defer{if access {url.stopAccessingSecurityScopedResource()}}
                working=true;defer{working=false}
                do {switch action {
                case .backup: let n=try await model.vault.backup(to:url);model.message="Đã sao lưu \(n) ảnh."
                case .restore: let (n,s)=try await model.vault.restore(from:url);model.message="Đã phục hồi \(n) ảnh, bỏ qua \(s) mục đã có."
                }} catch {model.message=error.localizedDescription}
                await model.reload()
            }
        }
        .alert("VieLens",isPresented:Binding(get:{model.message != nil && selection==nil},set:{if !$0 {model.message=nil}})){Button("Đóng"){model.message=nil}} message:{Text(model.message ?? "")}
    }
}
private struct CompareView:View {
    let shots:[Shot];let vault:Vault
    @State private var zoom=false
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack { VStack(spacing:8) {
            ForEach(shots){s in GeometryReader{g in DiskImage(url:vault.picture(s)).scaledToFit().scaleEffect(zoom ? 2:1).frame(width:g.size.width,height:g.size.height).clipped()}}
            Button(zoom ? "Xem toàn ảnh":"Soi giữa hai ảnh 2×"){zoom.toggle()}.padding()
        }.navigationTitle("Đối chiếu").navigationBarTitleDisplayMode(.inline).toolbar{Button("Xong"){dismiss()}} }
    }
}
private struct ShotDetail:View {
    @ObservedObject var model:LibraryModel
    let shot:Shot
    @Environment(\.dismiss) private var dismiss
    @State private var original=false,tags="",session="",editing=false,confirm=false
    @State private var notice:String?
    var current:Shot {model.shots.first{$0.id==shot.id} ?? shot}
    var body:some View {
        NavigationStack {
            VStack(spacing:12) {
                if current.enhanced {Picker("Phiên bản",selection:$original){Text("Ảnh hoàn thiện").tag(false);Text("Bản gốc").tag(true)}.pickerStyle(.segmented).padding(.horizontal)}
                DiskImage(url:model.vault.picture(current,original:original),limit:2200).scaledToFit().frame(maxHeight:.infinity)
                VStack(spacing:6){
                    Text([current.light.rawValue,current.look.rawValue,current.lens].filter{!$0.isEmpty}.joined(separator:" · ")).font(.subheadline)
                    if !current.session.isEmpty || !current.tags.isEmpty {Text([current.session,current.tags].filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)}
                    HStack(spacing:2){ForEach(1...5,id:\.self){n in Button {Task{await model.edit(shot.id,rating:current.rating==n ? 0 : n)}} label:{Image(systemName:n<=current.rating ? "star.fill":"star").foregroundStyle(gold).frame(width:35,height:40)}.accessibilityLabel("\(n) sao")}}
                }
                HStack(spacing:28) {
                    ShareLink(item:model.vault.picture(current,original:original)){Image(systemName:"square.and.arrow.up")}.accessibilityLabel("Chia sẻ ảnh")
                    Button {saveToPhotos()} label:{Image(systemName:"square.and.arrow.down")}.accessibilityLabel("Lưu vào Ảnh Apple")
                    Button {tags=current.tags;session=current.session;editing=true} label:{Image(systemName:"tag")}.accessibilityLabel("Đổi nhãn và phiên")
                    Button {if current.deleted != nil {Task{await model.edit(shot.id,trash:false);dismiss()}} else {confirm=true}} label:{Image(systemName:current.deleted==nil ? "trash":"arrow.uturn.backward")}.accessibilityLabel(current.deleted==nil ? "Chuyển vào thùng rác":"Phục hồi")
                }.font(.title3).padding(.bottom,18)
            }.navigationTitle(shot.day).navigationBarTitleDisplayMode(.inline).toolbar{Button("Xong"){dismiss()}}
        }.sheet(isPresented:$editing){NavigationStack{Form{TextField("Phiên chụp",text:$session);TextField("Nhãn ảnh",text:$tags)}.navigationTitle("Thông tin ảnh").toolbar{Button("Lưu"){Task{await model.edit(shot.id,tags:tags,session:session);editing=false}}}}.presentationDetents([.medium])}
        .confirmationDialog("Chuyển ảnh vào thùng rác trong 30 ngày?",isPresented:$confirm){Button("Chuyển vào thùng rác",role:.destructive){Task{await model.edit(shot.id,trash:true);dismiss()}}}
        .alert("VieLens",isPresented:Binding(get:{notice != nil || model.message != nil},set:{if !$0{notice=nil;model.message=nil}})){Button("Đóng"){notice=nil;model.message=nil}} message:{Text(notice ?? model.message ?? "")}
    }
    private func saveToPhotos() {
        let url=model.vault.picture(current,original:original),date=shot.date
        Task{
            let auth=await PHPhotoLibrary.requestAuthorization(for:.addOnly)
            guard auth == .authorized || auth == .limited else {notice="Hãy bật quyền thêm ảnh trong Cài đặt.";return}
            do {try await PHPhotoLibrary.shared().performChanges {
                let request=PHAssetCreationRequest.forAsset();request.creationDate=date
                request.addResource(with:.photo,fileURL:url,options:nil)
            };notice="Đã lưu vào Ảnh Apple."} catch {notice=error.localizedDescription}
        }
    }
}
