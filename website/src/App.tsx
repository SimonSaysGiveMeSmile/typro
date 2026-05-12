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

function useTypingDemo() {
  const [display, setDisplay] = useState("Fix typos on the go.");
  const frame = useRef(0);

  useEffect(() => {
    const seq: [string, number][] = [
      // type "Fix ptypso " with typo
      ["F", 80], ["Fi", 80], ["Fix", 80], ["Fix ", 80],
      ["Fix t", 80], ["Fix ty", 80], ["Fix typ", 80], ["Fix typs", 80], ["Fix typso", 80],
      ["Fix typso ", 80],
      // instant auto-correct: "typso" → "typos"
      ["Fix typos ", 400],
      // continue typing the rest
      ["Fix typos o", 80], ["Fix typos on", 80], ["Fix typos on ", 80],
      ["Fix typos on t", 80], ["Fix typos on th", 80], ["Fix typos on the", 80],
      ["Fix typos on the ", 80], ["Fix typos on the g", 80], ["Fix typos on the go", 80],
      ["Fix typos on the go.", 2000],
      // clear
      ["Fix typos on the go", 40], ["Fix typos on the g", 40], ["Fix typos on the ", 40],
      ["Fix typos on the", 40], ["Fix typos on th", 40], ["Fix typos on t", 40],
      ["Fix typos on ", 40], ["Fix typos on", 40], ["Fix typos o", 40], ["Fix typos ", 40],
      ["Fix typos", 40], ["Fix typo", 40], ["Fix typ", 40], ["Fix ty", 40], ["Fix t", 40],
      ["Fix ", 40], ["Fix", 40], ["Fi", 40], ["F", 40], ["", 400],
    ];

    let timeout: ReturnType<typeof setTimeout>;
    function step() {
      const [text, delay] = seq[frame.current % seq.length];
      setDisplay(text);
      frame.current = (frame.current + 1) % seq.length;
      timeout = setTimeout(step, delay);
    }
    timeout = setTimeout(step, 1200);
    return () => clearTimeout(timeout);
  }, []);

  return display;
}

type Theme = "system" | "light" | "dark";
const themes: Theme[] = ["system", "light", "dark"];
const themeLabel: Record<Theme, string> = { system: "Auto", light: "Light", dark: "Dark" };

const ThemeIcon = ({ theme }: { theme: Theme }) => {
  if (theme === "dark") return (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
      <path d="M12.5 8.5A5.5 5.5 0 0 1 5.5 1.5a5.5 5.5 0 1 0 7 7z" fill="currentColor"/>
    </svg>
  );
  if (theme === "light") return (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
      <circle cx="7" cy="7" r="2.8" fill="currentColor"/>
      <g stroke="currentColor" strokeWidth="1.2" strokeLinecap="round">
        <line x1="7" y1="0.5" x2="7" y2="2"/>
        <line x1="7" y1="12" x2="7" y2="13.5"/>
        <line x1="0.5" y1="7" x2="2" y2="7"/>
        <line x1="12" y1="7" x2="13.5" y2="7"/>
        <line x1="2.4" y1="2.4" x2="3.4" y2="3.4"/>
        <line x1="10.6" y1="10.6" x2="11.6" y2="11.6"/>
        <line x1="11.6" y1="2.4" x2="10.6" y2="3.4"/>
        <line x1="3.4" y1="10.6" x2="2.4" y2="11.6"/>
      </g>
    </svg>
  );
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
      <circle cx="7" cy="7" r="6" stroke="currentColor" strokeWidth="1.2"/>
      <path d="M7 1a6 6 0 0 1 0 12V1z" fill="currentColor"/>
    </svg>
  );
};

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
          <ThemeIcon theme={theme} />
        </button>
      </header>

      <section className="hero">
        <h1><span>{typingDemo}</span><span className="typing-cursor" /></h1>
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
