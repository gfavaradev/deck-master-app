import { redirect } from "next/navigation";

export default function Home() {
  // Il proxy / il layout dashboard reindirizzano al login se non autenticato.
  redirect("/dashboard");
}
