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
    @State private var index=0
    @State private var playing=true
    @State private var interval=3
    var body:some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if shots.indices.contains(index) {
                let shot=shots[index]
                DiskImage(url:vault.picture(shot),limit:1800).scaledToFit().id(shot.id).transition(.opacity)
                VStack {
                    HStack {
                        Button{dismiss()} label:{Image(systemName:"xmark.circle.fill").font(.title)}
                        Spacer()
                        Menu {ForEach([2,3,5,8],id:\.self){n in Button("\(n) giây"){interval=n}}} label:{Label("\(interval)s",systemImage:"timer")}
                    }.padding(20)
                    Spacer()
                    VStack(spacing:10){
                        Text(TimelineIndex.label(shot.day)).font(.system(.title2,design:.serif))
                        Text(shot.note ?? shot.session).font(.caption).lineLimit(2)
                        HStack(spacing:32){
                            Button{advance(-1)} label:{Image(systemName:"backward.fill")}
                            Button{playing.toggle()} label:{Image(systemName:playing ? "pause.fill":"play.fill")}
                            Button{advance(1)} label:{Image(systemName:"forward.fill")}
                        }.font(.title2)
                        Text("\(index+1) / \(shots.count)").font(.caption.monospacedDigit())
                    }.padding(20).frame(maxWidth:.infinity).background(.black.opacity(0.68))
                }
            } else {Button("Đóng"){dismiss()}}
        }.task(id:"\(playing)-\(interval)"){
            guard playing,shots.count>1 else{return}
            while !Task.isCancelled {
                do {try await Task.sleep(for:.seconds(interval))}catch{return}
                if !Task.isCancelled {advance(1)}
            }
        }
    }
    private func advance(_ amount:Int){guard !shots.isEmpty else{return};withAnimation(.easeInOut(duration:0.35)){index=(index+amount+shots.count)%shots.count}}
}
