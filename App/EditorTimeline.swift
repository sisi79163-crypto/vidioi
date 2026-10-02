import SwiftUI

struct EditorTimeline: View {
    @EnvironmentObject var store: EditorStore
    @State private var zoom = 44.0
    private var lanes: [Int] { Array(Set(store.project.clips.map(\.lane))).sorted(by: >) }
    private var width: Double { max(380,store.project.length * zoom + 80) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("TIMELINE").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(VTheme.muted)
                Spacer()
                Text("\(lanes.count) طبقات").font(.system(size: 10)).foregroundStyle(VTheme.muted)
                Button { zoom = max(12, zoom / 1.4) } label: { Image(systemName: "minus.magnifyingglass") }
                Button { zoom = min(140,zoom * 1.4) } label: { Image(systemName: "plus.magnifyingglass") }
            }.font(.system(size: 12)).foregroundStyle(.white).padding(.horizontal, 17).frame(height: 30)
            ScrollView([.horizontal,.vertical], showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    ruler
                    if lanes.isEmpty { RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 1,dash:[5,5])).foregroundStyle(VTheme.line).frame(width: width - 40,height: 53).overlay(Text("أضف وسائط لبدء التايملاين").font(.caption).foregroundStyle(VTheme.muted)) }
                    ForEach(lanes,id: \.self) { lane in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 9).fill(VTheme.elevated.opacity(0.25))
                            ForEach(store.project.clips.filter { $0.lane == lane }) { clip in
                                TimelineClip(clip:clip,zoom:zoom)
                                    .frame(width:max(22,clip.duration * zoom),height:clip.kind == .video ? 54 : 37)
                                    .offset(x:clip.start * zoom)
                            }
                        }.frame(width:width,height:store.project.clips.contains { $0.lane == lane && $0.kind == .video } ? 54 : 37)
                    }
                    Color.clear.frame(height: 12)
                }.frame(width:width,alignment:.leading)
                    .overlay(alignment:.topLeading) {
                        VStack(spacing:0) { RoundedRectangle(cornerRadius:2).fill(.white).frame(width:11,height:10); Rectangle().fill(.white).frame(width:1.5) }
                            .offset(x:store.playhead * zoom - 5.5).allowsHitTesting(false)
                    }.padding(.horizontal,20)
            }
        }.background(VTheme.surface.opacity(0.6)).environment(\.layoutDirection,.leftToRight)
    }
    private var ruler: some View {
        Canvas { ctx,size in
            let step = zoom < 25 ? 5 : 1
            for second in stride(from:0,through:Int(ceil(store.project.length))+2,by:step) {
                let x = Double(second) * zoom
                var path = Path(); path.move(to:CGPoint(x:x,y:19)); path.addLine(to:CGPoint(x:x,y:24))
                ctx.stroke(path,with:.color(VTheme.muted.opacity(0.5)),lineWidth:1)
                ctx.draw(Text(clockLabel(Double(second))).font(.system(size:8,design:.monospaced)).foregroundColor(VTheme.muted),at:CGPoint(x:x+2,y:8),anchor:.leading)
            }
        }.frame(width:width,height:25).contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { store.seek($0.location.x / zoom) })
    }
}
struct TimelineClip: View {
    @EnvironmentObject var store: EditorStore
    let clip:Clip
    let zoom:Double
    @State private var drag = 0.0
    private var selected:Bool { store.selected == clip.id }
    var body: some View {
        ZStack(alignment:.leading) {
            RoundedRectangle(cornerRadius:7).fill(clip.kind.tint.opacity(clip.kind == .text ? 0.26 : 0.16))
            if clip.kind == .video || clip.kind == .image {
                MediaThumbnail(url:clip.asset.map { store.assets.appendingPathComponent($0) }).opacity(0.7)
                LinearGradient(colors:[.black.opacity(0.55),.clear],startPoint:.leading,endPoint:.trailing)
            }
            HStack(spacing:5) { Image(systemName:clip.kind.icon); Text(clip.kind == .text ? clip.text : clip.name).lineLimit(1) }
                .font(.system(size:10,weight:.medium)).foregroundStyle(.white).padding(.horizontal,selected ? 13 : 8)
        }.clipShape(RoundedRectangle(cornerRadius:7))
            .overlay(RoundedRectangle(cornerRadius:7).stroke(selected ? VTheme.mint : clip.kind.tint.opacity(0.35),lineWidth:selected ? 2 : 1))
            .overlay(alignment:.leading) { if selected { trimHandle(left:true) } }
            .overlay(alignment:.trailing) { if selected { trimHandle(left:false) } }
            .offset(x:drag)
            .onTapGesture { store.selected = clip.id; store.seek(clip.start); UISelectionFeedbackGenerator().selectionChanged() }
            .gesture(DragGesture(minimumDistance:12).onChanged { drag = $0.translation.width }.onEnded { value in
                store.moveClip(clip.id,to:max(0,clip.start + value.translation.width / zoom)); drag = 0
            })
    }
    private func trimHandle(left:Bool)->some View {
        RoundedRectangle(cornerRadius:3).fill(VTheme.mint).frame(width:9).overlay(Capsule().fill(VTheme.ink).frame(width:2,height:14))
            .contentShape(Rectangle()).highPriorityGesture(DragGesture(minimumDistance:3).onEnded { value in store.trimClip(clip.id,leading:left,delta:value.translation.width / zoom) })
    }
}
