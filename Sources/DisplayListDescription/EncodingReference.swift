public struct DisplayListEncodingReference: Equatable, Sendable {
    public enum Category: String, CaseIterable, Sendable {
        case structure = "Structure"
        case content = "Content"
        case effect = "Effects"
    }

    public let id: String
    public let token: String
    public let name: String
    public let detail: String
    public let category: Category

    public init(id: String, token: String, name: String, detail: String, category: Category) {
        self.id = id
        self.token = token
        self.name = name
        self.detail = detail
        self.category = category
    }

    public static let all: [Self] = [
        .init(id: "structure.dl", token: "DL", name: "Display list", detail: "The root container for the complete DisplayList.", category: .structure),
        .init(id: "structure.item", token: "I:n", name: "Item identity", detail: "A DisplayList.Item. n is its identity; omitted identities become 0.", category: .structure),
        .init(id: "structure.effect", token: "E", name: "Effect item", detail: "Wraps an effect and any child items to which it applies.", category: .structure),
        .init(id: "structure.states", token: "states", name: "State variants", detail: "Contains the display lists stored for alternate state hashes.", category: .structure),
        .init(id: "structure.state-hash", token: "(hash …)", name: "State hash", detail: "Identifies one state variant and encloses its child items.", category: .structure),

        .init(id: "content.backdrop", token: "B", name: "Backdrop", detail: "Backdrop content with its color and filters omitted from the compact form.", category: .content),
        .init(id: "content.color", token: "C", name: "Color", detail: "A resolved color fill.", category: .content),
        .init(id: "content.chameleon-color", token: "CH", name: "Chameleon color", detail: "An adaptive fallback color with filters.", category: .content),
        .init(id: "content.image", token: "IM", name: "Image", detail: "Resolved image content.", category: .content),
        .init(id: "content.shape", token: "S", name: "Shape", detail: "A path rendered with a paint and fill style.", category: .content),
        .init(id: "content.shadow", token: "SH", name: "Shadow", detail: "A resolved path shadow.", category: .content),
        .init(id: "content.platform-view", token: "PV", name: "Platform view", detail: "Content backed by a native platform view.", category: .content),
        .init(id: "content.platform-layer", token: "PL", name: "Platform layer", detail: "Content backed by a native platform layer.", category: .content),
        .init(id: "content.text", token: "T", name: "Text", detail: "Resolved text content; the string and size are intentionally omitted.", category: .content),
        .init(id: "content.flattened", token: "F", name: "Flattened list", detail: "A nested DisplayList flattened into content. Its child items remain nested.", category: .content),
        .init(id: "content.drawing", token: "D", name: "Drawing", detail: "Rasterized drawing content.", category: .content),
        .init(id: "content.view", token: "V:type", name: "View factory", detail: "View content followed by the concrete factory type.", category: .content),
        .init(id: "content.placeholder", token: "@id", name: "Placeholder", detail: "A placeholder referencing another display-list identity.", category: .content),

        .init(id: "effect.geometry-group", token: "GG", name: "Geometry group", detail: "Keeps geometry effects grouped.", category: .effect),
        .init(id: "effect.compositing-group", token: "CG", name: "Compositing group", detail: "Composites child content as a group.", category: .effect),
        .init(id: "effect.backdrop-group", token: "BG", name: "Backdrop group", detail: "Marks a backdrop grouping boundary.", category: .effect),
        .init(id: "effect.archive", token: "A:id", name: "Archive", detail: "Archive metadata; id is a UUID or nil.", category: .effect),
        .init(id: "effect.properties", token: "PR", name: "Properties", detail: "One or more display properties such as foreground layers, privacy, or event behavior.", category: .effect),
        .init(id: "effect.platform-group", token: "PG", name: "Platform group", detail: "A group implemented by the platform renderer.", category: .effect),
        .init(id: "effect.opacity", token: "O", name: "Opacity", detail: "An opacity effect; the numeric value is omitted.", category: .effect),
        .init(id: "effect.blend-mode", token: "B", name: "Blend mode", detail: "A blend-mode effect. B is context-dependent: inside E it is not backdrop content.", category: .effect),
        .init(id: "effect.clip", token: "C", name: "Clip", detail: "A clipping path and style. C is context-dependent: inside E it is not color content.", category: .effect),
        .init(id: "effect.mask", token: "M", name: "Mask", detail: "A mask effect.", category: .effect),
        .init(id: "effect.transform", token: "T", name: "Transform", detail: "A geometry transform. T is context-dependent: inside E it is not text content.", category: .effect),
        .init(id: "effect.filter", token: "F", name: "Graphics filter", detail: "Any graphics filter; the specific filter parameters are omitted.", category: .effect),
        .init(id: "effect.animation", token: "AN", name: "Animation", detail: "An animation effect.", category: .effect),
        .init(id: "effect.content-transition", token: "TR", name: "Content transition", detail: "A content transition and optional animation.", category: .effect),
        .init(id: "effect.view", token: "(V:type)", name: "Effect view", detail: "A view-backed effect. Parentheses distinguish its nested effect form.", category: .effect),
        .init(id: "effect.accessibility", token: "AX", name: "Accessibility", detail: "Accessibility display metadata.", category: .effect),
        .init(id: "effect.platform", token: "PL", name: "Platform effect", detail: "A platform-defined effect. The full description omits this marker, so it cannot be inferred from an empty effect.", category: .effect),
        .init(id: "effect.state", token: "H:hash", name: "State", detail: "A state effect identified by its strong hash.", category: .effect),
        .init(id: "effect.interpolator-root", token: "IR", name: "Interpolator root", detail: "The root of an interpolator group.", category: .effect),
        .init(id: "effect.interpolator-layer", token: "IL", name: "Interpolator layer", detail: "A layer within an interpolator group.", category: .effect),
        .init(id: "effect.interpolator-animation", token: "IA", name: "Interpolator animation", detail: "Animation data attached to an interpolator.", category: .effect),
    ]
}
