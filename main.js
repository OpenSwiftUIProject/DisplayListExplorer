// The CodeMirror decoration pattern is adapted from SwiftFiddle/swift-ast-explorer
// (Apache-2.0). See THIRD_PARTY_NOTICES.md.
import { init } from "./.build/plugins/PackageToJS/outputs/Package/index.js";
import {
  Decoration,
  EditorView,
  drawSelection,
  highlightActiveLine,
  highlightActiveLineGutter,
  keymap,
  lineNumbers,
} from "@codemirror/view";
import { EditorState, StateEffect, StateField } from "@codemirror/state";
import {
  defaultKeymap,
  history,
  historyKeymap,
  indentWithTab,
} from "@codemirror/commands";
import { bracketMatching, indentUnit } from "@codemirror/language";
import { closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete";

const addMarksEffect = StateEffect.define();
const clearMarksEffect = StateEffect.define();
const markDecoration = Decoration.mark({ class: "cm-linked-highlight" });

const markField = StateField.define({
  create() {
    return Decoration.none;
  },
  update(marks, transaction) {
    marks = marks.map(transaction.changes);
    for (const effect of transaction.effects) {
      if (effect.is(addMarksEffect)) {
        marks = marks.update({ add: effect.value, sort: true });
      } else if (effect.is(clearMarksEffect)) {
        marks = Decoration.none;
      }
    }
    return marks;
  },
  provide: (field) => EditorView.decorations.from(field),
});

function forwardSourcePosition(event, view) {
  const position = view.posAtCoords({ x: event.clientX, y: event.clientY });
  if (position !== null && typeof globalThis.displayListSourceHover === "function") {
    globalThis.displayListSourceHover(position);
  }
}

const hoverBridge = EditorView.domEventHandlers({
  mousemove: forwardSourcePosition,
  mousedown: forwardSourcePosition,
  mouseleave() {
    globalThis.displayListSourceLeave?.();
  },
});

const changeBridge = EditorView.updateListener.of((update) => {
  if (update.docChanged) {
    globalThis.displayListDidChange?.(update.state.doc.toString());
  }
});

const editorContainer = document.getElementById("editor-container");
editorContainer.textContent = "";

const editorView = new EditorView({
  parent: editorContainer,
  state: EditorState.create({
    doc: "",
    extensions: [
      lineNumbers(),
      history(),
      drawSelection(),
      highlightActiveLine(),
      highlightActiveLineGutter(),
      bracketMatching(),
      closeBrackets(),
      indentUnit.of("  "),
      EditorState.tabSize.of(2),
      keymap.of([
        ...closeBracketsKeymap,
        ...defaultKeymap,
        ...historyKeymap,
        indentWithTab,
      ]),
      markField,
      hoverBridge,
      changeBridge,
      EditorView.contentAttributes.of({
        "aria-label": "DisplayList description editor",
        spellcheck: "false",
        autocapitalize: "off",
      }),
    ],
  }),
});

globalThis.displayListEditor = {
  getValue() {
    return editorView.state.doc.toString();
  },
  setValue(value) {
    editorView.dispatch({
      changes: { from: 0, to: editorView.state.doc.length, insert: value },
    });
  },
  markRange(from, to) {
    const lower = Math.max(0, Math.min(from, editorView.state.doc.length));
    const upper = Math.max(lower, Math.min(to, editorView.state.doc.length));
    if (lower < upper) {
      editorView.dispatch({
        effects: addMarksEffect.of([markDecoration.range(lower, upper)]),
      });
    }
  },
  clearMarks() {
    editorView.dispatch({ effects: clearMarksEffect.of(null) });
  },
  focus() {
    editorView.focus();
  },
};

await init();
