import Link from "next/link";
import { Button } from "@clipify/ui";

const STEPS = [
  "Paste a script or topic",
  "Choose a format + template",
  "Generate storyboard, visuals, voice & captions",
  "Render, preflight, download MP4",
];

export default function LandingPage() {
  return (
    <main className="flex flex-1 flex-col">
      <header className="mx-auto flex w-full max-w-5xl items-center justify-between px-6 py-6">
        <span className="text-lg font-semibold">Clipify</span>
        <nav className="flex items-center gap-3">
          <Link href="/login">
            <Button variant="ghost" size="sm">
              Log in
            </Button>
          </Link>
          <Link href="/signup">
            <Button size="sm">Get started</Button>
          </Link>
        </nav>
      </header>

      <section className="mx-auto flex w-full max-w-3xl flex-1 flex-col items-center justify-center gap-8 px-6 py-20 text-center">
        <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">
          Turn an idea into a publish-ready video.
        </h1>
        <p className="max-w-xl text-lg text-muted">
          Clipify researches your topic, writes a script, plans scenes, generates the
          visuals and narration, and renders a finished video — with a YouTube-oriented
          preflight check before you export.
        </p>
        <div className="flex gap-3">
          <Link href="/signup">
            <Button size="lg">Create your first video</Button>
          </Link>
          <Link href="/login">
            <Button size="lg" variant="outline">
              Log in
            </Button>
          </Link>
        </div>

        <ol className="mt-10 grid gap-3 text-left sm:grid-cols-2">
          {STEPS.map((step, i) => (
            <li
              key={step}
              className="flex items-start gap-3 rounded-lg border border-border bg-surface-1 p-4"
            >
              <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-accent/15 text-sm font-semibold text-accent">
                {i + 1}
              </span>
              <span className="text-sm">{step}</span>
            </li>
          ))}
        </ol>
      </section>

      <footer className="mx-auto w-full max-w-5xl px-6 py-8 text-sm text-muted">
        Clipify provides policy-aware checks only — not a guarantee of YouTube monetization.
      </footer>
    </main>
  );
}
