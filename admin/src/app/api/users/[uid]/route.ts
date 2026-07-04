import { NextRequest, NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth/guard";
import { setUserPro, setUserActive, setUserRole } from "@/lib/data/users";

export const runtime = "nodejs";

// PATCH /api/users/:uid  body: { action, value }
//   action "pro"    value boolean
//   action "active" value boolean
//   action "role"   value "administrator" | "user"
export async function PATCH(
  req: NextRequest,
  { params }: { params: Promise<{ uid: string }> },
) {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;

  const { uid } = await params;
  const { action, value } = await req.json().catch(() => ({}));

  try {
    switch (action) {
      case "pro":
        await setUserPro(uid, !!value);
        break;
      case "active":
        await setUserActive(uid, !!value);
        break;
      case "role":
        if (value !== "administrator" && value !== "user") {
          return NextResponse.json({ error: "invalid-role" }, { status: 400 });
        }
        await setUserRole(uid, value);
        break;
      default:
        return NextResponse.json({ error: "invalid-action" }, { status: 400 });
    }
    return NextResponse.json({ ok: true });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : String(e) },
      { status: 500 },
    );
  }
}
