import { test } from "node:test";
import assert from "node:assert/strict";
import { budget, median, overBudget, parseTop, summarize } from "../scripts/measure.mjs";

const top = `Processes: 1 total
PID    %CPU MEM  POWER IDLEW
10     0.0  20M  0.0   0
11     0.0  8M   0.0   0
Processes: 1 total
PID    %CPU MEM  POWER IDLEW
10     0.6  21M+ 0.5   3
11     0.1  9M   0.1   0
Processes: 1 total
PID    %CPU MEM  POWER IDLEW
10     1.0  23M- 0.9   6
11     0.0  1.5G 0.0   0
`;

test("top samples after the first are parsed per process", () => {
  const samples = parseTop(top);
  assert.equal(samples.length, 2);
  assert.deepEqual(samples[0].get("10"), { cpu: 0.6, memoryMB: 21, power: 0.5, wakeups: 3 });
  assert.equal(samples[1].get("11").memoryMB, 1536);
});

test("the summary keeps peak memory and flags what's over budget", () => {
  const result = summarize(new Map([["10", "NotchNotch"], ["11", "runner dev.test.big"]]), parseTop(top));
  assert.equal(result.rows[0].memoryMB, 23);
  assert.equal(result.rows[0].wakeupsPerSecond, 1.5);
  result.rows[0].cpu = 0.5; result.totals.cpu = 0.6;
  assert.deepEqual(overBudget(result), [`runner dev.test.big memory 1536 MB > ${budget.idle.runnerMemoryMB} MB`]);
});

test("the median run hides a window that caught a network refresh", () => {
  const run = (cpu) => ({ totals: { cpu } });
  assert.equal(median([run(1.4), run(0.2), run(0.4)]).totals.cpu, 0.4);
});
