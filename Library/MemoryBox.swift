import SwiftUI

struct MemoryBoxView:View{
    let shots:[Shot];let vault:Vault
    @ObservedObject private var archive=StoryArchive.shared
    @ObservedObject private var life=LifeArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var creature:MemoryCreature?
    @State private var selectedDay:String?
    @State private var echo:StoryEntry?
    @State private var listening=false
    @State private var letters=false
    private var days:[String]{MemorySync.activeDays(shots:shots,stories:archive,life:life).union(life.data.letters.map{LifeDate.key($0.opens)}).sorted(by:>)}
    private var byCreature:[MemoryCreature:[String]]{
        var result:[MemoryCreature:[String]]=[:]
        let grouped=Dictionary(grouping:shots,by:\.day)
        for day in days{
            let dna=MemoryDNA.day(day,shots:grouped[day] ?? [],archive:archive,life:life)
            for item in dna.creatures{result[item,default:[]].append(day)}
        }
        return result
    }
    var body:some View{
        NavigationStack{ScrollView{
            VStack(alignment:.leading,spacing:15){
                Text("Hộp ký ức").font(.system(size:32,design:.serif))
                Text("Mỗi vật phẩm gắn với những ngày bạn thực sự lưu giữ một điều đáng nhớ. Không mua điểm hay mất vật phẩm khi nghỉ.").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10){
                    ForEach(MemoryCreature.allCases){item in
                        let count=byCreature[item]?.count ?? 0
                        Button{if item == .key{letters=true}else{creature=item;selectedDay=nil}}label:{
                            VStack(spacing:8){
                                if let name=item.asset{Image(name).resizable().scaledToFit().frame(width:90,height:95).opacity(count>0 ? 1:0.3)}
                                Text(item.rawValue).font(.system(.headline,design:.serif))
                                Text(count>0 ? "\(count) ngày":"Chưa mở").font(.caption).foregroundStyle(count>0 ? gold:.secondary)
                            }.frame(maxWidth:.infinity).padding(12).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:14))
                        }.buttonStyle(.plain).disabled(count==0)
                    }
                }
                Button("Memory Echo · nghe lại một lời kể",systemImage:"waveform"){echo=archive.entries.values.filter{$0.audio != nil}.randomElement();listening=echo != nil}.disabled(!archive.entries.values.contains{$0.audio != nil})
            }.padding()
        }.navigationTitle("Memory Box").toolbar{Button("Đóng"){dismiss()}}}
        .sheet(item:$creature){item in NavigationStack{List{
            ForEach(byCreature[item] ?? [],id:\.self){day in NavigationLink(TimelineIndex.label(day)){MemoryCreatureReader(creature:item,day:day,shots:shots,vault:vault)}}
        }.navigationTitle(item.rawValue).toolbar{Button("Xong"){creature=nil}}}}
        .sheet(isPresented:$listening){if let audio=echo?.audio{VoiceHighlightView(audio:audio)}}
        .sheet(isPresented:$letters){FutureLetterStudio(life:life)}
    }
}
