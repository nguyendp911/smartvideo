import SwiftUI

struct ArchiveCalendar:View {
    let shots:[Shot]
    let vault:Vault
    let select:(String)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var month=Date()
    private var calendar:Calendar {var c=Calendar(identifier:.gregorian);c.firstWeekday=2;return c}
    private var formatter:DateFormatter {let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.calendar=calendar;f.dateFormat="yyyy-MM-dd";return f}
    private var start:Date {calendar.date(from:calendar.dateComponents([.year,.month],from:month)) ?? month}
    private var days:[Int] {
        let offset=(calendar.component(.weekday,from:start)+5)%7
        let count=calendar.range(of:.day,in:.month,for:start)?.count ?? 0
        return Array(repeating:0,count:offset)+Array(1...max(1,count))
    }
    var body:some View {
        NavigationStack {
            ScrollView {
                HStack {
                    Button {month=calendar.date(byAdding:.month,value:-1,to:start) ?? month} label:{Image(systemName:"chevron.left").frame(width:44,height:44)}
                    Spacer()
                    Text("Tháng \(calendar.component(.month,from:month)), \(calendar.component(.year,from:month))").font(.system(.title2,design:.serif))
                    Spacer()
                    Button {month=calendar.date(byAdding:.month,value:1,to:start) ?? month} label:{Image(systemName:"chevron.right").frame(width:44,height:44)}
                }
                let groups=Dictionary(grouping:shots,by:\.day)
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:3),count:7),spacing:4){
                    ForEach(["T2","T3","T4","T5","T6","T7","CN"],id:\.self){Text($0).font(.caption).foregroundStyle(.secondary)}
                    ForEach(days.indices,id:\.self){i in
                        let day=days[i]
                        if day==0 {Color.clear.frame(height:54)}
                        else {
                            let date=calendar.date(byAdding:.day,value:day-1,to:start) ?? start
                            let key=formatter.string(from:date), items=groups[key] ?? []
                            Button {select(key)} label:{
                                ZStack {
                                    Color.white.opacity(0.045)
                                    if let shot=items.first {DiskImage(url:vault.thumbnail(shot.id),limit:140).scaledToFill().frame(height:54).clipped().overlay(Color.black.opacity(0.42))}
                                    VStack(spacing:3){
                                        Text("\(day)").font(.subheadline.weight(.semibold))
                                        Text(items.isEmpty ? " " : "\(items.count) ảnh").font(.system(size:9)).lineLimit(1)
                                    }.foregroundStyle(.white)
                                }.frame(height:54).clipShape(RoundedRectangle(cornerRadius:7))
                            }.buttonStyle(.plain).disabled(items.isEmpty)
                        }
                    }
                }
                Button("Về tháng hiện tại"){month=Date()}.padding()
                Text("Chạm vào ngày có ảnh để mở dòng thời gian.").font(.caption).foregroundStyle(.secondary)
            }.padding(14).navigationTitle("Lịch khoảnh khắc").navigationBarTitleDisplayMode(.inline).toolbar{Button("Đóng"){dismiss()}}
        }
    }
}
struct ArchiveSlideshow:View {
    let shots:[Shot]
    let vault:Vault
    @Environment(\.dismiss) private var dismiss
    var body:some View{
        ZStack{
            Color.black.ignoresSafeArea()
            VStack(spacing:0){
                HStack{
                    Text("V I E L E N S   /   M O T I O N").font(.caption2.monospaced()).foregroundStyle(gold)
                    Spacer()
                    Button{dismiss()}label:{Image(systemName:"xmark.circle.fill").font(.title2).padding(8)}
                }.padding(.horizontal,16)
                Spacer(minLength:0)
                TimelineSlideStage(shots:shots,vault:vault)
                Spacer(minLength:0)
            }
        }
    }
}
