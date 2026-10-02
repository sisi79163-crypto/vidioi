import SwiftUI

struct ToolCanvas<Content:View>: View {
    var title:String
    var subtitle:String
    @ViewBuilder var content:Content
    @EnvironmentObject var store:EditorStore
    var body:some View {
        VStack(spacing:0) { SheetHeader(title:title,subtitle:subtitle); ScrollView { content.padding(.horizontal,22).padding(.bottom,35) } }
            .frame(maxWidth:.infinity,maxHeight:.infinity).background(VTheme.background)
            .alert("vidioi",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error=nil}})) { Button("حسنًا") { store.error=nil } } message: { Text(store.error ?? "") }
    }
}
struct InspectorPanel:View {
    @EnvironmentObject var store:EditorStore
    @State private var section = 0
    var body:some View {
        ToolCanvas(title:"تفاصيل اللقطة",subtitle:store.selectedClip?.name ?? "اختر عنصرًا من التايملاين") {
            if let clip=store.selectedClip {
                VStack(spacing:22) {
                    Picker("أدوات",selection:$section) { Text("تحويل").tag(0); Text("توقيت").tag(1); Text(clip.kind == .text ? "النص" : "ألوان").tag(2) }.pickerStyle(.segmented)
                    if section == 0 {
                        control("الحجم",key: \LayerStyle.scale,range:0.05...4,suffix:"×")
                        control("التمدد",key: \LayerStyle.stretch,range:0.1...3,suffix:"×")
                        HStack(spacing:18) { control("أفقي",key: \LayerStyle.x,range:0...1); control("عمودي",key: \LayerStyle.y,range:0...1) }
                        control("الدوران",key: \LayerStyle.rotation,range:-180...180,suffix:"°")
                        control("الشفافية",key: \LayerStyle.opacity,range:0...1)
                        HStack { Button("توسيط") { store.updateSelected {$0.style.x=0.5;$0.style.y=0.5} }; Spacer(); Button("إعادة التحويل") { store.updateSelected { c in c.style.x=0.5;c.style.y=0.5;c.style.scale=1;c.style.stretch=1;c.style.rotation=0;c.style.opacity=1 } } }.font(.caption).foregroundStyle(VTheme.mint)
                    } else if section == 1 {
                        timing("البداية",key: \Clip.start,range:0...max(60,store.project.length))
                        timing("المدة",key: \Clip.duration,range:0.05...max(60,clip.duration))
                        if clip.kind == .video || clip.kind == .audio {
                            NumericSlider(label:"السرعة",value:Binding(get:{store.selectedClip?.speed ?? 1},set:{store.setSelectedSpeed($0)}),range:0.25...4,suffix:"×")
                            timing("مستوى الصوت",key: \Clip.volume,range:0...2)
                        }
                        Stepper("ترتيب الطبقة · \(clip.lane)",value:Binding(get:{store.selectedClip?.lane ?? 0},set:{n in store.updateSelected {$0.lane=n}}),in:0...31).font(.system(size:13))
                    } else if clip.kind == .text {
                        TextField("اكتب النص",text:Binding(get:{store.selectedClip?.text ?? ""},set:{value in store.updateSelected {$0.text=value;$0.name=String(value.prefix(30))}}),axis:.vertical).font(.system(size:23,weight:.bold)).padding(20).background(VTheme.surface,in:RoundedRectangle(cornerRadius:18)).lineLimit(2...6)
                        Picker("الخط",selection:Binding(get:{store.selectedClip?.style.fontName ?? "Arial-BoldMT"},set:{value in store.updateSelected {$0.style.fontName=value}})) { ForEach(store.fonts,id:\.self) { Text($0).tag($0) } }.tint(.white)
                        control("حجم الخط",key: \LayerStyle.fontSize,range:8...220)
                        HStack(spacing:15) { ForEach(["#FFFFFF","#C6FA73","#FF4646","#E6C46B","#68DDE5","#B8A4F7"],id:\.self) { hex in Button { store.updateSelected {$0.style.color=hex} } label: { Circle().fill(Color(hex:hex)).frame(width:32,height:32).overlay(Circle().stroke(.white.opacity(clip.style.color == hex ? 1 : 0),lineWidth:2).padding(-4)) } } }
                    } else {
                        control("الإضاءة",key: \LayerStyle.brightness,range:-1...1)
                        control("التباين",key: \LayerStyle.contrast,range:0...3)
                        control("التشبع",key: \LayerStyle.saturation,range:0...3)
                        HStack { Button("سينمائي") { store.updateSelected {$0.style.brightness = -0.04;$0.style.contrast=1.18;$0.style.saturation=0.85} }; Button("حيوي") { store.updateSelected {$0.style.brightness=0.03;$0.style.contrast=1.06;$0.style.saturation=1.3} }; Button("طبيعي") { store.updateSelected {$0.style.brightness=0;$0.style.contrast=1;$0.style.saturation=1} } }.buttonStyle(VButton())
                    }
                }
            } else { emptySelection }
        }
    }
    private func control(_ label:String,key:WritableKeyPath<LayerStyle,Double>,range:ClosedRange<Double>,suffix:String="")->some View {
        NumericSlider(label:label,value:Binding(get:{store.selectedClip?.style[keyPath:key] ?? 1},set:{n in store.updateSelected {$0.style[keyPath:key]=n}}),range:range,suffix:suffix)
    }
    private func timing(_ label:String,key:WritableKeyPath<Clip,Double>,range:ClosedRange<Double>)->some View {
        NumericSlider(label:label,value:Binding(get:{store.selectedClip?[keyPath:key] ?? range.lowerBound},set:{n in store.updateSelected {$0[keyPath:key]=n}}),range:range,suffix:"s")
    }
}
var emptySelection:some View { VStack(spacing:15) { Image(systemName:"square.3.layers.3d").font(.system(size:35,weight:.ultraLight)).foregroundStyle(VTheme.mint); Text("اختر طبقة من التايملاين").font(.headline); Text("أدوات هذه الطبقة ستظهر هنا.").font(.caption).foregroundStyle(VTheme.muted) }.frame(maxWidth:.infinity).padding(.vertical,50) }
struct NumericSlider:View {
    var label:String
    @Binding var value:Double
    var range:ClosedRange<Double>
    var suffix:String=""
    var body:some View {
        VStack(spacing:9) {
            HStack { Text(label).font(.system(size:13,weight:.medium)); Spacer(); HStack(spacing:2) { TextField("",value:$value,format:.number.precision(.fractionLength(2))).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).frame(width:64); Text(suffix) }.font(.system(size:12,weight:.medium,design:.monospaced)).foregroundStyle(VTheme.mint).padding(.horizontal,10).padding(.vertical,6).background(VTheme.surface,in:RoundedRectangle(cornerRadius:7)) }
            Slider(value:$value,in:range).tint(VTheme.mint)
        }
    }
}
struct MotionPanel:View {
    @EnvironmentObject var store:EditorStore
    var body:some View {
        ToolCanvas(title:"Motion studio",subtitle:"حركة دقيقة. إيقاع خاص بك.") {
            if let clip=store.selectedClip,clip.kind != .audio {
                VStack(alignment:.leading,spacing:24) {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                        ForEach(MotionPreset.allCases,id:\.self) { motion in
                            Button { store.updateSelected {$0.style.motion=motion} } label: {
                                VStack(spacing:17) { MotionPreview(motion:motion).frame(height:60); HStack { Text(motion.title).font(.system(size:13,weight:.medium)); Spacer(); Image(systemName:clip.style.motion == motion ? "checkmark.circle.fill" : "circle").foregroundStyle(clip.style.motion == motion ? VTheme.mint : VTheme.muted) } }.padding(18).background(VTheme.surface,in:RoundedRectangle(cornerRadius:19)).overlay(RoundedRectangle(cornerRadius:19).stroke(clip.style.motion == motion ? VTheme.mint.opacity(0.5) : VTheme.line))
                            }.buttonStyle(.plain)
                        }
                    }
                    SectionHeading(title:"Keyframes",detail:"\(clip.keys.count) POINTS")
                    Text("ضع المؤشر عند لحظة الحركة، أضف نقطة، ثم عدّل قيمتها.").font(.caption).foregroundStyle(VTheme.muted)
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:90))],spacing:8) { ForEach(AnimatedProperty.allCases,id:\.self) { property in Button { store.addKey(property) } label: { Label(property.rawValue,systemImage:"plus.diamond").frame(maxWidth:.infinity) }.buttonStyle(VButton()).font(.caption) } }
                    ForEach(clip.keys.sorted {$0.time < $1.time}) { key in
                        HStack { Image(systemName:"diamond.fill").foregroundStyle(VTheme.mint).font(.caption); VStack(alignment:.leading) { Text(key.property.rawValue).font(.system(size:13,weight:.semibold)); Text("\(key.time,specifier:"%.2f") s").font(.caption).foregroundStyle(VTheme.muted) }; Spacer(); TextField("قيمة",value:Binding(get:{store.selectedClip?.keys.first {$0.id == key.id}?.value ?? key.value},set:{value in store.updateSelected {c in if let i=c.keys.firstIndex(where:{$0.id == key.id}) {c.keys[i].value=value}}}),format:.number).keyboardType(.numbersAndPunctuation).frame(width:70); Button {store.updateSelected {$0.keys.removeAll {$0.id == key.id}}} label:{Image(systemName:"xmark").foregroundStyle(VTheme.muted)} }.padding(15).background(VTheme.surface,in:RoundedRectangle(cornerRadius:13))
                    }
                }
            } else { emptySelection }
        }
    }
}
struct MotionPreview:View {
    var motion:MotionPreset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate=false
    var body:some View {
        Text("Aa").font(.system(size:34,weight:.black)).foregroundStyle(VTheme.mint)
            .scaleEffect(motion == .pop && !animate ? 0.65 : 1)
            .opacity(motion == .fade && !animate ? 0.2 : 1)
            .offset(x:motion == .slide && !animate ? -23 : 0)
            .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration:1.2).repeatForever(autoreverses:true)) {animate=true} } }
}
struct TitleStudio:View {
    @EnvironmentObject var store:EditorStore
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        ToolCanvas(title:"استوديو النصوص",subtitle:"عناوين مصممة لتتحرك مع قصتك") {
            VStack(spacing:12) {
                titleCard("عنوان قوي",sample:"لحظة تستحق",color:"#FFFFFF",motion:.pop,size:104,y:0.3)
                titleCard("كلمة بارزة",sample:"انتبه!",color:"#FF4646",motion:.pop,size:120,y:0.5)
                titleCard("ترجمة نظيفة",sample:"كل كلمة لها أثر",color:"#FFFFFF",motion:.fade,size:64,y:0.78)
                titleCard("بطاقة ذهبية",sample:"اكتب الحديث ومصدره",color:"#E6C46B",motion:.slide,size:70,y:0.4)
            }
        }
    }
    private func titleCard(_ name:String,sample:String,color:String,motion:MotionPreset,size:Double,y:Double)->some View {
        Button {
            store.addText(sample); store.updateSelected {$0.style.color=color;$0.style.motion=motion;$0.style.fontSize=size;$0.style.y=y}; dismiss()
        } label: {
            HStack { VStack(alignment:.leading,spacing:17) { Text(name).font(.system(size:10,weight:.medium)).foregroundStyle(VTheme.muted); Text(sample).font(.system(size:26,weight:.bold)).foregroundStyle(Color(hex:color)) }; Spacer(); Image(systemName:"plus.circle.fill").font(.system(size:25)).foregroundStyle(VTheme.mint) }.padding(23).frame(maxWidth:.infinity,alignment:.leading).background(VTheme.surface,in:RoundedRectangle(cornerRadius:20))
        }.buttonStyle(.plain)
    }
}
struct SettingsPanel:View {
    @EnvironmentObject var store:EditorStore
    var body:some View {
        ToolCanvas(title:"إعدادات المشروع",subtitle:"المقاس والإيقاع المناسبان للفيديو") {
            VStack(alignment:.leading,spacing:24) {
                TextField("اسم المشروع",text:Binding(get:{store.project.title},set:{value in store.change {$0.title=value}})).font(.system(size:20,weight:.semibold)).padding(18).background(VTheme.surface,in:RoundedRectangle(cornerRadius:16))
                formatPicker
                Picker("FPS",selection:Binding(get:{store.project.fps},set:{fps in store.change {$0.fps=fps}})) { ForEach([24,25,30,60],id:\.self) {Text("\($0) FPS").tag($0)} }.pickerStyle(.segmented)
            }
        }
    }
    private var formatPicker:some View {
        HStack(spacing:10) {
            formatButton("ريلز",w:1080,h:1920)
            formatButton("عريض",w:1920,h:1080)
            formatButton("مربع",w:1080,h:1080)
        }
    }
    private func formatButton(_ title:String,w:Int,h:Int)->some View {
        let active=store.project.width == w && store.project.height == h
        return Button {store.change {$0.width=w;$0.height=h}} label: { VStack(spacing:12) { RoundedRectangle(cornerRadius:3).stroke(active ? VTheme.mint : VTheme.muted,lineWidth:1.5).frame(width:w > h ? 37 : 24,height:h > w ? 37 : 24).frame(height:40); Text(title).font(.caption) }.frame(maxWidth:.infinity).padding(.vertical,18).background(active ? VTheme.mint.opacity(0.08) : VTheme.surface,in:RoundedRectangle(cornerRadius:15)) }.foregroundStyle(.white)
    }
}
struct ExportPanel:View {
    @EnvironmentObject var store:EditorStore
    @State private var quality = 1080
    var body:some View {
        ToolCanvas(title:"جاهز للمشاهدة",subtitle:"EXPORT YOUR STORY") {
            VStack(spacing:26) {
                ZStack { Circle().fill(VTheme.mint.opacity(0.09)).frame(width:95,height:95); Image(systemName:"arrow.up.right").font(.system(size:35,weight:.light)).foregroundStyle(VTheme.mint) }.padding(.top,12)
                HStack { Text("المدة"); Spacer(); Text(clockLabel(store.project.length)).monospacedDigit() }.font(.subheadline).foregroundStyle(VTheme.muted)
                Picker("الجودة",selection:$quality) { Text("1080p · Full HD").tag(1080); Text("4K · Ultra HD").tag(2160) }.pickerStyle(.segmented)
                Text("\(store.project.fps) FPS   ·   MP4   ·   بدون علامة مائية").font(.system(size:11,design:.monospaced)).foregroundStyle(VTheme.muted)
                if store.isBusy { ProgressView(store.status).tint(VTheme.mint).padding() }
                else if let url=store.exportURL { ShareLink(item:url) { Label("حفظ ومشاركة الفيديو",systemImage:"square.and.arrow.up").frame(maxWidth:.infinity) }.buttonStyle(VButton(prominent:true)) }
                else { Button { Task { store.change { p in let ratio=Double(p.width)/Double(p.height); if ratio > 1 {p.height=quality;p.width=quality == 2160 ? 3840:1920} else if ratio == 1 {p.width=quality;p.height=quality} else {p.width=quality;p.height=quality == 2160 ? 3840:1920} }; await store.export() } } label: { Label("تصدير الفيديو",systemImage:"arrow.up.right").frame(maxWidth:.infinity) }.buttonStyle(VButton(prominent:true)) }
            }
        }.onAppear {store.exportURL=nil;quality=max(store.project.width,store.project.height)>1920 ? 2160:1080}
    }
}
