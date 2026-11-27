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
private final class PhotoMemoryCache {
    static let shared=PhotoMemoryCache()
    let images=NSCache<NSString,UIImage>()
    private init(){images.totalCostLimit=48*1024*1024;images.countLimit=160}
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
        .task(id:"\(url.path)#\(limit)") {
            picture=nil
            let path=url, size=limit
            let img=await Task.detached(priority:.utility) { ()->UIImage? in
                let stamp=(try? path.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
                let key="\(path.path)#\(size)#\(stamp)" as NSString
                let cache=PhotoMemoryCache.shared.images
                if let hit=cache.object(forKey:key){return hit}
                guard let bytes=try? Data(contentsOf:path,options:.mappedIfSafe),let cg=PhotoEngine.thumb(bytes,limit:size) else{return nil}
                let image=UIImage(cgImage:cg)
                cache.setObject(image,forKey:key,cost:cg.bytesPerRow*cg.height)
                return image
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
    @State private var showTimeline=false
    @State private var showToday=false
    @State private var pendingTimeline=false
    @State private var timelineDay:String?
    @State private var options=false
    @State private var flash=FlashChoice.off
    @AppStorage("camera.quality") private var qualityValue=CaptureQuality.smart.rawValue
    @AppStorage("camera.timer") private var timer=0
    @AppStorage("camera.sequence") private var burst=1
    @AppStorage("camera.histogram") private var showHistogram=false
    @AppStorage("camera.center") private var centerGuide=false
    @State private var showPro=false
    @State private var countdown=0
    @State private var sequence:Task<Void,Never>?
    @State private var progress=""
    @State private var manualISO=100.0
    @State private var shutter=1.0/125
    @State private var grid=false
    @State private var shooting=false
    @State private var draft=""
    @State private var blink=false
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
                    Button{showToday=true}label:{Image(systemName:"sun.max").frame(width:36,height:44)}.accessibilityLabel("Hôm nay của tôi").disabled(shooting)
                    Menu {ForEach(FlashChoice.allCases,id:\.self){choice in Button(choice.rawValue,systemImage:choice.icon){flash=choice}}} label:{Image(systemName:flash.icon).frame(width:42,height:44)}.accessibilityLabel("Flash").disabled(!camera.controls.hasFlash || shooting)
                    Button {showPro=true} label:{Image(systemName:"dial.medium").frame(width:40,height:44)}.accessibilityLabel("Camera Pro").disabled(shooting)
                    Button {draft=session;options=true} label:{Image(systemName:"slider.horizontal.3").frame(width:42,height:44)}.accessibilityLabel("Cấu hình chụp").disabled(shooting)
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
                    if centerGuide {Image(systemName:"plus").font(.system(size:24,weight:.ultraLight)).foregroundStyle(.white.opacity(0.7)).allowsHitTesting(false)}
                    if showHistogram {
                        VStack{HStack{CameraHistogram(values:camera.histogram).frame(width:105,height:48);Spacer()};Spacer()}.padding(10).allowsHitTesting(false)
                    }
                    VStack{Spacer();HStack{
                        if camera.controls.locked {Label("AE/AF LOCK",systemImage:"lock.fill")}
                        if camera.controls.manual {Text("M")}
                        Text(String(format:"%+.1f EV",camera.controls.ev))
                        Spacer()
                        Text("ISO \(Int(camera.controls.iso))")
                    }.font(.caption2.monospacedDigit()).padding(8).background(.black.opacity(0.45))}.allowsHitTesting(false)
                    if countdown>0 {Text("\(countdown)").font(.system(size:88,weight:.thin,design:.rounded)).shadow(radius:8).allowsHitTesting(false)}
                    if blink {Color.white.opacity(0.67).allowsHitTesting(false)}
                }.frame(width:min(geo.size.width,max(1,(geo.size.height-203)*0.75)),height:min(geo.size.width*4/3,max(1,geo.size.height-203))).clipped()
                Spacer(minLength:0)
                HStack(spacing:12) {
                    ForEach(camera.lenses) {lens in
                        Button(lens.title){camera.change(to:lens.id)}.disabled(shooting)
                            .font(.subheadline.bold()).foregroundStyle(lens.id==camera.selected ? .black:.white)
                            .padding(.horizontal,12).frame(minHeight:32).background(lens.id==camera.selected ? gold:Color.white.opacity(0.12),in:Capsule())
                    }
                }.frame(height:40)
                HStack {
                    Button {showTimeline=true} label:{
                        if let shot=model.shots.first(where:{$0.deleted==nil}) {
                            DiskImage(url:model.vault.thumbnail(shot.id),limit:150).scaledToFill().frame(width:52,height:52).clipShape(RoundedRectangle(cornerRadius:13))
                        } else {Image(systemName:"rectangle.stack").frame(width:52,height:52).background(.white.opacity(0.09),in:RoundedRectangle(cornerRadius:13))}
                    }.accessibilityLabel("Mở Timeline").disabled(shooting)
                    Spacer()
                    Button(action:take) {
                        ZStack {Circle().stroke(gold,lineWidth:2).frame(width:78,height:78)
                            Circle().fill(shooting || model.processing ? Color.gray : .white).frame(width:64,height:64)
                            if model.processing || shooting {ProgressView().tint(.black)}
                        }
                    }.disabled(!shooting && (!camera.ready || model.processing)).accessibilityLabel(shooting ? "Dừng chuỗi chụp" : "Chụp ảnh")
                    Spacer()
                    Button {camera.change()} label:{Image(systemName:"camera.rotate").font(.title2).frame(width:52,height:52)}.accessibilityLabel("Đổi camera trước hoặc sau").disabled(shooting)
                }.padding(.horizontal,30).padding(.vertical,7)
                HStack(spacing:14){
                    Menu{ForEach(Look.allCases){item in Button(item.rawValue){lookValue=item.rawValue}}} label:{Label(look.rawValue,systemImage:"camera.filters")}
                    Menu{ForEach([0,3,5,10],id:\.self){t in Button(t==0 ? "Tắt hẹn giờ":"\(t)s"){timer=t}}} label:{Label(timer==0 ? "Tắt":"\(timer)s",systemImage:"timer")}
                    Menu{ForEach([1,3,5,10],id:\.self){n in Button("\(n) ảnh"){burst=n}}} label:{Label(burst==1 ? "Đơn":"\(burst) ảnh",systemImage:"square.stack")}
                }.font(.caption.weight(.medium)).foregroundStyle(gold).padding(.bottom,5).disabled(shooting)
                if !progress.isEmpty {Text(progress).font(.caption2).foregroundStyle(.secondary)}

            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(night)
        }.task {UIDevice.current.beginGeneratingDeviceOrientationNotifications();await model.reload();if !showTimeline && !showToday {camera.start()}}
        .onReceive(NotificationCenter.default.publisher(for:UIDevice.orientationDidChangeNotification)){ _ in
            let o=UIDevice.current.orientation;if o.isLandscape || o.isPortrait {facing=o}
        }
        .task(id:phase){
            guard phase == .active else{return}
            while !Task.isCancelled{
                try? LifeArchive.shared.recordGardenUse()
                do{try await Task.sleep(for:.seconds(60))}catch{return}
            }
        }
        .onChange(of:phase) { _,p in if p == .active && !showTimeline && !showToday {camera.start()} else {sequence?.cancel();camera.stop()} }
        .onChange(of:showTimeline){_,shown in if shown {camera.stop()} else if phase == .active && !showToday {camera.start()} }
        .onChange(of:showToday){_,shown in if shown{camera.stop()}else if phase == .active && !showTimeline{camera.start()}}
        .fullScreenCover(isPresented:$showToday,onDismiss:{if pendingTimeline{pendingTimeline=false;showTimeline=true}}){LifeToday(model:model,camera:{showToday=false},timeline:{day in timelineDay=day;pendingTimeline=true;showToday=false})}
        .fullScreenCover(isPresented:$showTimeline,onDismiss:{timelineDay=nil}){Timeline(model:model,initialDay:timelineDay)}
        .sheet(isPresented:$showPro){
            NavigationStack{
                Form{
                    Section("Zoom"){
                        if camera.controls.maxZoom>1{
                            Slider(value:Binding(get:{camera.controls.zoom},set:{camera.zoom($0)}),in:1...camera.controls.maxZoom)
                            Text(String(format:"%.2f×",camera.controls.zoom)).monospacedDigit()
                        }
                    }
                    Section("Phơi sáng"){
                        if camera.controls.maxEV>camera.controls.minEV && !camera.controls.manual{
                            Slider(value:Binding(get:{camera.controls.ev},set:{camera.exposureBias($0)}),in:camera.controls.minEV...camera.controls.maxEV)
                            Button("EV về 0"){camera.exposureBias(0)}
                        }
                        if camera.controls.canLock {Toggle("Khóa AE/AF",isOn:Binding(get:{camera.controls.locked},set:{camera.lockExposure($0)}))}
                        if camera.controls.canManual {
                            Text("ISO \(Int(manualISO)) · \(String(format:"%.4f",shutter)) s").monospacedDigit()
                            if camera.controls.maxISO>camera.controls.minISO {Slider(value:$manualISO,in:Double(camera.controls.minISO)...Double(camera.controls.maxISO))}
                            if camera.controls.maxExposure>camera.controls.minExposure && camera.controls.minExposure>0 {
                                Slider(value:Binding(get:{log(max(camera.controls.minExposure,min(camera.controls.maxExposure,shutter)))},set:{shutter=exp($0)}),in:log(camera.controls.minExposure)...log(camera.controls.maxExposure))
                            }
                            Button("Áp dụng ISO / màn trập"){camera.manualExposure(iso:manualISO,seconds:shutter)}
                            Button("Trở về tự động"){camera.lockExposure(false)}
                        }
                    }
                    Section("Khung ngắm"){
                        Toggle("Histogram trực tiếp",isOn:$showHistogram)
                        Toggle("Dấu tâm",isOn:$centerGuide)
                        Toggle("Lưới một phần ba",isOn:$grid)
                    }
                    Section("Ưu tiên chụp"){Picker("Chất lượng",selection:$qualityValue){ForEach(CaptureQuality.allCases,id:\.self){Text($0.rawValue).tag($0.rawValue)}}}
                }.navigationTitle("Camera Pro").navigationBarTitleDisplayMode(.inline).toolbar{Button("Xong"){showPro=false}}
                .onAppear{manualISO=max(camera.controls.minISO,min(camera.controls.maxISO,camera.controls.iso));shutter=max(camera.controls.minExposure,min(camera.controls.maxExposure,camera.controls.exposure))}
            }.presentationDetents([.large])
        }
        .sheet(isPresented:$options){
            NavigationStack {Form {
                Section("Màu khi chụp"){Picker("Chất ảnh",selection:$lookValue){ForEach(Look.allCases){Text($0.rawValue).tag($0.rawValue)}}}
                Section("Khung ngắm"){Toggle("Lưới một phần ba",isOn:$grid);Toggle("Histogram",isOn:$showHistogram);Toggle("Dấu tâm",isOn:$centerGuide)}
                Section("Lưu ảnh vào phiên"){TextField("Tên phiên chụp",text:$draft)
                    if !session.isEmpty {Button("Kết thúc phiên"){session="";draft="";options=false}}
                }
            }.navigationTitle("Tùy chọn chụp").toolbar{Button("Xong"){session=String(draft.trimmingCharacters(in:.whitespacesAndNewlines).prefix(100));options=false}}}
            .presentationDetents([.medium,.large])
        }
        .alert("VieLens",isPresented:Binding(get:{model.message != nil && !showTimeline},set:{if !$0 {model.message=nil}})){Button("Đóng"){model.message=nil}} message:{Text(model.message ?? "")}
    }
    private func take(){
        if shooting {sequence?.cancel();return}
        guard camera.ready,!model.processing else{return}
        let chosen=look,group=session,lens=camera.front ? "Trước" : (camera.lenses.first{$0.id==camera.selected}?.title ?? "")
        let flashMode=flash,quality=CaptureQuality(rawValue:qualityValue) ?? .smart,orientation=facing,total=max(1,min(10,burst)),delay=timer
        shooting=true
        sequence=Task{@MainActor in
            defer{shooting=false;countdown=0;progress="";sequence=nil}
            do{
                if delay>0 {
                    for tick in stride(from:delay,through:1,by:-1){countdown=tick;try await Task.sleep(for:.seconds(1))}
                    countdown=0
                }
                for i in 0..<total{
                    try Task.checkCancellation()
                    guard camera.ready,phase == .active else{break}
                    progress=total>1 ? "Ảnh \(i+1)/\(total)" : ""
                    let now=Date()
                    blink=true;UIImpactFeedbackGenerator(style:.light).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.09){blink=false}
                    let result:Result<Data,Error>=await withCheckedContinuation{continuation in
                        camera.capture(flash:flashMode,quality:quality,orientation:orientation){continuation.resume(returning:$0)}
                    }
                    switch result{
                    case .success(let bytes):await model.store(bytes,look:chosen,session:group,time:now,lens:lens)
                    case .failure(let error):model.message=error.localizedDescription;return
                    }
                    if model.message != nil{return}
                    if i+1<total {try await Task.sleep(for:.milliseconds(180))}
                }
            }catch is CancellationError{}catch{model.message=error.localizedDescription}
        }
    }
}
private struct CameraHistogram:View{
    let values:[Double]
    var body:some View{
        Canvas{ctx,size in
            let w=size.width/CGFloat(max(1,values.count))
            for (i,value) in values.enumerated(){
                let h=size.height*CGFloat(value)
                ctx.fill(Path(CGRect(x:CGFloat(i)*w,y:size.height-h,width:max(1,w-1),height:h)),with:.color(.white.opacity(0.85)))
            }
        }.padding(5).background(.black.opacity(0.65),in:RoundedRectangle(cornerRadius:6)).accessibilityLabel("Histogram độ sáng")
    }
}
