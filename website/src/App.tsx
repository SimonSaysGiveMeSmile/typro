import { KeyboardEvent, useMemo, useState } from "react";

type PendingFix = {
  word: string;
  boundary: string;
  start: number;
  corrected: string;
};

const corrections = new Map<string, string>([
  ["teh", "the"],
  ["mistika", "mistake"],
  ["recieve", "receive"],
  ["adress", "address"],
  ["seperate", "separate"],
  ["definately", "definitely"],
  ["occured", "occurred"],
  ["untill", "until"],
  ["wierd", "weird"],
  ["thier", "their"],
]);

const examples = ["I typed teh ", "Try mistika ", "Please recieve ", "Wrong adress "];

function findPendingFix(value: string): PendingFix | null {
  const match = value.match(/([A-Za-z']+)([ .,!?])$/);
  if (!match) return null;

  const word = match[1];
  const boundary = match[2];
  const correction = corrections.get(word.toLowerCase());
  if (!correction) return null;

  const corrected = /^[A-Z]/.test(word)
    ? correction.charAt(0).toUpperCase() + correction.slice(1)
    : correction;

  return {
    word,
    boundary,
    corrected,
    start: value.length - word.length - boundary.length,
  };
}

function App() {
  const [text, setText] = useState("");
  const pending = useMemo(() => findPendingFix(text), [text]);

  const handleKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key !== "Backspace" || !pending) return;

    event.preventDefault();
    setText(`${text.slice(0, pending.start)}${pending.corrected}${pending.boundary}`);
  };

  const status = pending
    ? {
        word: pending.word,
        suggestion: pending.corrected,
        action: "Press Backspace to apply the repair.",
      }
    : {
        word: "None",
        suggestion: "Waiting",
        action: "Type a demo typo followed by a space.",
      };

  return (
    <main className="app-shell">
      <header className="topbar">
        <a className="brand" href="#top" aria-label="Typro home">
          <span className="brand-mark">T</span>
          <span>Typro</span>
        </a>
        <nav aria-label="Primary navigation">
          <a href="#demo">Demo</a>
          <a href="#how">How it works</a>
          <a href="#download">Download</a>
        </nav>
      </header>

      <section id="top" className="hero section-frame">
        <div className="hero-copy">
          <p className="eyebrow">macOS typing assistant</p>
          <h1>Typo repair with a deliberate Delete tap.</h1>
          <p>
            Typro watches completed words, checks likely fixes on-device, and
            replaces the typo only when you confirm it.
          </p>
          <div className="actions">
            <a className="button primary" href="#demo">Try demo</a>
            <a className="button ghost" href="/download/typro-project.zip" download>Download ZIP</a>
          </div>
        </div>

        <div className="glass-terminal" aria-label="Typro example">
          <div className="terminal-header">
            <span></span>
            <span></span>
            <span></span>
          </div>
          <div className="terminal-lines">
            <p><b>You type</b><span>mistika </span></p>
            <p><b>Typro sees</b><span>mistake</span></p>
            <p><b>You press</b><span>Delete</span></p>
            <p><b>Result</b><span>mistake </span></p>
          </div>
        </div>
      </section>

      <section id="demo" className="demo section-frame">
        <div className="section-title">
          <p className="eyebrow">browser runtime</p>
          <h2>Try the interaction safely.</h2>
          <p>
            This React demo runs only inside the page. It mirrors Typro's flow:
            type a known typo, add a boundary, then press Backspace to accept.
          </p>
        </div>

        <div className="demo-grid">
          <div className="glass-panel">
            <label htmlFor="demo-input">Demo field</label>
            <textarea
              id="demo-input"
              value={text}
              onChange={(event) => setText(event.target.value)}
              onKeyDown={handleKeyDown}
              spellCheck={false}
              placeholder="Try: teh, mistika, recieve, adress"
            />
            <div className="example-row">
              {examples.map((example) => (
                <button key={example} type="button" onClick={() => setText(example)}>
                  {example.trim()}
                </button>
              ))}
              <button type="button" onClick={() => setText("")}>Clear</button>
            </div>
          </div>

          <aside className="status glass-panel" aria-live="polite">
            <h3>State</h3>
            <div>
              <span>Typed</span>
              <strong>{status.word}</strong>
            </div>
            <div>
              <span>Suggestion</span>
              <strong>{status.suggestion}</strong>
            </div>
            <div>
              <span>Next</span>
              <strong>{status.action}</strong>
            </div>
          </aside>
        </div>
      </section>

      <section id="how" className="how section-frame">
        <div className="section-title">
          <p className="eyebrow">how it works</p>
          <h2>Small buffer. Local check. Explicit repair.</h2>
        </div>
        <div className="steps">
          <article>
            <span>01</span>
            <h3>Watch</h3>
            <p>Typro keeps a short memory of the current word while you type.</p>
          </article>
          <article>
            <span>02</span>
            <h3>Suggest</h3>
            <p>At a space or punctuation mark, it asks macOS for a likely correction.</p>
          </article>
          <article>
            <span>03</span>
            <h3>Apply</h3>
            <p>If Delete is pressed next, Typro replaces the typo and preserves the boundary.</p>
          </article>
        </div>
      </section>

      <section id="download" className="download section-frame">
        <div>
          <p className="eyebrow">source package</p>
          <h2>Download the project.</h2>
          <p>The ZIP includes the Swift app source and this React TypeScript showcase.</p>
        </div>
        <a className="button primary" href="/download/typro-project.zip" download>Download project</a>
      </section>
    </main>
  );
}

export default App;
