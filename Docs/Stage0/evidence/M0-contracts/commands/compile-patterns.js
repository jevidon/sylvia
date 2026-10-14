// Compiles regular expressions as ECMA-262 and runs them on strings, for commands/check-patterns.py, which compares
// the results with Python's `re` and with the checker's ECMA-262 grammar check (Scripts/check-spike-anchors.py).
//
//   node Docs/Stage0/evidence/M0-contracts/commands/compile-patterns.js < request.json > results.json
//
// Request: {"patterns": [<pattern>, ...], "tests": [[<pattern>, <string>], ...]}
// Results: {"node": <version>, "compiled": [{"u": null | <error>, "plain": null | <error>}, ...],
//           "tests": [{"u": true | false | null, "plain": true | false | null}, ...]} (null: does not compile)
"use strict";
const input = JSON.parse(require("fs").readFileSync(0, "utf8"));
const compile = (pattern, flags) => {
  try {
    return { re: new RegExp(pattern, flags), error: null };
  } catch (e) {
    return { re: null, error: e.message };
  }
};
const compiled = input.patterns.map((p) => ({ u: compile(p, "u").error, plain: compile(p, "").error }));
const tests = input.tests.map(([p, s]) => {
  const out = {};
  for (const [key, flags] of [["u", "u"], ["plain", ""]]) {
    const { re } = compile(p, flags);
    out[key] = re === null ? null : re.test(s);
  }
  return out;
});
process.stdout.write(JSON.stringify({ node: process.version, compiled, tests }));
