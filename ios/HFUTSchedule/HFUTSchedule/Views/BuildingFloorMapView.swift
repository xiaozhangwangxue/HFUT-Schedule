import SwiftUI

struct BuildingRoomBox: Identifiable, Equatable {
    let name: String
    let rectangle: CGRect
    var id: String { "\(name)|\(rectangle)" }
}

final class BuildingRoomXMLParser: NSObject, XMLParserDelegate {
    private var text = ""
    private var fields: [String: String]?
    private(set) var rooms: [BuildingRoomBox] = []

    static func parse(_ data: Data) -> [BuildingRoomBox] {
        let delegate = BuildingRoomXMLParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { return [] }
        return delegate.rooms
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "object" { fields = [:] }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName != "object" { fields?[elementName] = text.trimmingCharacters(in: .whitespacesAndNewlines); return }
        defer { fields = nil }
        guard let f = fields, let name = f["name"], let x = Double(f["xmin"] ?? ""), let y = Double(f["ymin"] ?? ""),
              let right = Double(f["xmax"] ?? ""), let bottom = Double(f["ymax"] ?? ""), right > x, bottom > y,
              [x, y, right, bottom].allSatisfy(\.isFinite), x >= 0, y >= 0 else { return }
        rooms.append(BuildingRoomBox(name: name, rectangle: CGRect(x: x, y: y, width: right - x, height: bottom - y)))
    }
}

struct BuildingFloorMapView: View {
    let resource: String
    var initialRoom = ""
    @State private var image: UIImage?
    @State private var rooms: [BuildingRoomBox] = []
    @State private var query = ""
    @State private var selectedRoom: String?
    @State private var error: String?
    @State private var zoom = 1.0

    static func resourceURL(_ path: String) -> URL? {
        if let url = URL(string: path), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return url }
        return URL(string: path, relativeTo: URL(string: "https://raw.githubusercontent.com/Chiu-xaH/HFUT-Schedule/dev/src/source/building/detail/")!)?.absoluteURL
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                TextField("教室编号", text: $query).textFieldStyle(.roundedBorder)
                Button("定位") { selectedRoom = query.trimmingCharacters(in: .whitespacesAndNewlines) }
            }.padding(.horizontal)
            if let image {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        let width = geometry.size.width * zoom
                        let height = width * image.size.height / max(1, image.size.width)
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: image).resizable().frame(width: width, height: height)
                            ForEach(rooms) { room in
                                let rect = room.rectangle
                                let sx = width / image.size.width, sy = height / image.size.height
                                Button { selectedRoom = room.name; query = room.name } label: {
                                    Rectangle().fill(selectedRoom == room.name ? Color.red.opacity(0.35) : Color.clear)
                                        .overlay { Rectangle().stroke(selectedRoom == room.name ? Color.red : .clear, lineWidth: 2) }
                                }.frame(width: rect.width * sx, height: rect.height * sy)
                                    .offset(x: rect.minX * sx, y: rect.minY * sy)
                                    .accessibilityLabel("教室 \(room.name)")
                            }
                        }.frame(width: width, height: height)
                    }
                }
                HStack {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: $zoom, in: 1...3)
                    Image(systemName: "plus.magnifyingglass")
                }.padding(.horizontal)
                if let selectedRoom {
                    Text(rooms.contains { $0.name == selectedRoom } ? "已高亮教室 \(selectedRoom)" : "本层没有找到教室 \(selectedRoom)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let error { ContentUnavailableView("楼层图读取失败", systemImage: "building.2", description: Text(error)) }
            else { ProgressView() }
        }
        .task { await load() }
    }

    private func load() async {
        guard let url = Self.resourceURL(resource) else { error = "资源地址无效"; return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            self.image = image
            if let (xml, response) = try? await URLSession.shared.data(from: url.deletingPathExtension().appendingPathExtension("xml")),
               (response as? HTTPURLResponse)?.statusCode == 200 { rooms = BuildingRoomXMLParser.parse(xml) }
            query = initialRoom
            selectedRoom = initialRoom.isEmpty ? nil : initialRoom
        } catch { self.error = error.localizedDescription }
    }
}
