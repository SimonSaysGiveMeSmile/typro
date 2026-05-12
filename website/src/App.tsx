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

const examples = ["teh", "mistika", "recieve", "adress"];

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

  return (
    <main className="page">
      <header className="nav">
        <span className="brand">
          <img src="/icon.png" alt="" className="brand-icon" width={24} height={24} />
          <span className="wordmark">Typro</span>
        </span>
        <span className="tag">On-device</span>
      </header>

      <section className="hero">
        <h1>Fix typos with one&nbsp;Delete.</h1>
        <div className="hero-right">
          <p className="lede">
            Typro watches your typing, spots typos on-device, and selects the
            wrong letters at the end of the word. Hit Delete, retype, move on.
          </p>
          <div className="cta">
            <a
              className="btn primary"
              href="https://github.com/SimonSaysGiveMeSmile/typro/releases/latest"
              target="_blank"
              rel="noreferrer"
            >
              Download
            </a>
            <a className="btn ghost" href="#demo">Try the demo</a>
          </div>
        </div>
      </section>

      <section id="demo" className="demo">
        <div className="eyebrow">
          <span className="label">Demo</span>
          <span className="muted">Type a typo, add a space, then press Backspace.</span>
        </div>

        <textarea
          id="demo-input"
          className="field"
          value={text}
          onChange={(event) => setText(event.target.value)}
          onKeyDown={handleKeyDown}
          spellCheck={false}
          placeholder="e.g. teh&nbsp;"
          aria-label="Typo demo field"
        />

        <div className="demo-foot">
          <div className="hint" aria-live="polite">
            {pending ? (
              <>
                <span className="from">{pending.word}</span>
                <span className="arrow">→</span>
                <span className="to">{pending.corrected}</span>
                <span className="sep">·</span>
                <span className="action">Press Delete to apply</span>
              </>
            ) : (
              <span className="muted">Waiting for a typo…</span>
            )}
          </div>

          <div className="chips">
            {examples.map((word) => (
              <button
                key={word}
                type="button"
                onClick={() => setText(`${word} `)}
              >
                {word}
              </button>
            ))}
            <button type="button" onClick={() => setText("")}>
              Clear
            </button>
          </div>
        </div>
      </section>

      <section className="how">
        <div className="eyebrow">
          <span className="label">How it works</span>
        </div>
        <ol>
          <li>
            <span className="num">01</span>
            <div>
              <b>Watch</b>
              <p>A short buffer tracks the word you&rsquo;re typing.</p>
            </div>
          </li>
          <li>
            <span className="num">02</span>
            <div>
              <b>Check</b>
              <p>At a space or punctuation, macOS spell-check runs locally.</p>
            </div>
          </li>
          <li>
            <span className="num">03</span>
            <div>
              <b>Apply</b>
              <p>Press Delete and Typro swaps the word, keeping the boundary.</p>
            </div>
          </li>
        </ol>
      </section>

      <footer className="foot">
        <div>
          <p className="muted">macOS 14+ · Accessibility permission required.</p>
        </div>
        <div className="foot-links">
          <a href="https://github.com/SimonSaysGiveMeSmile/typro">Source</a>
          <a
            href="https://github.com/SimonSaysGiveMeSmile/typro/releases/latest"
            target="_blank"
            rel="noreferrer"
          >
            Releases
          </a>
        </div>
      </footer>
    </main>
  );
}

export default App;
