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
    const pre = "Fix ";
    const seq: [string, number][] = [
      // type with typo "typso"
      [pre + "t", 80], [pre + "ty", 80], [pre + "typ", 80], [pre + "typs", 80], [pre + "typso", 80],
      [pre + "typso ", 80], [pre + "typso o", 80], [pre + "typso on", 80], [pre + "typso on ", 80],
      [pre + "typso on t", 80], [pre + "typso on th", 80], [pre + "typso on the", 80],
      [pre + "typso on the ", 80], [pre + "typso on the g", 80], [pre + "typso on the go", 80],
      [pre + "typso on the go.", 900],
      // backspace "typso" → "typ"
      [pre + "typso on the go", 50], [pre + "typso on the g", 50], [pre + "typso on the ", 50],
      [pre + "typso on the", 50], [pre + "typso on th", 50], [pre + "typso on t", 50],
      [pre + "typso on ", 50], [pre + "typso on", 50], [pre + "typso o", 50], [pre + "typso ", 50],
      [pre + "typso", 50], [pre + "typs", 50], [pre + "typ", 50],
      // retype correctly "typos on the go."
      [pre + "typo", 80], [pre + "typos", 80], [pre + "typos ", 80], [pre + "typos o", 80],
      [pre + "typos on", 80], [pre + "typos on ", 80], [pre + "typos on t", 80],
      [pre + "typos on th", 80], [pre + "typos on the", 80], [pre + "typos on the ", 80],
      [pre + "typos on the g", 80], [pre + "typos on the go", 80], [pre + "typos on the go.", 1800],
      // clear back to start
      [pre + "typos on the go", 40], [pre + "typos on the g", 40], [pre + "typos on the ", 40],
      [pre + "typos on the", 40], [pre + "typos on th", 40], [pre + "typos on t", 40],
      [pre + "typos on ", 40], [pre + "typos on", 40], [pre + "typos o", 40], [pre + "typos ", 40],
      [pre + "typos", 40], [pre + "typo", 40], [pre + "typ", 40], [pre + "ty", 40],
      [pre + "t", 40], [pre, 300],
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
