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

const explorer = document.querySelector(".explorer");
const paneSplitter = document.getElementById("pane-splitter");
const verticalLayout = window.matchMedia("(max-width: 980px)");
const defaultPaneRatio = 0.5;
const minimumPaneRatio = 0.2;
const minimumPaneSize = 240;
let paneRatio = defaultPaneRatio;
let isResizingPanes = false;

function isVerticalLayout() {
  return verticalLayout.matches;
}

function paneRatioBounds() {
  const vertical = isVerticalLayout();
  const explorerSize = vertical ? explorer.clientHeight : explorer.clientWidth;
  const splitterSize = vertical ? paneSplitter.offsetHeight : paneSplitter.offsetWidth;
  const availableSize = Math.max(1, explorerSize - splitterSize);
  const lowerBound = Math.max(
    minimumPaneRatio,
    Math.min(0.5, minimumPaneSize / availableSize),
  );
  return { lower: lowerBound, upper: 1 - lowerBound };
}

function setPaneRatio(nextRatio) {
  const { lower, upper } = paneRatioBounds();
  paneRatio = Math.min(upper, Math.max(lower, nextRatio));
  explorer.style.setProperty("--source-pane-share", `${paneRatio}fr`);
  explorer.style.setProperty("--detail-pane-share", `${1 - paneRatio}fr`);

  const percentage = Math.round(paneRatio * 100);
  paneSplitter.setAttribute("aria-valuemin", String(Math.round(lower * 100)));
  paneSplitter.setAttribute("aria-valuemax", String(Math.round(upper * 100)));
  paneSplitter.setAttribute("aria-valuenow", String(percentage));
  paneSplitter.setAttribute("aria-valuetext", `Source pane ${percentage}%`);
}

function setPaneRatioFromPointer(event) {
  const vertical = isVerticalLayout();
  const explorerRect = explorer.getBoundingClientRect();
  const splitterSize = vertical ? paneSplitter.offsetHeight : paneSplitter.offsetWidth;
  const availableSize = Math.max(
    1,
    (vertical ? explorerRect.height : explorerRect.width) - splitterSize,
  );
  const pointerPosition = vertical
    ? event.clientY - explorerRect.top
    : event.clientX - explorerRect.left;
  setPaneRatio((pointerPosition - splitterSize / 2) / availableSize);
}

paneSplitter.addEventListener("pointerdown", (event) => {
  if (event.button !== 0) {
    return;
  }

  isResizingPanes = true;
  paneSplitter.setPointerCapture(event.pointerId);
  paneSplitter.classList.add("is-dragging");
  document.body.classList.add("is-resizing-panes");
  setPaneRatioFromPointer(event);
  event.preventDefault();
});

paneSplitter.addEventListener("pointermove", (event) => {
  if (isResizingPanes && paneSplitter.hasPointerCapture(event.pointerId)) {
    setPaneRatioFromPointer(event);
  }
});

function finishPaneResize(event) {
  if (!isResizingPanes) {
    return;
  }

  isResizingPanes = false;
  if (paneSplitter.hasPointerCapture(event.pointerId)) {
    paneSplitter.releasePointerCapture(event.pointerId);
  }
  paneSplitter.classList.remove("is-dragging");
  document.body.classList.remove("is-resizing-panes");
}

paneSplitter.addEventListener("pointerup", finishPaneResize);
paneSplitter.addEventListener("pointercancel", finishPaneResize);
paneSplitter.addEventListener("lostpointercapture", finishPaneResize);
paneSplitter.addEventListener("dblclick", () => setPaneRatio(defaultPaneRatio));

paneSplitter.addEventListener("keydown", (event) => {
  const vertical = isVerticalLayout();
  const decreaseKey = vertical ? "ArrowUp" : "ArrowLeft";
  const increaseKey = vertical ? "ArrowDown" : "ArrowRight";
  const step = event.shiftKey ? 0.1 : 0.02;

  if (event.key === decreaseKey) {
    setPaneRatio(paneRatio - step);
  } else if (event.key === increaseKey) {
    setPaneRatio(paneRatio + step);
  } else if (event.key === "Home") {
    setPaneRatio(paneRatioBounds().lower);
  } else if (event.key === "End") {
    setPaneRatio(paneRatioBounds().upper);
  } else {
    return;
  }

  event.preventDefault();
});

function updateSplitterOrientation() {
  paneSplitter.setAttribute(
    "aria-orientation",
    isVerticalLayout() ? "horizontal" : "vertical",
  );
  setPaneRatio(paneRatio);
}

verticalLayout.addEventListener("change", updateSplitterOrientation);
window.addEventListener("resize", () => setPaneRatio(paneRatio));
updateSplitterOrientation();

await init();
