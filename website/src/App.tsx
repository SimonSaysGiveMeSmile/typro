import { KeyboardEvent, useEffect, useMemo, useRef, useState } from "react";

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

// Typing animation: types "I love typo ", backtracks, fixes to "Typro "
function useTypingDemo() {
  const [display, setDisplay] = useState("");
  const frame = useRef(0);

  useEffect(() => {
    // sequence: [text, pause_ms]
    const seq: [string, number][] = [
      ["I", 80], ["I ", 80], ["I l", 80], ["I lo", 80], ["I lov", 80], ["I love", 80], ["I love ", 80],
      ["I love t", 80], ["I love ty", 80], ["I love typ", 80], ["I love typo", 80], ["I love typo ", 600],
      // backspace "typo "
      ["I love typo", 60], ["I love typ", 60], ["I love ty", 60], ["I love t", 60], ["I love ", 60],
      // retype "Typro "
      ["I love T", 80], ["I love Ty", 80], ["I love Typ", 80], ["I love Typr", 80], ["I love Typro", 80], ["I love Typro ", 1200],
      // clear
      ["I love Typro", 50], ["I love Typr", 50], ["I love Typ", 50], ["I love Ty", 50], ["I love T", 50],
      ["I love ", 50], ["I love", 50], ["I lov", 50], ["I lo", 50], ["I l", 50], ["I ", 50], ["I", 50], ["", 300],
    ];

    let timeout: ReturnType<typeof setTimeout>;
    function step() {
      const [text, delay] = seq[frame.current % seq.length];
      setDisplay(text);
      frame.current = (frame.current + 1) % seq.length;
      timeout = setTimeout(step, delay);
    }
    timeout = setTimeout(step, 400);
    return () => clearTimeout(timeout);
  }, []);

  return display;
}

type Theme = "system" | "light" | "dark";
const themes: Theme[] = ["system", "light", "dark"];
const themeLabel: Record<Theme, string> = { system: "Auto", light: "Light", dark: "Dark" };

function App() {
  const typingDemo = useTypingDemo();
  const [text, setText] = useState("");
  const pending = useMemo(() => findPendingFix(text), [text]);
  const [theme, setTheme] = useState<Theme>(() => {
    if (typeof window === "undefined") return "system";
    return (window.localStorage.getItem("typro-theme") as Theme) || "system";
  });

  useEffect(() => {
    const root = document.documentElement;
    if (theme === "system") root.removeAttribute("data-theme");
    else root.setAttribute("data-theme", theme);
    window.localStorage.setItem("typro-theme", theme);
  }, [theme]);

  const cycleTheme = () => {
    const next = themes[(themes.indexOf(theme) + 1) % themes.length];
    setTheme(next);
  };

  const handleKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key !== "Backspace" || !pending) return;
    event.preventDefault();
    setText(`${text.slice(0, pending.start)}${pending.corrected}${pending.boundary}`);
  };

  return (
    <main className="page">
      <header className="nav">
        <span className="brand">
          <img src="/new-icon.png" alt="" className="brand-icon" width={24} height={24} />
          <span className="wordmark">Typro</span>
        </span>
        <button
          type="button"
          className="tag theme-toggle"
          onClick={cycleTheme}
          aria-label={`Theme: ${themeLabel[theme]}. Click to change.`}
          title={`Theme: ${themeLabel[theme]}`}
        >
          {themeLabel[theme]}
        </button>
      </header>

      <section className="hero">
        <h1>Fix typos on the go.</h1>
        <div className="hero-right">
          <div className="typing-demo" aria-hidden="true">
            <span className="typing-text">{typingDemo}</span><span className="typing-cursor" />
          </div>
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
          <a href="https://github.com/SimonSaysGiveMeSmile/typro">Git Repo</a>
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
