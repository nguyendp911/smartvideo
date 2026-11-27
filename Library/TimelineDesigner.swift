import SwiftUI
struct TimelineDesigner:View {
    @Binding var layout:String
    @Binding var spacing:Double
    @Binding var radius:Double
    @Binding var columns:Int
    @Binding var caption:Bool
    @Binding var dateSize:Double
    @Environment(\.dismiss) private var dismiss
    private var theme:GalleryLayout{GalleryLayout(rawValue:layout) ?? .editorial}
    var body:some View {
        NavigationStack{
            Form{
                Section("Phong cách"){
                    ForEach(GalleryLayout.allCases,id:\.self){style in
                        Button{layout=style.rawValue}label:{
                            HStack{
                                RoundedRectangle(cornerRadius:8).fill(style.background).overlay{Image(systemName:style.hero ? "photo.artframe":"square.grid.3x3").foregroundStyle(style.accent)}.frame(width:48,height:38)
                                Text(style.rawValue);Spacer()
                                if style.rawValue==layout{Image(systemName:"checkmark").foregroundStyle(gold)}
                            }
                        }.buttonStyle(.plain)
                    }
                }
                Section("Tùy chỉnh"){
                    Stepper("Số cột: \(columns)",value:$columns,in:2...5)
                    LabeledContent("Khoảng cách",value:"\(Int(spacing)) pt")
                    Slider(value:$spacing,in:2...16,step:1)
                    LabeledContent("Bo góc",value:"\(Int(radius)) pt")
                    Slider(value:$radius,in:0...24,step:1)
                    LabeledContent("Cỡ ngày tháng",value:"\(Int(dateSize)) pt")
                    Slider(value:$dateSize,in:16...30,step:1)
                    Toggle("Tiêu đề ảnh nổi bật",isOn:$caption)
                }
                Section("Xem trước"){
                    VStack(alignment:.leading,spacing:CGFloat(spacing)){
                        Text("27 tháng 11, 2026").font(.system(size:dateSize,design:theme.font)).foregroundStyle(theme.accent)
                        if theme.hero {RoundedRectangle(cornerRadius:CGFloat(radius)).fill(theme.accent.opacity(0.3)).aspectRatio(theme.ratio,contentMode:.fit).overlay{Image(systemName:"photo").font(.largeTitle)}}
                        HStack(spacing:CGFloat(spacing)){ForEach(0..<max(2,min(5,columns)),id:\.self){i in RoundedRectangle(cornerRadius:CGFloat(radius)).fill(theme.accent.opacity(0.15+Double(i)*0.06)).aspectRatio(1,contentMode:.fit)}}
                    }.padding(12).background(theme.background,in:RoundedRectangle(cornerRadius:12))
                    Button("Khôi phục mặc định"){layout=GalleryLayout.editorial.rawValue;spacing=5;radius=8;columns=3;caption=true;dateSize=21}
                }
            }.navigationTitle("Timeline Designer").navigationBarTitleDisplayMode(.inline).toolbar{Button("Xong"){dismiss()}}
        }
    }
}
