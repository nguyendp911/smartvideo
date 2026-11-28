import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ImageIO

struct PhotoMaskStudio:View{
    let url:URL
    @Binding var recipe:CreativeRecipe
    @Environment(\.dismiss) private var dismiss
    @State private var document=PhotoMaskDocument(source:"")
    @State private var selected:UUID?
    @State private var preview:UIImage?
    @State private var overlay=true
    @State private var painting=false
    @State private var subtract=false
    @State private var brushSize=0.08
    @State private var drawing:[MaskPoint]=[]
    @State private var undoStack:[PhotoMaskDocument]=[]
    @State private var redoStack:[PhotoMaskDocument]=[]
    @State private var busy=false
    @State private var issue=""
    @State private var pickingSky=false
    @State private var importIssue=""
    @ObservedObject private var skill=MaskSkillStore.shared
    @State private var teach=true
    @State private var training=false
    @State private var resetSkill=false
    @State private var originalDocument=PhotoMaskDocument(source:"")
    private var index:Int?{document.layers.firstIndex{$0.id==selected}}
    var body:some View{
        NavigationStack{
            ScrollView{
                VStack(alignment:.leading,spacing:15){
                    Text("S E L E C T I V E  /  M A S K I N G").font(.caption2.monospaced()).foregroundStyle(gold)
                    previewPanel
                    skillPanel
                    HStack{
                        Toggle("Mặt nạ đỏ",isOn:$overlay).toggleStyle(.switch).font(.caption)
                        Spacer()
                        Button{undo()}label:{Image(systemName:"arrow.uturn.backward")}.disabled(undoStack.isEmpty)
                        Button{redo()}label:{Image(systemName:"arrow.uturn.forward")}.disabled(redoStack.isEmpty)
                    }
                    Menu{ForEach(PhotoMaskKind.allCases){kind in Button(kind.rawValue,systemImage:kind.symbol){add(kind)}}}label:{Label("Tạo mặt nạ",systemImage:"plus.circle.fill").frame(maxWidth:.infinity)}.buttonStyle(.borderedProminent)
                    ForEach(document.layers){layer in
                        HStack{
                            Button{selected=layer.id;painting=false}label:{HStack{Image(systemName:layer.kind.symbol);Text(layer.name);Spacer();if selected==layer.id{Image(systemName:"checkmark.circle.fill").foregroundStyle(gold)}}}.buttonStyle(.plain)
                            Button{checkpoint();if let i=document.layers.firstIndex(where:{$0.id==layer.id}){document.layers[i].enabled.toggle()}}label:{Image(systemName:layer.enabled ? "eye":"eye.slash")}
                            Button(role:.destructive){checkpoint();document.layers.removeAll{$0.id==layer.id};if selected==layer.id{selected=document.layers.last?.id}}label:{Image(systemName:"trash")}
                        }.padding(10).background(selected==layer.id ? gold.opacity(0.13):.white.opacity(0.05),in:RoundedRectangle(cornerRadius:10))
                    }
                    if let i=index{layerControls(i)}
                    if !issue.isEmpty{Text(issue).font(.caption).foregroundStyle(.orange)}
                    if !importIssue.isEmpty{Text(importIssue).font(.caption).foregroundStyle(.orange)}
                    Text("Mặt nạ áp dụng trước cắt/xoay ảnh và chỉ thuộc ảnh này. Các vùng AI có thể cần sửa cọ ở mép. Xem trước ở đây dùng ảnh gốc với chỉnh cục bộ; Photo Lab kết hợp thêm preset và ánh sáng toàn ảnh.").font(.caption2).foregroundStyle(.secondary)
                }.padding(14)
            }.navigationTitle("Masking Studio").navigationBarTitleDisplayMode(.inline).toolbar{
                ToolbarItem(placement:.cancellationAction){Button("Hủy"){dismiss()}.disabled(training)}
                ToolbarItem(placement:.confirmationAction){Button(training ? "Đang học…" : "Áp dụng"){applyAndLearn()}.disabled(busy || training || !issue.isEmpty)}
            }
        }.onAppear{
            let key=SemanticMaskEngine.sourceKey(url)
            document=recipe.masking?.first(where:{$0.source==key}) ?? PhotoMaskDocument(source:key)
            originalDocument=document
            selected=document.layers.last?.id
        }
        .interactiveDismissDisabled(training)
        .confirmationDialog("Xóa dữ liệu huấn luyện vùng chọn?",isPresented:$resetSkill){Button("Xóa hồ sơ học",role:.destructive){skill.reset()}}
        .fileImporter(isPresented:$pickingSky,allowedContentTypes:[.image]){result in
            do{
                guard let i=index,document.layers[i].kind == .sky else{return}
                let url=try result.get(),access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
                guard let bytes=try? Data(contentsOf:url,options:.mappedIfSafe),bytes.count<=50_000_000,let cg=PhotoEngine.thumb(bytes,limit:3000),let data=UIImage(cgImage:cg).jpegData(compressionQuality:0.94) else{throw PhotoMaskError.unreadable}
                checkpoint();document.layers[i].replacement=data;importIssue="";overlay=false
            }catch{importIssue=error.localizedDescription}
        }
        .task(id:PreviewKey(document:document,selected:selected,overlay:overlay)){
            let d=document,s=selected,o=overlay
            busy=true;issue=""
            do{
                try await Task.sleep(for:.milliseconds(160))
                let image=try await Task.detached(priority:.userInitiated){try SemanticMaskEngine.preview(url,document:d,selected:s,overlay:o)}.value
                if !Task.isCancelled{preview=image;busy=false}
            }catch{if !Task.isCancelled{issue=error.localizedDescription;busy=false}}
        }
    }
    private var skillPanel:some View{
        VStack(alignment:.leading,spacing:8){
            Label("Adaptive Skill Learning",systemImage:"brain").font(.headline)
            Toggle("Học từ vùng sửa đã xác nhận",isOn:$skill.enabled)
            if skill.enabled{
                Toggle("Dùng nét cọ lần này để dạy AI",isOn:$teach).font(.caption)
                ForEach([PhotoMaskKind.sky,.subject,.background]){kind in
                    let count=skill.profile.examples.filter{$0.kind==kind}.count
                    HStack{Text(kind.rawValue);Spacer();Text("\(count) ảnh đã sửa").monospacedDigit();if skill.model(kind) != nil{Image(systemName:"checkmark.seal.fill").foregroundStyle(.green)}}
                        .font(.caption)
                }
                if let model=skill.model(.sky){
                    Text("Sai số trên mẫu sửa giữ lại: "+String(format:"%.3f → %.3f",model.baselineLoss,model.validationLoss)).font(.caption2)
                }
            }
            Text("Chỉ dạy AI khi cọ thêm/bớt sửa lỗi nhận diện, không dùng khi tô vùng vì mục đích nghệ thuật. Cần ít nhất 3 ảnh, có cả nhãn thêm và bớt, và kiểm tra cải thiện trên ảnh giữ lại. Không gửi dữ liệu lên mạng.").font(.caption2).foregroundStyle(.secondary)
            if !skill.issue.isEmpty{Text(skill.issue).font(.caption).foregroundStyle(.orange)}
            Button("Đặt lại dữ liệu học",role:.destructive){resetSkill=true}.font(.caption)
        }.padding(10).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:10)).disabled(training)
    }
    private func applyAndLearn(){
        let final=document
        var docs=recipe.masking ?? [];docs.removeAll{$0.source==final.source};if !final.layers.isEmpty{docs.append(final)};recipe.masking=docs.isEmpty ? nil:docs
        let changed=final.layers.filter{layer in
            guard [.sky,.subject,.background].contains(layer.kind),layer.enabled,!layer.inverted,!layer.strokes.isEmpty else{return false}
            return originalDocument.layers.first(where:{$0.id==layer.id})?.strokes != layer.strokes
        }
        guard skill.enabled,teach,!changed.isEmpty else{dismiss();return}
        training=true
        Task{await skill.learn(url:url,document:PhotoMaskDocument(source:final.source,layers:changed));training=false;dismiss()}
    }
    private struct PreviewKey:Equatable{let document:PhotoMaskDocument;let selected:UUID?;let overlay:Bool}
    private var previewPanel:some View{
        Group{
            if let preview{
                GeometryReader{g in
                    ZStack{
                        Image(uiImage:preview).resizable().scaledToFit()
                        if painting{
                            Canvas{ctx,size in
                                var path=Path()
                                if let first=drawing.first{
                                    path.move(to:CGPoint(x:first.x*size.width,y:first.y*size.height))
                                    for p in drawing.dropFirst(){path.addLine(to:CGPoint(x:p.x*size.width,y:p.y*size.height))}
                                    ctx.stroke(path,with:.color(subtract ? .white.opacity(0.65):.red.opacity(0.5)),style:StrokeStyle(lineWidth:min(size.width,size.height)*brushSize,lineCap:.round,lineJoin:.round))
                                }
                            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0,coordinateSpace:.local).onChanged{v in
                                guard g.size.width>0,g.size.height>0 else{return}
                                let point=MaskPoint(x:Double(max(0,min(1,v.location.x/g.size.width))),y:Double(max(0,min(1,v.location.y/g.size.height))))
                                if drawing.count<2000{drawing.append(point)}
                            }.onEnded{_ in
                                guard let i=index,!drawing.isEmpty else{drawing=[];return}
                                checkpoint();document.layers[i].strokes.append(MaskStroke(subtract:subtract,size:brushSize,points:drawing));drawing=[]
                            })
                        }
                    }
                }.aspectRatio(preview.size.width/max(1,preview.size.height),contentMode:.fit)
            }else{DiskImage(url:url,limit:1200).scaledToFit().frame(maxHeight:350)}
        }.clipShape(RoundedRectangle(cornerRadius:10)).overlay(alignment:.topTrailing){if busy{ProgressView().padding(9).background(.black.opacity(0.55),in:Circle()).padding(6)}}
    }
    private func layerControls(_ i:Int)->some View{
        VStack(alignment:.leading,spacing:10){
            TextField("Tên mặt nạ",text:$document.layers[i].name).textFieldStyle(.roundedBorder)
            Toggle("Đảo vùng chọn",isOn:$document.layers[i].inverted)
            if [.sky,.subject,.background].contains(document.layers[i].kind){
                if document.layers[i].learnedCorrection != nil{Button("So sánh: dùng AI gốc"){checkpoint();document.layers[i].learnedCorrection=nil}}
                else if let model=skill.model(document.layers[i].kind){Button("Dùng AI đã học"){checkpoint();document.layers[i].learnedCorrection=model}}
            }
            control("Cường độ vùng",value:$document.layers[i].strength,range:0...1)
            control("Làm mềm viền",value:$document.layers[i].feather,range:0...0.05)
            if [.sky,.subject,.background,.luminance].contains(document.layers[i].kind){
                control("Ngưỡng chọn vùng",value:$document.layers[i].threshold,range:0.15...0.85)
            }
            if [.linear,.radial].contains(document.layers[i].kind){
                control("Vị trí ngang",value:$document.layers[i].centerX,range:0...1)
                control("Vị trí dọc",value:$document.layers[i].centerY,range:0...1)
                control("Bán kính / độ chuyển",value:$document.layers[i].radius,range:0.02...1)
                if document.layers[i].kind == .linear{control("Góc",value:$document.layers[i].angle,range:-180...180)}
            }
            Toggle("Vẽ tinh chỉnh vùng chọn",isOn:$painting)
            if painting{
                Picker("Cọ",selection:$subtract){Text("Thêm").tag(false);Text("Bớt").tag(true)}.pickerStyle(.segmented)
                control("Kích thước cọ",value:$brushSize,range:0.015...0.3)
                Button("Xóa nét cọ"){checkpoint();document.layers[i].strokes=[]}
                Text("Vuốt trực tiếp trên ảnh. Màu đỏ là vùng chọn. Tắt chế độ vẽ để cuộn.").font(.caption2)
            }
            if document.layers[i].kind == .sky{
                Divider()
                Button("Thay bầu trời từ ảnh trong Tệp",systemImage:"cloud.sun"){pickingSky=true}
                if document.layers[i].replacement != nil{
                    Text("Ảnh bầu trời đã nhập · chỉ ghép trong mặt nạ").font(.caption)
                    Button("Bỏ bầu trời thay thế",role:.destructive){checkpoint();document.layers[i].replacement=nil}
                }
            }
            Divider()
            Text("HẬU KỲ RIÊNG VÙNG").font(.caption2.monospaced()).foregroundStyle(gold)
            Picker("Preset màu trong vùng",selection:Binding(get:{document.layers[i].grade.preset ?? ""},set:{document.layers[i].grade.preset=$0.isEmpty ? nil:$0})){
                Text("Không").tag("")
                ForEach(PremiumPresets.all){p in Text(p.name).tag(p.id)}
            }
            if document.layers[i].grade.preset != nil{control("Cường độ preset",value:$document.layers[i].grade.presetStrength,range:0...1)}
            control("Phơi sáng",value:$document.layers[i].grade.exposure,range:-2...2)
            control("Tương phản",value:$document.layers[i].grade.contrast,range:0.5...1.6)
            control("Bão hòa",value:$document.layers[i].grade.saturation,range:0...2)
            control("Nhiệt độ",value:$document.layers[i].grade.warmth,range:-1...1)
            control("Tint",value:$document.layers[i].grade.tint,range:-1...1)
            control("Highlights",value:$document.layers[i].grade.highlights,range:-1...0)
            control("Shadows",value:$document.layers[i].grade.shadows,range:-0.5...1)
            control("Clarity",value:$document.layers[i].grade.clarity,range:0...1)
            control("Giảm mù (tương phản/màu)",value:$document.layers[i].grade.dehaze,range:-1...1)
            control("Độ nét",value:$document.layers[i].grade.sharpness,range:0...1)
            Button("Đặt lại thông số vùng"){checkpoint();document.layers[i].grade=LocalGrade()}
        }.padding(12).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
    }
    private func control(_ name:String,value:Binding<Double>,range:ClosedRange<Double>)->some View{
        VStack(alignment:.leading,spacing:2){
            HStack{Text(name);Spacer();Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2)))).monospacedDigit().foregroundStyle(gold)}.font(.caption)
            Slider(value:value,in:range,onEditingChanged:{editing in if editing{checkpoint()}})
        }
    }
    private func checkpoint(){undoStack.append(document);if undoStack.count>25{undoStack.removeFirst()};redoStack=[]}
    private func undo(){if let previous=undoStack.popLast(){redoStack.append(document);document=previous;if !document.layers.contains(where:{$0.id==selected}){selected=document.layers.last?.id}}}
    private func redo(){if let next=redoStack.popLast(){undoStack.append(document);document=next;if !document.layers.contains(where:{$0.id==selected}){selected=document.layers.last?.id}}}
    private func add(_ kind:PhotoMaskKind){
        checkpoint()
        var layer=PhotoMaskLayer(name:kind.rawValue+" \(document.layers.count+1)",kind:kind)
        layer.learnedCorrection=skill.model(kind)
        document.layers.append(layer);selected=layer.id;overlay=true;painting=kind == .brush
    }
}
