import SwiftUI

enum VineGrowthStage:Int,CaseIterable,Identifiable{
    case seed,sprout,young,budding,blooming,mature
    var id:Int{rawValue}
    var threshold:Int{[0,7,30,90,180,365][rawValue]}
    var title:String{["Mầm ký ức","Lá non","Dây leo nhỏ","Chớm nụ","Mùa hoa","Vườn ký ức"][rawValue]}
    var description:String{
        ["Thân mảnh và vài lá non.","Lá mới xuất hiện dọc thân.","Dây leo dài hơn, lá dày hơn.","Những nụ hoa đầu tiên trên nhánh.","Hoa bắt đầu nở trên cây ký ức.","Thân trưởng thành, nhiều hoa và nhánh phụ."][rawValue]
    }
}
struct VineGrowth:Equatable{
    let days:Int
    init(days:Int){self.days=max(0,days)}
    var stage:VineGrowthStage{VineGrowthStage.allCases.last(where:{$0.threshold<=days}) ?? .seed}
    var next:VineGrowthStage?{VineGrowthStage(rawValue:stage.rawValue+1)}
    var progress:Double{
        guard let next else{return 1}
        return Double(days-stage.threshold)/Double(next.threshold-stage.threshold)
    }
    var maturity:Double{(Double(stage.rawValue)+progress)/6}
    var leafDensity:Double{0.18+0.98*maturity}
    var leafScale:Double{0.47+0.53*maturity}
    var stemScale:Double{0.52+0.48*maturity}
    var flowerScale:Double{stage.rawValue>=VineGrowthStage.blooming.rawValue ? 0.58+0.42*progress:0}
    var bloomEvery:Int{stage == .mature ? 3:5}
    var hasBuds:Bool{stage.rawValue>=VineGrowthStage.budding.rawValue}
    var hasBranches:Bool{stage.rawValue>=VineGrowthStage.young.rawValue}
    var hasFlowers:Bool{stage.rawValue>=VineGrowthStage.blooming.rawValue}
}
struct VineGrowthCard:View{
    @ObservedObject var life:LifeArchive
    @State private var details=false
    private var growth:VineGrowth{VineGrowth(days:life.gardenDays)}
    var body:some View{
        Button{details=true}label:{
            HStack(spacing:12){
                VineRail(level:0,theme:.emerald,growth:growth).frame(width:38,height:68)
                VStack(alignment:.leading,spacing:5){
                    HStack{Text(growth.stage.title).font(.system(.headline,design:.serif));Spacer();Text("\(growth.days) ngày").font(.caption.monospacedDigit()).foregroundStyle(gold)}
                    Text(growth.stage.description).font(.caption2).foregroundStyle(.secondary)
                    if let next=growth.next{
                        ProgressView(value:growth.progress).tint(.green)
                        Text("\(max(0,next.threshold-growth.days)) ngày sử dụng nữa · \(next.title)").font(.caption2).foregroundStyle(.secondary)
                    }else{Text("Cây đã trưởng thành").font(.caption2).foregroundStyle(gold)}
                }
                Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(10).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).sheet(isPresented:$details){VineEvolutionView(life:life)}
    }
}
struct VineEvolutionView:View{
    @ObservedObject var life:LifeArchive
    @Environment(\.dismiss) private var dismiss
    @AppStorage("timeline.vine.theme") private var themeValue=VineTheme.emerald.rawValue
    private var growth:VineGrowth{VineGrowth(days:life.gardenDays)}
    var body:some View{
        NavigationStack{
            ScrollView{
                VStack(alignment:.leading,spacing:18){
                    Text("Ký ức lớn lên cùng bạn").font(.system(size:30,design:.serif))
                    Text("Mỗi ngày bạn thực sự mở và sử dụng VieLens được tính một lần. Không cần đăng nhập, không cần dùng liên tục. Cây không héo hay mất cấp khi bạn nghỉ.").font(.subheadline).foregroundStyle(.secondary)
                    HStack{
                        VineRail(level:2,theme:VineTheme(rawValue:themeValue) ?? .emerald,useCustom:true,growth:growth).frame(width:80,height:150)
                        VStack(alignment:.leading,spacing:8){Text(growth.stage.title).font(.system(.title,design:.serif));Text("\(growth.days) ngày sử dụng").font(.caption).foregroundStyle(gold);Text(growth.stage.description).font(.caption)}
                    }.padding().frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:16))
                    ForEach(VineGrowthStage.allCases){stage in
                        HStack(spacing:14){
                            VineRail(level:0,theme:VineTheme(rawValue:themeValue) ?? .emerald,growth:VineGrowth(days:stage.threshold)).frame(width:42,height:90)
                            VStack(alignment:.leading,spacing:5){Text(stage.title).font(.headline);Text(stage.threshold==0 ? "Bắt đầu":"\(stage.threshold) ngày sử dụng").font(.caption).foregroundStyle(gold);Text(stage.description).font(.caption2).foregroundStyle(.secondary)}
                            Spacer()
                            if stage.threshold<=growth.days{Image(systemName:"checkmark.circle.fill").foregroundStyle(.green)}else{Image(systemName:"lock").foregroundStyle(.secondary)}
                        }.padding(10).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
                    }
                    Text("Đổi bộ dây leo không làm mất tuổi cây. Các ngày sử dụng được lưu trên máy và nằm trong bản sao lưu Life.").font(.caption).foregroundStyle(.secondary)
                    if let issue=life.issue{Text(issue).font(.caption).foregroundStyle(.secondary)}
                }.padding(18)
            }.navigationTitle("Vine Evolution").navigationBarTitleDisplayMode(.inline).toolbar{Button("Xong"){dismiss()}}
        }
    }
}
