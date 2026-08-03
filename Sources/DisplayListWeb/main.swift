import DisplayListDescription
import JavaScriptKit

private let document = JSObject.global.document
private let input = document.getElementById("description-input").object!
private let output = document.getElementById("minimal-output").object!
private let errorMessage = document.getElementById("conversion-error").object!
private let copyButton = document.getElementById("copy-button").object!
private let clearButton = document.getElementById("clear-button").object!
private let sampleButton = document.getElementById("sample-button").object!
private let status = document.getElementById("wasm-status").object!
private let referenceContainer = document.getElementById("encoding-reference").object!

private var retainedClosures: [JSClosure] = []
private var latestMinimalDescription = ""

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

private func renderReference() {
    referenceContainer.innerHTML = ""

    for category in DisplayListEncodingReference.Category.allCases {
        let section = document.createElement("section")
        section.className = "reference-group"

        let heading = document.createElement("h3")
        heading.textContent = .string(category.rawValue)
        _ = section.appendChild(heading)

        let grid = document.createElement("div")
        grid.className = "reference-grid"

        for reference in DisplayListEncodingReference.all where reference.category == category {
            let article = document.createElement("article")
            article.className = "encoding-card"
            article.id = .string("encoding-\(reference.id)")

            let token = document.createElement("code")
            token.textContent = .string(reference.token)
            _ = article.appendChild(token)

            let copy = document.createElement("div")
            let name = document.createElement("h4")
            name.textContent = .string(reference.name)
            _ = copy.appendChild(name)

            let detail = document.createElement("p")
            detail.textContent = .string(reference.detail)
            _ = copy.appendChild(detail)
            _ = article.appendChild(copy)
            _ = grid.appendChild(article)
        }

        _ = section.appendChild(grid)
        _ = referenceContainer.appendChild!(section)
    }
}

private func setUsedEncodings(_ used: Set<String>) {
    for reference in DisplayListEncodingReference.all {
        guard let card = document.getElementById("encoding-\(reference.id)").object else { continue }
        _ = card.classList.toggle("is-used", used.contains(reference.id))
    }
}

private func convertCurrentInput() {
    let source = input.value.string ?? ""
    guard source.contains(where: { !$0.isWhitespace }) else {
        latestMinimalDescription = ""
        output.textContent = "Your minimal description will appear here."
        output.className = "output-placeholder"
        errorMessage.hidden = .boolean(true)
        copyButton.disabled = .boolean(true)
        setUsedEncodings([])
        return
    }

    do {
        let conversion = try DisplayListDescriptionConverter.convert(source)
        latestMinimalDescription = conversion.minimalDescription
        output.textContent = .string(conversion.minimalDescription)
        output.className = ""
        errorMessage.hidden = .boolean(true)
        copyButton.disabled = .boolean(false)
        setUsedEncodings(conversion.usedEncodingIDs)
    } catch {
        latestMinimalDescription = ""
        output.textContent = "Unable to convert this description."
        output.className = "output-placeholder"
        errorMessage.textContent = .string(String(describing: error))
        errorMessage.hidden = .boolean(false)
        copyButton.disabled = .boolean(true)
        setUsedEncodings([])
    }
}

private func installEventHandlers() {
    let inputClosure = JSClosure { _ in
        convertCurrentInput()
        return .undefined
    }
    input.oninput = .object(inputClosure)
    retainedClosures.append(inputClosure)

    let sampleClosure = JSClosure { _ in
        input.value = .string(sampleDescription)
        convertCurrentInput()
        _ = input.focus!()
        return .undefined
    }
    sampleButton.onclick = .object(sampleClosure)
    retainedClosures.append(sampleClosure)

    let clearClosure = JSClosure { _ in
        input.value = .string("")
        convertCurrentInput()
        _ = input.focus!()
        return .undefined
    }
    clearButton.onclick = .object(clearClosure)
    retainedClosures.append(clearClosure)

    let copyClosure = JSClosure { _ in
        guard !latestMinimalDescription.isEmpty else { return .undefined }
        _ = JSObject.global.navigator.clipboard.writeText(latestMinimalDescription)
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
}

renderReference()
installEventHandlers()
status.textContent = "SwiftWasm ready"
_ = status.classList.add("is-ready")
input.value = .string(sampleDescription)
convertCurrentInput()
