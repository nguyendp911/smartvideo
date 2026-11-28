import SwiftUI
import UIKit

struct PremiumEffectsPanel:View{
    @Binding var recipe:CreativeRecipe
    let group:Group
    var openMask:(()->Void)?=nil
    var heal:(()->Void)?=nil
    var healRadius:Binding<Double>?=nil
    var sourceKey:String?=nil
    enum Group{case color,portrait,lighting,restoration}
    private var e:PremiumEffects{recipe.effects ?? PremiumEffects()}
    private func bind<T>(_ key:WritableKeyPath<PremiumEffects,T>)->Binding<T>{
        Binding(get:{e[keyPath:key]},set:{v in var next=e;next[keyPath:key]=v;recipe.effects=next})
    }
    var body:some View{
        VStack(alignment:.leading,spacing:9){
            switch group{
            case .color:
                Label("Premium Color Protection",systemImage:"paintpalette").font(.headline)
                control("Bảo vệ sắc độ da / màu trung tính",\.protectSkin,0...1)
                Toggle("Adaptive Preset",isOn:bind(\.adaptivePreset)).font(.subheadline)
                Text("Cường độ preset tự giảm khi ảnh đã rất bão hòa hoặc có nhiều vùng sáng. Bảo vệ màu dựa trên sắc độ, không phải phân vùng da chuyên dụng.").font(.caption).foregroundStyle(.secondary)
            case .portrait:
                Label("Premium Portrait Studio",systemImage:"person.crop.circle").font(.headline)
                Text("Dodge & Burn và Skin Equalizer dùng mặt nạ mặt hoặc cọ đang bật cuối cùng. Hair Detail cần cọ vẽ tóc riêng; mắt dùng Vision nếu chưa có mặt nạ mắt.").font(.caption).foregroundStyle(.secondary)
                if let openMask{Button("Chọn hoặc sửa vùng",systemImage:"paintbrush.pointed",action:openMask)}
                control("Dodge & Burn (EV)",\.dodgeBurn,-1...1)
                control("Skin Equalizer",\.skinEqualizer,0...1)
                control("Eye Enhancement",\.eyeDetail,0...1)
                control("Hair Detail · vùng cọ",\.hairDetail,0...1)
                control("Xóa phông theo mặt nạ",\.backgroundBlur,0...1)
                Text("Xóa phông 2D từ mask chủ thể; không phải bản đồ độ sâu hoặc quang học 3D.").font(.caption2).foregroundStyle(.secondary)
                Divider()
                Label("Healing · sao chép vùng gần",systemImage:"bandage").font(.subheadline.weight(.semibold))
                Text("Chạm vùng da sạch rồi chạm khuyết điểm để sao chép mềm. Chỉ dùng khi ảnh chưa cắt/xoay/lật.").font(.caption).foregroundStyle(.secondary)
                if let healRadius{Slider(value:healRadius,in:0.004...0.04)}
                if let heal{Button("Chọn điểm nguồn & điểm sửa",systemImage:"eyedropper",action:heal).disabled(sourceKey==nil || recipe.crop != "Gốc" || (recipe.rotation ?? 0) != 0 || recipe.mirror==true)}
                if let key=sourceKey{
                    Text("\(e.spots[key]?.count ?? 0) điểm sửa").font(.caption)
                    HStack{
                        Button("Hoàn tác điểm cuối"){var next=e;if next.spots[key]?.isEmpty==false{next.spots[key]?.removeLast()};recipe.effects=next}.disabled(e.spots[key]?.isEmpty != false)
                        Spacer()
                        Button("Xóa điểm sửa",role:.destructive){var next=e;next.spots.removeValue(forKey:key);recipe.effects=next}.disabled(e.spots[key]?.isEmpty != false)
                    }.font(.caption)
                }
            case .lighting:
                Label("Premium Lighting Studio",systemImage:"lightbulb.max").font(.headline)
                Text("Mô phỏng ánh sáng 2D theo gradient và mặt nạ. Không thay nền, không tái tạo nguồn sáng vật lý 3D.").font(.caption).foregroundStyle(.secondary)
                control("Virtual Softbox",\.softbox,0...1)
                control("Directional Light · góc",\.direction,-180...180)
                control("Độ mềm nguồn sáng",\.softness,0...1)
                control("Light Temperature",\.lightWarmth,-1...1)
                control("Shadow Control",\.shadow,0...1)
                control("Rim Light · viền chủ thể",\.rim,0...1)
                control("Light Spill · hắt màu viền",\.spill,0...1)
                control("Ambient Matching · cân sáng",\.ambient,0...1)
                if let openMask{Button("Tinh chỉnh chủ thể",systemImage:"paintbrush.pointed",action:openMask)}
            case .restoration:
                Label("Premium Restoration Studio",systemImage:"wand.and.stars").font(.headline)
                Text("Các bộ lọc này xử lý tín hiệu ảnh, không tạo chi tiết mới bằng AI. Không thể khôi phục thông tin đã mất.").font(.caption).foregroundStyle(.secondary)
                control("Denoise · khử nhiễu",\.denoise,0...1)
                control("Giảm nhòe nhẹ · tăng chi tiết",\.deblur,0...1)
                control("Giảm vết nén JPEG",\.jpegRepair,0...1)
                control("Ảnh cũ · phục hồi tương phản",\.fadedPhoto,0...1)
                control("Highlight Recovery · nén vùng sáng",\.highlightRecovery,0...1)
                Picker("Tăng kích thước xuất (Lanczos)",selection:bind(\.upscale)){Text("1×").tag(1);Text("2×").tag(2)}
                Text("2× bị giới hạn bởi độ phân giải xuất và 70 MP; không phải AI Super Resolution.").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(11).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
    }
    private func control(_ title:String,_ key:WritableKeyPath<PremiumEffects,Double>,_ range:ClosedRange<Double>)->some View{
        VStack(spacing:3){
            HStack{Text(title);Spacer();Text(e[keyPath:key].formatted(.number.precision(.fractionLength(2)))).foregroundStyle(gold).monospacedDigit()}.font(.caption)
            Slider(value:bind(key),in:range)
        }
    }
}
struct PremiumEditCandidates:View{
    let url:URL
    @Binding var recipe:CreativeRecipe
    let sampleCount:Int
    let learned:TasteProfile
    @State private var candidates:[Candidate]=[]
    @State private var snapshot:CreativeRecipe?
    @State private var busy=false
    @State private var generation=UUID()
    struct Candidate:Identifiable{
        let id=UUID()
        let title:String
        let recipe:CreativeRecipe
        let image:UIImage
    }
    var body:some View{
        VStack(alignment:.leading,spacing:10){
            Label("Best Edit Selection",systemImage:"rectangle.on.rectangle").font(.headline)
            Text("Kết xuất các phương án từ chính ảnh đang chọn. Chọn bằng mắt; không tự gán điểm đẹp.").font(.caption).foregroundStyle(.secondary)
            Button("Tạo 3 phương án",systemImage:"sparkles"){generate()}.disabled(busy)
            if busy{ProgressView()}
            if snapshot==recipe && !candidates.isEmpty{
                HStack(alignment:.top,spacing:8){
                    ForEach(candidates){candidate in
                        Button{recipe=candidate.recipe;candidates=[];snapshot=nil}label:{
                            VStack{Image(uiImage:candidate.image).resizable().scaledToFit().frame(maxHeight:110);Text(candidate.title).font(.caption2);Text("Áp dụng").font(.caption2).foregroundStyle(gold)}
                        }.buttonStyle(.plain).frame(maxWidth:.infinity)
                    }
                }
            }else if !candidates.isEmpty{Text("Công thức đã thay đổi. Tạo lại phương án.").font(.caption).foregroundStyle(.secondary)}
            Divider()
            Label("Personal Color DNA",systemImage:"chart.bar.xaxis").font(.headline)
            Text("\(sampleCount) ảnh đã lưu chỉnh sửa · thống kê trên thiết bị").font(.caption).foregroundStyle(.secondary)
            if !learned.samples.isEmpty{
                let samples=learned.samples
                let n=Double(samples.count)
                Text("Phơi sáng TB: \(samples.reduce(0.0){$0+$1.global.exposure}/n,specifier:"%.2f") EV").font(.caption)
                Text("Bão hòa TB: \(samples.reduce(0.0){$0+$1.global.saturation}/n,specifier:"%.2f")").font(.caption)
                Text("Nhiệt độ màu TB: \(samples.reduce(0.0){$0+$1.global.warmth}/n,specifier:"%.2f")").font(.caption)
            }
            Text("Consistency: xuất theo cùng công thức cho các ảnh đã chọn. Adaptive Preset thay đổi cường độ dựa trên từng ảnh nếu bật.").font(.caption2).foregroundStyle(.secondary)
        }.padding(10).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
        .onDisappear{generation=UUID()}
    }
    private func generate(){
        let input=recipe,source=url,id=UUID();generation=id;busy=true;candidates=[];snapshot=input
        Task{
            let stats=await Task.detached(priority:.utility){()->EditingFeatures? in
                guard let data=try? Data(contentsOf:source,options:.mappedIfSafe),let cg=PhotoEngine.thumb(data,limit:512) else{return nil}
                return EditingFeatures.analyze(cg)
            }.value
            guard generation==id else{return}
            var natural=input,soft=input,contrast=input
            if let stats{
                let baseline=stats.baseline()
                natural.exposure=baseline.exposure;natural.highlights=baseline.highlights;natural.shadows=baseline.shadows
            }
            soft.contrast=max(0.75,input.contrast*0.92);soft.saturation=max(0,input.saturation*0.88);soft.highlights=max(-1,(input.highlights ?? 0)-0.15)
            contrast.contrast=min(1.5,input.contrast*1.12);contrast.saturation=min(2,input.saturation*1.06)
            var result:[Candidate]=[]
            for (title,variant) in [("Cân bằng",natural),("Dịu nhẹ",soft),("Chiều sâu",contrast)]{
                guard generation==id else{return}
                if let bytes=await PhotoPreviewWorker.shared.photo(source,recipe:variant,maxSize:280,thumbnail:true),let image=UIImage(data:bytes){result.append(Candidate(title:title,recipe:variant,image:image))}
            }
            guard generation==id else{return};candidates=result;busy=false
        }
    }
}
