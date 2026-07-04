"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  GoogleAuthProvider,
  signInWithPopup,
  signInWithEmailAndPassword,
  type User,
} from "firebase/auth";
import { auth } from "@/lib/firebase/client";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function establishSession(user: User) {
    const idToken = await user.getIdToken();
    const res = await fetch("/api/session", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ idToken }),
    });
    if (res.ok) {
      router.push("/dashboard");
      router.refresh();
      return;
    }
    await auth.signOut();
    if (res.status === 403) {
      setError("Questo account non è un amministratore.");
    } else {
      setError("Login non riuscito. Riprova.");
    }
  }

  async function handleGoogle() {
    setError(null);
    setBusy(true);
    try {
      const cred = await signInWithPopup(auth, new GoogleAuthProvider());
      await establishSession(cred.user);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Errore Google Sign-In.");
    } finally {
      setBusy(false);
    }
  }

  async function handleEmail(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      const cred = await signInWithEmailAndPassword(auth, email, password);
      await establishSession(cred.user);
    } catch {
      setError("Email o password non validi.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-app px-4">
      <div className="w-full max-w-sm rounded-2xl border border-line bg-panel p-8 shadow-xl">
        <h1 className="text-xl font-semibold text-accent">Deck Master</h1>
        <p className="mb-6 text-sm text-ink-2">Dashboard amministrazione</p>

        <button
          onClick={handleGoogle}
          disabled={busy}
          className="mb-4 w-full rounded-lg bg-white px-4 py-2.5 text-sm font-medium text-neutral-900 transition hover:bg-neutral-200 disabled:opacity-50"
        >
          Accedi con Google
        </button>

        <div className="my-4 flex items-center gap-3 text-xs text-ink-3">
          <span className="h-px flex-1 bg-panel-2" />
          oppure
          <span className="h-px flex-1 bg-panel-2" />
        </div>

        <form onSubmit={handleEmail} className="space-y-3">
          <input
            type="email"
            required
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full rounded-lg border border-line-strong bg-app px-3 py-2 text-sm text-ink outline-none focus:border-accent"
          />
          <input
            type="password"
            required
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full rounded-lg border border-line-strong bg-app px-3 py-2 text-sm text-ink outline-none focus:border-accent"
          />
          <button
            type="submit"
            disabled={busy}
            className="w-full rounded-lg bg-accent px-4 py-2.5 text-sm font-semibold text-app transition hover:bg-accent-2 disabled:opacity-50"
          >
            Accedi
          </button>
        </form>

        {error && (
          <p className="mt-4 rounded-lg bg-red-950/60 px-3 py-2 text-sm text-bad">
            {error}
          </p>
        )}
      </div>
    </div>
  );
}
