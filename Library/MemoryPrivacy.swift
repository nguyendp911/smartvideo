import SwiftUI
import LocalAuthentication
import CryptoKit
import Security
import UIKit

/// Separate encrypted correspondence; never written into public StoryArchive.
private enum LetterCrypt{
    static var folder:URL{FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("VieLensSecretLetters",isDirectory:true)}
    static func files()->[URL]{((try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? []).filter{$0.pathExtension=="letter"}.sorted{$0.lastPathComponent<$1.lastPathComponent}}
    static func key(_ context:LAContext)throws->SymmetricKey{
        let base:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.nguyendp911.smartvideo.letters",kSecAttrAccount as String:"aes256-v1"]
        var q=base;q[kSecReturnData as String]=true;q[kSecUseAuthenticationContext as String]=context
        var result:CFTypeRef?
        let status=SecItemCopyMatching(q as CFDictionary,&result)
        if status==errSecSuccess,let data=result as? Data,data.count==32{return SymmetricKey(data:data)}
        guard status==errSecItemNotFound,files().isEmpty else{throw CameraError.unreadable}
        guard let access=SecAccessControlCreateWithFlags(nil,kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,.userPresence,nil) else{throw CameraError.writeFailed}
        let key=SymmetricKey(size:.bits256);var add=base;add[kSecAttrAccessControl as String]=access;add[kSecValueData as String]=key.withUnsafeBytes{Data($0)}
        guard SecItemAdd(add as CFDictionary,nil)==errSecSuccess else{throw CameraError.writeFailed}
        return key
    }
    struct Letter:Codable{let title:String;let text:String;let date:Date}
    static func save(_ letter:Letter,key:SymmetricKey)throws{
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.complete])
        guard let encrypted=try AES.GCM.seal(JSONEncoder().encode(letter),using:key).combined else{throw CameraError.writeFailed}
        try encrypted.write(to:folder.appendingPathComponent(UUID().uuidString+".letter"),options:[.atomic,.completeFileProtection])
    }
    static func read(_ url:URL,key:SymmetricKey)throws->Letter{try JSONDecoder().decode(Letter.self,from:AES.GCM.open(AES.GCM.SealedBox(combined:Data(contentsOf:url)),using:key))}
}
struct SecretLetterView:View{
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var key:SymmetricKey?
    @State private var files:[URL]=[]
    @State private var title=""
    @State private var bodyText=""
    @State private var opened:LetterCrypt.Letter?
    @State private var notice=""
    @State private var generation=UUID()
    @State private var busy=false
    @State private var deleteURL:URL?
    var body:some View{
        NavigationStack{List{
            if let key{
                Section("Lá thư mới"){
                    TextField("Tiêu đề",text:$title)
                    TextEditor(text:$bodyText).frame(minHeight:130)
                    Button("Niêm phong mã hóa",systemImage:"envelope.fill"){do{try LetterCrypt.save(.init(title:title,text:bodyText,date:Date()),key:key);title="";bodyText="";files=LetterCrypt.files();notice="Đã mã hóa."}catch{notice=error.localizedDescription}}.disabled(title.isEmpty || bodyText.isEmpty)
                }
                Section("Phong thư"){
                    ForEach(files,id:\.self){url in
                        Button{do{opened=try LetterCrypt.read(url,key:key)}catch{notice=error.localizedDescription}}label:{Label("Thư "+String(url.deletingPathExtension().lastPathComponent.prefix(8)),systemImage:"lock.doc")}.swipeActions{Button("Xóa",role:.destructive){deleteURL=url}}
                    }
                    if let opened{VStack(alignment:.leading,spacing:14){Image(systemName:"envelope.open.fill").font(.largeTitle).foregroundStyle(gold);Text(opened.title).font(.system(.title,design:.serif));Text(opened.text).font(.system(.body,design:.serif)).lineSpacing(8);Button("Gấp thư"){self.opened=nil}}.padding()}
                }
                Button("Khóa lại"){lock()}
            }else{Button("Mở bằng Face ID / mật mã",systemImage:"lock.shield"){unlock()}.disabled(busy)}
            Text("Thư AES-GCM độc lập với story công khai. Khóa gắn với mật mã thiết bị, không nằm trong backup. Không chuyển story công khai vào kho này tự động.").font(.caption).foregroundStyle(.secondary)
            Text(notice).font(.caption)
        }.navigationTitle("Secret Letter").toolbar{Button("Đóng"){dismiss()}}}
        .confirmationDialog("Xóa vĩnh viễn thư mã hóa?",isPresented:Binding(get:{deleteURL != nil},set:{if !$0{deleteURL=nil}})){Button("Xóa",role:.destructive){if let url=deleteURL{do{try FileManager.default.removeItem(at:url);files=LetterCrypt.files();opened=nil}catch{notice=error.localizedDescription}};deleteURL=nil}}
        .onChange(of:phase){_,p in if p == .background{lock()}}.onDisappear{lock()}
    }
    private func lock(){generation=UUID();deleteURL=nil;key=nil;files=[];opened=nil;title="";bodyText="";notice="";busy=false}
    private func unlock(){
        let token=generation,context=LAContext();busy=true
        Task{do{
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication,localizedReason:"Mở thư riêng tư"),generation==token else{busy=false;return}
            let k=try await Task.detached(priority:.userInitiated){try LetterCrypt.key(context)}.value
            if generation==token{key=k;files=LetterCrypt.files()}
        }catch{if generation==token{notice=error.localizedDescription}}
        if generation==token{busy=false}}
    }
}
struct TimelineFocusView:View{
    let shots:[Shot];let vault:Vault
    @ObservedObject private var archive=StoryArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var target:StoryTarget?
    @State private var zoom=1.0
    @State private var showControls=false
    var body:some View{
        ScrollView{
            LazyVStack(spacing:24){
                ForEach(TimelineIndex.group(shots,period:.day,newest:true)){g in
                    HStack(alignment:.top,spacing:5){
                        VineRail(level:0,theme:.emerald,growth:VineGrowth(days:LifeArchive.shared.gardenDays)).frame(width:32)
                        VStack(alignment:.leading,spacing:12){
                            Text(TimelineIndex.label(g.key)).font(.system(.title3,design:.serif)).foregroundStyle(gold)
                            ForEach(g.items){s in Button{target = .photo(s)}label:{
                                VStack(alignment:.leading){DiskImage(url:vault.picture(s),limit:1400).scaledToFit().clipShape(RoundedRectangle(cornerRadius:10));if let e=archive.entry(StoryTarget.photo(s).id){Text(e.title).font(.system(.headline,design:.serif));Text(e.body).font(.caption)}}
                            }.buttonStyle(.plain)}
                            if let e=archive.entry("period:"+g.key){Button{target = .group(g)}label:{Text(e.title+"\n"+e.body).font(.system(.body,design:.serif)).lineSpacing(5)}.buttonStyle(.plain)}
                        }
                    }
                }
            }.padding(12).padding(.top,30).scaleEffect(zoom,anchor:.top)
        }.background(night).overlay(alignment:.topTrailing){Button{dismiss()}label:{Image(systemName:"xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.65)).padding(16)}}
        .simultaneousGesture(MagnifyGesture().onChanged{v in zoom=max(0.85,min(1.15,v.magnification))}.onEnded{_ in withAnimation{zoom=1}})
        .sheet(item:$target){LifeStorySheet(target:$0,vault:vault,archive:archive)}
    }
}
