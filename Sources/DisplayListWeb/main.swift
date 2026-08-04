import DisplayListDescription
import JavaScriptKit

private let document = JSObject.global.document
private let editor = JSObject.global.displayListEditor.object!
private let output = document.getElementById("minimal-output").object!
private let errorMessage = document.getElementById("conversion-error").object!
private let copyButton = document.getElementById("copy-button").object!
private let shareButton = document.getElementById("share-button").object!
private let clearButton = document.getElementById("clear-button").object!
private let sampleButton = document.getElementById("sample-button").object!
private let status = document.getElementById("wasm-status").object!
private let infoContainer = document.getElementById("encoding-info").object!
private let statisticsContainer = document.getElementById("encoding-statistics").object!
private let statisticsSummary = document.getElementById("statistics-summary").object!
private let mappingSummary = document.getElementById("mapping-summary").object!
private let hoverInspector = document.getElementById("hover-inspector").object!
private let directionToggle = document.getElementById("direction-toggle").object!
private let conversionSummary = document.getElementById("conversion-summary").object!
private let sourceTitle = document.getElementById("source-title").object!
private let outputTitle = document.getElementById("output-title").object!
private let outputTabLabel = document.getElementById("output-tab-label").object!
private let forwardLimitation = document.getElementById("forward-limitation").object!
private let reverseLimitation = document.getElementById("reverse-limitation").object!
private let urlState = JSObject.global.displayListURLState.object!

private enum ConversionDirection: Equatable {
    case descriptionToMinimal
    case minimalToDescription
}

private struct ExplorerConversion {
    let output: String
    let usedEncodingIDs: Set<String>
    let spans: [DisplayListDescriptionSpan]

    init(_ conversion: DisplayListDescriptionConversion) {
        output = conversion.minimalDescription
        usedEncodingIDs = conversion.usedEncodingIDs
        spans = conversion.spans
    }

    init(_ conversion: DisplayListMinimalDescriptionConversion) {
        output = conversion.description
        usedEncodingIDs = conversion.usedEncodingIDs
        spans = conversion.spans
    }
}

private let tabNames = ["minimal", "info", "statistics"]
private var retainedClosures: [JSClosure] = []
private var outputClosures: [JSClosure] = []
private var statisticsClosures: [JSClosure] = []
private var direction = ConversionDirection.descriptionToMinimal
private var latestConversion: ExplorerConversion?
private var latestSource = ""
private var latestOutput = ""
private var latestSharedEncoding = ""
private var highlightedOutputElements: [JSObject] = []
private var activeHighlightKey: String?
private var isInitializingEditor = true
private var isURLStateActive = false

private let sampleDescription = """
(display-list
  (item #:identity 42 #:version 1
    (frame (0.0 0.0; 120.0 44.0))
    (content-seed 1)
    (color #007AFFFF))
  (item #:identity 43 #:version 1
    (frame (8.0 8.0; 104.0 28.0))
    (effect #:opacity 0.72
      (item #:identity 44 #:version 1
        (frame (8.0 8.0; 104.0 28.0))
        (content-seed 2)
        (text "Hello, DisplayList" #:size (104.0, 28.0))))))
"""

private let sampleMinimalDescription = "(DL(I:42 C)(I:43(E O(I:44 T))))"

private func reference(for encodingID: String) -> DisplayListEncodingReference? {
    DisplayListEncodingReference.all.first { $0.id == encodingID }
}

private func cssIdentifier(_ encodingID: String) -> String {
    encodingID.map { character in
        character.isLetter || character.isNumber ? String(character) : "-"
    }.joined()
}

private func renderInfo() {
    infoContainer.innerHTML = ""

    for category in DisplayListEncodingReference.Category.allCases {
        let heading = document.createElement("h3")
        heading.className = "info-category-heading"
        heading.textContent = .string(category.rawValue)
        _ = infoContainer.appendChild!(heading)

        for item in DisplayListEncodingReference.all where item.category == category {
            let row = document.createElement("article")
            row.className = "encoding-info-row"

            let token = document.createElement("code")
            token.className = "encoding-token"
            token.textContent = .string(item.token)
            _ = row.appendChild(token)

            let name = document.createElement("h3")
            name.textContent = .string(item.name)
            _ = row.appendChild(name)

            let detail = document.createElement("p")
            detail.textContent = .string(item.detail)
            _ = row.appendChild(detail)

            _ = infoContainer.appendChild!(row)
        }
    }
}

private func appendHeaderCell(_ text: String, to row: JSValue) {
    let cell = document.createElement("th")
    cell.scope = "col"
    cell.textContent = .string(text)
    _ = row.appendChild(cell)
}

private func renderStatistics(_ conversion: ExplorerConversion?) {
    statisticsContainer.innerHTML = ""
    statisticsClosures.removeAll(keepingCapacity: true)

    guard let conversion, !conversion.spans.isEmpty else {
        statisticsSummary.textContent = "No mapped encodings yet."
        let empty = document.createElement("p")
        empty.className = "empty-state"
        empty.textContent = "Paste an input value to see occurrence counts."
        _ = statisticsContainer.appendChild!(empty)
        return
    }

    let counts = conversion.spans.reduce(into: [String: Int]()) { result, span in
        result[span.encodingID, default: 0] += 1
    }
    statisticsSummary.textContent = .string(
        "\(conversion.spans.count) linked ranges · \(counts.count) encoding types"
    )

    let table = document.createElement("table")
    table.className = "statistics-table"

    let head = document.createElement("thead")
    let headRow = document.createElement("tr")
    appendHeaderCell("Encoding", to: headRow)
    appendHeaderCell("Count", to: headRow)
    _ = head.appendChild(headRow)
    _ = table.appendChild(head)

    let body = document.createElement("tbody")
    for item in DisplayListEncodingReference.all {
        guard let count = counts[item.id] else { continue }

        let row = document.createElement("tr")
        row.className = "statistics-row"
        row.tabIndex = 0
        _ = row.setAttribute("data-encoding-id", item.id)

        let enterClosure = JSClosure { _ in
            highlightEncoding(item.id)
            return .undefined
        }
        row.onmouseenter = .object(enterClosure)
        row.onfocus = .object(enterClosure)
        statisticsClosures.append(enterClosure)

        let leaveClosure = JSClosure { _ in
            clearHighlight()
            return .undefined
        }
        row.onmouseleave = .object(leaveClosure)
        row.onblur = .object(leaveClosure)
        statisticsClosures.append(leaveClosure)

        let encodingCell = document.createElement("td")
        let token = document.createElement("code")
        token.textContent = .string(item.token)
        _ = encodingCell.appendChild(token)
        let name = document.createElement("span")
        name.className = "stat-name"
        name.textContent = .string(item.name)
        _ = encodingCell.appendChild(name)
        _ = row.appendChild(encodingCell)

        let countCell = document.createElement("td")
        let badge = document.createElement("span")
        badge.className = "stat-count"
        badge.textContent = .string(String(count))
        _ = countCell.appendChild(badge)
        _ = row.appendChild(countCell)

        _ = body.appendChild(row)
    }
    _ = table.appendChild(body)
    _ = statisticsContainer.appendChild!(table)
}

private func utf16Substring(_ text: String, from start: Int, to end: Int) -> String {
    let codeUnits = Array(text.utf16)
    guard start >= 0, end <= codeUnits.count, start <= end else { return "" }
    return String(decoding: codeUnits[start..<end], as: UTF16.self)
}

private func renderMappedOutput(_ conversion: ExplorerConversion) {
    output.innerHTML = ""
    output.className = "minimal-output"
    outputClosures.removeAll(keepingCapacity: true)

    let text = conversion.output
    let spans = conversion.spans
    let boundaries = Set(
        [0, text.utf16.count] + spans.flatMap { [$0.outputStart, $0.outputEnd] }
    ).sorted()

    for (start, end) in zip(boundaries, boundaries.dropFirst()) where start < end {
        let fragment = utf16Substring(text, from: start, to: end)
        let active = spans.filter {
            $0.outputStart <= start && $0.outputEnd >= end
        }.sorted { lhs, rhs in
            let lhsLength = lhs.outputEnd - lhs.outputStart
            let rhsLength = rhs.outputEnd - rhs.outputStart
            if lhsLength != rhsLength { return lhsLength < rhsLength }
            return lhs.sourceEnd - lhs.sourceStart < rhs.sourceEnd - rhs.sourceStart
        }

        guard let primary = active.first else {
            _ = output.appendChild!(document.createTextNode(fragment))
            continue
        }

        let segment = document.createElement("span")
        let mappingClasses = active.map { "mapping-\($0.occurrenceID)" }
        let encodingClasses = Set(active.map { "encoding-\(cssIdentifier($0.encodingID))" })
        segment.className = .string(
            (["mapped-output"] + mappingClasses + encodingClasses.sorted()).joined(separator: " ")
        )
        _ = segment.setAttribute("data-primary-occurrence", primary.occurrenceID)
        if let item = reference(for: primary.encodingID) {
            segment.title = .string("\(item.token) · \(item.name)")
        }
        let enterClosure = JSClosure { _ in
            highlightOccurrence(primary.occurrenceID)
            return .undefined
        }
        segment.onmouseenter = .object(enterClosure)
        segment.onclick = .object(enterClosure)
        outputClosures.append(enterClosure)

        let leaveClosure = JSClosure { _ in
            clearHighlight()
            return .undefined
        }
        segment.onmouseleave = .object(leaveClosure)
        outputClosures.append(leaveClosure)

        segment.textContent = .string(fragment)
        _ = output.appendChild!(segment)
    }
}

private func setOutputPlaceholder(_ text: String) {
    output.innerHTML = ""
    outputClosures.removeAll(keepingCapacity: true)
    output.className = "minimal-output output-placeholder"
    output.textContent = .string(text)
}

private func lineAndColumn(at utf16Offset: Int, in source: String) -> (line: Int, column: Int) {
    let prefix = utf16Substring(source, from: 0, to: min(utf16Offset, source.utf16.count))
    let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
    return (lines.count, (lines.last?.utf16.count ?? 0) + 1)
}

private func setInspector(encodingID: String, count: Int = 1, span: DisplayListDescriptionSpan? = nil) {
    hoverInspector.innerHTML = ""
    guard let item = reference(for: encodingID) else {
        hoverInspector.textContent = .string(encodingID)
        return
    }

    let token = document.createElement("code")
    token.textContent = .string(item.token)
    _ = hoverInspector.appendChild!(token)

    let name = document.createElement("strong")
    name.textContent = .string(item.name)
    _ = hoverInspector.appendChild!(name)

    let detail = document.createElement("span")
    if let span {
        let start = lineAndColumn(at: span.sourceStart, in: latestSource)
        let end = lineAndColumn(at: span.sourceEnd, in: latestSource)
        detail.textContent = .string("\(start.line):\(start.column)–\(end.line):\(end.column) · \(item.detail)")
    } else {
        detail.textContent = .string("\(count) occurrences · \(item.detail)")
    }
    _ = hoverInspector.appendChild!(detail)
}

private func resetInspector() {
    hoverInspector.textContent = "Hover a mapped element on either side to inspect its encoding."
}

private func clearHighlight() {
    activeHighlightKey = nil
    _ = editor.clearMarks!()
    for element in highlightedOutputElements {
        _ = element.classList.remove("is-linked-highlight")
        _ = element.classList.remove("is-group-highlight")
    }
    highlightedOutputElements.removeAll(keepingCapacity: true)
    resetInspector()
}

private func collectElements(matching selector: String, className: String) {
    let nodes = document.querySelectorAll(selector)
    let count = Int(nodes.length.number ?? 0)
    guard count > 0 else { return }
    for index in 0..<count {
        guard let element = nodes[index].object else { continue }
        _ = element.classList.add(className)
        highlightedOutputElements.append(element)
    }
}

private func highlightOccurrence(_ occurrenceID: String) {
    let key = "occurrence:\(occurrenceID)"
    guard activeHighlightKey != key,
          let span = latestConversion?.spans.first(where: { $0.occurrenceID == occurrenceID }) else {
        return
    }

    clearHighlight()
    activeHighlightKey = key
    _ = editor.markRange!(span.sourceStart, span.sourceEnd)
    collectElements(matching: ".mapping-\(occurrenceID)", className: "is-linked-highlight")
    setInspector(encodingID: span.encodingID, span: span)
}

private func highlightEncoding(_ encodingID: String) {
    let key = "encoding:\(encodingID)"
    guard activeHighlightKey != key, let conversion = latestConversion else { return }
    let spans = conversion.spans.filter { $0.encodingID == encodingID }
    guard !spans.isEmpty else { return }

    clearHighlight()
    activeHighlightKey = key
    for span in spans {
        _ = editor.markRange!(span.sourceStart, span.sourceEnd)
    }
    collectElements(
        matching: ".encoding-\(cssIdentifier(encodingID))",
        className: "is-group-highlight"
    )
    setInspector(encodingID: encodingID, count: spans.count)
}

private func sourceSpan(at offset: Int) -> DisplayListDescriptionSpan? {
    latestConversion?.spans.filter {
        $0.sourceStart <= offset && offset < $0.sourceEnd
    }.min { lhs, rhs in
        let lhsLength = lhs.sourceEnd - lhs.sourceStart
        let rhsLength = rhs.sourceEnd - rhs.sourceStart
        if lhsLength != rhsLength { return lhsLength < rhsLength }
        return lhs.outputEnd - lhs.outputStart < rhs.outputEnd - rhs.outputStart
    }
}

private func sample(for direction: ConversionDirection) -> String {
    switch direction {
    case .descriptionToMinimal:
        return sampleDescription
    case .minimalToDescription:
        return sampleMinimalDescription
    }
}

private func updateDirectionInterface() {
    switch direction {
    case .descriptionToMinimal:
        conversionSummary.textContent = "DisplayList.description → minimalDescription"
        sourceTitle.textContent = "DisplayList Description"
        outputTitle.textContent = "minimalDescription"
        outputTabLabel.textContent = "minimalDesc"
        directionToggle.textContent = "⇄ Reverse"
        directionToggle.ariaLabel = "Convert minimalDescription back to DisplayList description"
        forwardLimitation.hidden = .boolean(false)
        reverseLimitation.hidden = .boolean(true)
    case .minimalToDescription:
        conversionSummary.textContent = "minimalDescription → reconstructed description"
        sourceTitle.textContent = "minimalDescription"
        outputTitle.textContent = "Reconstructed Description"
        outputTabLabel.textContent = "Description"
        directionToggle.textContent = "⇄ Forward"
        directionToggle.ariaLabel = "Convert DisplayList description to minimalDescription"
        forwardLimitation.hidden = .boolean(true)
        reverseLimitation.hidden = .boolean(false)
    }
}

private func swapDirection() {
    let nextInput = latestOutput
    switch direction {
    case .descriptionToMinimal:
        direction = .minimalToDescription
    case .minimalToDescription:
        direction = .descriptionToMinimal
    }
    updateDirectionInterface()
    _ = editor.setValue!(nextInput.isEmpty ? sample(for: direction) : nextInput)
    _ = editor.focus!()
}

private func syncSharedEncodingURL() {
    guard isURLStateActive else { return }

    if latestSharedEncoding.isEmpty {
        _ = urlState.clearEncoding!()
    } else {
        _ = urlState.setEncoding!(latestSharedEncoding)
    }
}

private func convert(_ source: String) {
    latestSource = source
    clearHighlight()

    guard source.contains(where: { !$0.isWhitespace }) else {
        latestConversion = nil
        latestOutput = ""
        latestSharedEncoding = ""
        setOutputPlaceholder(
            direction == .descriptionToMinimal
                ? "Your minimal description will appear here."
                : "Your reconstructed description will appear here."
        )
        mappingSummary.textContent = "No linked ranges"
        errorMessage.hidden = .boolean(true)
        copyButton.disabled = .boolean(true)
        shareButton.disabled = .boolean(true)
        renderStatistics(nil)
        syncSharedEncodingURL()
        return
    }

    do {
        let conversion: ExplorerConversion
        let sharedEncoding: String
        switch direction {
        case .descriptionToMinimal:
            let result = try DisplayListDescriptionConverter.convert(source)
            conversion = ExplorerConversion(result)
            sharedEncoding = result.minimalDescription
        case .minimalToDescription:
            let result = try DisplayListMinimalDescriptionConverter.convert(source)
            conversion = ExplorerConversion(result)
            sharedEncoding = try DisplayListDescriptionConverter
                .convert(result.description)
                .minimalDescription
        }
        latestConversion = conversion
        latestOutput = conversion.output
        latestSharedEncoding = sharedEncoding
        renderMappedOutput(conversion)
        mappingSummary.textContent = .string(
            "\(conversion.spans.count) linked ranges · \(conversion.usedEncodingIDs.count) encodings"
        )
        errorMessage.hidden = .boolean(true)
        copyButton.disabled = .boolean(false)
        shareButton.disabled = .boolean(false)
        renderStatistics(conversion)
        syncSharedEncodingURL()
    } catch {
        latestConversion = nil
        latestOutput = ""
        latestSharedEncoding = ""
        setOutputPlaceholder("Unable to convert this input.")
        mappingSummary.textContent = "Conversion failed"
        errorMessage.textContent = .string(String(describing: error))
        errorMessage.hidden = .boolean(false)
        copyButton.disabled = .boolean(true)
        shareButton.disabled = .boolean(true)
        renderStatistics(nil)
        syncSharedEncodingURL()
    }
}

private func selectTab(_ name: String) {
    guard tabNames.contains(name) else { return }
    for tabName in tabNames {
        guard let button = document.getElementById("\(tabName)-tab").object,
              let panel = document.getElementById("\(tabName)-panel").object else {
            continue
        }
        let isSelected = tabName == name
        _ = button.classList.toggle("is-active", isSelected)
        _ = panel.classList.toggle("is-active", isSelected)
        button.ariaSelected = .string(isSelected ? "true" : "false")
        panel.hidden = .boolean(!isSelected)
    }
    copyButton.hidden = .boolean(name != "minimal")
}

private func installEventHandlers() {
    let changeClosure = JSClosure { arguments in
        if !isInitializingEditor {
            isURLStateActive = true
        }
        convert(arguments.first?.string ?? "")
        return .undefined
    }
    JSObject.global.displayListDidChange = .object(changeClosure)
    retainedClosures.append(changeClosure)

    let sourceHoverClosure = JSClosure { arguments in
        guard let offset = arguments.first?.number,
              let span = sourceSpan(at: Int(offset)) else {
            clearHighlight()
            return .undefined
        }
        highlightOccurrence(span.occurrenceID)
        return .undefined
    }
    JSObject.global.displayListSourceHover = .object(sourceHoverClosure)
    retainedClosures.append(sourceHoverClosure)

    let sourceLeaveClosure = JSClosure { _ in
        clearHighlight()
        return .undefined
    }
    JSObject.global.displayListSourceLeave = .object(sourceLeaveClosure)
    retainedClosures.append(sourceLeaveClosure)

    let sampleClosure = JSClosure { _ in
        _ = editor.setValue!(sample(for: direction))
        _ = editor.focus!()
        return .undefined
    }
    sampleButton.onclick = .object(sampleClosure)
    retainedClosures.append(sampleClosure)

    let clearClosure = JSClosure { _ in
        _ = editor.setValue!("")
        _ = editor.focus!()
        return .undefined
    }
    clearButton.onclick = .object(clearClosure)
    retainedClosures.append(clearClosure)

    let copyClosure = JSClosure { _ in
        guard !latestOutput.isEmpty else { return .undefined }
        _ = JSObject.global.navigator.clipboard.writeText(latestOutput)
        copyButton.textContent = "Copied"

        let resetClosure = JSClosure { _ in
            copyButton.textContent = "Copy"
            return .undefined
        }
        _ = JSObject.global.setTimeout!(resetClosure, 1_400)
        return .undefined
    }
    copyButton.onclick = .object(copyClosure)
    retainedClosures.append(copyClosure)

    let shareClosure = JSClosure { _ in
        guard !latestSharedEncoding.isEmpty else { return .undefined }
        isURLStateActive = true
        guard let href = urlState.setEncoding!(latestSharedEncoding).string else {
            return .undefined
        }
        _ = JSObject.global.navigator.clipboard.writeText(href)
        shareButton.textContent = "Link copied"

        let resetClosure = JSClosure { _ in
            shareButton.textContent = "Copy link"
            return .undefined
        }
        _ = JSObject.global.setTimeout!(resetClosure, 1_400)
        return .undefined
    }
    shareButton.onclick = .object(shareClosure)
    retainedClosures.append(shareClosure)

    let directionClosure = JSClosure { _ in
        swapDirection()
        return .undefined
    }
    directionToggle.onclick = .object(directionClosure)
    retainedClosures.append(directionClosure)

    for tabName in tabNames {
        guard let button = document.getElementById("\(tabName)-tab").object else { continue }
        let tabClosure = JSClosure { _ in
            selectTab(tabName)
            return .undefined
        }
        button.onclick = .object(tabClosure)
        retainedClosures.append(tabClosure)
    }

}

renderInfo()
installEventHandlers()
selectTab("minimal")
let initialSharedEncoding = urlState.readEncoding!().string
if initialSharedEncoding != nil {
    direction = .minimalToDescription
    isURLStateActive = true
}
updateDirectionInterface()
status.textContent = "SwiftWasm ready"
_ = status.classList.add("is-ready")
_ = editor.setValue!(initialSharedEncoding ?? sample(for: direction))
isInitializingEditor = false
_ = editor.focus!()
