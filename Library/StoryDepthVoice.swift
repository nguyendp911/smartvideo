import SwiftUI
import AVFoundation
import Speech
import UIKit

struct SpokenWord:Identifiable,Equatable{
    let id:Int;let text:String;let start:Double;let duration:Double
}
@MainActor final class VoiceHighlightModel:ObservableObject{
    @Published var words:[SpokenWord]=[]
    @Published var current:Int?
    @Published var status=""
    @Published var playing=false
    @Published var working=false
    private var player:AVAudioPlayer?
    private var recognition:SFSpeechRecognitionTask?
    private var temporary:URL?
    private var playback:Task<Void,Never>?
    private var generation=UUID()
    func recognize(_ audio:Data,locale:String){
        stop();recognition?.cancel();cleanup();words=[];current=nil;working=true
        let token=UUID();generation=token
        status="Kiểm tra nhận dạng offline…"
        SFSpeechRecognizer.requestAuthorization{[weak self] auth in
            Task{@MainActor in
                guard let self,self.generation==token else{return}
                guard auth == .authorized else{self.status="Chưa được cấp quyền nhận dạng giọng nói.";self.working=false;return}
                guard let recognizer=SFSpeechRecognizer(locale:Locale(identifier:locale)),recognizer.supportsOnDeviceRecognition,recognizer.isAvailable else{self.status="Thiết bị/ngôn ngữ chưa hỗ trợ nhận dạng offline. Không gửi audio lên máy chủ.";self.working=false;return}
                do{
                    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".m4a")
                    try audio.write(to:url,options:[.atomic,.completeFileProtection]);self.temporary=url
                    let request=SFSpeechURLRecognitionRequest(url:url);request.requiresOnDeviceRecognition=true;request.shouldReportPartialResults=false
                    self.recognition=recognizer.recognitionTask(with:request){[weak self] result,error in
                        Task{@MainActor in
                            guard let self,self.generation==token else{return}
                            if let result,result.isFinal{
                                self.words=result.bestTranscription.segments.enumerated().map{SpokenWord(id:$0.offset,text:$0.element.substring,start:$0.element.timestamp,duration:$0.element.duration)}
                                self.status="Bản chép lời tự động; có thể sai từ hoặc dấu.";self.working=false;self.cleanup()
                            }else if let error{self.status=error.localizedDescription;self.working=false;self.cleanup()}
                        }
                    }
                }catch{self.status=error.localizedDescription;self.working=false;self.cleanup()}
            }
        }
    }
    func toggle(_ audio:Data){
        if playing{stop();return}
        do{
            let session=AVAudioSession.sharedInstance();try session.setCategory(.playback,mode:.default,options:[.mixWithOthers]);try session.setActive(true)
            let p=try AVAudioPlayer(data:audio);player=p
            guard p.play() else{throw CameraError.unreadable}
            playing=true
            playback=Task{[weak self] in
                while !Task.isCancelled{
                    guard let self,self.playing,let player=self.player,player.isPlaying else{break}
                    let t=player.currentTime
                    self.current=self.words.last(where:{$0.start<=t && t<$0.start+max(0.15,$0.duration)+0.14})?.id
                    do{try await Task.sleep(for:.milliseconds(50))}catch{return}
                }
                self?.stop()
            }
        }catch{status=error.localizedDescription;stop()}
    }
    func stop(){playback?.cancel();playback=nil;player?.stop();player=nil;playing=false;current=nil}
    private func cleanup(){if let temporary{try? FileManager.default.removeItem(at:temporary)};temporary=nil}
    func close(){generation=UUID();recognition?.cancel();recognition=nil;cleanup();stop();working=false;words=[];status=""}
}
struct VoiceHighlightView:View{
    let audio:Data
    @StateObject private var model=VoiceHighlightModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var locale="vi-VN"
    private var transcript:Text{
        model.words.reduce(Text("")){text,word in text+Text(word.text+" ").foregroundColor(model.current==word.id ? gold:.primary).bold(model.current==word.id)}
    }
    var body:some View{
        NavigationStack{ScrollView{VStack(alignment:.leading,spacing:15){
            Text("Voice Highlight").font(.system(.largeTitle,design:.serif))
            Text("Nhận dạng lời kể trên thiết bị khi iOS hỗ trợ, rồi tô sáng theo timestamp của bản chép lời, không giả lập đồng bộ từng từ từ nội dung story.").font(.caption).foregroundStyle(.secondary)
            Picker("Ngôn ngữ",selection:$locale){Text("Tiếng Việt").tag("vi-VN");Text("English").tag("en-US")}
            Button("Nhận dạng lời kể offline"){model.recognize(audio,locale:locale)}.disabled(model.working)
            if model.working{ProgressView()}
            Button(model.playing ? "Dừng":"Nghe lời kể",systemImage:model.playing ? "stop.fill":"play.fill"){model.toggle(audio)}.buttonStyle(.borderedProminent)
            transcript.font(.system(.title3,design:.serif)).lineSpacing(8)
            Text(model.status).font(.caption)
        }.padding()}.navigationTitle("Lời kể đồng bộ").toolbar{Button("Đóng"){dismiss()}}}
        .onChange(of:phase){_,p in if p == .background{model.close()}}.onDisappear{model.close()}
    }
}
struct PhotoParallaxView:View{
    let shot:Shot;let vault:Vault
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var cutout:UIImage?
    @State private var loading=false
    @State private var movement=CGSize.zero
    @State private var notice=""
    var body:some View{
        NavigationStack{ScrollView{VStack(spacing:16){
            GeometryReader{g in
                ZStack{
                    DiskImage(url:vault.picture(shot),limit:1000).scaledToFill().frame(width:g.size.width,height:g.size.height).blur(radius:cutout == nil ? 0:12).scaleEffect(1.12).offset(x:-movement.width*0.25,y:-movement.height*0.25)
                    if let cutout{Image(uiImage:cutout).resizable().scaledToFit().frame(width:g.size.width,height:g.size.height).offset(x:movement.width*0.65,y:movement.height*0.65)}
                }.clipped().gesture(DragGesture().onChanged{v in if !reduced{movement=CGSize(width:max(-22,min(22,v.translation.width*0.18)),height:max(-22,min(22,v.translation.height*0.18)))}}.onEnded{_ in withAnimation(reduced ? nil:.spring(response:0.6,dampingFraction:0.8)){movement = .zero}})
            }.frame(height:420).clipShape(RoundedRectangle(cornerRadius:16))
            Button("Tách chủ thể & tạo chiều sâu"){loading=true;let url=vault.picture(shot);Task{let data=await Task.detached(priority:.userInitiated){StorySubjectCutout.make(url:url)}.value;cutout=data.flatMap{UIImage(data:$0)};notice=cutout==nil ? "Không nhận diện được chủ thể.":"Kéo ảnh nhẹ để xem hai lớp chuyển động.";loading=false}}.disabled(loading)
            if loading{ProgressView()}
            Text(notice).font(.caption)
            Text("Xem trước 2 lớp ảnh; nền được làm mờ, không phục dựng phần bị che. Chưa xuất parallax tách chủ thể thành MP4.").font(.caption).foregroundStyle(.secondary)
        }.padding()}.navigationTitle("Photo Parallax").toolbar{Button("Đóng"){dismiss()}}}
    }
}
