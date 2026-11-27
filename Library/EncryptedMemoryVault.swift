import SwiftUI
import LocalAuthentication
import CryptoKit
import Security

private enum SecureMemoryError:LocalizedError{
    case keychain(OSStatus),access,invalid
    var errorDescription:String?{
        switch self{case .keychain(let code):return "Keychain: \(code)";case .access:return "Thiết bị chưa hỗ trợ xác thực.";case .invalid:return "Không đọc được bản sao mã hóa."}
    }
}
private enum SecureMemoryStorage{
    static var folder:URL{FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("VieLensPrivate",isDirectory:true)}
    static func key(context:LAContext)throws->SymmetricKey{
        let base:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.nguyendp911.smartvideo.private",kSecAttrAccount as String:"aes256-v1"]
        var query=base
        query[kSecReturnData as String]=true
        query[kSecUseAuthenticationContext as String]=context
        var result:CFTypeRef?
        let status=SecItemCopyMatching(query as CFDictionary,&result)
        if status==errSecSuccess,let data=result as? Data,data.count==32{return SymmetricKey(data:data)}
        guard status==errSecItemNotFound else{throw SecureMemoryError.keychain(status)}
        // Never silently replace a missing key when encrypted files already exist.
        if !files().isEmpty{throw SecureMemoryError.invalid}
        let key=SymmetricKey(size:.bits256)
        guard let access=SecAccessControlCreateWithFlags(nil,kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,.userPresence,nil) else{throw SecureMemoryError.access}
        var add=base
        add[kSecAttrAccessControl as String]=access
        add[kSecValueData as String]=key.withUnsafeBytes{Data($0)}
        let saved=SecItemAdd(add as CFDictionary,nil)
        guard saved==errSecSuccess else{throw SecureMemoryError.keychain(saved)}
        return key
    }
    static func files()->[URL]{
        ((try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? []).filter{$0.pathExtension=="vlenc"}.sorted{$0.lastPathComponent<$1.lastPathComponent}
    }
    static func copy(_ source:URL,key:SymmetricKey)throws{
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.complete])
        let data=try Data(contentsOf:source,options:.mappedIfSafe)
        guard let encrypted=try AES.GCM.seal(data,using:key).combined else{throw SecureMemoryError.invalid}
        try encrypted.write(to:folder.appendingPathComponent(UUID().uuidString+".vlenc"),options:[.atomic,.completeFileProtection])
    }
    static func open(_ url:URL,key:SymmetricKey)throws->Data{
        try AES.GCM.open(AES.GCM.SealedBox(combined:Data(contentsOf:url)),using:key)
    }
}
struct EncryptedMemoryVault:View{
    let shots:[Shot]
    let vault:Vault
    @Environment(\.scenePhase) private var phase
    @State private var key:SymmetricKey?
    @State private var files=[URL]()
    @State private var preview:UIImage?
    @State private var notice=""
    @State private var working=false
    @State private var deletion:URL?
    @State private var generation=UUID()
    var body:some View{
        VStack(spacing:14){
            if let key{
                HStack{Text("\(files.count) bản sao mã hóa");Spacer();Button("Khóa"){lock()}}.padding(.horizontal)
                Button("Sao chép mã hóa \(shots.count) ảnh"){
                    working=true;notice=""
                    let items=shots,v=vault,token=generation
                    Task{
                        let count=await Task.detached(priority:.utility){()->Int in
                            var n=0
                            for shot in items{do{try SecureMemoryStorage.copy(v.picture(shot,original:true),key:key);n+=1}catch{}}
                            return n
                        }.value
                        if token==generation{files=SecureMemoryStorage.files();notice="Đã tạo \(count)/\(items.count) bản sao.";working=false}
                    }
                }.buttonStyle(.borderedProminent).disabled(working || shots.isEmpty)
                if working{ProgressView()}
                List{
                    ForEach(files,id:\.self){url in
                        Button{
                            let token=generation
                            Task{
                                let data=await Task.detached(priority:.utility){try? SecureMemoryStorage.open(url,key:key)}.value
                                if token==generation{preview=data.flatMap{UIImage(data:$0)};if preview==nil{notice="Không đọc được bản sao."}}
                            }
                        }label:{Label("Ảnh mã hóa \(url.lastPathComponent.prefix(8))",systemImage:"lock.doc")}
                        .swipeActions{Button(role:.destructive){deletion=url}label:{Label("Xóa",systemImage:"trash")}}
                    }
                }
                if let preview{Image(uiImage:preview).resizable().scaledToFit().frame(maxHeight:240).onTapGesture{self.preview=nil}}
            }else{
                Spacer()
                Image(systemName:"lock.shield").font(.system(size:62,weight:.light)).foregroundStyle(gold)
                Text("Private Vault").font(.system(.largeTitle,design:.serif))
                Button("Mở bằng Face ID / mật mã"){unlock()}.buttonStyle(.borderedProminent).disabled(working)
                Spacer()
            }
            Text("Chỉ tạo bản sao mã hóa AES-GCM. Ảnh gốc vẫn nằm trong Timeline. Khóa gắn với thiết bị, không nằm trong sao lưu VieLens; không xóa ảnh gốc nếu chưa có bản sao lưu độc lập.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            Text(notice).font(.caption).padding(.bottom,8)
        }.navigationTitle("Private Vault").navigationBarTitleDisplayMode(.inline)
        .onChange(of:phase){_,p in if p == .background{lock()}}
        .onDisappear{lock()}
        .confirmationDialog("Xóa bản sao mã hóa?",isPresented:Binding(get:{deletion != nil},set:{if !$0{deletion=nil}})){
            Button("Xóa",role:.destructive){if let deletion{do{try FileManager.default.removeItem(at:deletion);files=SecureMemoryStorage.files();preview=nil}catch{notice=error.localizedDescription}};deletion=nil}
        }
    }
    private func lock(){generation=UUID();key=nil;preview=nil;files=[];working=false;notice=""}
    private func unlock(){
        let context=LAContext()
        var error:NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication,error:&error) else{notice=error?.localizedDescription ?? "Chưa bật mật mã.";return}
        working=true
        let token=generation
        Task{
            do{
                let success=try await context.evaluatePolicy(.deviceOwnerAuthentication,localizedReason:"Mở kho ký ức VieLens")
                guard success,token==generation else{working=false;return}
                let unlocked=try await Task.detached(priority:.userInitiated){try SecureMemoryStorage.key(context:context)}.value
                if token==generation{key=unlocked;files=SecureMemoryStorage.files();notice=""}
            }catch{if token==generation{notice=error.localizedDescription}}
            if token==generation{working=false}
        }
    }
}
