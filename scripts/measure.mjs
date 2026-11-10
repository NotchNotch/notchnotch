// Measures what the running NotchNotch costs: CPU, memory, energy impact and
// idle wakeups for the app and every extension process, sampled with `top`.
//
//   node scripts/measure.mjs [--seconds 60] [--runs 3] [--budget] [--json]
//
// --budget exits 1 when a total is over the budget in docs/internals/performance.md.
// Leave the Mac alone while it runs; the notch should be closed unless you are
// measuring the open notch on purpose.
import { spawnSync } from "node:child_process";
import { parseArgs } from "node:util";

/** Keep in step with docs/internals/performance.md. */
export const budget = {
  idle: { appCPU: 1.0, totalCPU: 2.0, appMemoryMB: 60, runnerMemoryMB: 40, totalWakeupsPerSecond: 10 },
};

const { values } = parseArgs({ options: { seconds: { type: "string", default: "60" }, runs: { type: "string", default: "1" },
  budget: { type: "boolean" }, json: { type: "boolean" } } });
const seconds = Math.max(6, Number(values.seconds));
const interval = 3;

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  return result.status === 0 ? result.stdout : "";
}

/** The app and every process it started (runners, helpers), by pid. */
export function processes() {
  const app = run("pgrep", ["-f", "NotchNotch.app/Contents/MacOS/NotchNotch"]).trim().split("\n").filter(Boolean)[0];
  if (!app) throw new Error("NotchNotch isn't running.");
  const found = new Map([[app, "NotchNotch"]]);
  const pending = [app];
  while (pending.length) {
    for (const child of run("pgrep", ["-P", pending.pop()]).trim().split("\n").filter(Boolean)) {
      if (found.has(child)) continue;
      const command = run("ps", ["-o", "command=", "-p", child]).trim();
      const extension = /\/(?:Extensions|extensions)\/([^/]+)\//.exec(command)?.[1];
      found.set(child, command.includes("ExtensionRunner") ? `runner ${extension ?? "?"}` : command.split("/").pop().slice(0, 40));
      pending.push(child);
    }
  }
  return found;
}

/** `top -stats` columns for each sample after the first, whose CPU covers no interval. */
export function parseTop(output) {
  const samples = output.split(/^PID\s+%CPU/m).slice(2);
  return samples.map((sample) => new Map(sample.split("\n").slice(1).map((line) => line.trim().split(/\s+/)).filter((cells) => cells.length >= 5)
    .map(([pid, cpu, memory, power, wakeups]) => [pid, { cpu: Number(cpu), memoryMB: megabytes(memory), power: Number(power), wakeups: Number(wakeups) }])));
}

function megabytes(text) {
  const match = /^([\d.]+)([BKMG])/.exec(text);
  if (!match) return 0;
  return Number(match[1]) * { B: 1 / 1048576, K: 1 / 1024, M: 1, G: 1024 }[match[2]];
}

export function summarize(names, samples) {
  const rows = [...names].map(([pid, name]) => {
    const seen = samples.map((sample) => sample.get(pid)).filter(Boolean);
    const average = (key) => seen.reduce((sum, value) => sum + value[key], 0) / Math.max(1, seen.length);
    return { pid, name, cpu: average("cpu"), memoryMB: Math.max(0, ...seen.map((value) => value.memoryMB)),
      power: average("power"), wakeupsPerSecond: average("wakeups") / interval };
  });
  const total = (key) => rows.reduce((sum, row) => sum + row[key], 0);
  return { rows, totals: { cpu: total("cpu"), memoryMB: total("memoryMB"), power: total("power"), wakeupsPerSecond: total("wakeupsPerSecond") } };
}

export function overBudget({ rows, totals }, limits = budget.idle) {
  const problems = [];
  const app = rows.find((row) => row.name === "NotchNotch");
  if (app && app.cpu > limits.appCPU) problems.push(`app CPU ${app.cpu.toFixed(1)}% > ${limits.appCPU}%`);
  if (totals.cpu > limits.totalCPU) problems.push(`total CPU ${totals.cpu.toFixed(1)}% > ${limits.totalCPU}%`);
  if (app && app.memoryMB > limits.appMemoryMB) problems.push(`app memory ${app.memoryMB.toFixed(0)} MB > ${limits.appMemoryMB} MB`);
  for (const row of rows.filter((row) => row.name.startsWith("runner"))) {
    if (row.memoryMB > limits.runnerMemoryMB) problems.push(`${row.name} memory ${row.memoryMB.toFixed(0)} MB > ${limits.runnerMemoryMB} MB`);
  }
  if (totals.wakeupsPerSecond > limits.totalWakeupsPerSecond) problems.push(`wakeups ${totals.wakeupsPerSecond.toFixed(0)}/s > ${limits.totalWakeupsPerSecond}/s`);
  return problems;
}

/** Total CPU seconds each process has used, from `ps` (exact, unlike top's instant samples). */
export function cpuSeconds(pids) {
  const times = new Map();
  for (const line of run("ps", ["-o", "pid=,time=", "-p", pids.join(",")]).trim().split("\n")) {
    const [pid, time] = line.trim().split(/\s+/);
    if (!time) continue;
    const parts = time.split(":").map(Number);
    times.set(pid, parts.reduce((total, part) => total * 60 + part, 0));
  }
  return times;
}

/** One window: exact CPU from `ps`, memory, energy and wakeups from `top`. */
function measureOnce(names) {
  const pids = [...names.keys()].flatMap((pid) => ["-pid", pid]);
  const before = cpuSeconds([...names.keys()]), started = Date.now();
  const output = run("top", ["-l", String(Math.ceil(seconds / interval) + 1), "-s", String(interval), "-stats", "pid,cpu,mem,power,idlew", ...pids]);
  const after = cpuSeconds([...names.keys()]), elapsed = (Date.now() - started) / 1000;
  const result = summarize(names, parseTop(output));
  // CPU from the exact counters; top's per-sample CPU is too noisy to average.
  for (const row of result.rows) row.cpu = ((after.get(row.pid) ?? 0) - (before.get(row.pid) ?? 0)) / elapsed * 100;
  result.totals.cpu = result.rows.reduce((sum, row) => sum + row.cpu, 0);
  return result;
}

/** The run with the median total CPU: periodic network fetches land in some windows and not others. */
export function median(results) {
  return [...results].sort((a, b) => a.totals.cpu - b.totals.cpu)[Math.floor(results.length / 2)];
}

if (process.argv[1]?.endsWith("measure.mjs")) {
  const names = processes();
  const runs = Array.from({ length: Math.max(1, Number(values.runs)) }, () => measureOnce(names));
  const result = median(runs);
  if (runs.length > 1) console.error(`Runs: ${runs.map((run) => run.totals.cpu.toFixed(1) + "%").join(", ")}; showing the median.`);
  if (values.json) console.log(JSON.stringify(result, null, 2));
  else {
    console.log(`${"Process".padEnd(42)} ${"CPU %".padStart(6)} ${"Memory".padStart(8)} ${"Energy".padStart(7)} ${"Wakeups/s".padStart(10)}`);
    for (const row of [...result.rows].sort((a, b) => b.cpu - a.cpu)) {
      console.log(`${row.name.padEnd(42)} ${row.cpu.toFixed(1).padStart(6)} ${(row.memoryMB.toFixed(0) + " MB").padStart(8)} ${row.power.toFixed(1).padStart(7)} ${row.wakeupsPerSecond.toFixed(1).padStart(10)}`);
    }
    const t = result.totals;
    console.log(`${"Total".padEnd(42)} ${t.cpu.toFixed(1).padStart(6)} ${(t.memoryMB.toFixed(0) + " MB").padStart(8)} ${t.power.toFixed(1).padStart(7)} ${t.wakeupsPerSecond.toFixed(1).padStart(10)}`);
  }
  if (values.budget) {
    const problems = overBudget(result);
    for (const problem of problems) console.error(`✗ ${problem}`);
    if (problems.length) process.exit(1);
    console.error("Within the idle budget.");
  }
}
