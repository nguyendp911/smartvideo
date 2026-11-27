import SwiftUI
import PhotosUI
import AVFoundation

let gold=Color(red:0.93,green:0.73,blue:0.43)
let night=Color(red:0.065,green:0.075,blue:0.079)
@main struct VieLensApp:App {
    var body: some Scene { WindowGroup { CameraHome().preferredColorScheme(.dark).tint(gold) } }
}
@MainActor final class LibraryModel:ObservableObject {
    @Published var shots=[Shot]()
    @Published var message:String?
    @Published var processing=false
    let vault:Vault
    init(_ vault:Vault = .shared) {self.vault=vault}
    func reload() async { do { shots=try await vault.all() } catch { message=error.localizedDescription } }
    func store(_ data:Data, look:Look, session:String, time:Date, lens:String) async {
        processing=true;defer{processing=false}
        do {
            let added=try await vault.add(data,look:look,session:session,time:time,lens:lens)
            await reload()
            if !added.enhanced {message="Đã giữ ảnh gốc. iPhone chưa thể hoàn tất xử lý màu."}
        } catch {message=error.localizedDescription}
    }
    func edit(_ id:UUID,rating:Int?=nil,tags:String?=nil,session:String?=nil,trash:Bool?=nil) async {
        do {try await vault.edit(id,rating:rating,tags:tags,session:session,trash:trash);await reload()} catch {message=error.localizedDescription}
    }
}
struct DiskImage:View {
    let url:URL
    var limit=1200
    @State private var picture:UIImage?
    var body:some View {
        Group {
            if let picture {Image(uiImage:picture).resizable()}
            else {Rectangle().fill(.white.opacity(0.08)).overlay(Image(systemName:"photo").foregroundStyle(.secondary))}
        }
        .task(id:url) {
            picture=nil
            let path=url, size=limit
            let img=await Task.detached(priority:.utility) { ()->UIImage? in
                guard let bytes=try? Data(contentsOf:path,options:.mappedIfSafe),let cg=PhotoEngine.thumb(bytes,limit:size) else{return nil}
                return UIImage(cgImage:cg)
            }.value
            if !Task.isCancelled {picture=img}
        }
    }
}
struct CameraHome:View {
    @StateObject private var camera=Camera()
    @StateObject private var model=LibraryModel()
    @Environment(\.scenePhase) private var phase
    @AppStorage("look") private var lookValue=Look.neutral.rawValue
    @AppStorage("session") private var session=""
    @State private var showTimeline=false, options=false,flash=false,grid=false,shooting=false
    @State private var draft="", blink=false
    @State private var facing=UIDeviceOrientation.portrait
    var look:Look {Look(rawValue:lookValue) ?? .neutral}
    var body:some View {
        GeometryReader { geo in
            VStack(spacing:0) {
                HStack {
                    VStack(alignment:.leading,spacing:3) {
                        Text("VieLens").font(.system(size:30,weight:.medium,design:.serif))
                        Text(session.isEmpty ? "MÁY ẢNH" : session.uppercased()).font(.caption2.weight(.semibold)).tracking(1.6).foregroundStyle(gold).lineLimit(1)
                    }
                    Spacer()
                    Button {flash.toggle()} label:{Image(systemName:flash ? "bolt.badge.automatic.fill":"bolt.slash").frame(width:42,height:44)}.accessibilityLabel(flash ? "Tắt flash tự động":"Bật flash tự động")
                    Button {draft=session;options=true} label:{Image(systemName:"slider.horizontal.3").frame(width:42,height:44)}.accessibilityLabel("Cấu hình chụp")
                }.padding(.horizontal,18).padding(.vertical,9)
                Spacer(minLength:3)
                ZStack {
                    CameraPreview(camera:camera)
                    if grid {
                        Canvas {ctx,size in
                            var p=Path()
                            for i in 1...2 {
                                let f=CGFloat(i)/3
                                p.move(to:CGPoint(x:f*size.width,y:0));p.addLine(to:CGPoint(x:f*size.width,y:size.height))
                                p.move(to:CGPoint(x:0,y:f*size.height));p.addLine(to:CGPoint(x:size.width,y:f*size.height))
                            }
                            ctx.stroke(p,with:.color(.white.opacity(0.34)),lineWidth:0.6)
                        }.allowsHitTesting(false)
                    }
                    if let issue=camera.issue {
                        VStack(spacing:14) {
                            Image(systemName:"camera.aperture").font(.largeTitle).foregroundStyle(gold)
                            Text(issue).font(.callout).multilineTextAlignment(.center)
                            if AVCaptureDevice.authorizationStatus(for:.video) == .denied {
                                Link("Mở Cài đặt",destination:URL(string:UIApplication.openSettingsURLString)!)
                            }
                            Button("Mở Timeline"){showTimeline=true}.buttonStyle(.bordered)
                        }.padding(28).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:18))
                    }
                    if blink {Color.white.opacity(0.67).allowsHitTesting(false)}
                }.frame(width:min(geo.size.width,max(1,(geo.size.height-203)*0.75)),height:min(geo.size.width*4/3,max(1,geo.size.height-203))).clipped()
                Spacer(minLength:0)
                HStack(spacing:12) {
                    ForEach(camera.lenses) {lens in
                        Button(lens.title){camera.change(to:lens.id)}
                            .font(.subheadline.bold()).foregroundStyle(lens.id==camera.selected ? .black:.white)
                            .padding(.horizontal,12).frame(minHeight:32).background(lens.id==camera.selected ? gold:Color.white.opacity(0.12),in:Capsule())
                    }
                }.frame(height:40)
                HStack {
                    Button {showTimeline=true} label:{
                        if let shot=model.shots.first(where:{$0.deleted==nil}) {
                            DiskImage(url:model.vault.thumbnail(shot.id),limit:150).scaledToFill().frame(width:52,height:52).clipShape(RoundedRectangle(cornerRadius:13))
                        } else {Image(systemName:"rectangle.stack").frame(width:52,height:52).background(.white.opacity(0.09),in:RoundedRectangle(cornerRadius:13))}
                    }.accessibilityLabel("Mở Timeline")
                    Spacer()
                    Button(action:take) {
                        ZStack {Circle().stroke(gold,lineWidth:2).frame(width:78,height:78)
                            Circle().fill(shooting || model.processing ? Color.gray : .white).frame(width:64,height:64)
                            if model.processing || shooting {ProgressView().tint(.black)}
                        }
                    }.disabled(!camera.ready || shooting || model.processing).accessibilityLabel("Chụp ảnh")
                    Spacer()
                    Button {camera.change()} label:{Image(systemName:"camera.rotate").font(.title2).frame(width:52,height:52)}.accessibilityLabel("Đổi camera trước hoặc sau")
                }.padding(.horizontal,30).padding(.vertical,7)
                Text(look.rawValue).font(.caption.weight(.medium)).foregroundStyle(gold).padding(.bottom,7)
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(night)
        }.task {UIDevice.current.beginGeneratingDeviceOrientationNotifications();await model.reload();if !showTimeline {camera.start()}}
        .onReceive(NotificationCenter.default.publisher(for:UIDevice.orientationDidChangeNotification)){ _ in
            let o=UIDevice.current.orientation;if o.isLandscape || o.isPortrait {facing=o}
        }
        .onChange(of:phase) { _,p in if p == .active && !showTimeline {camera.start()} else {camera.stop()} }
        .onChange(of:showTimeline){_,shown in if shown {camera.stop()} else if phase == .active {camera.start()} }
        .fullScreenCover(isPresented:$showTimeline){Timeline(model:model)}
        .sheet(isPresented:$options){
            NavigationStack {Form {
                Section("Màu khi chụp"){Picker("Chất ảnh",selection:$lookValue){ForEach(Look.allCases){Text($0.rawValue).tag($0.rawValue)}}.pickerStyle(.segmented)}
                Section("Khung ngắm"){Toggle("Lưới một phần ba",isOn:$grid);Toggle("Flash tự động",isOn:$flash)}
                Section("Lưu ảnh vào phiên"){TextField("Tên phiên chụp",text:$draft)
                    if !session.isEmpty {Button("Kết thúc phiên"){session="";draft="";options=false}}
                }
            }.navigationTitle("Tùy chọn chụp").toolbar{Button("Xong"){session=String(draft.trimmingCharacters(in:.whitespacesAndNewlines).prefix(100));options=false}}}
            .presentationDetents([.medium,.large])
        }
        .alert("VieLens",isPresented:Binding(get:{model.message != nil && !showTimeline},set:{if !$0 {model.message=nil}})){Button("Đóng"){model.message=nil}} message:{Text(model.message ?? "")}
    }
    private func take() {
        guard !shooting && !model.processing else{return}
        let chosen=look, group=session, now=Date(),lens=camera.front ? "Trước" : (camera.lenses.first{$0.id==camera.selected}?.title ?? "")
        shooting=true;blink=true;UIImpactFeedbackGenerator(style:.light).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline:.now()+0.09){blink=false}
        camera.capture(flash:flash,orientation:facing){result in
            switch result {
            case .success(let data): Task {await model.store(data,look:chosen,session:group,time:now,lens:lens);shooting=false}
            case .failure(let error): shooting=false;model.message=error.localizedDescription
            }
        }
    }
}
