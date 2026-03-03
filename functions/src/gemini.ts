import { GoogleGenerativeAI } from "@google/generative-ai";

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY || "");

export async function suggestActivities(
  windows: Array<{ startMs: number; endMs: number; durationMinutes: number }>
): Promise<Map<number, string>> {
  const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });
  const suggestions = new Map<number, string>();

  const windowDescriptions = windows.slice(0, 10).map((w, i) => {
    const start = new Date(w.startMs);
    const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    const day = days[start.getUTCDay()];
    const hour = start.getUTCHours();
    const isWeekend = start.getUTCDay() === 0 || start.getUTCDay() === 6;
    return `${i + 1}. ${day} ${hour}:00 UTC, ${w.durationMinutes} minutes${isWeekend ? " (weekend)" : ""}`;
  }).join("\n");

  const prompt = `Suggest one couple activity for each time window (max 8 words each). Be specific and fun.\n\n${windowDescriptions}\n\nFormat: one suggestion per line, numbered.`;

  try {
    const result = await model.generateContent(prompt);
    const text = result.response.text();
    const lines = text.split("\n").filter((l) => l.trim());

    for (let i = 0; i < Math.min(lines.length, windows.length); i++) {
      const suggestion = lines[i].replace(/^\d+\.\s*/, "").trim();
      if (suggestion) suggestions.set(i, suggestion);
    }
  } catch (err) {
    console.warn("Gemini suggestion failed:", err);
  }

  return suggestions;
}
