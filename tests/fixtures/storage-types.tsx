import { useStoredState } from "@notchnotch/sdk";
type Duration = "15" | "25";
export function Probe() {
  const [count, setCount] = useStoredState("count", 0); setCount(count + 1);
  const [flag, setFlag] = useStoredState("flag", true); setFlag(!flag);
  const [d, setD] = useStoredState<Duration>("d", "25"); setD("15");
  // @ts-expect-error narrow type kept for explicit generics
  setD("99");
  // @ts-expect-error functions are not JSON
  useStoredState("bad", () => 1);
  const n: number = count; const s: Duration = d; void n; void s;
  return null;
}
