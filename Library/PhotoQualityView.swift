import SwiftUI
import ImageIO
import UIKit

struct PhotoQualityReport{
    let width:Int;let height:Int;let bytes:Int;let format:String
    let histogram:[Int];let dark:Double;let bright:Double;let edge:Double
    static func analyze(_ url:URL)->Self?{
        guard let data=try? Data(contentsOf:url,options:.mappedIfSafe),let source=CGImageSourceCreateWithData(data as CFData,nil),let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any],let cg=PhotoEngine.thumb(data,limit:512) else{return nil}
        let w=128,h=128;var pixels=[UInt8](repeating:0,count:w*h)
        let ok=pixels.withUnsafeMutableBytes{p->Bool in
            guard let ctx=CGContext(data:p.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else{return false}
            ctx.draw(cg,in:CGRect(x:0,y:0,width:w,height:h));return true
        }
        guard ok else{return nil}
        var bins=[Int](repeating:0,count:64),detail=0.0
        for p in pixels{bins[Int(p)/4]+=1}
        for y in 1..<h{for x in 1..<w{let i=y*w+x;detail+=abs(Double(pixels[i])-Double(pixels[i-1]))+abs(Double(pixels[i])-Double(pixels[i-w]))}}
        let total=Double(pixels.count)
        return Self(width:props[kCGImagePropertyPixelWidth as String] as? Int ?? cg.width,height:props[kCGImagePropertyPixelHeight as String] as? Int ?? cg.height,bytes:data.count,format:CGImageSourceGetType(source).map{$0 as String} ?? "Không rõ",histogram:bins,dark:Double(bins.prefix(2).reduce(0,+))/total,bright:Double(bins.suffix(2).reduce(0,+))/total,edge:detail/total)
    }
}
struct PhotoQualityView:View{
    let url:URL
    @Environment(\.dismiss) private var dismiss
    @State private var report:PhotoQualityReport?
    @State private var done=false
    var body:some View{
        NavigationStack{List{
            if let r=report{
                Section("Ảnh đang xem"){
                    LabeledContent("Độ phân giải",value:"\(r.width) × \(r.height)")
                    LabeledContent("Megapixel",value:String(format:"%.1f MP",Double(r.width)*Double(r.height)/1_000_000))
                    LabeledContent("Dung lượng",value:ByteCountFormatter.string(fromByteCount:Int64(r.bytes),countStyle:.file))
                    LabeledContent("Định dạng",value:r.format)
                }
                Section("Histogram độ sáng"){
                    GeometryReader{g in
                        HStack(alignment:.bottom,spacing:1){ForEach(r.histogram.indices,id:\.self){i in Rectangle().fill(gold.opacity(0.8)).frame(height:g.size.height*CGFloat(r.histogram[i])/CGFloat(max(1,r.histogram.max() ?? 1)))}}
                    }.frame(height:120)
                    HStack{Text("Tối");Spacer();Text("Sáng")}.font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Pixel rất tối",value:r.dark.formatted(.percent.precision(.fractionLength(1))))
                    LabeledContent("Pixel rất sáng",value:r.bright.formatted(.percent.precision(.fractionLength(1))))
                    LabeledContent("Chỉ số biên chi tiết",value:String(format:"%.2f",r.edge))
                    Text("Thống kê trên mẫu ảnh xám thu nhỏ, dùng để tham khảo vùng sáng/tối và chi tiết; không phải kết luận ảnh bị mờ hay cháy sáng.").font(.caption).foregroundStyle(.secondary)
                }
            }else if done{Text("Không đọc được thông tin ảnh.")}else{ProgressView("Đang phân tích…")}
        }.navigationTitle("Photo Inspector").toolbar{Button("Xong"){dismiss()}}}
        .task{report=await Task.detached(priority:.utility){PhotoQualityReport.analyze(url)}.value;done=true}
    }
}
