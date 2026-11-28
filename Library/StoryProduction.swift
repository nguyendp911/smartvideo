import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit
import Vision
import CoreImage
#if canImport(FoundationModels)
import FoundationModels
#endif

enum StoryWritingAssistant{
    @MainActor static func write(facts:String,mood:String)async throws->String{
        #if canImport(FoundationModels)
        if #available(iOS 26.0,*),SystemLanguageModel.default.isAvailable{
            let session=LanguageModelSession(instructions:"Write a short natural Vietnamese personal memory story, using only the user's provided facts. Do not invent events, places, people or dialogue. Return only the draft.")
            let reply=try await session.respond(to:"Cảm xúc: \(mood)\nDữ kiện: \(facts)\nViết 3–5 câu tiếng Việt.")
            return reply.content
        }
        #endif
        throw NSError(domain:"VieLens.StoryWriter",code:1,userInfo:[NSLocalizedDescriptionKey:"Apple Intelligence không khả dụng trên thiết bị hoặc ngôn ngữ hiện tại. Hãy dùng mẫu viết offline."])
    }
    static func template(facts:String,mood:String)->String{
        let prefix=mood.isEmpty ? "Một khoảnh khắc mình muốn giữ lại.":"Một khoảnh khắc mang theo cảm xúc \(mood.lowercased())."
        return prefix+"\n\n"+facts+"\n\nMong rằng khi nhìn lại, mình vẫn còn nhớ những điều này."
    }
}
struct StoryWriterSheet:View{
    let mood:String
    let apply:(String)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var facts=""
    @State private var draft=""
    @State private var busy=false
    @State private var failure=""
    var body:some View{
        NavigationStack{
            Form{
                Section("Thông tin thật của bạn"){TextField("Ai, ở đâu, điều gì đã xảy ra…",text:$facts,axis:.vertical).lineLimit(4...10)}
                Section{
                    Button("Viết bằng Apple Intelligence"){busy=true;failure="";Task{do{draft=try await StoryWritingAssistant.write(facts:facts,mood:mood)}catch{failure=error.localizedDescription};busy=false}}.disabled(busy || facts.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    Button("Tạo từ mẫu offline"){draft=StoryWritingAssistant.template(facts:facts,mood:mood)}.disabled(busy || facts.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    if busy{ProgressView()}
                    if !failure.isEmpty{Text(failure).font(.caption)}
                }
                Section("Bản nháp để bạn duyệt"){TextEditor(text:$draft).frame(minHeight:150)}
                Text("AI chạy qua Apple Intelligence khi khả dụng. Kiểm tra lại nội dung trước khi lưu.").font(.caption).foregroundStyle(.secondary)
            }.navigationTitle("Story Writer").toolbar{
                ToolbarItem(placement:.cancellationAction){Button("Đóng"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Dùng bản nháp"){apply(draft);dismiss()}.disabled(draft.isEmpty || busy)}
            }
        }
    }
}
enum StorySoundscape:String,CaseIterable,Codable{
    case none="Tắt",rain="Mưa nhẹ",forest="Gió rừng",sea="Sóng biển"
    func generate()->Data?{
        guard self != .none else{return nil}
        let rate=22050,count=rate*8
        var bytes=Data()
        func word<T:FixedWidthInteger>(_ x:T){var le=x.littleEndian;withUnsafeBytes(of:&le){bytes.append(contentsOf:$0)}}
        bytes.append(contentsOf:"RIFF".utf8);word(UInt32(36+count*2));bytes.append(contentsOf:"WAVEfmt ".utf8);word(UInt32(16));word(UInt16(1));word(UInt16(1));word(UInt32(rate));word(UInt32(rate*2));word(UInt16(2));word(UInt16(16));bytes.append(contentsOf:"data".utf8);word(UInt32(count*2))
        var seed:UInt64=81,low=0.0
        for i in 0..<count{
            seed=seed &* 6364136223846793005 &+ 1
            let noise=Double((seed>>40)&0xffffff)/Double(0xffffff)*2-1
            low=low*0.97+noise*0.03
            let t=Double(i)/Double(rate),env=min(1,min(t*4,(8-t)*4))
            let wave:Double
            switch self{
            case .rain:wave=noise*0.16+low*0.22
            case .forest:wave=low*(0.8+0.4*sin(t*1.4))+noise*0.015
            case .sea:wave=(low*1.4+noise*0.04)*(0.45+0.45*sin(t*Double.pi/2))
            case .none:wave=0
            }
            word(Int16(max(-1,min(1,wave*env))*32767))
        }
        return bytes
    }
}
enum StorySubjectCutout{
    static func make(url:URL)->Data?{
        guard let data=try? Data(contentsOf:url),let cg=PhotoEngine.thumb(data,limit:1500) else{return nil}
        let handler=VNImageRequestHandler(cgImage:cg,options:[:]),request=VNGenerateForegroundInstanceMaskRequest()
        do{
            try handler.perform([request])
            guard let result=request.results?.first,!result.allInstances.isEmpty else{return nil}
            let buffer=try result.generateScaledMaskForImage(forInstances:result.allInstances,from:handler)
            let input=CIImage(cgImage:cg),mask=CIImage(cvPixelBuffer:buffer)
            let background=CIImage(color:.clear).cropped(to:input.extent)
            let out=input.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:background,kCIInputMaskImageKey:mask])
            guard let image=CIContext().createCGImage(out,from:input.extent) else{return nil}
            return UIImage(cgImage:image).pngData()
        }catch{return nil}
    }
}
struct StoryDirection:Codable,Equatable{
    var motion="zoom"
    var transition="dissolve"
    var opening=""
    var ending=""
    var signature=""
    var typography="Hiện đại"
    var voiceVolume=1.0
    var ambientVolume=0.18
    var musicVolume=0.22
    var startScale=1.0
    var endScale=1.075
}
enum StoryFilmExporter{
    static func export(story:StoryEntry,shots:[Shot],vault:Vault,vertical:Bool,seconds:Int,direction:StoryDirection = StoryDirection(),music:Data?=nil,musicExtension:String="m4a")async throws->URL{
        let items=Array(shots.prefix(60))
        guard !items.isEmpty else{throw CameraError.unreadable}
        let narration=story.audio
        let voiceLength=narration.flatMap{try? AVAudioPlayer(data:$0).duration} ?? 0
        let per=max(seconds,Int(ceil(voiceLength/Double(items.count))))
        let title=direction.opening.isEmpty ? (story.title.isEmpty ? "Miền ký ức":story.title):direction.opening
        let captions=Dictionary(uniqueKeysWithValues:items.map{shot in
            let text=story.captions[shot.id.uuidString] ?? (shot.id==items.first?.id ? String(story.body.prefix(180)):TimelineIndex.label(shot.day))
            let ending=shot.id==items.last?.id ? [direction.ending,direction.signature].filter{!$0.isEmpty}.joined(separator:"\n"):""
            return (shot.id,ending.isEmpty ? text:text+"\n"+ending)
        })
        let video=try await MemoryMovie.make(items,vault:vault,width:vertical ? 1080:1920,height:vertical ? 1920:1080,seconds:max(1,per),title:title,motion:direction.motion=="pan" ? .pan:direction.motion=="still" ? .still:.zoom,transition:direction.transition=="cut" ? .cut:direction.transition=="fade" ? .fade:.dissolve,captions:captions,direction:direction)
        guard narration != nil || (story.soundscape ?? .none) != .none || music != nil else{return video}
        do{
            let output=try await mix(video:video,voice:narration,sound:story.soundscape ?? .none,music:music,musicExtension:musicExtension,direction:direction)
            try? FileManager.default.removeItem(at:video);return output
        }catch{try? FileManager.default.removeItem(at:video);throw error}
    }
    private static func mix(video:URL,voice:Data?,sound:StorySoundscape,music:Data?,musicExtension:String,direction:StoryDirection)async throws->URL{
        let source=AVURLAsset(url:video),duration=try await source.load(.duration)
        let comp=AVMutableComposition()
        guard let original=try await source.loadTracks(withMediaType:.video).first,let track=comp.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) else{throw CameraError.writeFailed}
        try track.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:original,at:.zero)
        track.preferredTransform=try await original.load(.preferredTransform)
        var params=[AVAudioMixInputParameters](),temp=[URL]()
        defer{for u in temp{try? FileManager.default.removeItem(at:u)}}
        for (data,ext,loop,volume) in [(voice,"m4a",false,Float(direction.voiceVolume)),(sound.generate(),"wav",true,Float(direction.ambientVolume)),(music,musicExtension,true,Float(direction.musicVolume))]{
            guard let data else{continue}
            let url=try CreativeEngine.exportURL(data,extension:ext);temp.append(url)
            let asset=AVURLAsset(url:url),length=try await asset.load(.duration)
            guard CMTimeGetSeconds(length)>0,let src=try await asset.loadTracks(withMediaType:.audio).first,let dest=comp.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) else{throw CameraError.unreadable}
            var pos=CMTime.zero
            repeat{
                let n=CMTimeMinimum(CMTimeSubtract(duration,pos),length)
                try dest.insertTimeRange(CMTimeRange(start:.zero,duration:n),of:src,at:pos);pos=CMTimeAdd(pos,n)
            }while loop && CMTimeCompare(pos,duration)<0
            let p=AVMutableAudioMixInputParameters(track:dest);p.setVolume(volume,at:.zero);params.append(p)
        }
        let mix=AVMutableAudioMix();mix.inputParameters=params
        let out=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
        guard let session=AVAssetExportSession(asset:comp,presetName:AVAssetExportPresetHighestQuality) else{throw CameraError.writeFailed}
        session.outputURL=out;session.outputFileType = .mp4;session.audioMix=mix
        await session.export()
        guard session.status == .completed else{throw session.error ?? CameraError.writeFailed}
        return out
    }
}
struct StoryFilmView:View{
    let story:StoryEntry
    let shots:[Shot]
    let vault:Vault
    @Environment(\.dismiss) private var dismiss
    @State private var vertical=true
    @State private var seconds=4
    @State private var direction=StoryDirection()
    @State private var music:Data?
    @State private var musicName=""
    @State private var musicExtension="m4a"
    @State private var pickingMusic=false
    @State private var working=false
    @State private var output:URL?
    @State private var notice=""
    var body:some View{
        NavigationStack{
            Form{
                Text(story.title.isEmpty ? "Phim ký ức":story.title).font(.headline)
                Toggle("Dọc 9:16",isOn:$vertical)
                Picker("Giây tối thiểu mỗi ảnh",selection:$seconds){ForEach([2,4,6,8],id:\.self){Text("\($0)").tag($0)}}
                Section("Story Director"){
                    TextField("Lời mở đầu",text:$direction.opening)
                    TextField("Lời kết",text:$direction.ending)
                    TextField("Chữ ký",text:$direction.signature)
                    Picker("Typography",selection:$direction.typography){ForEach(["Hiện đại","Cổ điển","Máy đánh chữ"],id:\.self){Text($0).tag($0)}}
                    Picker("Chuyển động",selection:$direction.motion){Text("Tĩnh").tag("still");Text("Phóng").tag("zoom");Text("Lia").tag("pan")}
                    Picker("Chuyển cảnh",selection:$direction.transition){Text("Cắt").tag("cut");Text("Mờ").tag("fade");Text("Hòa trộn").tag("dissolve")}
                    Text("Keyframe đầu · \(direction.startScale,format:.number.precision(.fractionLength(2)))")
                    Slider(value:$direction.startScale,in:1...1.3)
                    Text("Keyframe cuối · \(direction.endScale,format:.number.precision(.fractionLength(2)))")
                    Slider(value:$direction.endScale,in:1...1.3)
                }
                Section("Sound Designer"){
                    Text("Giọng kể");Slider(value:$direction.voiceVolume,in:0...1)
                    Text("Môi trường");Slider(value:$direction.ambientVolume,in:0...1)
                    Button("Chọn nhạc từ Tệp"){pickingMusic=true}
                    if music != nil{Text(musicName);Text("Âm lượng nhạc");Slider(value:$direction.musicVolume,in:0...1);Button("Bỏ nhạc",role:.destructive){music=nil;musicName=""}}
                }
                Text("1080p · tối đa 60 ảnh · tiêu đề, chú thích, lời kể và âm thanh môi trường. Tự tăng thời lượng để không cắt lời kể.").font(.caption)
                Button("Xuất phim story"){working=true;notice="";let v=vertical,s=seconds,d=direction,m=music,ext=musicExtension;Task{do{output=try await Task.detached(priority:.userInitiated){try await StoryFilmExporter.export(story:story,shots:shots,vault:vault,vertical:v,seconds:s,direction:d,music:m,musicExtension:ext)}.value;notice="Đã xuất phim."}catch{notice=error.localizedDescription};working=false}}.disabled(working || shots.isEmpty)
                if working{ProgressView()}
                if let output{ShareLink(item:output){Label("Lưu / gửi tặng phim",systemImage:"square.and.arrow.up")}}
                Text(notice).font(.caption)
            }.navigationTitle("Story Director").toolbar{Button("Đóng"){dismiss()}}
        }.fileImporter(isPresented:$pickingMusic,allowedContentTypes:[.audio]){result in
            do{let url=try result.get(),access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}};let data=try Data(contentsOf:url);guard data.count<=30_000_000 else{throw CameraError.unreadable};_ = try AVAudioPlayer(data:data);music=data;musicName=url.lastPathComponent;musicExtension=url.pathExtension.isEmpty ? "m4a":url.pathExtension;notice=""}catch{notice=error.localizedDescription}
        }
    }
}
