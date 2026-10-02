import SwiftUI

struct AssistantPanel:View {
    @EnvironmentObject var store:EditorStore
    @EnvironmentObject var account:ChatGPTAccount
    @AppStorage("aiEndpoint") private var endpoint=""
    @AppStorage("aiProvider") private var provider="chatgpt"
    @State private var prompt=""
    @State private var connect=false
    @State private var working=false
    @State private var note=""
    @State private var requestTask:Task<Void,Never>?
    private var ready:Bool {provider=="gateway" ? !endpoint.isEmpty && !SecureSettings.token().isEmpty : account.isConnected}
    var body:some View {
        ToolCanvas(title:"مساعد المونتاج",subtitle:"فكرتك بالكلام. تعديلات على التايملاين.") {
            VStack(alignment:.leading,spacing:21) {
                Button {connect=true} label: {
                    HStack(spacing:12) { Image(systemName:"sparkles").font(.system(size:23)).foregroundStyle(VTheme.mint); VStack(alignment:.leading,spacing:4) { Text(provider=="gateway" ? "OpenAI API" : "ChatGPT").font(.system(size:14,weight:.semibold)); Text(ready ? "إعداد الاتصال متوفر" : "اربط حسابك لتبدأ").font(.system(size:11)).foregroundStyle(VTheme.muted) };Spacer();TinyBadge(text:ready ? "CONFIGURED":"CONNECT",color:ready ? VTheme.mint:VTheme.lavender);Image(systemName:"chevron.right").font(.caption).foregroundStyle(VTheme.muted) }.padding(17).background(VTheme.surface,in:RoundedRectangle(cornerRadius:18))
                }.buttonStyle(.plain)
                if provider=="chatgpt",!account.models.isEmpty {
                    Picker("النموذج",selection:$account.model) {ForEach(account.models) {Text($0.name).tag($0.id)}}.tint(.white).onChange(of:account.model) {_,model in UserDefaults.standard.set(model,forKey:"chatgptModel")}
                }
                if let plan=store.pendingPlan {
                    planCard(plan)
                } else {
                    Text("ماذا تريد أن تغيّر؟").font(.system(size:23,weight:.bold))
                    TextField("مثال: اجعل العنوان أحمر وأضف حركة تكبير ناعمة…",text:$prompt,axis:.vertical).font(.system(size:16)).lineLimit(4...7).padding(19).background(VTheme.surface,in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(VTheme.line))
                    HStack(spacing:8) {
                        suggestion("هوك أقوى","كبّر أول عنوان موجود واجعله أحمر مع حركة pop. لا تغيّر كلمات النص.")
                        suggestion("ألوان سينمائية","عدّل إضاءة وتباين وتشبع مقاطع الفيديو بشكل سينمائي خفيف.")
                    }
                    if working {
                        HStack {ProgressView().tint(VTheme.mint);Text("ChatGPT يجهّز التعديلات…").font(.caption);Spacer();Button("إلغاء") {requestTask?.cancel()}}.padding(16)
                    } else {
                        Button { if ready {send()} else {connect=true} } label:{Label(ready ? "جهّز خطة المونتاج":"ربط ChatGPT",systemImage:"sparkles").frame(maxWidth:.infinity)}.buttonStyle(VButton(prominent:true)).disabled(prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && ready)
                    }
                }
                if !note.isEmpty {Text(note).font(.caption).foregroundStyle(VTheme.mint)}
                HStack(alignment:.top,spacing:8) {Image(systemName:"lock.shield").foregroundStyle(VTheme.muted);Text("ترسل بيانات الطبقات والنصوص فقط. تراجع التعديلات قبل تطبيقها، ويمكنك التراجع عنها.").font(.system(size:11)).foregroundStyle(VTheme.muted)}
                ShareLink(item:store.projectJSON()) {Label("مشاركة بيانات المشروع",systemImage:"square.and.arrow.up")}.font(.caption).foregroundStyle(VTheme.muted)
            }
        }.sheet(isPresented:$connect) {ConnectionPanel()}.onDisappear {requestTask?.cancel()}
            .task {if provider=="chatgpt",account.isConnected,account.models.isEmpty {try? await account.loadModels()}}
    }
    private func suggestion(_ title:String,_ text:String)->some View {Button {prompt=text} label:{Text(title).font(.system(size:11,weight:.medium)).padding(.horizontal,13).padding(.vertical,10).background(VTheme.elevated,in:Capsule())}.foregroundStyle(VTheme.muted)}
    private func planCard(_ plan:EditPlan)->some View {
        VStack(alignment:.leading,spacing:17) {
            HStack {TinyBadge(text:"EDIT PLAN");Spacer();Text("\(plan.operations.count) تعديل").font(.caption).foregroundStyle(VTheme.muted)}
            Text(plan.summary).font(.system(size:15,weight:.medium)).lineSpacing(5)
            ForEach(Array(plan.operations.enumerated()),id:\.offset) { index,op in
                HStack(alignment:.top,spacing:12) {Text(String(format:"%02d",index+1)).font(.system(size:10,design:.monospaced)).foregroundStyle(VTheme.mint).padding(.top,3);VStack(alignment:.leading,spacing:4) {Text(operationTitle(op)).font(.system(size:12,weight:.semibold));Text(op.text ?? op.number.map {String(format:"%.2f",$0)} ?? "").font(.system(size:11)).foregroundStyle(VTheme.muted).lineLimit(3)}}
            }
            HStack {Button("تجاهل") {store.pendingPlan=nil}.buttonStyle(VButton());Button {store.applyPlan();if store.error==nil {note="تم تطبيق الخطة. يمكنك التراجع من المحرّر."}} label:{Text("تطبيق التعديلات").frame(maxWidth:.infinity)}.buttonStyle(VButton(prominent:true))}.disabled(plan.operations.isEmpty)
        }.padding(20).background(VTheme.surface,in:RoundedRectangle(cornerRadius:22))
    }
    private func operationTitle(_ op:EditOperation)->String {
        let layer=store.project.clips.first {$0.id.uuidString.lowercased()==op.clipID?.lowercased()}?.name ?? "طبقة"
        switch op.action {case "addText":return "إضافة نص";case "remove":return "حذف \(layer)";case "keyframe":return "تحريك \(layer) · \(op.property ?? "")";default:return "\(layer) · \(op.property ?? "تعديل")"}
    }
    private func send() {
        guard !working else{return};working=true;note=""
        let snapshot=store.project
        requestTask=Task { @MainActor in
            defer {working=false}
            do {
                let plan:EditPlan
                if provider=="gateway" {plan=try await AIClient.plan(prompt:prompt,project:snapshot,endpoint:endpoint,token:SecureSettings.token())}
                else {
                    if account.models.isEmpty {try await account.loadModels()}
                    plan=try await AIClient.chatGPT(prompt:prompt,project:snapshot,model:account.model,accessToken:try await account.accessToken())
                }
                try Task.checkCancellation()
                guard store.project==snapshot else {throw EditError.invalid("تغيّر المشروع أثناء الطلب. أعد تجهيز الخطة.")}
                store.pendingPlan=plan
            } catch is CancellationError {note="أُلغي الطلب"} catch {store.error=error.localizedDescription}
        }
    }
}
struct ConnectionPanel:View {
    @EnvironmentObject var account:ChatGPTAccount
    @EnvironmentObject var store:EditorStore
    @AppStorage("aiProvider") private var provider="chatgpt"
    @AppStorage("aiEndpoint") private var endpoint=""
    @State private var token=SecureSettings.token()
    @State private var testing=false
    @State private var message=""
    var body:some View {
        ToolCanvas(title:"اتصال الذكاء",subtitle:"ChatGPT داخل مساحة المونتاج") {
            VStack(alignment:.leading,spacing:23) {
                Picker("الاتصال",selection:$provider) {Text("ChatGPT").tag("chatgpt");Text("خادم API").tag("gateway")}.pickerStyle(.segmented)
                if provider=="chatgpt" {
                    VStack(alignment:.leading,spacing:15) {
                        Image(systemName:"sparkles").font(.system(size:33,weight:.light)).foregroundStyle(VTheme.mint)
                        Text(account.isConnected ? "حسابك متصل":"منتجك. ومعه مساعد.").font(.system(size:26,weight:.bold))
                        Text(account.session?.email ?? "سجّل الدخول بحساب ChatGPT وامنح vidioi صلاحية تجهيز تعديلات الفيديو.").font(.system(size:13)).foregroundStyle(VTheme.muted).lineSpacing(4)
                    }.padding(23).frame(maxWidth:.infinity,alignment:.leading).background(VTheme.surface,in:RoundedRectangle(cornerRadius:22))
                    if account.connecting {HStack {ProgressView();Text(account.message).font(.caption);Spacer();Button("إلغاء") {account.cancel()}}}
                    else {
                        Button {account.signIn()} label:{Text("Continue with ChatGPT").font(.system(size:15,weight:.semibold)).frame(maxWidth:.infinity).frame(height:52).foregroundStyle(.black).background(.white,in:Capsule())}.accessibilityIdentifier("chatgptSignIn")
                    }
                    if account.isConnected {
                        Button {testing=true;Task {defer{testing=false};do{try await account.loadModels()}catch{message=error.localizedDescription}}} label:{Label("اختبار الاتصال وجلب النماذج",systemImage:"checkmark.shield").frame(maxWidth:.infinity)}.buttonStyle(VButton()).disabled(testing)
                        if !account.models.isEmpty {Picker("النموذج",selection:$account.model) {ForEach(account.models) {Text($0.name).tag($0.id)}}.onChange(of:account.model) {_,value in UserDefaults.standard.set(value,forKey:"chatgptModel")}}
                        Button("فصل الحساب من الجهاز",role:.destructive) {account.signOut()}.font(.caption)
                    }
                    if !account.message.isEmpty {Text(account.message).font(.caption).foregroundStyle(VTheme.muted)}
                    Text("يخضع استخدام خطة ChatGPT لتوفر الميزة وصلاحيات حسابك. لا يمنح الاتصال وصولًا إلى محادثاتك السابقة.").font(.system(size:11)).foregroundStyle(VTheme.muted)
                } else {
                    Text("OpenAI API عبر خادمك").font(.title3.bold())
                    TextField("https://your-server.example",text:$endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).padding(17).background(VTheme.surface,in:RoundedRectangle(cornerRadius:14))
                    SecureField("رمز اتصال vidioi",text:$token).padding(17).background(VTheme.surface,in:RoundedRectangle(cornerRadius:14))
                    Button {testing=true;Task {defer{testing=false};do {try SecureSettings.save(token:token);message=try await AIClient.testGateway(endpoint:endpoint,token:token)}catch{message=error.localizedDescription}}} label:{Label("حفظ واختبار الاتصال",systemImage:"bolt.horizontal").frame(maxWidth:.infinity)}.buttonStyle(VButton(prominent:true)).disabled(testing)
                    Text("مفتاح OpenAI يبقى على الخادم. الحقل أعلاه لرمز اتصال التطبيق فقط.").font(.caption).foregroundStyle(VTheme.muted)
                }
                if testing {ProgressView().tint(VTheme.mint)}
                if !message.isEmpty {Text(message).font(.caption).foregroundStyle(VTheme.mint)}
            }
        }
    }
}
